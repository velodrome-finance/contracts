// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";

import {IVotes} from "./governance/IVotes.sol";
import {IVoter} from "./interfaces/IVoter.sol";
import {IMinter} from "./interfaces/IMinter.sol";
import {IVotingEscrow} from "contracts/interfaces/IVotingEscrow.sol";
import {GovernorSimple, IGovernor} from "./governance/GovernorSimple.sol";
import {EpochGovernorCountingFractional} from "./governance/EpochGovernorCountingFractional.sol";
import {GovernorSimpleVotes} from "./governance/GovernorSimpleVotes.sol";
import {GovernorCommentable} from "./governance/GovernorCommentable.sol";
import {GovernorProposalWindow} from "./governance/GovernorProposalWindow.sol";
import {VelodromeTimeLibrary} from "./libraries/VelodromeTimeLibrary.sol";
import {DelegationHelperLibrary} from "contracts/libraries/DelegationHelperLibrary.sol";

/**
 * @title EpochGovernor
 * @notice Epoch based governance system that allows for a three option majority (against, for, abstain) and fractional votes.
 * @notice Refer to SPECIFICATION.md.
 * @author velodrome.finance, @figs999, @pegahcarter
 * @dev Note that hash proposals are unique per epoch, but calls to a function with different values
 *      may be allowed any number of times. It is best to use EpochGovernor with a function that accepts
 *      no values.
 */
contract EpochGovernor is
    GovernorSimple,
    EpochGovernorCountingFractional,
    GovernorSimpleVotes,
    GovernorCommentable,
    GovernorProposalWindow
{
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;
    using DelegationHelperLibrary for IVotingEscrow;

    error GovernorRelayNotSupported();

    address public immutable minter;

    /// @dev Stores most recent voting result. Will be either Defeated, Succeeded or Expired.
    ///      Any contracts that wish to use this governor must read from this to determine results.
    ProposalState public result;

    constructor(IVotes _ve, address _minter, IVoter _voter, address _owner)
        GovernorSimple("Epoch Governor", _owner)
        GovernorSimpleVotes(_ve)
        GovernorCommentable(_voter)
    {
        minter = _minter;
    }

    /**
     * @dev See {IGovernor-state}.
     */
    function state(uint256 _proposalId) public view virtual override returns (ProposalState) {
        // We read the struct fields into the stack at once so Solidity emits a single SLOAD
        ProposalCore storage proposal = _proposals[_proposalId];
        bool proposalExecuted = proposal.executed;
        bool proposalCanceled = proposal.canceled;

        if (proposalExecuted) {
            return ProposalState.Executed;
        }

        if (proposalCanceled) {
            return ProposalState.Canceled;
        }

        uint256 snapshot = proposalSnapshot({_proposalId: _proposalId});

        if (snapshot == 0) {
            revert GovernorNonexistentProposal({_proposalId: _proposalId});
        }

        uint256 currentTimepoint = clock();

        if (snapshot >= currentTimepoint) {
            return ProposalState.Pending;
        }

        uint256 deadline = proposalDeadline({_proposalId: _proposalId});

        if (deadline >= currentTimepoint) {
            return ProposalState.Active;
        }

        return _selectWinner({_proposalId: _proposalId});
    }

    function _quorumReached(uint256 _proposalId) internal view virtual override returns (bool) {
        return true;
    }

    function _voteSucceeded(uint256 _proposalId) internal view virtual override returns (bool) {
        return true;
    }

    /// @inheritdoc GovernorSimple
    function propose(
        uint256 _tokenId,
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        string memory _description
    ) public virtual override(GovernorSimple, GovernorProposalWindow) returns (uint256) {
        return GovernorProposalWindow.propose({
            _tokenId: _tokenId,
            _targets: _targets,
            _values: _values,
            _calldatas: _calldatas,
            _description: _description
        });
    }

    /**
     * @dev Internal propose mechanism. Can be overridden to add more logic on proposal creation.
     *
     * Emits a {IGovernor-ProposalCreated} event.
     */
    function _propose(
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        string memory _description,
        address _proposer
    ) internal virtual override returns (uint256 _proposalId) {
        uint256 epochVoteEnd = VelodromeTimeLibrary.epochVoteEnd({timestamp: block.timestamp});
        _proposalId = hashProposal({
            _targets: _targets,
            _values: _values,
            _calldatas: _calldatas,
            _descriptionHash: bytes32(epochVoteEnd)
        });

        if (_targets.length != _values.length || _targets.length != _calldatas.length || _targets.length != 1) {
            revert GovernorInvalidProposalLength({
                _targets: _targets.length,
                _calldatas: _calldatas.length,
                _values: _values.length
            });
        }
        if (_proposals[_proposalId].voteStart != 0) {
            revert GovernorUnexpectedProposalState({
                _proposalId: _proposalId,
                _current: state({_proposalId: _proposalId}),
                _expectedStates: bytes32(0)
            });
        }
        if (_targets[0] != minter || bytes4(_calldatas[0]) != IMinter.nudge.selector) {
            revert GovernorInvalidTargetOrCalldata({_target: _targets[0], _callData: bytes4(_calldatas[0])});
        }

        ProposalCore storage proposal = _proposals[_proposalId];
        proposal.proposer = _proposer;

        uint256 voteStart = Math.max({a: clock(), b: VelodromeTimeLibrary.epochVoteStart({timestamp: block.timestamp})});
        proposal.voteStart = SafeCast.toUint48({value: voteStart + votingDelay()});
        proposal.voteDuration = SafeCast.toUint32(epochVoteEnd - voteStart);

        emit ProposalCreated({
            _proposalId: _proposalId,
            _proposer: _proposer,
            _targets: _targets,
            _values: _values,
            _signatures: new string[](_targets.length),
            _calldatas: _calldatas,
            _voteStart: voteStart,
            _voteEnd: epochVoteEnd,
            _description: _description
        });

        // Using a named return variable to avoid stack too deep errors
    }

    /**
     * @dev See {IGovernor-execute}.
     */
    function execute(
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        bytes32 _descriptionHash
    ) public payable virtual override returns (uint256) {
        uint256 proposalId = hashProposal({
            _targets: _targets,
            _values: _values,
            _calldatas: _calldatas,
            _descriptionHash: bytes32(VelodromeTimeLibrary.epochVoteEnd({timestamp: block.timestamp}))
        });

        ProposalState status = _validateStateBitmap({
            _proposalId: proposalId,
            _allowedStates: _encodeStateBitmap({_proposalState: ProposalState.Succeeded})
                | _encodeStateBitmap({_proposalState: ProposalState.Defeated})
                | _encodeStateBitmap({_proposalState: ProposalState.Expired})
        });

        // mark as executed before calls to avoid reentrancy
        _proposals[proposalId].executed = true;

        result = status;

        // before execute: register governance call in queue.
        if (_executor() != address(this)) {
            for (uint256 i = 0; i < _targets.length; ++i) {
                if (_targets[i] == address(this)) {
                    _governanceCall.pushBack({value: keccak256(_calldatas[i])});
                }
            }
        }

        _executeOperations({
            _proposalId: proposalId,
            _targets: _targets,
            _values: _values,
            _calldatas: _calldatas,
            _descriptionHash: _descriptionHash
        });

        // after execute: cleanup governance call queue.
        if (_executor() != address(this) && !_governanceCall.empty()) {
            _governanceCall.clear();
        }

        emit ProposalExecuted({_proposalId: proposalId});

        return proposalId;
    }

    function relay(address, /* target */ uint256, /* value */ bytes calldata /* data */ )
        external
        payable
        virtual
        override
        onlyGovernance
    {
        revert GovernorRelayNotSupported();
    }

    function votingDelay() public pure override returns (uint256) {
        return 2;
    }

    function votingPeriod() public pure override returns (uint256) {
        return (1 weeks);
    }

    function quorum(uint256 _timepoint) public view virtual override returns (uint256) {
        return 0;
    }

    /**
     * The proposal id is produced by hashing the ABI encoded epochVoteEnd. It can be computed in
     * advance, before the proposal is submitted with the help of the VelodromeTimeLibrary.
     */
    function hashProposal(
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        bytes32 _descriptionHash
    ) public pure override returns (uint256) {
        return uint256(keccak256(abi.encode(_descriptionHash)));
    }
}

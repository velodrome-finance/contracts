// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IERC165, ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IGovernor as IOZGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

import {IGovernor, IERC6372} from "./IGovernor.sol";

/**
 * @dev Modified lightly from OpenZeppelin's Governor contract to support three option voting via callback.
 * A counting module is only required to implement _selectWinner and _countVote.
 * Adheres to IGovernor interface, with the following changes:
 * - hashProposal(...) generates a hash that allows for only one proposal per epoch
 * - state(...) returns a simple majority
 * - cancel(...) not supported
 *
 */
abstract contract GovernorSimple is ERC165, EIP712, Nonces, Ownable, IGovernor, IERC721Receiver, IERC1155Receiver {
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;

    bytes32 public constant BALLOT_TYPEHASH =
        keccak256("Ballot(uint256 proposalId,uint8 support,address voter,uint256 nonce)");
    bytes32 public constant EXTENDED_BALLOT_TYPEHASH = keccak256(
        "ExtendedBallot(uint256 proposalId,uint8 support,address voter,uint256 nonce,string reason,bytes params)"
    );

    struct ProposalCore {
        address proposer;
        uint48 voteStart;
        uint32 voteDuration;
        bool executed;
        bool canceled;
        uint48 etaSeconds;
    }

    bytes32 private constant ALL_PROPOSAL_STATES_BITMAP = bytes32((2 ** (uint8(type(ProposalState).max) + 1)) - 1);
    string private _name;

    mapping(uint256 proposalId => ProposalCore) internal _proposals;

    // This queue keeps track of the governor operating on itself. Calls to functions protected by the {onlyGovernance}
    // modifier needs to be whitelisted in this queue. Whitelisting is set in {execute}, consumed by the
    // {onlyGovernance} modifier and eventually reset after {_executeOperations} completes. This ensures that the
    // execution of {onlyGovernance} protected calls can only be achieved through successful proposals.
    DoubleEndedQueue.Bytes32Deque internal _governanceCall;

    /**
     * @dev Restricts a function so it can only be executed through governance proposals. For example, governance
     * parameter setters in {GovernorSettings} are protected using this modifier.
     *
     * The governance executing address may be different from the Governor's own address, for example it could be a
     * timelock. This can be customized by modules by overriding {_executor}. The executor is only able to invoke these
     * functions during the execution of the governor's {execute} function, and not under any other circumstances. Thus,
     * for example, additional timelock proposers are not able to change governance parameters without going through the
     * governance protocol (since v4.6).
     */
    modifier onlyGovernance() {
        _checkGovernance();
        _;
    }

    /**
     * @dev Sets the value for {name} and {version}
     */
    constructor(string memory name_, address _owner) EIP712(name_, version()) Ownable(_owner) {
        _name = name_;
    }

    /**
     * @dev Function to receive ETH that will be handled by the governor (disabled if executor is a third party contract)
     */
    receive() external payable virtual {
        if (_executor() != address(this)) {
            revert GovernorDisabledDeposit();
        }
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 _interfaceId) public view virtual override(IERC165, ERC165) returns (bool) {
        return (_interfaceId == type(IGovernor).interfaceId ^ IOZGovernor.cancel.selector)
            || _interfaceId == type(IERC1155Receiver).interfaceId || super.supportsInterface({interfaceId: _interfaceId});
    }

    /**
     * @dev See {IGovernor-name}.
     */
    function name() public view virtual returns (string memory) {
        return _name;
    }

    /**
     * @dev See {IGovernor-version}.
     */
    function version() public view virtual returns (string memory) {
        return "1";
    }

    /**
     * @dev See {IGovernor-hashProposal}.
     *
     * The proposal id is produced by hashing the ABI encoded `targets` array, the `values` array, the `calldatas` array
     * and the descriptionHash (bytes32 which itself is the keccak256 hash of the description string). This proposal id
     * can be produced from the proposal data which is part of the {ProposalCreated} event. It can even be computed in
     * advance, before the proposal is submitted.
     *
     * Note that the chainId and the governor address are not part of the proposal id computation. Consequently, the
     * same proposal (with same operation and same description) will have the same id if submitted on multiple governors
     * across multiple networks. This also means that in order to execute the same operation twice (on the same
     * governor) the proposer will have to change the description in order to avoid proposal id conflicts.
     */
    function hashProposal(
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        bytes32 _descriptionHash
    ) public pure virtual returns (uint256) {
        return uint256(keccak256(abi.encode(_targets, _values, _calldatas, _descriptionHash)));
    }

    /**
     * @dev See {IGovernor-state}.
     */
    function state(uint256 _proposalId) public view virtual returns (ProposalState) {
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
        } else if (!_quorumReached({_proposalId: _proposalId}) || !_voteSucceeded({_proposalId: _proposalId})) {
            return ProposalState.Defeated;
        } else if (proposalEta({_proposalId: _proposalId}) == 0) {
            return ProposalState.Succeeded;
        } else {
            return ProposalState.Queued;
        }
    }

    /**
     * @dev See {IGovernor-proposalThreshold}.
     */
    function proposalThreshold() public view virtual returns (uint256) {
        return 0;
    }

    /**
     * @dev See {IGovernor-proposalSnapshot}.
     */
    function proposalSnapshot(uint256 _proposalId) public view virtual returns (uint256) {
        return _proposals[_proposalId].voteStart;
    }

    /**
     * @dev See {IGovernor-proposalDeadline}.
     */
    function proposalDeadline(uint256 _proposalId) public view virtual returns (uint256) {
        return _proposals[_proposalId].voteStart + _proposals[_proposalId].voteDuration;
    }

    /**
     * @dev See {IGovernor-proposalProposer}.
     */
    function proposalProposer(uint256 _proposalId) public view virtual returns (address) {
        return _proposals[_proposalId].proposer;
    }

    /**
     * @dev See {IGovernor-proposalEta}.
     */
    function proposalEta(uint256 _proposalId) public view virtual returns (uint256) {
        return _proposals[_proposalId].etaSeconds;
    }

    /**
     * @dev See {IGovernor-proposalNeedsQueuing}.
     */
    function proposalNeedsQueuing(uint256) public view virtual returns (bool) {
        return false;
    }

    /**
     * @dev Reverts if the `msg.sender` is not the executor. In case the executor is not this contract
     * itself, the function reverts if `msg.data` is not whitelisted as a result of an {execute}
     * operation. See {onlyGovernance}.
     */
    function _checkGovernance() internal virtual {
        if (_executor() != msg.sender) {
            revert GovernorOnlyExecutor({_account: msg.sender});
        }
        if (_executor() != address(this)) {
            bytes32 msgDataHash = keccak256(msg.data);
            // loop until popping the expected operation - throw if deque is empty (operation not authorized)
            while (_governanceCall.popFront() != msgDataHash) {}
        }
    }

    /**
     * @dev Amount of votes already cast passes the threshold limit.
     */
    function _quorumReached(uint256 _proposalId) internal view virtual returns (bool);

    /**
     * @dev Is the proposal successful or not.
     */
    function _voteSucceeded(uint256 _proposalId) internal view virtual returns (bool);

    /**
     * @dev Get the voting weight of `tokenId`, owned by `account` at a specific `timepoint`, for a vote as described by `params`.
     */
    function _getVotes(address _account, uint256 _tokenId, uint256 _timepoint, bytes memory _params)
        internal
        view
        virtual
        returns (uint256);

    /**
     * @dev Register a vote for `proposalId` by `tokenId` with a given `support`, voting `weight` and voting `params`.
     *
     * Note: Support is generic and can represent various things depending on the voting system used.
     */
    function _countVote(
        uint256 _proposalId,
        uint256 _tokenId,
        uint8 _support,
        uint256 _totalWeight,
        bytes memory _params
    ) internal virtual returns (uint256);

    /**
     * @dev Hook that should be called every time the tally for a proposal is updated.
     *
     *
     *
     * Note: This function must run successfully. Reverts will result in the bricking of governance
     */
    function _tallyUpdated(uint256 _proposalId) internal virtual {}

    /**
     * @dev Default additional encoded parameters used by castVote methods that don't include them
     *
     * Note: Should be overridden by specific implementations to use an appropriate value, the
     * meaning of the additional params, in the context of that implementation
     */
    function _defaultParams() internal view virtual returns (bytes memory) {
        return "";
    }

    /**
     * @dev See {IGovernor-propose}. This function has opt-in frontrunning protection, described in {_isValidDescriptionForProposer}.
     */
    function propose(
        uint256 _tokenId,
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        string memory _description
    ) public virtual returns (uint256) {
        address proposer = msg.sender;

        // check description restriction
        if (!_isValidDescriptionForProposer({_proposer: proposer, _description: _description})) {
            revert GovernorRestrictedProposer({_proposer: proposer});
        }

        // check proposal threshold
        uint256 votesThreshold = proposalThreshold();
        if (votesThreshold > 0) {
            uint256 proposerVotes = getVotes({_account: proposer, _tokenId: _tokenId, _timepoint: clock() - 1});
            if (proposerVotes < votesThreshold) {
                revert GovernorInsufficientProposerVotes({
                    _proposer: proposer,
                    _votes: proposerVotes,
                    _threshold: votesThreshold
                });
            }
        }

        return _propose({
            _targets: _targets,
            _values: _values,
            _calldatas: _calldatas,
            _description: _description,
            _proposer: proposer
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
    ) internal virtual returns (uint256 _proposalId) {
        _proposalId = hashProposal({
            _targets: _targets,
            _values: _values,
            _calldatas: _calldatas,
            _descriptionHash: keccak256(bytes(_description))
        });

        if (_targets.length != _values.length || _targets.length != _calldatas.length || _targets.length == 0) {
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

        uint256 snapshot = clock() + votingDelay();
        uint256 duration = votingPeriod();

        ProposalCore storage proposal = _proposals[_proposalId];

        proposal.proposer = _proposer;
        proposal.voteStart = SafeCast.toUint48(snapshot);
        proposal.voteDuration = SafeCast.toUint32(duration);

        emit ProposalCreated({
            _proposalId: _proposalId,
            _proposer: _proposer,
            _targets: _targets,
            _values: _values,
            _signatures: new string[](_targets.length),
            _calldatas: _calldatas,
            _voteStart: snapshot,
            _voteEnd: snapshot + duration,
            _description: _description
        });

        // Using a named return variable to avoid stack too deep errors
    }

    /**
     * @dev See {IGovernor-queue}.
     */
    function queue(
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        bytes32 _descriptionHash
    ) public virtual returns (uint256) {
        uint256 proposalId = hashProposal({
            _targets: _targets,
            _values: _values,
            _calldatas: _calldatas,
            _descriptionHash: _descriptionHash
        });

        _validateStateBitmap({
            _proposalId: proposalId,
            _allowedStates: _encodeStateBitmap({_proposalState: ProposalState.Succeeded})
        });

        uint48 etaSeconds = _queueOperations({
            _proposalId: proposalId,
            _targets: _targets,
            _values: _values,
            _calldatas: _calldatas,
            _descriptionHash: _descriptionHash
        });

        if (etaSeconds != 0) {
            _proposals[proposalId].etaSeconds = etaSeconds;
            emit ProposalQueued({_proposalId: proposalId, _etaSeconds: etaSeconds});
        } else {
            revert GovernorQueueNotImplemented();
        }

        return proposalId;
    }

    /**
     * @dev Internal queuing mechanism. Can be overridden (without a super call) to modify the way queuing is
     * performed (for example adding a vault/timelock).
     *
     * This is empty by default, and must be overridden to implement queuing.
     *
     * This function returns a timestamp that describes the expected ETA for execution. If the returned value is 0
     * (which is the default value), the core will consider queueing did not succeed, and the public {queue} function
     * will revert.
     *
     * NOTE: Calling this function directly will NOT check the current state of the proposal, or emit the
     * `ProposalQueued` event. Queuing a proposal should be done using {queue}.
     */
    function _queueOperations(
        uint256 _proposalId,
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        bytes32 _descriptionHash
    ) internal virtual returns (uint48) {
        return 0;
    }

    /**
     * @dev See {IGovernor-execute}.
     */
    function execute(
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        bytes32 _descriptionHash
    ) public payable virtual returns (uint256) {
        uint256 proposalId = hashProposal({
            _targets: _targets,
            _values: _values,
            _calldatas: _calldatas,
            _descriptionHash: _descriptionHash
        });

        _validateStateBitmap({
            _proposalId: proposalId,
            _allowedStates: _encodeStateBitmap({_proposalState: ProposalState.Succeeded})
                | _encodeStateBitmap({_proposalState: ProposalState.Queued})
        });

        // mark as executed before calls to avoid reentrancy
        _proposals[proposalId].executed = true;

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

    /**
     * @dev Internal execution mechanism. Can be overridden (without a super call) to modify the way execution is
     * performed (for example adding a vault/timelock).
     *
     * NOTE: Calling this function directly will NOT check the current state of the proposal, set the executed flag to
     * true or emit the `ProposalExecuted` event. Executing a proposal should be done using {execute} or {_execute}.
     */
    function _executeOperations(
        uint256 _proposalId,
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        bytes32 _descriptionHash
    ) internal virtual {
        for (uint256 i = 0; i < _targets.length; ++i) {
            (bool success, bytes memory returndata) = _targets[i].call{value: _values[i]}(_calldatas[i]);
            Address.verifyCallResult({success: success, returndata: returndata});
        }
    }

    /**
     * @dev See {IGovernor-getVotes}.
     */
    function getVotes(address _account, uint256 _tokenId, uint256 _timepoint) public view virtual returns (uint256) {
        return _getVotes({_account: _account, _tokenId: _tokenId, _timepoint: _timepoint, _params: _defaultParams()});
    }

    /**
     * @dev See {IGovernor-getVotesWithParams}.
     */
    function getVotesWithParams(address _account, uint256 _tokenId, uint256 _timepoint, bytes memory _params)
        public
        view
        virtual
        returns (uint256)
    {
        return _getVotes({_account: _account, _tokenId: _tokenId, _timepoint: _timepoint, _params: _params});
    }

    /**
     * @dev See {IGovernor-castVote}.
     */
    function castVote(uint256 _proposalId, uint256 _tokenId, uint8 _support) public virtual returns (uint256) {
        return _castVote({
            _proposalId: _proposalId,
            _account: msg.sender,
            _tokenId: _tokenId,
            _support: _support,
            _reason: ""
        });
    }

    /**
     * @dev See {IGovernor-castVoteWithReason}.
     */
    function castVoteWithReason(uint256 _proposalId, uint256 _tokenId, uint8 _support, string calldata _reason)
        public
        virtual
        returns (uint256)
    {
        return _castVote({
            _proposalId: _proposalId,
            _account: msg.sender,
            _tokenId: _tokenId,
            _support: _support,
            _reason: _reason
        });
    }

    /**
     * @dev See {IGovernor-castVoteWithReasonAndParams}.
     */
    function castVoteWithReasonAndParams(
        uint256 _proposalId,
        uint256 _tokenId,
        uint8 _support,
        string calldata _reason,
        bytes memory _params
    ) public virtual returns (uint256) {
        return _castVote({
            _proposalId: _proposalId,
            _account: msg.sender,
            _tokenId: _tokenId,
            _support: _support,
            _reason: _reason,
            _params: _params
        });
    }

    /**
     * @dev See {IGovernor-castVoteBySig}.
     */
    function castVoteBySig(
        uint256 _proposalId,
        uint256 _tokenId,
        uint8 _support,
        address _voter,
        bytes memory _signature
    ) public virtual returns (uint256) {
        bool valid = SignatureChecker.isValidSignatureNow({
            signer: _voter,
            hash: _hashTypedDataV4({
                structHash: keccak256(abi.encode(BALLOT_TYPEHASH, _proposalId, _support, _voter, _useNonce({owner: _voter})))
            }),
            signature: _signature
        });

        if (!valid) {
            revert GovernorInvalidSignature({_voter: _voter});
        }

        return
            _castVote({_proposalId: _proposalId, _account: _voter, _tokenId: _tokenId, _support: _support, _reason: ""});
    }

    /**
     * @dev See {IGovernor-castVoteWithReasonAndParamsBySig}.
     */
    function castVoteWithReasonAndParamsBySig(
        uint256 _proposalId,
        uint256 _tokenId,
        uint8 _support,
        address _voter,
        string calldata _reason,
        bytes memory _params,
        bytes memory _signature
    ) public virtual returns (uint256) {
        bool valid = SignatureChecker.isValidSignatureNow({
            signer: _voter,
            hash: _hashTypedDataV4({
                structHash: keccak256(
                    abi.encode(
                        EXTENDED_BALLOT_TYPEHASH,
                        _proposalId,
                        _support,
                        _voter,
                        _useNonce({owner: _voter}),
                        keccak256(bytes(_reason)),
                        keccak256(_params)
                    )
                )
            }),
            signature: _signature
        });

        if (!valid) {
            revert GovernorInvalidSignature({_voter: _voter});
        }

        return _castVote({
            _proposalId: _proposalId,
            _account: _voter,
            _tokenId: _tokenId,
            _support: _support,
            _reason: _reason,
            _params: _params
        });
    }

    /**
     * @dev Internal vote casting mechanism: Check that the vote is pending, that it has not been cast yet, retrieve
     * voting weight using {IGovernor-getVotes} and call the {_countVote} internal function. Uses the _defaultParams().
     *
     * Emits a {IGovernor-VoteCast} event.
     */
    function _castVote(uint256 _proposalId, address _account, uint256 _tokenId, uint8 _support, string memory _reason)
        internal
        virtual
        returns (uint256)
    {
        return _castVote({
            _proposalId: _proposalId,
            _account: _account,
            _tokenId: _tokenId,
            _support: _support,
            _reason: _reason,
            _params: _defaultParams()
        });
    }

    /**
     * @dev Internal vote casting mechanism: Check that the vote is pending, that it has not been cast yet, retrieve
     * voting weight using {IGovernor-getVotes} and call the {_countVote} internal function.
     *
     * Emits a {IGovernor-VoteCast} event.
     */
    function _castVote(
        uint256 _proposalId,
        address _account,
        uint256 _tokenId,
        uint8 _support,
        string memory _reason,
        bytes memory _params
    ) internal virtual returns (uint256) {
        _validateStateBitmap({
            _proposalId: _proposalId,
            _allowedStates: _encodeStateBitmap({_proposalState: ProposalState.Active})
        });

        uint256 totalWeight = _getVotes({
            _account: _account,
            _tokenId: _tokenId,
            _timepoint: proposalSnapshot({_proposalId: _proposalId}),
            _params: _params
        });
        uint256 votedWeight = _countVote({
            _proposalId: _proposalId,
            _tokenId: _tokenId,
            _support: _support,
            _totalWeight: totalWeight,
            _params: _params
        });

        if (_params.length == 0) {
            emit VoteCast({
                _voter: _account,
                _tokenId: _tokenId,
                _proposalId: _proposalId,
                _support: _support,
                _weight: votedWeight,
                _reason: _reason
            });
        } else {
            emit VoteCastWithParams({
                _voter: _account,
                _tokenId: _tokenId,
                _proposalId: _proposalId,
                _support: _support,
                _weight: votedWeight,
                _reason: _reason,
                _params: _params
            });
        }

        _tallyUpdated({_proposalId: _proposalId});

        return votedWeight;
    }

    /**
     * @dev Relays a transaction or function call to an arbitrary target. In cases where the governance executor
     * is some contract other than the governor itself, like when using a timelock, this function can be invoked
     * in a governance proposal to recover tokens or Ether that was sent to the governor contract by mistake.
     * Note that if the executor is simply the governor itself, use of `relay` is redundant.
     */
    function relay(address _target, uint256 _value, bytes calldata _data) external payable virtual onlyGovernance {
        (bool success, bytes memory returndata) = _target.call{value: _value}(_data);

        Address.verifyCallResult({success: success, returndata: returndata});
    }

    /**
     * @dev Address through which the governor executes action. Will be overloaded by module that execute actions
     * through another contract such as a timelock.
     */
    function _executor() internal view virtual returns (address) {
        return address(this);
    }

    /**
     * @dev See {IERC721Receiver-onERC721Received}.
     * Receiving tokens is disabled if the governance executor is other than the governor itself (eg. when using with a timelock).
     */
    function onERC721Received(address, address, uint256, bytes memory) public virtual returns (bytes4) {
        if (_executor() != address(this)) {
            revert GovernorDisabledDeposit();
        }
        return this.onERC721Received.selector;
    }

    /**
     * @dev See {IERC1155Receiver-onERC1155Received}.
     * Receiving tokens is disabled if the governance executor is other than the governor itself (eg. when using with a timelock).
     */
    function onERC1155Received(address, address, uint256, uint256, bytes memory) public virtual returns (bytes4) {
        if (_executor() != address(this)) {
            revert GovernorDisabledDeposit();
        }
        return this.onERC1155Received.selector;
    }

    /**
     * @dev See {IERC1155Receiver-onERC1155BatchReceived}.
     * Receiving tokens is disabled if the governance executor is other than the governor itself (eg. when using with a timelock).
     */
    function onERC1155BatchReceived(address, address, uint256[] memory, uint256[] memory, bytes memory)
        public
        virtual
        returns (bytes4)
    {
        if (_executor() != address(this)) {
            revert GovernorDisabledDeposit();
        }
        return this.onERC1155BatchReceived.selector;
    }

    /**
     * @dev Encodes a `ProposalState` into a `bytes32` representation where each bit enabled corresponds to
     * the underlying position in the `ProposalState` enum. For example:
     *
     * 0x000...10000
     *   ^^^^^^------ ...
     *         ^----- Succeeded
     *          ^---- Defeated
     *           ^--- Canceled
     *            ^-- Active
     *             ^- Pending
     */
    function _encodeStateBitmap(ProposalState _proposalState) internal pure returns (bytes32) {
        return bytes32(1 << uint8(_proposalState));
    }

    /**
     * @dev Check that the current state of a proposal matches the requirements described by the `allowedStates` bitmap.
     * This bitmap should be built using `_encodeStateBitmap`.
     *
     * If requirements are not met, reverts with a {GovernorUnexpectedProposalState} error.
     */
    function _validateStateBitmap(uint256 _proposalId, bytes32 _allowedStates) internal view returns (ProposalState) {
        ProposalState currentState = state({_proposalId: _proposalId});
        if (_encodeStateBitmap({_proposalState: currentState}) & _allowedStates == bytes32(0)) {
            revert GovernorUnexpectedProposalState({
                _proposalId: _proposalId,
                _current: currentState,
                _expectedStates: _allowedStates
            });
        }
        return currentState;
    }

    /*
     * @dev Check if the proposer is authorized to submit a proposal with the given description.
     *
     * If the proposal description ends with `#proposer=0x???`, where `0x???` is an address written as a hex string
     * (case insensitive), then the submission of this proposal will only be authorized to said address.
     *
     * This is used for frontrunning protection. By adding this pattern at the end of their proposal, one can ensure
     * that no other address can submit the same proposal. An attacker would have to either remove or change that part,
     * which would result in a different proposal id.
     *
     * If the description does not match this pattern, it is unrestricted and anyone can submit it. This includes:
     * - If the `0x???` part is not a valid hex string.
     * - If the `0x???` part is a valid hex string, but does not contain exactly 40 hex digits.
     * - If it ends with the expected suffix followed by newlines or other whitespace.
     * - If it ends with some other similar suffix, e.g. `#other=abc`.
     * - If it does not end with any such suffix.
     */
    function _isValidDescriptionForProposer(address _proposer, string memory _description)
        internal
        view
        virtual
        returns (bool)
    {
        unchecked {
            uint256 length = bytes(_description).length;

            // Length is too short to contain a valid proposer suffix
            if (length < 52) {
                return true;
            }

            // Extract what would be the `#proposer=` marker beginning the suffix
            bytes10 marker = bytes10(_unsafeReadBytesOffset({_buffer: bytes(_description), _offset: length - 52}));

            // If the marker is not found, there is no proposer suffix to check
            if (marker != bytes10("#proposer=")) {
                return true;
            }

            // Check that the last 42 characters (after the marker) are a properly formatted address.
            (bool success, address recovered) =
                Strings.tryParseAddress({input: _description, begin: length - 42, end: length});

            return !success || recovered == _proposer;
        }
    }

    /**
     * @inheritdoc IERC6372
     */
    function clock() public view virtual returns (uint48);

    /**
     * @inheritdoc IERC6372
     */
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public view virtual returns (string memory);

    /**
     * @inheritdoc IGovernor
     */
    function votingDelay() public view virtual returns (uint256);

    /**
     * @inheritdoc IGovernor
     */
    function votingPeriod() public view virtual returns (uint256);

    /**
     * @inheritdoc IGovernor
     */
    function quorum(uint256 _timepoint) public view virtual returns (uint256);

    /**
     * @dev Reads a bytes32 from a bytes array without bounds checking.
     *
     * NOTE: making this function internal would mean it could be used with memory unsafe offset, and marking the
     * assembly block as such would prevent some optimizations.
     */
    function _unsafeReadBytesOffset(bytes memory _buffer, uint256 _offset) private pure returns (bytes32 value) {
        // This is not memory safe in the general case, but all calls to this private function are within bounds.
        assembly ("memory-safe") {
            value := mload(add(_buffer, add(0x20, _offset)))
        }
    }
}

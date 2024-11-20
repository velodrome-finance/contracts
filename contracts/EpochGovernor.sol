// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import {IVotes} from "./governance/IVotes.sol";
import {IVoter} from "./interfaces/IVoter.sol";
import {GovernorSimple, IGovernor} from "./governance/GovernorSimple.sol";
import {GovernorCountingFractional} from "./governance/GovernorCountingFractional.sol";
import {GovernorSimpleVotes} from "./governance/GovernorSimpleVotes.sol";
import {GovernorCommentable} from "./governance/GovernorCommentable.sol";
import {GovernorProposalWindow} from "./governance/GovernorProposalWindow.sol";

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
    GovernorCountingFractional,
    GovernorSimpleVotes,
    GovernorCommentable,
    GovernorProposalWindow
{
    constructor(IVotes _ve, address _minter, IVoter _voter, address _owner)
        GovernorSimple("Epoch Governor", _minter, _owner)
        GovernorSimpleVotes(_ve)
        GovernorCommentable(_voter)
    {}

    /// @inheritdoc GovernorSimple
    function propose(
        uint256 tokenId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public virtual override(GovernorSimple, GovernorProposalWindow) returns (uint256) {
        return GovernorProposalWindow.propose(tokenId, targets, values, calldatas, description);
    }

    function votingDelay() public pure override returns (uint256) {
        return 1;
    }

    function votingPeriod() public pure override returns (uint256) {
        return (1 weeks);
    }
}

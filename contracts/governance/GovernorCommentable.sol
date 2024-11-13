// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import {GovernorSimple} from "./GovernorSimple.sol";
import {IVoter} from "../interfaces/IVoter.sol";
import {IVetoGovernor} from "./IVetoGovernor.sol";
import {IVotingEscrow} from "contracts/interfaces/IVotingEscrow.sol";

abstract contract GovernorCommentable is GovernorSimple {
    uint256 public constant COMMENT_DENOMINATOR = 1_000_000_000;
    IVoter public immutable _voter;
    IVotingEscrow public immutable escrow;

    constructor(IVoter voter_) {
        _voter = voter_;
        escrow = IVotingEscrow(voter_.ve());
    }

    /**
     * @dev Comment mechanism for active or pending proposals. Requires a certain amount of votes. Emits a comment
     *      containing the message.
     *
     * Emits a {IVetoGovernor-Comment} event.
     */
    function comment(uint256 proposalId, uint256 tokenId, string calldata message) external virtual override {
        bytes memory params;

        _validateStateBitmap(
            proposalId, _encodeStateBitmap(ProposalState.Active) | _encodeStateBitmap(ProposalState.Pending)
        );

        uint256 startTime = proposalSnapshot(proposalId);
        uint256 weight = _getVotes(msg.sender, tokenId, startTime, params);
        uint256 commentWeighting = IVetoGovernor(_voter.governor()).commentWeighting();
        uint256 minimumWeight = (escrow.getPastTotalSupply(startTime) * commentWeighting) / COMMENT_DENOMINATOR;

        if (weight < minimumWeight) revert GovernorInsufficientVotingPower(weight, minimumWeight);

        emit Comment(proposalId, msg.sender, tokenId, message);
    }
}

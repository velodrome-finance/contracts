// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import {GovernorSimple} from "./GovernorSimple.sol";
import {IGovernorCommentable} from "./IGovernorCommentable.sol";
import {IVoter} from "../interfaces/IVoter.sol";
import {IVotingEscrow} from "contracts/interfaces/IVotingEscrow.sol";

abstract contract GovernorCommentable is GovernorSimple, IGovernorCommentable {
    /// @inheritdoc IGovernorCommentable
    uint256 public constant COMMENT_DENOMINATOR = 1_000_000_000;

    /// @inheritdoc IGovernorCommentable
    IVotingEscrow public immutable escrow;
    /// @inheritdoc IGovernorCommentable
    uint256 public commentWeighting = 4_000;

    constructor(IVoter _voter) {
        escrow = IVotingEscrow(_voter.ve());
    }

    /// @inheritdoc IGovernorCommentable
    function comment(uint256 _proposalId, uint256 _tokenId, string calldata _message) external virtual override {
        bytes memory params;

        _validateStateBitmap({
            _proposalId: _proposalId,
            _allowedStates: _encodeStateBitmap({_proposalState: ProposalState.Active})
                | _encodeStateBitmap({_proposalState: ProposalState.Pending})
        });

        uint256 startTime = proposalSnapshot({_proposalId: _proposalId});
        uint256 weight = _getVotes({_account: msg.sender, _tokenId: _tokenId, _timepoint: startTime, _params: params});
        uint256 minimumWeight =
            (escrow.getPastTotalSupply({timestamp: startTime}) * commentWeighting) / COMMENT_DENOMINATOR;

        if (weight < minimumWeight) {
            revert GovernorInsufficientVotingPower({_weight: weight, _minimumWeight: minimumWeight});
        }

        emit Comment({_proposalId: _proposalId, _account: msg.sender, _tokenId: _tokenId, _comment: _message});
    }

    /// @inheritdoc IGovernorCommentable
    function setCommentWeighting(uint256 _commentWeighting) external onlyOwner {
        if (_commentWeighting > COMMENT_DENOMINATOR) revert CommentWeightingTooHigh();
        commentWeighting = _commentWeighting;

        emit SetCommentWeighting({_commentWeighting: _commentWeighting});
    }
}

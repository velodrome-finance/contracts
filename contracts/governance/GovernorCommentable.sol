// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {GovernorSimple} from "./GovernorSimple.sol";
import {IGovernorCommentable} from "./IGovernorCommentable.sol";
import {IVoter} from "../interfaces/IVoter.sol";
import {IVotingEscrow} from "contracts/interfaces/IVotingEscrow.sol";

abstract contract GovernorCommentable is GovernorSimple, Ownable, IGovernorCommentable {
    /// @inheritdoc IGovernorCommentable
    uint256 public constant COMMENT_DENOMINATOR = 1_000_000_000;

    /// @inheritdoc IGovernorCommentable
    IVotingEscrow public immutable escrow;
    /// @inheritdoc IGovernorCommentable
    uint256 public commentWeighting = 4_000;

    constructor(IVoter _voter, address _owner) Ownable(_owner) {
        escrow = IVotingEscrow(_voter.ve());
    }

    /// @inheritdoc IGovernorCommentable
    function comment(uint256 _proposalId, uint256 _tokenId, string calldata _message) external virtual override {
        bytes memory params;

        _validateStateBitmap({
            proposalId: _proposalId,
            allowedStates: _encodeStateBitmap({proposalState: ProposalState.Active})
                | _encodeStateBitmap({proposalState: ProposalState.Pending})
        });

        uint256 startTime = proposalSnapshot({proposalId: _proposalId});
        uint256 weight = _getVotes({account: msg.sender, tokenId: _tokenId, timepoint: startTime, params: params});
        uint256 minimumWeight = (escrow.getPastTotalSupply(startTime) * commentWeighting) / COMMENT_DENOMINATOR;

        if (weight < minimumWeight) revert GovernorInsufficientVotingPower(weight, minimumWeight);

        emit Comment({proposalId: _proposalId, account: msg.sender, tokenId: _tokenId, comment: _message});
    }

    /// @inheritdoc IGovernorCommentable
    function setCommentWeighting(uint256 _commentWeighting) external onlyOwner {
        if (_commentWeighting > COMMENT_DENOMINATOR) revert CommentWeightingTooHigh();
        commentWeighting = _commentWeighting;

        emit SetCommentWeighting(_commentWeighting);
    }
}

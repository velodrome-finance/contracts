// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IVotingEscrow} from "../VotingEscrow.sol";

interface IGovernorCommentable {
    error CommentWeightingTooHigh();

    event CommentWeightingSet(uint256 _commentWeighting);

    /// @notice Denominator used to calculate minimum voting power required to comment.
    function COMMENT_DENOMINATOR() external view returns (uint256);

    /// @notice Numerator used to calculate minimum voting power required to comment.
    function commentWeighting() external view returns (uint256);

    /// @notice Set minimum % of total supply required to comment
    /// @dev Callable only by owner
    /// @param _commentWeighting Weighting required for comment (note the denominator value).
    function setCommentWeighting(uint256 _commentWeighting) external;

    /**
     * @dev Add a comment to a proposal
     *
     * Emits a {Comment} event.
     */
    function comment(uint256 _proposalId, uint256 _tokenId, string calldata _message) external;
}

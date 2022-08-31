// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {ManagedReward} from "./ManagedReward.sol";
import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";

/// @notice Stores rewards that are max-locked (i.e. rebases / tokens that were compounded)
/// @dev Rewards are distributed based on weight contribution to managed nft
contract LockedManagedReward is ManagedReward {
    constructor(address _voter) ManagedReward(_voter) {}

    /// @inheritdoc ManagedReward
    /// @dev Called by VotingEscrow to retrieve locked rewards
    function getReward(uint256 tokenId, address[] memory tokens) external override nonReentrant {
        address sender = _msgSender();
        require(sender == ve, "LockedManagedReward: not voting escrow");
        require(tokens.length == 1, "LockedManagedReward: can only claim single token");
        require(tokens[0] == IVotingEscrow(ve).token(), "LockedManagedReward: can only claim escrow token");

        _getReward(sender, tokenId, tokens);
    }

    /// @inheritdoc ManagedReward
    /// @dev Called by VotingEscrow to add rebases / compounded rewards for disbursement
    function notifyRewardAmount(address token, uint256 amount) external override nonReentrant {
        address sender = _msgSender();
        require(sender == ve, "LockedManagedReward: only voting escrow");
        require(token == IVotingEscrow(ve).token(), "LockedManagedReward: not escrow token");

        _notifyRewardAmount(sender, token, amount);
    }
}

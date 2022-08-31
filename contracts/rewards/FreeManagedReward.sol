// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {ManagedReward} from "./ManagedReward.sol";
import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";
import {IVoter} from "../interfaces/IVoter.sol";

/// @notice Stores rewards that are free to be distributed
/// @dev Rewards are distributed based on weight contribution to managed nft
contract FreeManagedReward is ManagedReward {
    constructor(address _voter) ManagedReward(_voter) {}

    /// @inheritdoc ManagedReward
    function getReward(uint256 tokenId, address[] memory tokens) external override nonReentrant {
        require(IVotingEscrow(ve).isApprovedOrOwner(_msgSender(), tokenId), "FreeManagedReward: unpermissioned");

        address owner = IVotingEscrow(ve).ownerOf(tokenId);

        _getReward(owner, tokenId, tokens);
    }

    /// @inheritdoc ManagedReward
    function notifyRewardAmount(address token, uint256 amount) external override nonReentrant {
        address sender = _msgSender();
        if (!isReward[token]) {
            require(IVoter(voter).isWhitelistedToken(token), "FreeManagedReward: token not whitelisted");
            isReward[token] = true;
            rewards.push(token);
        }

        _notifyRewardAmount(sender, token, amount);
    }
}

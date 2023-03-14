// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {IManagedRewardsFactory} from "../interfaces/IManagedRewardsFactory.sol";
import {FreeManagedReward} from "../rewards/FreeManagedReward.sol";
import {LockedManagedReward} from "../rewards/LockedManagedReward.sol";

contract ManagedRewardsFactory is IManagedRewardsFactory {
    /// @inheritdoc IManagedRewardsFactory
    function createRewards(address voter) external returns (address lockedManagedReward, address freeManagedReward) {
        lockedManagedReward = address(new LockedManagedReward(voter));
        freeManagedReward = address(new FreeManagedReward(voter));
        emit ManagedRewardCreated(voter, lockedManagedReward, freeManagedReward);
    }
}

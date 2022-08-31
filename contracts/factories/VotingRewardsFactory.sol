// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {IVotingRewardsFactory} from "../interfaces/IVotingRewardsFactory.sol";
import {FeesVotingReward} from "../rewards/FeesVotingReward.sol";
import {BribeVotingReward} from "../rewards/BribeVotingReward.sol";

contract VotingRewardsFactory is IVotingRewardsFactory {
    function createRewards(address[] memory rewards)
        external
        returns (address feesVotingReward, address bribeVotingReward)
    {
        feesVotingReward = address(new FeesVotingReward(msg.sender, rewards));
        bribeVotingReward = address(new BribeVotingReward(msg.sender, rewards));
    }
}

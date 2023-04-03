// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {IVotingRewardsFactory} from "../interfaces/IVotingRewardsFactory.sol";
import {FeesVotingReward} from "../rewards/FeesVotingReward.sol";
import {BribeVotingReward} from "../rewards/BribeVotingReward.sol";

contract VotingRewardsFactory is IVotingRewardsFactory {
    /// @inheritdoc IVotingRewardsFactory
    function createRewards(address _forwarder, address[] memory _rewards)
        external
        returns (address feesVotingReward, address bribeVotingReward)
    {
        feesVotingReward = address(new FeesVotingReward(_forwarder, msg.sender, _rewards));
        bribeVotingReward = address(new BribeVotingReward(_forwarder, msg.sender, _rewards));
    }
}

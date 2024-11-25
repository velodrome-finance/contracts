// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IVotingRewardsFactory {
    /// @notice creates an incentiveVotingReward and a FeesVotingReward contract for a gauge
    /// @param _forwarder            Address of trusted forwarder
    /// @param _rewards             Addresses of pool tokens to be used as valid rewards tokens
    /// @return feesVotingReward    Address of FeesVotingReward contract created
    /// @return incentiveVotingReward   Address of IncentiveVotingReward contract created
    function createRewards(address _forwarder, address[] memory _rewards)
        external
        returns (address feesVotingReward, address incentiveVotingReward);
}

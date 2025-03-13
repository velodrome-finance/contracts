// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISinkGauge {
    error NotVoter();
    error ZeroAmount();

    event NotifyReward(address indexed _from, uint256 _amount);
    event ClaimRewards(address indexed _from, uint256 _amount);

    /// @notice Address of the token (VELO v2) rewarded to stakers
    function rewardToken() external view returns (address);

    /// @notice Address of Velodrome v2 Voter
    function voter() external view returns (address);

    /// @notice Address of the minter contract
    function minter() external view returns (address);

    /// @notice Total amount of rewards sent back to minter
    function lockedRewards() external view returns (uint256);

    /// @notice Amount of rewards for a given epoch
    /// @param _epochStart Start time of rewards epoch
    /// @return Amount of token
    function tokenRewardsPerEpoch(uint256 _epochStart) external view returns (uint256);

    /// @notice Kept for compatibility with voter calls.
    /// @dev Returns `0` to allow rewards to flow into sink gauge.
    function left() external view returns (uint256 _left);

    /// @notice Kept for compatibility.
    /// @dev Get reward is done directly in notifyRewardAmount.
    function getReward(address) external;

    /// @notice Notifies gauge of gauge rewards and sends them to minter.
    function notifyRewardAmount(uint256 _amount) external;
}

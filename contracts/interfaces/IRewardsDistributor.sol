// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRewardsDistributor {
    event CheckpointToken(uint256 time, uint256 tokens);
    event Claimed(uint256 indexed tokenId, uint256 indexed claimEpoch, uint256 indexed maxEpoch, uint256 amount);

    error NotDepositor();

    function checkpointToken() external;

    function checkpointTotalSupply() external;

    function claimable(uint256 tokenId) external view returns (uint256);

    function claim(uint256 tokenId) external returns (uint256);
}

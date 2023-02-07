pragma solidity 0.8.13;

interface IRewardsDistributor {
    event CheckpointToken(uint256 time, uint256 tokens);
    event Claimed(uint256 tokenId, uint256 amount, uint256 claimEpoch, uint256 maxEpoch);

    function checkpointToken() external;

    function checkpointTotalSupply() external;

    function claimable(uint256 tokenId) external view returns (uint256);

    function claim(uint256 tokenId) external returns (uint256);
}

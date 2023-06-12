// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRewardsDistributor {
    event CheckpointToken(uint256 time, uint256 tokens);
    event Claimed(uint256 indexed tokenId, uint256 indexed epochStart, uint256 indexed epochEnd, uint256 amount);

    error NotDepositor();

    /// @notice Called by Minter to notify Distributor of rebases
    function checkpointToken() external;

    /// @notice Returns the amount of rebases claimable for a given token ID
    /// @dev Allows claiming of rebases up to 50 epochs old
    /// @param tokenId The token ID to check
    /// @return The amount of rebases claimable for the given token ID
    function claimable(uint256 tokenId) external view returns (uint256);

    /// @notice Claims rebases for a given token ID
    /// @dev Allows claiming of rebases up to 50 epochs old
    /// @param tokenId The token ID to claim for
    /// @return The amount of rebases claimed
    function claim(uint256 tokenId) external returns (uint256);

    /// @notice Claims rebases for a list of token IDs
    /// @param tokenIds The token IDs to claim for
    /// @return Whether or not the claim succeeded
    function claimMany(uint256[] calldata tokenIds) external returns (bool);

    /// @notice Used to set minter once on initialization
    /// @dev Callable once by Minter only, Minter is immutable
    function setDepositor(address _depositor) external;
}

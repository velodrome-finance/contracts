// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IManagedRewardsFactory {
    /// @notice creates a LockedManagedReward and a FreeManagedReward contract for a managed veNFT
    /// @param voter Address of Voter.sol
    /// @return lockedManagedReward Address of LockedManagedReward contract created
    /// @return freeManagedReward   Address of FreeManagedReward contract created
    function createRewards(address voter) external returns (address lockedManagedReward, address freeManagedReward);
}

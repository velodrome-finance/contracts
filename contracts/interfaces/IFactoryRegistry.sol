// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IFactoryRegistry {
    error PathAlreadyApproved();
    error PathNotApproved();
    error SameAddress();
    error ZeroAddress();

    event Approve(address indexed pairFactory, address indexed votingRewardsFactory, address indexed gaugeFactory);
    event Unapprove(address indexed pairFactory, address indexed votingRewardsFactory, address indexed gaugeFactory);
    event SetManagedRewardsFactory(address indexed _newRewardsFactory);

    /// @notice Approve a set of factories used in Velodrome Protocol
    /// @dev Callable by onlyOwner
    /// @param pairFactory .
    /// @param votingRewardsFactory .
    /// @param gaugeFactory .
    function approve(
        address pairFactory,
        address votingRewardsFactory,
        address gaugeFactory
    ) external;

    /// @notice Unapprove a set of factories used in Velodrome Protocol
    /// @dev Callable by onlyOwner
    /// @param pairFactory .
    /// @param votingRewardsFactory .
    /// @param gaugeFactory .
    function unapprove(
        address pairFactory,
        address votingRewardsFactory,
        address gaugeFactory
    ) external;

    /// @notice Check if a set of factories are approved for use in Velodrome Protocol
    /// @param pairFactory .
    /// @param votingRewardsFactory .
    /// @param gaugeFactory .
    /// @return True if set of factories are approved, else false
    function isApproved(
        address pairFactory,
        address votingRewardsFactory,
        address gaugeFactory
    ) external view returns (bool);

    /// @notice Factory to create free and locked rewards for a managed veNFT
    function managedRewardsFactory() external view returns (address);

    /// @notice Set the rewards factory address
    /// @dev Callable by onlyOwner
    /// @param _newManagedRewardsFactory address of new managedRewardsFactory
    function setManagedRewardsFactory(address _newManagedRewardsFactory) external;
}

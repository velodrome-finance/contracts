// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IFactoryRegistry} from "./interfaces/IFactoryRegistry.sol";

/// @author Carter Carlson (@pegahcarter)
contract FactoryRegistry is IFactoryRegistry, Ownable {
    /// @dev poolFactory => votingRewardsFactory => gaugeFactory => true if path exists, else false
    mapping(address => mapping(address => mapping(address => bool))) private _approved;

    /// @dev factory to create free and locked rewards for a managed veNFT
    address private _managedRewardsFactory;

    // Velodrome protocol will always have a usable poolFactory, votingRewardsFactory, and gaugeFactory
    address public immutable fallbackPoolFactory;
    address public immutable fallbackVotingRewardsFactory;
    address public immutable fallbackGaugeFactory;

    constructor(
        address _fallbackPoolFactory,
        address _fallbackVotingRewardsFactory,
        address _fallbackGaugeFactory,
        address _newManagedRewardsFactory
    ) {
        fallbackPoolFactory = _fallbackPoolFactory;
        fallbackVotingRewardsFactory = _fallbackVotingRewardsFactory;
        fallbackGaugeFactory = _fallbackGaugeFactory;

        setManagedRewardsFactory(_newManagedRewardsFactory);
    }

    /// @inheritdoc IFactoryRegistry
    function approve(
        address poolFactory,
        address votingRewardsFactory,
        address gaugeFactory
    ) public onlyOwner {
        if (_approved[poolFactory][votingRewardsFactory][gaugeFactory]) revert PathAlreadyApproved();
        _approved[poolFactory][votingRewardsFactory][gaugeFactory] = true;
        emit Approve(poolFactory, votingRewardsFactory, gaugeFactory);
    }

    /// @inheritdoc IFactoryRegistry
    function unapprove(
        address poolFactory,
        address votingRewardsFactory,
        address gaugeFactory
    ) external onlyOwner {
        if (!_approved[poolFactory][votingRewardsFactory][gaugeFactory]) revert PathNotApproved();
        delete _approved[poolFactory][votingRewardsFactory][gaugeFactory];
        emit Unapprove(poolFactory, votingRewardsFactory, gaugeFactory);
    }

    /// @inheritdoc IFactoryRegistry
    function isApproved(
        address poolFactory,
        address votingRewardsFactory,
        address gaugeFactory
    ) external view returns (bool) {
        if (
            (poolFactory == fallbackPoolFactory) &&
            (votingRewardsFactory == fallbackVotingRewardsFactory) &&
            (gaugeFactory == fallbackGaugeFactory)
        ) return true;
        return _approved[poolFactory][votingRewardsFactory][gaugeFactory];
    }

    /// @inheritdoc IFactoryRegistry
    function managedRewardsFactory() external view returns (address) {
        return _managedRewardsFactory;
    }

    /// @inheritdoc IFactoryRegistry
    function setManagedRewardsFactory(address _newManagedRewardsFactory) public onlyOwner {
        if (_newManagedRewardsFactory == _managedRewardsFactory) revert SameAddress();
        if (_newManagedRewardsFactory == address(0)) revert ZeroAddress();
        _managedRewardsFactory = _newManagedRewardsFactory;
        emit SetManagedRewardsFactory(_newManagedRewardsFactory);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IFactoryRegistry} from "./interfaces/IFactoryRegistry.sol";

/// @author Carter Carlson (@pegahcarter)
contract FactoryRegistry is IFactoryRegistry, Ownable {
    /// @dev pairFactory => votingRewardsFactory => gaugeFactory => true if path exists, else false
    mapping(address => mapping(address => mapping(address => bool))) private _approved;

    /// @dev factory to create free and locked rewards for a managed veNFT
    address private _managedRewardsFactory;

    // Velodrome protocol will always have a usable pairFactory, votingRewardsFactory, and gaugeFactory
    address public immutable fallbackPairFactory;
    address public immutable fallbackVotingRewardsFactory;
    address public immutable fallbackGaugeFactory;

    constructor(
        address _fallbackPairFactory,
        address _fallbackVotingRewardsFactory,
        address _fallbackGaugeFactory,
        address _newManagedRewardsFactory
    ) {
        fallbackPairFactory = _fallbackPairFactory;
        fallbackVotingRewardsFactory = _fallbackVotingRewardsFactory;
        fallbackGaugeFactory = _fallbackGaugeFactory;

        setManagedRewardsFactory(_newManagedRewardsFactory);
    }

    /// @inheritdoc IFactoryRegistry
    function approve(
        address pairFactory,
        address votingRewardsFactory,
        address gaugeFactory
    ) public onlyOwner {
        require(!_approved[pairFactory][votingRewardsFactory][gaugeFactory], "FactoryRegistry: already approved");
        _approved[pairFactory][votingRewardsFactory][gaugeFactory] = true;
        emit Approve(pairFactory, votingRewardsFactory, gaugeFactory);
    }

    /// @inheritdoc IFactoryRegistry
    function unapprove(
        address pairFactory,
        address votingRewardsFactory,
        address gaugeFactory
    ) external onlyOwner {
        require(_approved[pairFactory][votingRewardsFactory][gaugeFactory], "FactoryRegistry: not approved");
        delete _approved[pairFactory][votingRewardsFactory][gaugeFactory];
        emit Unapprove(pairFactory, votingRewardsFactory, gaugeFactory);
    }

    /// @inheritdoc IFactoryRegistry
    function isApproved(
        address pairFactory,
        address votingRewardsFactory,
        address gaugeFactory
    ) external view returns (bool) {
        if (
            (pairFactory == fallbackPairFactory) &&
            (votingRewardsFactory == fallbackVotingRewardsFactory) &&
            (gaugeFactory == fallbackGaugeFactory)
        ) return true;
        return _approved[pairFactory][votingRewardsFactory][gaugeFactory];
    }

    /// @inheritdoc IFactoryRegistry
    function managedRewardsFactory() external view returns (address) {
        return _managedRewardsFactory;
    }

    /// @inheritdoc IFactoryRegistry
    function setManagedRewardsFactory(address _newManagedRewardsFactory) public onlyOwner {
        require(_newManagedRewardsFactory != _managedRewardsFactory, "FactoryRegistry: same address");
        require(_newManagedRewardsFactory != address(0), "FactoryRegistry: zero address");
        _managedRewardsFactory = _newManagedRewardsFactory;
        emit SetManagedRewardsFactory(_newManagedRewardsFactory);
    }
}

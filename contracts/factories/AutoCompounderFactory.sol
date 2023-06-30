// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IVoter} from "../interfaces/IVoter.sol";
import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";
import {IRouter} from "../interfaces/IRouter.sol";
import {IAutoCompounderFactory} from "../interfaces/factories/IAutoCompounderFactory.sol";
import {AutoCompounder} from "../AutoCompounder.sol";
import {CompoundOptimizer} from "../CompoundOptimizer.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @title AutoCompounderFactory
/// @author @pegahcarter
/// @notice Factory contract to create AutoCompounders and manage authorized callers of the AutoCompounders
contract AutoCompounderFactory is IAutoCompounderFactory {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @inheritdoc IAutoCompounderFactory
    uint256 public rewardAmount = 10 * 1e18;
    /// @inheritdoc IAutoCompounderFactory
    uint256 public constant MAX_REWARD_AMOUNT = 1_000 * 1e18;
    /// @inheritdoc IAutoCompounderFactory
    uint256 public constant MIN_REWARD_AMOUNT = 1e17;

    address public immutable forwarder;
    address public immutable router;
    address public immutable voter;
    address public immutable optimizer;
    IVotingEscrow public immutable ve;

    EnumerableSet.AddressSet private _autoCompounders;
    EnumerableSet.AddressSet private _keepers;

    constructor(address _forwarder, address _voter, address _router, address _optimizer) {
        forwarder = _forwarder;
        voter = _voter;
        router = _router;
        optimizer = _optimizer;

        ve = IVotingEscrow(IVoter(voter).ve());
    }

    /// @inheritdoc IAutoCompounderFactory
    function createAutoCompounder(address _admin, uint256 _tokenId) external returns (address autoCompounder) {
        if (_admin == address(0)) revert ZeroAddress();
        if (_tokenId == 0) revert TokenIdZero();
        if (!ve.isApprovedOrOwner(msg.sender, _tokenId)) revert TokenIdNotApproved();
        if (ve.escrowType(_tokenId) != IVotingEscrow.EscrowType.MANAGED) revert TokenIdNotManaged();

        // create the autocompounder contract
        autoCompounder = address(new AutoCompounder(forwarder, router, voter, optimizer, _admin));

        // transfer nft to autocompounder
        ve.safeTransferFrom(ve.ownerOf(_tokenId), autoCompounder, _tokenId);
        AutoCompounder(autoCompounder).initialize(_tokenId);

        _autoCompounders.add(autoCompounder);
        emit CreateAutoCompounder(msg.sender, _admin, autoCompounder);
    }

    /// @inheritdoc IAutoCompounderFactory
    function setRewardAmount(uint256 _rewardAmount) external {
        if (msg.sender != ve.team()) revert NotTeam();
        if (_rewardAmount == rewardAmount) revert AmountSame();
        if (_rewardAmount < MIN_REWARD_AMOUNT || _rewardAmount > MAX_REWARD_AMOUNT) revert AmountOutOfAcceptableRange();
        rewardAmount = _rewardAmount;
        emit SetRewardAmount(_rewardAmount);
    }

    // TODO: unit testing
    // TODO: natspec
    /// @inheritdoc IAutoCompounderFactory
    function addKeeper(address _keeper) external {
        if (msg.sender != ve.team()) revert NotTeam();
        if (_keeper == address(0)) revert ZeroAddress();
        if (isKeeper(_keeper)) revert KeeperAlreadyExists();
        _keepers.add(_keeper);
    }

    /// @inheritdoc IAutoCompounderFactory
    function removeKeeper(address _keeper) external {
        if (msg.sender != ve.team()) revert NotTeam();
        if (_keeper == address(0)) revert ZeroAddress();
        if (!isKeeper(_keeper)) revert KeeperDoesNotExist();
        _keepers.remove(_keeper);
    }

    /// @inheritdoc IAutoCompounderFactory
    function keepers() external view returns (address[] memory) {
        return _keepers.values();
    }

    /// @inheritdoc IAutoCompounderFactory
    function keepersLength() external view returns (uint256) {
        return _keepers.length();
    }

    /// @inheritdoc IAutoCompounderFactory
    function isKeeper(address _keeper) public view returns (bool) {
        return _keepers.contains(_keeper);
    }

    /// @inheritdoc IAutoCompounderFactory
    function autoCompounders() external view returns (address[] memory) {
        return _autoCompounders.values();
    }

    /// @inheritdoc IAutoCompounderFactory
    function autoCompoundersLength() external view returns (uint256) {
        return _autoCompounders.length();
    }

    /// @inheritdoc IAutoCompounderFactory
    function isAutoCompounder(address _autoCompounder) external view returns (bool) {
        return _autoCompounders.contains(_autoCompounder);
    }
}

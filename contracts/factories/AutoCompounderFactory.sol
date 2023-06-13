// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IVoter} from "../interfaces/IVoter.sol";
import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";
import {IRouter} from "../interfaces/IRouter.sol";
import {IAutoCompounderFactory} from "../interfaces/factories/IAutoCompounderFactory.sol";
import {AutoCompounder} from "../AutoCompounder.sol";
import {CompoundOptimizer} from "../CompoundOptimizer.sol";

contract AutoCompounderFactory is IAutoCompounderFactory {
    /// @notice The amount rewarded per token a caller earns from calling AutoCompounder.claimXAndCompound()
    uint256 public rewardAmount = 10 * 1e18;
    uint256 internal constant MAX_REWARD_AMOUNT = 1_000 * 1e18; // 1,000 VELO
    uint256 internal constant MIN_REWARD_AMOUNT = 1e17; // 0.1 VELO

    address public immutable forwarder;
    address public immutable router;
    address public immutable voter;
    address public immutable optimizer;
    IVotingEscrow public immutable ve;

    mapping(address => bool) public isAutoCompounder;

    constructor(address _forwarder, address _voter, address _router, address _optimizer) {
        forwarder = _forwarder;
        voter = _voter;
        router = _router;
        optimizer = _optimizer;

        ve = IVotingEscrow(IVoter(voter).ve());
    }

    function createAutoCompounder(address _admin, uint256 _tokenId) external returns (address autoCompounder) {
        if (_tokenId == 0) revert TokenIdZero();
        if (!ve.isApprovedOrOwner(msg.sender, _tokenId)) revert TokenIdNotApproved();
        if (ve.escrowType(_tokenId) != IVotingEscrow.EscrowType.MANAGED) revert TokenIdNotManaged();

        // create the autocompounder contract
        autoCompounder = address(new AutoCompounder(forwarder, router, voter, optimizer, _admin));

        // transfer nft to autocompounder
        ve.safeTransferFrom(ve.ownerOf(_tokenId), autoCompounder, _tokenId);
        AutoCompounder(autoCompounder).initialize(_tokenId);

        isAutoCompounder[autoCompounder] = true;
        emit CreateAutoCompounder(msg.sender, _admin, autoCompounder);
    }

    function setRewardAmount(uint256 _rewardAmount) external {
        if (msg.sender != ve.team()) revert NotTeam();
        if (_rewardAmount == rewardAmount) revert AmountSame();
        if (_rewardAmount < MIN_REWARD_AMOUNT || _rewardAmount > MAX_REWARD_AMOUNT) revert AmountOutOfAcceptableRange();
        rewardAmount = _rewardAmount;
        emit SetRewardAmount(_rewardAmount);
    }
}

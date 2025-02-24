// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {IVoter} from "../../interfaces/IVoter.sol";
import {IMinter} from "../../interfaces/IMinter.sol";
import {ISinkGauge} from "../../interfaces/sink/ISinkGauge.sol";
import {VelodromeTimeLibrary} from "../../libraries/VelodromeTimeLibrary.sol";

/// @title Velodrome Sink Gauge
/// @notice Sink Gauge contract to send emissions back to minter
contract SinkGauge is ISinkGauge, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;

    /// @inheritdoc ISinkGauge
    address public immutable rewardToken;
    /// @inheritdoc ISinkGauge
    address public immutable voter;
    /// @inheritdoc ISinkGauge
    address public immutable minter;
    /// @inheritdoc ISinkGauge
    uint256 public lockedRewards;
    /// @inheritdoc ISinkGauge
    mapping(uint256 _epochStart => uint256) public tokenRewardsPerEpoch;

    constructor(address _voter) {
        voter = _voter;
        minter = IVoter(_voter).minter();
        rewardToken = address(IMinter(minter).velo());
    }

    /// @inheritdoc ISinkGauge
    function left() external pure returns (uint256) {
        return 0;
    }

    /// @inheritdoc ISinkGauge
    function getReward(address) external {}

    /// @inheritdoc ISinkGauge
    function notifyRewardAmount(uint256 _amount) external nonReentrant {
        if (msg.sender != voter) revert NotVoter();
        if (_amount == 0) revert ZeroAmount();

        lockedRewards += _amount;
        uint256 epochStart = VelodromeTimeLibrary.epochStart({timestamp: block.timestamp});
        tokenRewardsPerEpoch[epochStart] = _amount;

        IERC20(rewardToken).safeTransferFrom({from: msg.sender, to: minter, value: _amount});

        emit NotifyReward({_from: msg.sender, _amount: _amount});
        emit ClaimRewards({_from: minter, _amount: _amount});
    }
}

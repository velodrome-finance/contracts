// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {IGaugeFactory} from "../interfaces/IGaugeFactory.sol";
import {Gauge} from "../Gauge.sol";

contract GaugeFactory is IGaugeFactory {
    function createGauge(
        address _pool,
        address _feesVotingReward,
        address _rewardToken,
        bool isPair
    ) external returns (address gauge) {
        gauge = address(new Gauge(_pool, _feesVotingReward, _rewardToken, msg.sender, isPair));
    }
}

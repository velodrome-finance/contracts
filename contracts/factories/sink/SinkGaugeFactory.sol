// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import {SinkGauge} from "../../gauges/sink/SinkGauge.sol";
import {ISinkGaugeFactory} from "../../interfaces/factories/sink/ISinkGaugeFactory.sol";

/// @title Velodrome Sink Gauge Factory
contract SinkGaugeFactory is ISinkGaugeFactory {
    /// @inheritdoc ISinkGaugeFactory
    address public immutable gauge;

    constructor(address _voter) {
        gauge = address(new SinkGauge({_voter: _voter}));
    }

    /// @inheritdoc ISinkGaugeFactory
    function createGauge(address, address, address, address, bool) external view returns (address) {
        return gauge;
    }
}

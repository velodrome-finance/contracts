// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import {SinkPool} from "../../sink/SinkPool.sol";
import {ISinkPoolFactory} from "../../interfaces/factories/sink/ISinkPoolFactory.sol";

/// @title Velodrome Sink Pool Factory
contract SinkPoolFactory is ISinkPoolFactory {
    /// @inheritdoc ISinkPoolFactory
    address public immutable pool;

    constructor() {
        pool = address(new SinkPool());
        emit PoolCreated(address(0), address(0), true, pool, 0);
    }

    /// @inheritdoc ISinkPoolFactory
    function isPair(address) external pure returns (bool) {
        return false;
    }

    /// @inheritdoc ISinkPoolFactory
    function isPool(address) external pure returns (bool) {
        return false;
    }
}

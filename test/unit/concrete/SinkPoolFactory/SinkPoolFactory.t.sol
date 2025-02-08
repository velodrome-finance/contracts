// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "test/BaseTest.sol";

contract SinkPoolFactoryTest is BaseTest {
    function _setUp() public override {
        sinkPoolFactory = new SinkPoolFactory();
    }

    function test_InitialState() public view {
        assertNotEq(sinkPoolFactory.pool(), address(0));
        assertFalse(sinkPoolFactory.isPool(sinkPoolFactory.pool()));
        assertFalse(sinkPoolFactory.isPair(sinkPoolFactory.pool()));
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "test/BaseTest.sol";

contract SinkGaugeFactoryTest is BaseTest {
    function _setUp() public override {
        sinkGaugeFactory = new SinkGaugeFactory({_voter: address(voter)});
    }

    function test_InitialState() public {
        assertNotEq(sinkGaugeFactory.gauge(), address(0));
        assertEq(
            sinkGaugeFactory.createGauge(address(0), address(0), address(0), address(0), false),
            sinkGaugeFactory.gauge()
        );
    }
}

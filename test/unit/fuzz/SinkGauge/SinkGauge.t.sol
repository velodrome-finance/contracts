// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "test/BaseTest.sol";

contract SinkGaugeTest is BaseTest {
    function _setUp() public override {
        vm.prank(address(gaugeFactory));
        sinkGauge = new SinkGauge({_voter: address(voter)});
    }
}

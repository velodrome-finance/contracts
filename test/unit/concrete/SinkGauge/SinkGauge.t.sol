// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "test/BaseTest.sol";

contract SinkGaugeTest is BaseTest {
    function _setUp() public override {
        vm.prank(address(gaugeFactory));
        sinkGauge = new SinkGauge({_voter: address(voter)});
    }

    function test_InitialState() public {
        assertEq(sinkGauge.rewardToken(), address(VELO));
        assertEq(sinkGauge.voter(), address(voter));
        assertEq(sinkGauge.minter(), address(minter));
        assertEq(sinkGauge.lockedRewards(), 0);
    }
}

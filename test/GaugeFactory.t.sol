// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "./BaseTest.sol";
import {IGaugeFactory} from "contracts/interfaces/factories/IGaugeFactory.sol";

contract GaugeFactoryTest is BaseTest {
    address public notifyAdmin;

    event SetNotifyAdmin(address indexed notifyAdmin);

    function _setUp() public override {
        notifyAdmin = gaugeFactory.notifyAdmin();
    }

    function testCannotSetNotifyAdminIfNotNotifyAdmin() public {
        vm.startPrank(address(owner2));
        vm.expectRevert(IGaugeFactory.NotAuthorized.selector);
        gaugeFactory.setNotifyAdmin(address(owner2));
    }

    function testCannotSetNotifyAdminIfZeroAddress() public {
        vm.startPrank(notifyAdmin);
        vm.expectRevert(IGaugeFactory.ZeroAddress.selector);
        gaugeFactory.setNotifyAdmin(address(0));
    }

    function testSetNotifyAdmin() public {
        vm.startPrank(notifyAdmin);
        vm.expectEmit(address(gaugeFactory));
        emit SetNotifyAdmin(address(owner2));
        gaugeFactory.setNotifyAdmin(address(owner2));

        assertEq(gaugeFactory.notifyAdmin(), address(owner2));
    }
}

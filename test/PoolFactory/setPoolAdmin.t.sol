// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../BaseTest.sol";

contract SetPoolAdminTest is BaseTest {
    event SetPoolAdmin(address indexed poolAdmin);

    function test_InitialState() public {
        assertEq(factory.poolAdmin(), address(this));
    }

    function test_SetPoolAdmin() public {
        vm.expectEmit(true, false, false, false);
        emit SetPoolAdmin({poolAdmin: address(1)});
        factory.setPoolAdmin(address(1));

        assertEq(factory.poolAdmin(), address(1));
    }

    function test_RevertIf_ZeroAddress() public {
        vm.expectRevert(IPoolFactory.ZeroAddress.selector);
        factory.setPoolAdmin(address(0));
    }

    function test_RevertIf_NotPoolAdmin() public {
        vm.expectRevert(IPoolFactory.NotPoolAdmin.selector);
        vm.prank(address(1));
        factory.setPoolAdmin(address(1));
    }
}

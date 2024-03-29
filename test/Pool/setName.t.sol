// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../BaseTest.sol";

contract SetNameTest is BaseTest {
    function test_InitialState() public {
        assertEq(pool.name(), "StableV2 AMM - USDC/FRAX");
    }

    function test_SetName() public {
        pool.setName("Some new name");
        assertEq(pool.name(), "Some new name");
    }

    function test_RevertIf_NotPoolAdmin() public {
        vm.prank(address(owner2));
        vm.expectRevert(IPoolFactory.NotPoolAdmin.selector);
        pool.setName("Some new name");
    }
}

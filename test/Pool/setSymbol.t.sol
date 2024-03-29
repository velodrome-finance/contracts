// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../BaseTest.sol";

contract SetSymbolTest is BaseTest {
    function test_InitialState() public {
        assertEq(pool.symbol(), "sAMMV2-USDC/FRAX");
    }

    function test_SetSymbol() public {
        pool.setSymbol("Some new symbol");
        assertEq(pool.symbol(), "Some new symbol");
    }

    function test_RevertIf_NotPoolAdmin() public {
        vm.prank(address(owner2));
        vm.expectRevert(IPoolFactory.NotPoolAdmin.selector);
        pool.setSymbol("Some new symbol");
    }
}

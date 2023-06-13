// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./BaseTest.sol";

contract VeloTest is BaseTest {
    Velo token;

    function _setUp() public override {
        token = new Velo();
    }

    function testCannotSetMinterIfNotMinter() public {
        vm.prank(address(owner2));
        vm.expectRevert(IVelo.NotMinter.selector);
        token.setMinter(address(owner3));
    }

    function testSetMinter() public {
        token.setMinter(address(owner3));

        assertEq(token.minter(), address(owner3));
    }

    function testCannotSetSinkManagerIfNotOwner() public {
        vm.prank(address(owner2));
        vm.expectRevert(IVelo.NotOwner.selector);
        token.setSinkManager(address(owner3));
    }

    function testCannotSetSinkManagerIfAlreadySet() public {
        token.setSinkManager(address(owner2));
        assertEq(token.sinkManager(), address(owner2));

        vm.expectRevert(IVelo.SinkManagerAlreadySet.selector);
        token.setSinkManager(address(owner2));
    }

    function testSetSinkManager() public {
        token.setSinkManager(address(owner2));

        assertEq(token.sinkManager(), address(owner2));
    }

    function testCannotMintIfNotMinterOrSinkManager() public {
        vm.prank(address(owner2));
        vm.expectRevert(IVelo.NotMinterOrSinkManager.selector);
        token.mint(address(owner2), TOKEN_1);
    }
}

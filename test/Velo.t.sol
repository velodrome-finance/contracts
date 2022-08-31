// 1:1 with Hardhat test
pragma solidity 0.8.13;

import "./BaseTest.sol";

contract VeloTest is BaseTest {
    Velo token;

    function _setUp() public override {
        token = new Velo();
    }

    function testCannotSetMinterIfNotMinter() public {
        vm.prank(address(owner2));
        vm.expectRevert("Velo: not minter");
        token.setMinter(address(owner3));
    }

    function testSetMinter() public {
        token.setMinter(address(owner3));

        assertEq(token.minter(), address(owner3));
    }

    function testCannotSetSinkManagerIfNotOwner() public {
        vm.prank(address(owner2));
        vm.expectRevert("Velo: not owner");
        token.setSinkManager(address(owner3));
    }

    function testCannotSetSinkManagerIfAlreadySet() public {
        token.setSinkManager(address(owner2));
        assertEq(token.sinkManager(), address(owner2));

        vm.expectRevert("Velo: sink manager already set");
        token.setSinkManager(address(owner2));
    }

    function testSetSinkManager() public {
        token.setSinkManager(address(owner2));

        assertEq(token.sinkManager(), address(owner2));
    }

    function testCannotMintIfNotMinterOrSinkManager() public {
        vm.prank(address(owner2));
        vm.expectRevert("Velo: not minter or sink manager");
        token.mint(address(owner2), TOKEN_1);
    }
}

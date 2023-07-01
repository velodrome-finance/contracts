// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./BaseTest.sol";
import "contracts/AutoCompounder.sol";
import "contracts/CompoundOptimizer.sol";
import "contracts/factories/AutoCompounderFactory.sol";

contract AutoCompounderFactoryTest is BaseTest {
    uint256 tokenId;
    uint256 mTokenId;

    AutoCompounderFactory autoCompounderFactory;
    AutoCompounder autoCompounder;
    CompoundOptimizer optimizer;

    constructor() {
        deploymentType = Deployment.FORK;
    }

    function _setUp() public override {
        escrow.setTeam(address(owner4));
        optimizer = new CompoundOptimizer(
            address(USDC),
            address(WETH),
            address(FRAX), // OP
            address(VELO),
            address(vFactory),
            address(factory),
            address(router)
        );
        autoCompounderFactory = new AutoCompounderFactory(
            address(forwarder),
            address(voter),
            address(router),
            address(optimizer)
        );
    }

    function testCannotCreateAutoCompounderWithNoAdmin() public {
        vm.expectRevert(IAutoCompounderFactory.ZeroAddress.selector);
        autoCompounderFactory.createAutoCompounder(address(0), 1);
    }

    function testCannotCreateAutoCompounderWithZeroTokenId() public {
        vm.expectRevert(IAutoCompounderFactory.TokenIdZero.selector);
        autoCompounderFactory.createAutoCompounder(address(1), 0);
    }

    function testCannotCreateAutoCompounderIfNotApprovedSender() public {
        vm.prank(escrow.allowedManager());
        mTokenId = escrow.createManagedLockFor(address(owner));
        vm.expectRevert(IAutoCompounderFactory.TokenIdNotApproved.selector);
        vm.prank(address(owner2));
        autoCompounderFactory.createAutoCompounder(address(1), mTokenId);
    }

    function testCannotCreateAutoCompounderIfTokenNotManaged() public {
        VELO.approve(address(escrow), TOKEN_1);
        tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        vm.expectRevert(IAutoCompounderFactory.TokenIdNotManaged.selector);
        autoCompounderFactory.createAutoCompounder(address(1), tokenId); // normal

        vm.prank(escrow.allowedManager());
        mTokenId = escrow.createManagedLockFor(address(owner));
        voter.depositManaged(tokenId, mTokenId);
        vm.expectRevert(IAutoCompounderFactory.TokenIdNotManaged.selector);
        autoCompounderFactory.createAutoCompounder(address(1), tokenId); // locked
    }

    function testCreateAutoCompounder() public {}

    function testCannotAddHighLiquidityTokenIfNotTeam() public {
        assertTrue(msg.sender != escrow.team());
        vm.expectRevert(IAutoCompounderFactory.NotTeam.selector);
        autoCompounderFactory.addHighLiquidityToken(address(USDC));
    }

    function testCannotAddHighLiquidityTokenIfZeroAddress() public {
        vm.prank(escrow.team());
        vm.expectRevert(IAutoCompounderFactory.ZeroAddress.selector);
        autoCompounderFactory.addHighLiquidityToken(address(0));
    }

    function testCannotAddHighLiquidityTokenIfAlreadyExists() public {
        vm.startPrank(escrow.team());
        autoCompounderFactory.addHighLiquidityToken(address(USDC));
        vm.expectRevert(IAutoCompounderFactory.HighLiquidityTokenAlreadyExists.selector);
        autoCompounderFactory.addHighLiquidityToken(address(USDC));
    }

    function testAddHighLiquidityToken() public {
        assertFalse(autoCompounderFactory.isHighLiquidityToken(address(USDC)));
        assertEq(autoCompounderFactory.highLiquidityTokens(), new address[](0));
        assertEq(autoCompounderFactory.highLiquidityTokensLength(), 0);
        vm.prank(escrow.team());
        autoCompounderFactory.addHighLiquidityToken(address(USDC));
        assertTrue(autoCompounderFactory.isHighLiquidityToken(address(USDC)));
        address[] memory highLiquidityTokens = new address[](1);
        highLiquidityTokens[0] = address(USDC);
        assertEq(autoCompounderFactory.highLiquidityTokens(), highLiquidityTokens);
        assertEq(autoCompounderFactory.highLiquidityTokensLength(), 1);
    }

    function testCannotAddKeeperIfNotTeam() public {}

    function testCannotAddKeeperIfZeroAddress() public {}

    function testCannotAddKeeperIfKeeperAlreadyExists() public {}

    function testAddKeeper() public {}

    function testCannotRemoveKeeperIfNotTeam() public {}

    function testCannotRemoveKeeperIfZeroAddress() public {}

    function testCannotRemoveKeeperIfKeeperDoesntExist() public {}

    function testRemoveKeeper() public {}
}

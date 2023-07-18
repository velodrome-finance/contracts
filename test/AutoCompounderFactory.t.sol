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
            address(factory),
            address(router)
        );
        autoCompounderFactory = new AutoCompounderFactory(
            address(forwarder),
            address(voter),
            address(router),
            address(optimizer),
            address(factoryRegistry),
            new address[](0)
        );
    }

    function testCreateAutoCompounderFactoryWithHighLiquidityTokens() public {
        address[] memory highLiquidityTokens = new address[](2);
        highLiquidityTokens[0] = address(FRAX);
        highLiquidityTokens[1] = address(USDC);
        autoCompounderFactory = new AutoCompounderFactory(
            address(forwarder),
            address(voter),
            address(router),
            address(optimizer),
            address(factoryRegistry),
            highLiquidityTokens
        );
        assertTrue(autoCompounderFactory.isHighLiquidityToken(address(FRAX)));
        assertTrue(autoCompounderFactory.isHighLiquidityToken(address(USDC)));
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
        vm.startPrank(address(owner));
        escrow.approve(address(autoCompounderFactory), mTokenId);
        escrow.setApprovalForAll(address(autoCompounderFactory), true);
        vm.stopPrank();
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

    function testCreateAutoCompounder() public {
        vm.prank(escrow.allowedManager());
        mTokenId = escrow.createManagedLockFor(address(owner));

        assertEq(autoCompounderFactory.autoCompoundersLength(), 0);

        vm.startPrank(address(owner));
        escrow.approve(address(autoCompounderFactory), mTokenId);
        autoCompounder = AutoCompounder(autoCompounderFactory.createAutoCompounder(address(owner), mTokenId));

        assertFalse(address(autoCompounder) == address(0));
        assertEq(autoCompounderFactory.autoCompoundersLength(), 1);
        address[] memory autoCompounders = autoCompounderFactory.autoCompounders();
        assertEq(address(autoCompounder), autoCompounders[0]);
        assertEq(escrow.balanceOf(address(autoCompounder)), 1);
        assertEq(escrow.ownerOf(mTokenId), address(autoCompounder));

        assertEq(address(autoCompounder.autoCompounderFactory()), address(autoCompounderFactory));
        assertEq(address(autoCompounder.router()), address(router));
        assertEq(address(autoCompounder.voter()), address(voter));
        assertEq(address(autoCompounder.optimizer()), address(optimizer));
        assertEq(address(autoCompounder.ve()), voter.ve());
        assertEq(address(autoCompounder.velo()), address(VELO));
        assertEq(address(autoCompounder.distributor()), escrow.distributor());

        assertEq(VELO.allowance(address(autoCompounder), address(escrow)), type(uint256).max);
        assertTrue(autoCompounder.hasRole(0x00, address(owner))); // DEFAULT_ADMIN_ROLE
        assertTrue(autoCompounder.hasRole(keccak256("ALLOWED_CALLER"), address(owner)));

        assertEq(autoCompounder.tokenId(), mTokenId);
    }

    function testCreateAutoCompounderByApproved() public {
        vm.prank(escrow.allowedManager());
        mTokenId = escrow.createManagedLockFor(address(owner));

        assertEq(autoCompounderFactory.autoCompoundersLength(), 0);

        vm.startPrank(address(owner));
        escrow.setApprovalForAll(address(autoCompounderFactory), true);
        escrow.approve(address(owner2), mTokenId);
        vm.stopPrank();
        vm.prank(address(owner2));
        autoCompounder = AutoCompounder(autoCompounderFactory.createAutoCompounder(address(owner), mTokenId));

        assertFalse(address(autoCompounder) == address(0));
        assertEq(autoCompounderFactory.autoCompoundersLength(), 1);
        address[] memory autoCompounders = autoCompounderFactory.autoCompounders();
        assertEq(address(autoCompounder), autoCompounders[0]);
        assertEq(escrow.balanceOf(address(autoCompounder)), 1);
        assertEq(escrow.ownerOf(mTokenId), address(autoCompounder));
        assertEq(autoCompounder.tokenId(), mTokenId);
    }

    function testCreateAutoCompounderByApprovedForAll() public {
        vm.prank(escrow.allowedManager());
        mTokenId = escrow.createManagedLockFor(address(owner));

        assertEq(autoCompounderFactory.autoCompoundersLength(), 0);

        vm.startPrank(address(owner));
        escrow.approve(address(autoCompounderFactory), mTokenId);
        escrow.setApprovalForAll(address(owner2), true);
        vm.stopPrank();
        vm.prank(address(owner2));
        autoCompounder = AutoCompounder(autoCompounderFactory.createAutoCompounder(address(owner), mTokenId));

        assertFalse(address(autoCompounder) == address(0));
        assertEq(autoCompounderFactory.autoCompoundersLength(), 1);
        address[] memory autoCompounders = autoCompounderFactory.autoCompounders();
        assertEq(address(autoCompounder), autoCompounders[0]);
        assertEq(escrow.balanceOf(address(autoCompounder)), 1);
        assertEq(escrow.ownerOf(mTokenId), address(autoCompounder));
        assertEq(autoCompounder.tokenId(), mTokenId);
    }

    function testCannotAddHighLiquidityTokenIfNotTeam() public {
        vm.startPrank(address(owner2));
        assertTrue(msg.sender != factoryRegistry.owner());
        vm.expectRevert(IAutoCompounderFactory.NotTeam.selector);
        autoCompounderFactory.addHighLiquidityToken(address(USDC));
    }

    function testCannotAddHighLiquidityTokenIfZeroAddress() public {
        vm.prank(factoryRegistry.owner());
        vm.expectRevert(IAutoCompounderFactory.ZeroAddress.selector);
        autoCompounderFactory.addHighLiquidityToken(address(0));
    }

    function testCannotAddHighLiquidityTokenIfAlreadyExists() public {
        vm.startPrank(factoryRegistry.owner());
        autoCompounderFactory.addHighLiquidityToken(address(USDC));
        vm.expectRevert(IAutoCompounderFactory.HighLiquidityTokenAlreadyExists.selector);
        autoCompounderFactory.addHighLiquidityToken(address(USDC));
    }

    function testAddHighLiquidityToken() public {
        assertFalse(autoCompounderFactory.isHighLiquidityToken(address(USDC)));
        assertEq(autoCompounderFactory.highLiquidityTokens(), new address[](0));
        assertEq(autoCompounderFactory.highLiquidityTokensLength(), 0);
        vm.prank(factoryRegistry.owner());
        autoCompounderFactory.addHighLiquidityToken(address(USDC));
        assertTrue(autoCompounderFactory.isHighLiquidityToken(address(USDC)));
        address[] memory highLiquidityTokens = new address[](1);
        highLiquidityTokens[0] = address(USDC);
        assertEq(autoCompounderFactory.highLiquidityTokens(), highLiquidityTokens);
        assertEq(autoCompounderFactory.highLiquidityTokensLength(), 1);
    }

    function testCannotAddKeeperIfNotTeam() public {
        vm.startPrank(address(owner2));
        assertTrue(msg.sender != factoryRegistry.owner());
        vm.expectRevert(IAutoCompounderFactory.NotTeam.selector);
        autoCompounderFactory.addKeeper(address(owner2));
    }

    function testCannotAddKeeperIfZeroAddress() public {
        vm.prank(factoryRegistry.owner());
        vm.expectRevert(IAutoCompounder.ZeroAddress.selector);
        autoCompounderFactory.addKeeper(address(0));
    }

    function testCannotAddKeeperIfKeeperAlreadyExists() public {
        vm.startPrank(factoryRegistry.owner());
        autoCompounderFactory.addKeeper(address(owner));
        vm.expectRevert(IAutoCompounderFactory.KeeperAlreadyExists.selector);
        autoCompounderFactory.addKeeper(address(owner));
    }

    function testAddKeeper() public {
        assertEq(autoCompounderFactory.keepersLength(), 0);
        assertEq(autoCompounderFactory.keepers(), new address[](0));
        assertFalse(autoCompounderFactory.isKeeper(address(owner)));

        vm.prank(factoryRegistry.owner());
        autoCompounderFactory.addKeeper(address(owner));

        assertEq(autoCompounderFactory.keepersLength(), 1);
        address[] memory keepers = autoCompounderFactory.keepers();
        assertEq(keepers.length, 1);
        assertEq(keepers[0], address(owner));
        assertTrue(autoCompounderFactory.isKeeper(address(owner)));
    }

    function testCannotRemoveKeeperIfNotTeam() public {
        vm.prank(address(owner2));
        vm.expectRevert(IAutoCompounderFactory.NotTeam.selector);
        autoCompounderFactory.removeKeeper(address(owner));
    }

    function testCannotRemoveKeeperIfZeroAddress() public {
        vm.prank(factoryRegistry.owner());
        vm.expectRevert(IAutoCompounderFactory.ZeroAddress.selector);
        autoCompounderFactory.removeKeeper(address(0));
    }

    function testCannotRemoveKeeperIfKeeperDoesntExist() public {
        vm.prank(factoryRegistry.owner());
        vm.expectRevert(IAutoCompounderFactory.KeeperDoesNotExist.selector);
        autoCompounderFactory.removeKeeper(address(owner));
    }

    function testRemoveKeeper() public {
        vm.startPrank(factoryRegistry.owner());

        autoCompounderFactory.addKeeper(address(owner));
        autoCompounderFactory.removeKeeper(address(owner));

        assertEq(autoCompounderFactory.keepersLength(), 0);
        assertEq(autoCompounderFactory.keepers(), new address[](0));
        assertFalse(autoCompounderFactory.isKeeper(address(owner)));
    }
}

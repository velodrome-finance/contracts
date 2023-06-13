// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./BaseTest.sol";

contract SinkManagerTest is BaseTest {
    // veNFTv1 tokenIds
    uint256 tokenId1;
    uint256 tokenId2;
    uint256 tokenId3;

    constructor() {
        deploymentType = Deployment.FORK;
    }

    function _setUp() public override {
        // Create some veNFTs
        vVELO.approve(address(vEscrow), TOKEN_1);
        tokenId1 = vEscrow.create_lock(TOKEN_1 / 4, 4 * 365 * 86400);
        vm.startPrank(address(owner2));
        vVELO.approve(address(vEscrow), TOKEN_1);
        tokenId2 = vEscrow.create_lock(TOKEN_1, 4 * 365 * 86400);
        vm.stopPrank();
        vm.startPrank(address(owner3));
        vVELO.approve(address(vEscrow), TOKEN_1);
        tokenId3 = vEscrow.create_lock(TOKEN_1, 4 * 365 * 86400);
        vm.stopPrank();
        skip(1);

        // seed gauge with rewards, note voter already has maximum approval for gauge
        vm.prank(address(vVoter));
        IGaugeV1(gaugeSinkDrain).notifyRewardAmount(address(vVELO), TOKEN_1);

        skip(1);
        vm.roll(block.number + 1);
    }

    // --------------------------------------------------------------------
    // Conversion methods
    // --------------------------------------------------------------------

    function testCannotConvertIfOwnedTokenIdNotSet() external {
        // Create new sinkManager
        SinkManager newSinkManager = new SinkManager(
            address(forwarder),
            address(sinkDrain),
            facilitatorImplementation,
            address(voter),
            address(vVELO),
            address(vVELO),
            address(vEscrow),
            address(escrow),
            address(vDistributor)
        );

        // Fail if attempting to convert vEscrow
        vm.expectRevert(ISinkManager.TokenIdNotSet.selector);
        newSinkManager.convertVe(tokenId1);

        // Fail if attempting to convert velo
        uint256 amount = TOKEN_1 / 4;
        vVELO.approve(address(sinkManager), amount);
        vm.expectRevert(ISinkManager.TokenIdNotSet.selector);
        newSinkManager.convertVELO(amount);
    }

    function testCannotConvertVeNotApproved() external {
        vm.startPrank(address(owner2));
        vm.expectRevert(ISinkManager.NFTNotApproved.selector);
        sinkManager.convertVe(tokenId2);
    }

    function testCannotConvertVeExpired() external {
        // fast-fwd to after lock expires
        vm.warp(block.timestamp + 4 * 365 * 86400 + 1);
        vm.startPrank(address(owner2));
        vEscrow.approve(address(sinkManager), tokenId2);
        vm.expectRevert(ISinkManager.NFTExpired.selector);
        sinkManager.convertVe(tokenId2);
    }

    function testCannotConvertVeAlreadyConverted() external {
        vm.startPrank(address(owner2));
        vEscrow.approve(address(sinkManager), tokenId2);
        sinkManager.convertVe(tokenId2);
        vm.expectRevert(ISinkManager.NFTAlreadyConverted.selector);
        sinkManager.convertVe(tokenId2);
        vm.stopPrank();
    }

    // NOTE: This compares user points of v1 veNFT *after* convertVe()
    function testConvertVe() external {
        // pre-loading veNFTv1 balances of sinkManager-owned vEscrow
        (int128 lockAmountSink, uint256 lockEndSink) = vEscrow.locked(ownedTokenId);
        // pre-loading veNFTv1 balances of vEscrow to convert
        (int128 lockAmount, uint256 lockEnd) = vEscrow.locked(tokenId2);
        uint256 beforeSupply = VELO.totalSupply();

        // convert the vEscrow
        vm.startPrank(address(owner2));
        vEscrow.approve(address(sinkManager), tokenId2);
        uint256 tokenIdV2 = sinkManager.convertVe(tokenId2);

        // Ensure veNFTv1 tokenId2 was burned from merge
        assertEq(vEscrow.ownerOf(tokenId2), address(0));

        // Ensure owned vEscrow lock values change accordingly
        (int128 lockAmountSinkAfter, uint256 lockEndSinkAfter) = vEscrow.locked(ownedTokenId);
        assertEq(lockAmountSinkAfter, lockAmountSink + lockAmount);
        assertEq(lockEndSink, lockEndSinkAfter);

        // Ensure VELOv2 minted == lock amount
        assertEq(VELO.totalSupply() - beforeSupply, uint256(int256(lockAmount)));
        assertEq(VELO.balanceOf(address(escrow)), uint256(int256(lockAmount)));

        // Ensure supply tracked in veNFTv2 increases by locked amount
        assertEq(escrow.supply(), uint256(int256(lockAmount)));

        // Ensure veNFTv2 Point == veNFTv1 Point

        // 1. Ensure voting power is accurate

        // NOTE: we are looking at tokenId3 which has the same balance of tokenId2 but has not
        // been zero'd out from the merge like tokenId2
        uint256 balanceV1 = vEscrow.balanceOfNFT(tokenId3);
        uint256 balanceV2 = escrow.balanceOfNFT(tokenIdV2);
        assertEq(balanceV1, balanceV2);

        // Ensure that the user point epoch uses the first index
        uint256 lastEpochStoredV2 = escrow.userPointEpoch(tokenIdV2);
        // Ensure that the user point epoch uses the first index
        assertEq(lastEpochStoredV2, 1);

        /*
         2. Comparing point history
            - bias should change from checkpointing v2 veNFT at a newer timestamp (ts + 1)
            - slope should not change
            - timestamp should be the block timestamp, which is two seconds after original timestamp
                    as we have skipped forward two seconds in `skip()`
            - blk should increase by 1 from `vm.roll()`

        NOTE: using tokenId3 again, see above
        */

        uint256 lastEpochStored = vEscrow.user_point_epoch(tokenId3);
        IVotingEscrowV1.Point memory pt1 = vEscrow.user_point_history(tokenId3, lastEpochStored);
        lastEpochStoredV2 = escrow.userPointEpoch(tokenIdV2);
        IVotingEscrow.UserPoint memory pt2 = escrow.userPointHistory(tokenIdV2, lastEpochStoredV2);
        assertGt(pt1.bias, pt2.bias);
        assertEq(pt1.slope, pt2.slope);
        assertEq(pt1.ts + 2, pt2.ts);
        assertEq(pt2.ts, block.timestamp);
        assertEq(pt1.blk + 1, pt2.blk);
        assertEq(pt2.blk, block.number);

        // Ensure veNFTv2 LockedBalance == veNFTv1 LockedBalance
        IVotingEscrow.LockedBalance memory locked2;
        locked2 = escrow.locked(tokenIdV2);
        assertEq(lockEnd, locked2.end);
        assertEq(lockAmount, locked2.amount);

        // Ensure conversion of vEscrow is stored
        assertEq(sinkManager.conversions(tokenId2), tokenIdV2);
        assertTrue(sinkManager.facilitators(tokenId2) != address(0));
        assertEq(sinkManager.captured(block.timestamp), TOKEN_1);
    }

    function testConvertVeUsesNewFacilitators() external {
        vEscrow.approve(address(sinkManager), tokenId1);
        sinkManager.convertVe(tokenId1);

        vm.startPrank(address(owner2));
        vEscrow.approve(address(sinkManager), tokenId2);
        sinkManager.convertVe(tokenId2);
        vm.stopPrank();

        assertTrue(sinkManager.facilitators(tokenId1) != address(0));
        assertTrue(sinkManager.facilitators(tokenId2) != address(0));
        assertTrue(sinkManager.facilitators(tokenId1) != sinkManager.facilitators(tokenId2));
    }

    function testConvertVeRemovesFacilitatorApproval() external {
        assertEq(vEscrow.getApproved(ownedTokenId), address(0));
        vEscrow.approve(address(sinkManager), tokenId1);
        sinkManager.convertVe(tokenId1);

        assertEq(vEscrow.getApproved(ownedTokenId), address(0));
    }

    function testConvertVeExtendLockOfOwnedTokenId() external {
        // fast fwd a little
        skip(1 weeks);

        // make a new veNFT which has an expiration date later than the ownedTokenId
        uint256 tokenId = vEscrow.create_lock(TOKEN_1 / 4, 4 * 365 * 86400);

        // Ensure lock date of newly created vEscrow surpasses locked veNFT
        (int128 lockAmount, uint256 lockEnd) = vEscrow.locked(tokenId);
        (int128 lockAmountSink, uint256 lockEndSink) = vEscrow.locked(ownedTokenId);
        assertGt(lockEnd, lockEndSink);

        // Convert the vEscrow
        vEscrow.approve(address(sinkManager), tokenId);
        sinkManager.convertVe(tokenId);

        // Ensure owned vEscrow lock values change accordingly
        (int128 lockAmountSinkAfter, uint256 lockEndSinkAfter) = vEscrow.locked(ownedTokenId);
        assertEq(lockAmountSinkAfter, lockAmountSink + lockAmount);
        assertEq(lockEnd, lockEndSinkAfter);
        assertEq(sinkManager.captured(block.timestamp), TOKEN_1 / 4);
    }

    function testConvertVELO() external {
        // pre-checks
        (int128 lockAmount, uint256 lockEnd) = vEscrow.locked(ownedTokenId);
        uint256 veloBalanceOwner = vVELO.balanceOf(address(owner));
        uint256 veloV2BalanceOwner = VELO.balanceOf(address(owner));
        uint256 veloBalanceVe = vVELO.balanceOf(address(vEscrow));

        uint256 amount = TOKEN_1 / 4;
        vVELO.approve(address(sinkManager), amount);
        sinkManager.convertVELO(amount);

        assertEq(sinkManager.captured(block.timestamp), TOKEN_1 / 4);
        // Ensure vVELO was transferred from user to veNFTv1
        assertEq(veloBalanceOwner - amount, vVELO.balanceOf(address(owner)));
        assertEq(veloBalanceVe + amount, vVELO.balanceOf(address(vEscrow)));

        // Ensure v1 vEscrow lock amount increases
        (int128 lockAmountAfter, uint256 lockEndAfter) = vEscrow.locked(ownedTokenId);
        assertEq(lockAmountAfter, lockAmount + int128(int256(amount)));
        // Lock time shouldn't change from increase_amount
        assertEq(lockEnd, lockEndAfter);

        // Ensure VELOv2 was minted to owner
        assertEq(veloV2BalanceOwner + amount, VELO.balanceOf(address(owner)));
    }

    function testPoolConverter() external {
        // Ensure the factory recognized the sinkConverter
        assertTrue(factory.isPool(address(sinkConverter)));

        // Ensure the router shows the correct pool for the sinkConverter
        address routerPool = router.poolFor(address(vVELO), address(VELO), false, address(0));
        assertGt(uint256(uint160(routerPool)), 0);
        assertEq(routerPool, address(sinkConverter));

        // Create route and assert the amount out returned between the router and pool is the same
        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route(address(vVELO), address(VELO), false, address(0));
        uint256 expectedAmountOut = sinkConverter.getAmountOut(TOKEN_1, address(vVELO));
        assertEq(expectedAmountOut, router.getAmountsOut(TOKEN_1, routes)[1]);
        assertEq(expectedAmountOut, TOKEN_1);

        // convert velo to v2
        uint256 balanceBefore = VELO.balanceOf(address(owner));
        (int128 lockedBefore, ) = vEscrow.locked(ownedTokenId);
        vVELO.approve(address(router), TOKEN_1);
        router.swapExactTokensForTokens(TOKEN_1, TOKEN_1, routes, address(owner), block.timestamp);
        uint256 balanceAfter = VELO.balanceOf(address(owner));
        assertEq(balanceAfter - balanceBefore, TOKEN_1);
        (int128 lockedAfter, ) = vEscrow.locked(ownedTokenId);
        assertEq(uint256(int256(lockedAfter - lockedBefore)), TOKEN_1);
    }

    // --------------------------------------------------------------------
    // Voting / Rewards
    // --------------------------------------------------------------------

    function testClaimRebaseAndGaugeRewards() external {
        vMinter.update_period();
        skip(1 weeks);
        vm.roll(block.number + 1);
        vMinter.update_period();
        skip(1 weeks);
        vm.roll(block.number + 1);
        vMinter.update_period();
        vVoter.distribute(address(gaugeSinkDrain));
        // Check amount claimable from rebase
        uint256 claimableRebase = vDistributor.claimable(ownedTokenId);
        assertGt(claimableRebase, 0);

        // Pre-load current voting balance
        uint256 votingBalanceBefore = vEscrow.balanceOfNFT(ownedTokenId);
        (int128 _amountBefore, ) = vEscrow.locked(ownedTokenId);
        uint256 amountBefore = uint256(int256(_amountBefore));

        // should also have rewards from gauge - which are already added to the escrow
        sinkManager.claimRebaseAndGaugeRewards();

        uint256 votingBalanceAfter = vEscrow.balanceOfNFT(ownedTokenId);

        // Expect voting power after should have increased by
        // more than the claimable rebase, which means gauge rewards were
        // claimed as well
        assertGt(votingBalanceAfter, votingBalanceBefore + claimableRebase);
        // Similarly, amount locked should be greater than just amount + claiamble rebase
        // to include the addition in gauge rewards
        (int128 _amountAfter, ) = vEscrow.locked(ownedTokenId);
        uint256 amountAfter = uint256(int256(_amountAfter));
        assertGt(amountAfter, amountBefore + claimableRebase);
    }

    function testClaimIncreasesUnlockTimeIfNeeded() external {
        // Have a full epoch process of rewards so that distribute works
        vMinter.update_period();
        skip(1 weeks);
        vm.roll(block.number + 1);
        vMinter.update_period();
        skip(1 weeks);
        vm.roll(block.number + 1);
        // vMinter.update_period();
        vVoter.distribute(address(gaugeSinkDrain));

        (int128 amountBefore, uint256 endBefore) = vEscrow.locked(ownedTokenId);
        // claimRebaseAndGaugeRewards should work and increase locked.end since there has not
        // been a merge with a veNFT that expires at the next max epoch end
        sinkManager.claimRebaseAndGaugeRewards();
        (int128 amountAfter, uint256 endAfter) = vEscrow.locked(ownedTokenId);
        assertEq(endBefore + 14 days, endAfter);
        // Ensure the amount locked of the veNFT has increased from successfully claiming the rebase
        assertGt(amountAfter, amountBefore);
    }

    function testClaimDoesNotIncreaseUnlockTimeIfNeeded() external {
        // Have a full epoch process of rewards so that distribute works
        vMinter.update_period();
        skip(1 weeks);
        vm.roll(block.number + 1);
        vMinter.update_period();
        skip(1 weeks);
        vm.roll(block.number + 1);
        vMinter.update_period();
        vVoter.distribute(address(gaugeSinkDrain));

        (, uint256 endBefore) = vEscrow.locked(ownedTokenId);
        // user creates veNFT which expires at the new max epoch end
        uint256 tokenId = vEscrow.create_lock(TOKEN_1 / 4, 4 * 365 days);
        // user merges veNFT into ownedTokenId, increasing the lock  period
        vEscrow.approve(address(sinkManager), tokenId);
        sinkManager.convertVe(tokenId);
        // ensure the lock period was increased
        (int128 amountAfterMerge, uint256 endAfterMerge) = vEscrow.locked(ownedTokenId);
        assertEq(endBefore + 14 days, endAfterMerge);
        // claimRebaseAndGaugeRewards should work and no change locked.end for ownedTokenId
        sinkManager.claimRebaseAndGaugeRewards();
        (int128 amountAfterClaim, uint256 endAfterClaim) = vEscrow.locked(ownedTokenId);
        assertEq(endAfterMerge, endAfterClaim);
        // Ensure the amount locked of the veNFT has increased from successfully claiming the rebase
        assertGt(amountAfterClaim, amountAfterMerge);
    }

    function testConvertVeSuccessfullyIncreasesVoteToGauge() external {
        uint256 votesToPoolBefore = vVoter.votes(ownedTokenId, address(sinkDrain));

        vm.startPrank(address(owner3));
        vEscrow.approve(address(sinkManager), tokenId3);
        sinkManager.convertVe(tokenId3);

        uint256 votesToPoolAfter = vVoter.votes(ownedTokenId, address(sinkDrain));
        assertGt(votesToPoolAfter, votesToPoolBefore);
    }

    // --------------------------------------------------------------------
    // Admin
    // --------------------------------------------------------------------

    function testCannotSetOwnedTokenIdV1Twice() external {
        vm.expectRevert(ISinkManager.TokenIdAlreadySet.selector);
        sinkManager.setOwnedTokenId(69);
    }

    function testCannotSetupSinkDrainTwice() external {
        vm.expectRevert(ISinkManager.GaugeAlreadySet.selector);
        sinkManager.setupSinkDrain(address(gaugeSinkDrain));
    }

    function testCannotSetupSinkDrainIfOwnedTokenIdNotSet() external {
        // Create new sinkManager
        SinkManager newSinkManager = new SinkManager(
            address(forwarder),
            address(sinkDrain),
            facilitatorImplementation,
            address(voter),
            address(vVELO),
            address(VELO),
            address(vEscrow),
            address(escrow),
            address(vDistributor)
        );

        vm.expectRevert(ISinkManager.TokenIdNotSet.selector);
        newSinkManager.setupSinkDrain(address(gaugeSinkDrain));
    }

    function testSetupSinkDrain() external {
        // NOTE: everything to gaugeSinkDrain is recycled from BaseTest._forkSetup()
        sinkDrain = new SinkDrain();
        sinkManager = new SinkManager(
            address(forwarder),
            address(sinkDrain),
            facilitatorImplementation,
            address(vVoter),
            address(vVELO),
            address(VELO),
            address(vEscrow),
            address(escrow),
            address(vDistributor)
        );
        sinkDrain.mint(address(sinkManager));

        // Setup SinkDrain
        vm.prank(vVoter.governor());
        gaugeSinkDrain = IGaugeV1(vVoter.createGauge(address(sinkDrain)));

        // create v1 nft as the ownedTokenId for SinkManager
        vVELO.approve(address(vEscrow), TOKEN_1 / 4);
        ownedTokenId = vEscrow.create_lock(TOKEN_1 / 4, 4 * 365 * 86400);
        vEscrow.safeTransferFrom(address(owner), address(sinkManager), ownedTokenId);
        sinkManager.setOwnedTokenId(ownedTokenId);

        // Move forward in time as escrow transfer above has balance to 0 for flash tx protection
        skip(1);
        vm.roll(block.number + 1);

        uint256 preTotalWeight = vVoter.totalWeight();
        sinkManager.setupSinkDrain(address(gaugeSinkDrain));

        // Ensure the sinkManager deposit balance is updated in gauge
        assertEq(sinkDrain.totalSupply(), gaugeSinkDrain.totalSupply());
        assertEq(sinkDrain.totalSupply(), gaugeSinkDrain.balanceOf(address(sinkManager)));

        // Ensure the sinkManager has voted for the gaugeSinkDrain with full balance
        uint256 votingPower = vEscrow.balanceOfNFT(ownedTokenId);
        uint256 postTotalWeight = vVoter.totalWeight();
        assertEq(postTotalWeight - preTotalWeight, votingPower);
        assertEq(vVoter.usedWeights(ownedTokenId), votingPower);
    }
}

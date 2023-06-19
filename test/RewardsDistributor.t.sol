// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./BaseTest.sol";

contract RewardsDistributorTest is BaseTest {
    event Claimed(uint256 indexed tokenId, uint256 indexed epochStart, uint256 indexed epochEnd, uint256 amount);

    function _setUp() public override {
        // timestamp: 604801
        VELO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        skip(1);

        address[] memory pools = new address[](2);
        pools[0] = address(pool);
        pools[1] = address(pool2);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 1;
        weights[1] = 1;

        skip(1 hours);
        voter.vote(tokenId, pools, weights);
    }

    function testInitialize() public {
        assertEq(distributor.startTime(), 604800);
        assertEq(distributor.lastTokenTime(), 604800);
        assertEq(distributor.token(), address(VELO));
        assertEq(address(distributor.ve()), address(escrow));
    }

    function testClaim() public {
        skipToNextEpoch(1 days); // epoch 1, ts: 1296000, blk: 2

        VELO.approve(address(escrow), TOKEN_1M);
        uint256 tokenId = escrow.createLock(TOKEN_1M, MAXTIME);

        IVotingEscrow.LockedBalance memory locked = escrow.locked(tokenId);
        assertEq(convert(locked.amount), TOKEN_1M);
        assertEq(locked.end, 127008000);
        assertEq(locked.isPermanent, false);

        assertEq(escrow.userPointEpoch(tokenId), 1);
        IVotingEscrow.UserPoint memory userPoint = escrow.userPointHistory(tokenId, 1);
        assertEq(convert(userPoint.slope), TOKEN_1M / MAXTIME); // TOKEN_1M / MAXTIME
        assertEq(convert(userPoint.bias), 996575342465753345952000); // (TOKEN_1M / MAXTIME) * (127008000 - 1296000)
        assertEq(userPoint.ts, 1296000);
        assertEq(userPoint.blk, 2);

        vm.startPrank(address(owner2));
        VELO.approve(address(escrow), TOKEN_1M);
        uint256 tokenId2 = escrow.createLock(TOKEN_1M, MAXTIME);
        vm.stopPrank();

        locked = escrow.locked(tokenId2);
        assertEq(convert(locked.amount), TOKEN_1M);
        assertEq(locked.end, 127008000);
        assertEq(locked.isPermanent, false);

        assertEq(escrow.userPointEpoch(tokenId2), 1);
        userPoint = escrow.userPointHistory(tokenId2, 1);
        assertEq(convert(userPoint.slope), TOKEN_1M / MAXTIME); // TOKEN_1M / MAXTIME
        assertEq(convert(userPoint.bias), 996575342465753345952000); // (TOKEN_1M / MAXTIME) * (127008000 - 1296000)
        assertEq(userPoint.ts, 1296000);
        assertEq(userPoint.blk, 2);

        // epoch 2
        skipToNextEpoch(0); // distribute epoch 1's rebases
        minter.updatePeriod();
        assertEq(distributor.claimable(tokenId), 117308174817358107217);
        assertEq(distributor.claimable(tokenId2), 117308174817358107217);

        // epoch 3
        skipToNextEpoch(0); // distribute epoch 2's rebases
        minter.updatePeriod();
        assertEq(distributor.claimable(tokenId), 221502635337542795673);
        assertEq(distributor.claimable(tokenId2), 221502635337542795673);

        // epoch 4
        skipToNextEpoch(0); // distribute epoch 3's rebases
        minter.updatePeriod();
        assertEq(distributor.claimable(tokenId), 276337074327168793939);
        assertEq(distributor.claimable(tokenId2), 276337074327168793939);

        // epoch 5
        skipToNextEpoch(0); // distribute epoch 4's rebases
        minter.updatePeriod();
        assertEq(distributor.claimable(tokenId), 308557941052823456387);
        assertEq(distributor.claimable(tokenId2), 308557941052823456387);

        IVotingEscrow.LockedBalance memory preLocked = escrow.locked(tokenId);
        vm.expectEmit(true, true, true, true, address(distributor));
        emit Claimed(tokenId, 1209600, 3628800, 308557941052823456387);
        distributor.claim(tokenId);
        IVotingEscrow.LockedBalance memory postLocked = escrow.locked(tokenId);
        assertEq(postLocked.amount - preLocked.amount, 308557941052823456387);
        assertEq(postLocked.end, 127008000);
        assertEq(postLocked.isPermanent, false);
    }

    function testClaimWithPermanentLocks() public {
        skipToNextEpoch(1 days); // epoch 1, ts: 1296000, blk: 2

        VELO.approve(address(escrow), TOKEN_1M);
        uint256 tokenId = escrow.createLock(TOKEN_1M, MAXTIME);
        escrow.lockPermanent(tokenId);

        IVotingEscrow.LockedBalance memory locked = escrow.locked(tokenId);
        assertEq(convert(locked.amount), TOKEN_1M);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, true);

        assertEq(escrow.userPointEpoch(tokenId), 1);
        IVotingEscrow.UserPoint memory userPoint = escrow.userPointHistory(tokenId, 1);
        assertEq(convert(userPoint.slope), 0);
        assertEq(convert(userPoint.bias), 0);
        assertEq(userPoint.ts, 1296000);
        assertEq(userPoint.blk, 2);
        assertEq(userPoint.permanent, TOKEN_1M);

        vm.startPrank(address(owner2));
        VELO.approve(address(escrow), TOKEN_1M);
        uint256 tokenId2 = escrow.createLock(TOKEN_1M, MAXTIME);
        escrow.lockPermanent(tokenId2);
        vm.stopPrank();

        locked = escrow.locked(tokenId2);
        assertEq(convert(locked.amount), TOKEN_1M);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, true);

        assertEq(escrow.userPointEpoch(tokenId2), 1);
        userPoint = escrow.userPointHistory(tokenId2, 1);
        assertEq(convert(userPoint.slope), 0);
        assertEq(convert(userPoint.bias), 0);
        assertEq(userPoint.ts, 1296000);
        assertEq(userPoint.blk, 2);
        assertEq(userPoint.permanent, TOKEN_1M);

        // epoch 2
        skipToNextEpoch(0); // distribute epoch 1's rebases
        minter.updatePeriod();
        assertEq(distributor.claimable(tokenId), 120000118520578147262);
        assertEq(distributor.claimable(tokenId2), 120000118520578147262);

        // epoch 3
        skipToNextEpoch(0); // distribute epoch 2's rebases
        minter.updatePeriod();
        assertEq(distributor.claimable(tokenId), 228145302791169389113);
        assertEq(distributor.claimable(tokenId2), 228145302791169389113);

        // epoch 4
        skipToNextEpoch(0); // distribute epoch 3's rebases
        minter.updatePeriod();
        assertEq(distributor.claimable(tokenId), 285895829055518482329);
        assertEq(distributor.claimable(tokenId2), 285895829055518482329);

        // epoch 5
        skipToNextEpoch(0); // distribute epoch 4's rebases
        minter.updatePeriod();
        assertEq(distributor.claimable(tokenId), 320331678939668340029);
        assertEq(distributor.claimable(tokenId2), 320331678939668340029);

        IVotingEscrow.LockedBalance memory preLocked = escrow.locked(tokenId);
        vm.expectEmit(true, true, true, true, address(distributor));
        emit Claimed(tokenId, 1209600, 3628800, 320331678939668340029);
        distributor.claim(tokenId);
        IVotingEscrow.LockedBalance memory postLocked = escrow.locked(tokenId);
        assertEq(postLocked.amount - preLocked.amount, 320331678939668340029);
        assertEq(postLocked.end, 0);
        assertEq(postLocked.isPermanent, true);
    }

    function testClaimWithBothLocks() public {
        skipToNextEpoch(1 days); // epoch 1, ts: 1296000, blk: 2

        VELO.approve(address(escrow), TOKEN_1M);
        uint256 tokenId = escrow.createLock(TOKEN_1M, MAXTIME);
        escrow.lockPermanent(tokenId);

        vm.startPrank(address(owner2));
        VELO.approve(address(escrow), TOKEN_1M);
        uint256 tokenId2 = escrow.createLock(TOKEN_1M, MAXTIME);
        vm.stopPrank();

        // expect permanent lock to earn more rebases
        // epoch 2
        skipToNextEpoch(0); // distribute epoch 1's rebases
        minter.updatePeriod();
        assertEq(distributor.claimable(tokenId), 119097712378909854335);
        assertEq(distributor.claimable(tokenId2), 118200401791428842760);

        // epoch 3
        skipToNextEpoch(0); // distribute epoch 2's rebases
        minter.updatePeriod();
        assertEq(distributor.claimable(tokenId), 225913737479343957233);
        assertEq(distributor.claimable(tokenId2), 223699517840142918804);

        // epoch 4
        skipToNextEpoch(0); // distribute epoch 3's rebases
        minter.updatePeriod();
        assertEq(distributor.claimable(tokenId), 282679639020640461146);
        assertEq(distributor.claimable(tokenId2), 279493400969439648943);

        // epoch 5
        skipToNextEpoch(0); // distribute epoch 4's rebases
        minter.updatePeriod();
        assertEq(distributor.claimable(tokenId), 316364880014824140653);
        assertEq(distributor.claimable(tokenId2), 312440335578734008537);

        uint256 pre = convert(escrow.locked(tokenId).amount);
        vm.expectEmit(true, true, true, true, address(distributor));
        emit Claimed(tokenId, 1209600, 3628800, 316364880014824140653);
        distributor.claim(tokenId);
        uint256 post = convert(escrow.locked(tokenId).amount);

        assertEq(post - pre, 316364880014824140653);
    }

    function testClaimWithLockCreatedMoreThan50EpochsLater() public {
        for (uint256 i = 0; i < 55; i++) {
            skipToNextEpoch(0);
            minter.updatePeriod();
        }

        VELO.approve(address(escrow), TOKEN_1M);
        uint256 tokenId = escrow.createLock(TOKEN_1M, MAXTIME);
        VELO.approve(address(escrow), TOKEN_1M);
        uint256 tokenId2 = escrow.createLock(TOKEN_1M, MAXTIME);

        skipToNextEpoch(0);
        minter.updatePeriod();
        assertEq(distributor.claimable(tokenId), 52046866841850578);
        assertEq(distributor.claimable(tokenId2), 52046866841850578);

        skipToNextEpoch(0);
        minter.updatePeriod();
        assertEq(distributor.claimable(tokenId), 100963251676787397);
        assertEq(distributor.claimable(tokenId2), 100963251676787397);

        uint256 pre = convert(escrow.locked(tokenId).amount);
        vm.expectEmit(true, true, true, true, address(distributor));
        emit Claimed(tokenId, 33868800, 35078400, 100963251676787397);
        distributor.claim(tokenId);
        uint256 post = convert(escrow.locked(tokenId).amount);

        assertEq(post - pre, 100963251676787397);
    }

    function testClaimWithIncreaseAmountOnEpochFlip() public {
        skipToNextEpoch(1 days); // epoch 1
        VELO.approve(address(escrow), TOKEN_1M);
        uint256 tokenId = escrow.createLock(TOKEN_1M, MAXTIME);
        VELO.approve(address(escrow), TOKEN_1M);
        uint256 tokenId2 = escrow.createLock(TOKEN_1M, MAXTIME);

        skipToNextEpoch(0); // distribute epoch 1's rebases
        minter.updatePeriod();
        assertEq(distributor.claimable(tokenId), 117308174817358107217);
        assertEq(distributor.claimable(tokenId2), 117308174817358107217);

        skipToNextEpoch(0);
        assertEq(distributor.claimable(tokenId), 117308174817358107217);
        assertEq(distributor.claimable(tokenId2), 117308174817358107217);
        // making lock larger on flip should not impact claimable
        VELO.approve(address(escrow), TOKEN_1M);
        escrow.increaseAmount(tokenId, TOKEN_1M);
        minter.updatePeriod(); // epoch 1's rebases available
        assertEq(distributor.claimable(tokenId), 221502635337542795673);
        assertEq(distributor.claimable(tokenId2), 221502635337542795673);
    }

    function testClaimWithExpiredNFT() public {
        // test reward claims to expired NFTs are distributed as unlocked VELO
        // ts: 608402
        VELO.approve(address(escrow), TOKEN_1M);
        uint256 tokenId = escrow.createLock(TOKEN_1M, WEEK * 4);

        skipToNextEpoch(1);
        minter.updatePeriod();
        assertEq(distributor.claimable(tokenId), 178570821996319);

        for (uint256 i = 0; i < 4; i++) {
            minter.updatePeriod();
            skipToNextEpoch(1);
        }
        minter.updatePeriod();

        assertGt(distributor.claimable(tokenId), 178570821996319); // accrued rebases

        IVotingEscrow.LockedBalance memory locked = escrow.locked(tokenId);
        assertGt(block.timestamp, locked.end); // lock expired

        uint256 rebase = distributor.claimable(tokenId);
        uint256 pre = VELO.balanceOf(address(owner));
        vm.expectEmit(true, true, true, true, address(distributor));
        emit Claimed(tokenId, 604800, 3628800, 204006674754980);
        distributor.claim(tokenId);
        uint256 post = VELO.balanceOf(address(owner));

        locked = escrow.locked(tokenId); // update locked value post claim

        assertEq(post - pre, rebase); // expired rebase distributed as unlocked VELO
        assertEq(uint256(uint128(locked.amount)), TOKEN_1M); // expired nft locked balance unchanged
    }

    function testClaimManyWithExpiredNFT() public {
        // test claim many with one expired nft and one normal nft
        // ts: 608402
        VELO.approve(address(escrow), TOKEN_1M);
        uint256 tokenId = escrow.createLock(TOKEN_1M, WEEK * 4);
        VELO.approve(address(escrow), TOKEN_1M);
        uint256 tokenId2 = escrow.createLock(TOKEN_1M, MAXTIME);

        skipToNextEpoch(1);
        minter.updatePeriod();
        assertEq(distributor.claimable(tokenId), 874877078693644301);
        assertEq(distributor.claimable(tokenId2), 60366485641276490642);

        for (uint256 i = 0; i < 4; i++) {
            minter.updatePeriod();
            skipToNextEpoch(1);
        }
        minter.updatePeriod();

        assertGt(distributor.claimable(tokenId), 0); // accrued rebases
        assertGt(distributor.claimable(tokenId2), 0);

        IVotingEscrow.LockedBalance memory locked = escrow.locked(tokenId);
        assertGt(block.timestamp, locked.end); // lock expired

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = tokenId;
        tokenIds[1] = tokenId2;

        uint256 rebase = distributor.claimable(tokenId);
        uint256 rebase2 = distributor.claimable(tokenId2);

        uint256 pre = VELO.balanceOf(address(owner));
        assertTrue(distributor.claimMany(tokenIds));
        uint256 post = VELO.balanceOf(address(owner));

        locked = escrow.locked(tokenId); // update locked value post claim
        IVotingEscrow.LockedBalance memory postLocked2 = escrow.locked(tokenId2);

        assertEq(post - pre, rebase); // expired rebase distributed as unlocked VELO
        assertEq(uint256(uint128(locked.amount)), TOKEN_1M); // expired nft locked balance unchanged
        assertEq(uint256(uint128(postLocked2.amount)) - uint256(uint128(locked.amount)), rebase2); // rebase accrued to normal nft
    }

    function testClaimRebaseWithManagedLocks() public {
        minter.updatePeriod(); // does nothing
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1M, MAXTIME);
        escrow.lockPermanent(tokenId);
        uint256 tokenId2 = escrow.createLock(TOKEN_1M, MAXTIME);
        escrow.lockPermanent(tokenId2);
        uint256 mTokenId = escrow.createManagedLockFor(address(owner));

        voter.depositManaged(tokenId2, mTokenId);

        skipAndRoll(1 hours); // created at epoch 0 + 1 days + 1 hours
        uint256 tokenId3 = escrow.createLock(TOKEN_1M, MAXTIME);
        escrow.lockPermanent(tokenId3);

        assertEq(distributor.claimable(tokenId), 0);
        assertEq(distributor.claimable(tokenId2), 0);
        assertEq(distributor.claimable(tokenId3), 0);
        assertEq(distributor.claimable(mTokenId), 0);

        skipToNextEpoch(0); // epoch 1
        minter.updatePeriod();

        // epoch 0 rebases distributed
        assertEq(distributor.claimable(tokenId), 540000357287733143637);
        assertEq(distributor.claimable(tokenId2), 0);
        assertEq(distributor.claimable(tokenId3), 540000357287733143637);
        assertEq(distributor.claimable(mTokenId), 540000357287733143637);

        skipAndRoll(1 days); // deposit @ epoch 1 + 1 days
        voter.depositManaged(tokenId3, mTokenId);

        skipToNextEpoch(0); // epoch 2
        minter.updatePeriod();

        // epoch 1 rebases distributed
        assertEq(distributor.claimable(tokenId), 783314140765968792053);
        assertEq(distributor.claimable(tokenId2), 0);
        assertEq(distributor.claimable(tokenId3), 540000357287733143637);
        assertEq(distributor.claimable(mTokenId), 1026627924244204440469);
        distributor.claim(mTokenId); // claim token rewards
        assertEq(distributor.claimable(mTokenId), 0);

        uint256 tokenId4 = escrow.createLock(TOKEN_1M, MAXTIME); // lock created in epoch 2
        escrow.lockPermanent(tokenId4);

        skipToNextEpoch(1 hours); // epoch 3
        minter.updatePeriod();

        // epoch 2 rebases distributed
        assertEq(distributor.claimable(tokenId), 1013052874240492772189);
        assertEq(distributor.claimable(tokenId2), 0);
        assertEq(distributor.claimable(tokenId3), 540000357287733143637); // claimable unchanged
        assertEq(distributor.claimable(tokenId4), 229738733474523980136); // claim rebases from last epoch
        assertEq(distributor.claimable(mTokenId), 459713323148113403351);

        skipToNextEpoch(0); // epoch 4
        minter.updatePeriod();

        // rewards for epoch 2 locks
        assertEq(distributor.claimable(tokenId), 1152223645763475949490);
        assertEq(distributor.claimable(tokenId2), 0);
        assertEq(distributor.claimable(tokenId3), 540000357287733143637); // claimable unchanged
        assertEq(distributor.claimable(tokenId4), 368909504997507157437);
        assertEq(distributor.claimable(mTokenId), 738197742794363862612);

        skipAndRoll(1 hours + 1);
        voter.withdrawManaged(tokenId3);

        for (uint256 i = 0; i <= 6; i++) {
            if (i == tokenId2) continue;
            distributor.claim(i);
            assertEq(distributor.claimable(i), 0);
        }

        assertLt(VELO.balanceOf(address(distributor)), 100); // dust
    }

    function testClaimRebaseWithDepositManaged() public {
        minter.updatePeriod(); // does nothing
        vm.startPrank(address(owner2));
        VELO.approve(address(escrow), TOKEN_10M);
        uint256 tokenId = escrow.createLock(TOKEN_10M, MAXTIME);
        escrow.lockPermanent(tokenId);
        vm.stopPrank();

        vm.startPrank(address(owner3));
        VELO.approve(address(escrow), TOKEN_10M);
        uint256 tokenId2 = escrow.createLock(TOKEN_10M, MAXTIME);
        escrow.lockPermanent(tokenId2);
        vm.stopPrank();
        uint256 mTokenId = escrow.createManagedLockFor(address(owner));

        assertEq(distributor.claimable(tokenId), 0);
        assertEq(distributor.claimable(tokenId2), 0);
        assertEq(distributor.claimable(mTokenId), 0);

        skipToNextEpoch(0); // epoch 1
        minter.updatePeriod();

        // epoch 0 rebases distributed
        assertEq(distributor.claimable(tokenId), 240000023819178860615692);
        assertEq(distributor.claimable(tokenId2), 240000023819178860615692);
        assertEq(distributor.claimable(mTokenId), 0);

        skipAndRoll(1 days);
        vm.prank(address(owner3));
        voter.depositManaged(tokenId2, mTokenId);

        assertEq(distributor.claimable(tokenId), 240000023819178860615692);
        assertEq(distributor.claimable(tokenId2), 240000023819178860615692);
        assertEq(distributor.claimable(mTokenId), 0);

        skipToNextEpoch(1 hours); // epoch 2
        minter.updatePeriod();

        assertEq(distributor.claimable(tokenId), 345160623903379414405721);
        assertEq(distributor.claimable(tokenId2), 240000023819178860615692); // claimable unchanged
        assertEq(distributor.claimable(mTokenId), 105160600084200553790029); // rebase earned by tokenId2

        skipAndRoll(1);
        vm.prank(address(owner3));
        voter.withdrawManaged(tokenId2);

        skipToNextEpoch(0); // epoch 3
        minter.updatePeriod();

        assertEq(distributor.claimable(tokenId), 401642795611076233518536);
        assertEq(distributor.claimable(tokenId2), 296056645365878538584660);
        assertEq(distributor.claimable(mTokenId), 105160600084200553790029); // claimable unchanged
    }

    function testCannotClaimRebaseWithLockedNFT() public {
        VELO.approve(address(escrow), TOKEN_1M);
        uint256 tokenId = escrow.createLock(TOKEN_1M, MAXTIME);
        escrow.lockPermanent(tokenId);
        uint256 mTokenId = escrow.createManagedLockFor(address(owner));

        skipToNextEpoch(2 hours); // epoch 1
        minter.updatePeriod();

        assertEq(distributor.claimable(tokenId), 59294235341880442146);
        assertEq(distributor.claimable(mTokenId), 0);

        voter.depositManaged(tokenId, mTokenId);

        skipToNextEpoch(1 days); // epoch 3
        minter.updatePeriod();

        vm.expectRevert(IRewardsDistributor.NotManagedOrNormalNFT.selector);
        distributor.claim(tokenId);
    }

    function testCannotClaimBeforeUpdatePeriod() public {
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1M, MAXTIME);
        uint256 tokenId2 = escrow.createLock(TOKEN_1M * 8, MAXTIME);

        skipToNextEpoch(2 hours); // epoch 1
        minter.updatePeriod();

        assertEq(distributor.claimable(tokenId), 4695083555992579290349);
        assertEq(distributor.claimable(tokenId2), 37560668447940637284081);

        skipToNextEpoch(1 hours); // epoch 3
        vm.expectRevert(IRewardsDistributor.UpdatePeriod.selector);
        distributor.claim(tokenId);

        skipAndRoll(1 hours);
        minter.updatePeriod();

        distributor.claim(tokenId);
    }

    function testCannotCheckpointTokenIfNotMinter() public {
        vm.expectRevert(IRewardsDistributor.NotMinter.selector);
        vm.prank(address(owner2));
        distributor.checkpointToken();
    }

    function testClaimBeforeLockedEnd() public {
        uint256 duration = WEEK * 12;
        vm.startPrank(address(owner));
        VELO.approve(address(escrow), TOKEN_1M);
        uint256 tokenId = escrow.createLock(TOKEN_1M, duration);

        skipToNextEpoch(1);
        minter.updatePeriod();
        assertGt(distributor.claimable(tokenId), 0);

        IVotingEscrow.LockedBalance memory locked = escrow.locked(tokenId);
        vm.warp(locked.end - 1);
        assertEq(block.timestamp, locked.end - 1);
        minter.updatePeriod();

        // Rebase should deposit into veNFT one second before expiry
        distributor.claim(tokenId);
        locked = escrow.locked(tokenId);
        assertGt(uint256(uint128((locked.amount))), TOKEN_1M);
    }

    function testClaimOnLockedEnd() public {
        uint256 duration = WEEK * 12;
        vm.startPrank(address(owner));
        VELO.approve(address(escrow), TOKEN_1M);
        uint256 tokenId = escrow.createLock(TOKEN_1M, duration);

        skipToNextEpoch(1);
        minter.updatePeriod();
        assertGt(distributor.claimable(tokenId), 0);

        IVotingEscrow.LockedBalance memory locked = escrow.locked(tokenId);
        vm.warp(locked.end);
        assertEq(block.timestamp, locked.end);
        minter.updatePeriod();

        // Rebase should deposit into veNFT one second before expiry
        uint256 balanceBefore = VELO.balanceOf(address(owner));
        distributor.claim(tokenId);
        assertGt(VELO.balanceOf(address(owner)), balanceBefore);
    }
}

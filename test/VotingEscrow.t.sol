// 1:1 with Hardhat test
pragma solidity 0.8.13;

import "./BaseTest.sol";

contract VotingEscrowTest is BaseTest {
    event NotifyReward(address indexed from, address indexed reward, uint256 epoch, uint256 amount);

    function testInitialState() public {
        assertEq(escrow.team(), address(owner));
        assertEq(escrow.allowedManager(), address(owner));
        // voter should already have been setup
        assertEq(escrow.voter(), address(voter));
    }

    function testCannotDepositForWithLockedNFT() public {
        uint256 mTokenId = escrow.createManagedLockFor(address(owner2));
        VELO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        voter.depositManaged(tokenId, mTokenId);
        assertEq(uint256(escrow.escrowType(tokenId)), uint256(IVotingEscrow.EscrowType.LOCKED));

        vm.expectRevert("VotingEscrow: nft locked");
        escrow.depositFor(tokenId, TOKEN_1);
    }

    function testCannotDepositForWithManagedNFTIfNotDistributor() public {
        uint256 mTokenId = escrow.createManagedLockFor(address(owner2));
        VELO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        voter.depositManaged(tokenId, mTokenId);

        vm.expectRevert("VotingEscrow: not distributor");
        escrow.depositFor(mTokenId, TOKEN_1);
    }

    function testDepositForWithManagedNFT() public {
        uint256 reward = TOKEN_1;
        uint256 mTokenId = escrow.createManagedLockFor(address(owner2));
        LockedManagedReward lockedManagedReward = LockedManagedReward(escrow.managedToLocked(mTokenId));
        assertEq(VELO.allowance(address(escrow), address(lockedManagedReward)), 0);

        VELO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        voter.depositManaged(tokenId, mTokenId);
        deal(address(VELO), address(distributor), TOKEN_1);

        uint256 pre = VELO.balanceOf(address(lockedManagedReward));
        IVotingEscrow.LockedBalance memory preLocked = escrow.locked(mTokenId);
        vm.prank(address(distributor));
        vm.expectEmit(true, false, false, true, address(lockedManagedReward));
        emit NotifyReward(address(escrow), address(VELO), 604800, reward);
        escrow.depositFor(mTokenId, reward);
        uint256 post = VELO.balanceOf(address(lockedManagedReward));
        IVotingEscrow.LockedBalance memory postLocked = escrow.locked(mTokenId);

        assertEq(uint256(uint128(postLocked.amount)) - uint256(uint128(preLocked.amount)), reward);
        assertEq(post - pre, reward);
        assertEq(VELO.allowance(address(escrow), address(lockedManagedReward)), 0);
    }

    function testDepositFor() public {
        VELO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        IVotingEscrow.LockedBalance memory preLocked = escrow.locked(tokenId);
        VELO.approve(address(escrow), TOKEN_1);
        escrow.depositFor(tokenId, TOKEN_1);
        IVotingEscrow.LockedBalance memory postLocked = escrow.locked(tokenId);

        assertEq(uint256(uint128(postLocked.amount)) - uint256(uint128(preLocked.amount)), TOKEN_1);
    }

    function testCreateLock() public {
        VELO.approve(address(escrow), 1e25);
        uint256 lockDuration = 7 * 24 * 3600; // 1 week

        // Balance should be zero before and 1 after creating the lock
        assertEq(escrow.balanceOf(address(owner)), 0);
        escrow.createLock(1e25, lockDuration);
        assertEq(escrow.ownerOf(1), address(owner));
        assertEq(escrow.balanceOf(address(owner)), 1);
        assertEq(
            keccak256(abi.encodePacked(escrow.escrowType(1))),
            keccak256(abi.encodePacked(IVotingEscrow.EscrowType.NORMAL))
        );
        assertEq(escrow.numCheckpoints(address(owner)), 1);
        IVotingEscrow.Checkpoint memory checkpoint = escrow.checkpoints(address(owner), 0);
        assertEq(checkpoint.fromTimestamp, 0);
        assertEq(checkpoint.tokenIds.length, 1);
        assertEq(checkpoint.tokenIds[0], 1);
        uint256[] memory tokenIds = escrow.getTokenIdsAt(address(owner), 1);
        assertEq(tokenIds.length, 1);
        assertEq(tokenIds[0], 1);
    }

    function testCreateLockOutsideAllowedZones() public {
        VELO.approve(address(escrow), 1e25);
        vm.expectRevert("VotingEscrow: lock duration greater than 4 years");
        escrow.createLock(1e21, MAXTIME + 1 weeks);
    }

    function testBurnFromApproved() public {
        VELO.approve(address(escrow), 1e25);
        uint256 tokenId = escrow.createLock(1e21, MAXTIME);
        skipAndRoll(MAXTIME + 1);
        escrow.approve(address(owner2), tokenId);
        vm.prank(address(owner2));
        // should not revert
        escrow.withdraw(tokenId);
    }

    function testWithdraw() public {
        VELO.approve(address(escrow), 1e25);
        uint256 lockDuration = 7 * 24 * 3600; // 1 week
        escrow.createLock(1e25, lockDuration);

        // Try withdraw early
        uint256 tokenId = 1;
        vm.expectRevert(abi.encodePacked("VotingEscrow: lock not expired"));
        escrow.withdraw(tokenId);
        // Now try withdraw after the time has expired
        skip(lockDuration);
        vm.roll(block.number + 1); // mine the next block
        escrow.withdraw(tokenId);

        assertEq(VELO.balanceOf(address(owner)), 1e25);
        // Check that the NFT is burnt
        assertEq(escrow.balanceOfNFT(tokenId), 0);
        assertEq(escrow.ownerOf(tokenId), address(0));
    }

    function testCheckTokenURICalls() public {
        // tokenURI should not work for non-existent token ids
        vm.expectRevert(abi.encodePacked("VotingEscrow: query for nonexistent token"));
        escrow.tokenURI(999);
        VELO.approve(address(escrow), 1e25);
        uint256 lockDuration = 7 * 24 * 3600; // 1 week
        escrow.createLock(1e25, lockDuration);

        uint256 tokenId = 1;
        skip(lockDuration);
        vm.roll(block.number + 1); // mine the next block

        // Just check that this doesn't revert
        escrow.tokenURI(tokenId);

        // Withdraw, which destroys the NFT
        escrow.withdraw(tokenId);

        // tokenURI should not work for this anymore as the NFT is burnt
        vm.expectRevert(abi.encodePacked("VotingEscrow: query for nonexistent token"));
        escrow.tokenURI(tokenId);
    }

    function testConfirmSupportsInterfaceWorksWithAssertedInterfaces() public {
        // Check that it supports all the asserted interfaces.
        bytes4 ERC165_INTERFACE_ID = 0x01ffc9a7;
        bytes4 ERC721_INTERFACE_ID = 0x80ac58cd;
        bytes4 ERC721_METADATA_INTERFACE_ID = 0x5b5e139f;

        assertTrue(escrow.supportsInterface(ERC165_INTERFACE_ID));
        assertTrue(escrow.supportsInterface(ERC721_INTERFACE_ID));
        assertTrue(escrow.supportsInterface(ERC721_METADATA_INTERFACE_ID));
    }

    function testCheckSupportsInterfaceHandlesUnsupportedInterfacesCorrectly() public {
        bytes4 ERC721_FAKE = 0x780e9d61;
        assertFalse(escrow.supportsInterface(ERC721_FAKE));
    }

    function testCannotMergeSameVeNFT() public {
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        vm.expectRevert("VotingEscrow: same nft");
        escrow.merge(tokenId, tokenId);
    }

    function testCannotMergeFromVeNFTWithNoApprovalOrOwnership() public {
        VELO.approve(address(escrow), type(uint256).max);
        uint256 ownerTokenId = escrow.createLock(TOKEN_1, MAXTIME);

        vm.startPrank(address(owner2));
        VELO.approve(address(escrow), type(uint256).max);
        uint256 owner2TokenId = escrow.createLock(TOKEN_1, MAXTIME);
        vm.stopPrank();

        vm.expectRevert("VotingEscrow: invalid permissions (from)");
        escrow.merge(owner2TokenId, ownerTokenId);
    }

    function testCannotMergeToVeNFTWithNoApprovalOrOwnership() public {
        VELO.approve(address(escrow), type(uint256).max);
        uint256 ownerTokenId = escrow.createLock(TOKEN_1, MAXTIME);

        vm.startPrank(address(owner2));
        VELO.approve(address(escrow), type(uint256).max);
        uint256 owner2TokenId = escrow.createLock(TOKEN_1, MAXTIME);
        vm.stopPrank();

        vm.expectRevert("VotingEscrow: invalid permissions (to)");
        escrow.merge(ownerTokenId, owner2TokenId);
    }

    function testCannotMergeAlreadyVotedFromVeNFT() public {
        skip(1 hours);
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId2 = escrow.createLock(TOKEN_1, MAXTIME);

        skip(1);

        address[] memory pools = new address[](1);
        pools[0] = address(pair);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        voter.vote(tokenId, pools, weights);

        skip(1);

        vm.expectRevert("VotingEscrow: voted");
        escrow.merge(tokenId, tokenId2);
    }

    function testMergeWithFromLockTimeGreaterThanToLockTime() public {
        // first veNFT max lock time (4yrs)
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        // second veNFT only 1 yr lock time
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId2 = escrow.createLock(TOKEN_1, 365 days);

        uint256 veloSupply = escrow.supply();
        uint256 expectedLockTime = escrow.lockedEnd(tokenId);
        skip(1);

        escrow.merge(tokenId, tokenId2);

        assertEq(escrow.balanceOf(address(owner)), 1);
        assertEq(escrow.ownerOf(tokenId), address(0));
        assertEq(escrow.ownerOf(tokenId2), address(owner));
        assertEq(escrow.supply(), veloSupply);

        IVotingEscrow.LockedBalance memory lockedFrom = escrow.locked(tokenId);
        assertEq(lockedFrom.amount, 0);
        assertEq(lockedFrom.end, 0);

        IVotingEscrow.LockedBalance memory lockedTo = escrow.locked(tokenId2);
        assertEq(uint256(uint128(lockedTo.amount)), TOKEN_1 * 2);
        assertEq(uint256(uint128(lockedTo.end)), expectedLockTime);
    }

    function testMergeWithToLockTimeGreaterThanFromLockTime() public {
        // first veNFT max lock time (4yrs)
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        // second veNFT only 1 yr lock time
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId2 = escrow.createLock(TOKEN_1, 365 days);

        uint256 veloSupply = escrow.supply();
        uint256 expectedLockTime = escrow.lockedEnd(tokenId);

        skip(1);

        escrow.merge(tokenId2, tokenId);

        assertEq(escrow.balanceOf(address(owner)), 1);
        assertEq(escrow.ownerOf(tokenId), address(owner));
        assertEq(escrow.ownerOf(tokenId2), address(0));
        assertEq(escrow.supply(), veloSupply);

        IVotingEscrow.LockedBalance memory lockedFrom = escrow.locked(tokenId2);
        assertEq(lockedFrom.amount, 0);
        assertEq(lockedFrom.end, 0);

        IVotingEscrow.LockedBalance memory lockedTo = escrow.locked(tokenId);
        assertEq(uint256(uint128(lockedTo.amount)), TOKEN_1 * 2);
        assertEq(uint256(uint128(lockedTo.end)), expectedLockTime);
    }

    function testMergeWithExpiredFromVeNFT() public {
        // first veNFT max lock time (4yrs)
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        // second veNFT only 1 week lock time
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId2 = escrow.createLock(TOKEN_1, 1 weeks);

        uint256 expectedLockTime = escrow.lockedEnd(tokenId);

        // let first veNFT expire
        skip(4 weeks);

        uint256 lock = escrow.lockedEnd(tokenId2);
        assertLt(lock, block.timestamp); // check expired

        escrow.merge(tokenId2, tokenId);

        assertEq(escrow.balanceOf(address(owner)), 1);
        assertEq(escrow.ownerOf(tokenId), address(owner));
        assertEq(escrow.ownerOf(tokenId2), address(0));

        IVotingEscrow.LockedBalance memory lockedFrom = escrow.locked(tokenId2);
        assertEq(lockedFrom.amount, 0);
        assertEq(lockedFrom.end, 0);

        IVotingEscrow.LockedBalance memory lockedTo = escrow.locked(tokenId);
        assertEq(uint256(uint128(lockedTo.amount)), TOKEN_1 * 2);
        assertEq(uint256(uint128(lockedTo.end)), expectedLockTime);
    }

    function testCannotMergeWithExpiredToVeNFT() public {
        // first veNFT max lock time (4yrs)
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        // second veNFT only 1 week lock time
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId2 = escrow.createLock(TOKEN_1, 1 weeks);

        // let second veNFT expire
        skip(4 weeks);

        vm.expectRevert("VotingEscrow: to nft lock expired");
        escrow.merge(tokenId, tokenId2);
    }

    function testMergeWithVotedToVeNFT() public {
        skip(1 weeks / 2);

        // create a bribe
        LR.approve(address(bribeVotingReward), TOKEN_1);
        bribeVotingReward.notifyRewardAmount(address(LR), TOKEN_1);

        // first veNFT max lock time (4yrs)
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        // second veNFT only 1 yr lock time
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId2 = escrow.createLock(TOKEN_1, 365 days);

        uint256 expectedLockTime = escrow.lockedEnd(tokenId);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pair);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        voter.vote(1, pools, weights);

        skip(1 days);

        // can merge into a veNFT that voted this epoch
        escrow.merge(tokenId2, tokenId);

        assertEq(escrow.balanceOf(address(owner)), 1);
        assertEq(escrow.ownerOf(tokenId), address(owner));
        assertEq(escrow.ownerOf(tokenId2), address(0));

        IVotingEscrow.LockedBalance memory lockedFrom = escrow.locked(tokenId2);
        assertEq(lockedFrom.amount, 0);
        assertEq(lockedFrom.end, 0);

        IVotingEscrow.LockedBalance memory lockedTo = escrow.locked(tokenId);
        assertEq(uint256(uint128(lockedTo.amount)), TOKEN_1 * 2);
        assertEq(uint256(uint128(lockedTo.end)), expectedLockTime);

        skipToNextEpoch(1);

        // to veNFT can still claim rewards
        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1);
    }

    function testCannotEnableSplitForAllIfNotTeam() public {
        vm.prank(address(owner2));
        vm.expectRevert("VotingEscrow: not team");
        escrow.enableSplitForAll();
    }

    function testEnableSplitForAll() public {
        assertFalse(escrow.anyoneCanSplit());

        escrow.enableSplitForAll();

        assertTrue(escrow.anyoneCanSplit());
    }

    function testCannotAllowSplitIfNotTeam() public {
        vm.prank(address(owner2));
        vm.expectRevert("VotingEscrow: not team");
        escrow.allowSplit(1);
    }

    function testAllowSplit() public {
        assertFalse(escrow.canSplit(1));

        escrow.allowSplit(1);

        assertTrue(escrow.canSplit(1));
    }

    function testCannotSplitWithManagedNFT() public {
        escrow.enableSplitForAll();
        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, 4 * 365 * 86400);
        voter.depositManaged(tokenId, mTokenId);

        vm.expectRevert("VotingEscrow: split requires normal nft");
        escrow.split(mTokenId, TOKEN_1 / 2);
    }

    function testCannotSplitWithAmountZero() public {
        escrow.enableSplitForAll();
        VELO.approve(address(escrow), type(uint256).max);
        uint256 ownerTokenId = escrow.createLock(TOKEN_1, MAXTIME);

        vm.expectRevert("VotingEscrow: zero amount");
        escrow.split(ownerTokenId, 0);
    }

    function testCannotSplitVeNFTWithNoApprovalOrOwnership() public {
        escrow.enableSplitForAll();
        VELO.approve(address(escrow), type(uint256).max);
        uint256 ownerTokenId = escrow.createLock(TOKEN_1, MAXTIME);

        vm.expectRevert("VotingEscrow: from: invalid permissions");
        vm.prank(address(owner2));
        escrow.split(ownerTokenId, TOKEN_1 / 2);
    }

    function testCannotSplitWithExpiredVeNFT() public {
        escrow.enableSplitForAll();
        // create veNFT with one week locktime
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, 1 weeks);

        // let second veNFT expire
        skip(1 weeks + 1);

        vm.expectRevert("VotingEscrow: nft lock expired");
        escrow.split(tokenId, TOKEN_1 / 2);
    }

    function testCannotSplitWithAlreadyVotedVeNFT() public {
        skip(1 hours);
        escrow.enableSplitForAll();
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        skip(1);

        address[] memory pools = new address[](1);
        pools[0] = address(pair);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        voter.vote(tokenId, pools, weights);

        skip(1);

        vm.expectRevert("VotingEscrow: voted");
        escrow.split(tokenId, TOKEN_1 / 2);
    }

    function testCannotSplitWithAmountTooBig() public {
        escrow.enableSplitForAll();
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        vm.expectRevert("VotingEscrow: amount too big");
        escrow.split(tokenId, TOKEN_1);
    }

    function testCannotSplitIfNotPermissioned() public {
        VELO.approve(address(escrow), type(uint256).max);
        escrow.createLock(TOKEN_1, MAXTIME);

        vm.expectRevert("VotingEscrow: split not public yet");
        escrow.split(1, TOKEN_1 / 4);
    }

    function testCannotSplitThenTransferOriginal() public {
        skip(1 weeks / 2);

        escrow.allowSplit(1);
        VELO.approve(address(escrow), type(uint256).max);
        escrow.createLock(TOKEN_1, MAXTIME);

        escrow.split(1, TOKEN_1 / 4);
        vm.expectRevert(); // TODO: change to error message check when merged
        escrow.transferFrom(address(owner), address(owner2), 1);
    }

    function testSplitOwnershipFromOwner() public {
        skip(1 weeks / 2);

        escrow.allowSplit(1);
        VELO.approve(address(escrow), type(uint256).max);
        escrow.createLock(TOKEN_1, MAXTIME);

        (uint256 splitTokenId1, uint256 splitTokenId2) = escrow.split(1, TOKEN_1 / 4);
        assertEq(escrow.ownerOf(splitTokenId1), address(owner));
        assertEq(escrow.ownerOf(splitTokenId2), address(owner));
        assertEq(escrow.ownerOf(1), address(0));
    }

    function testSplitOwnershipFromApproved() public {
        skip(1 weeks / 2);

        escrow.allowSplit(1);
        VELO.approve(address(escrow), type(uint256).max);
        escrow.createLock(TOKEN_1, MAXTIME);
        escrow.approve(address(owner2), 1);

        vm.prank(address(owner2));
        (uint256 splitTokenId1, uint256 splitTokenId2) = escrow.split(1, TOKEN_1 / 4);
        assertEq(escrow.ownerOf(splitTokenId1), address(owner));
        assertEq(escrow.ownerOf(splitTokenId2), address(owner));
        assertEq(escrow.ownerOf(1), address(0));
    }

    function testSplitWhenAllowSplit() public {
        skip(1 weeks / 2);

        escrow.allowSplit(1);

        VELO.approve(address(escrow), type(uint256).max);
        escrow.createLock(TOKEN_1, MAXTIME); // 1

        // generate new nfts with same amounts / locktime
        escrow.createLock((TOKEN_1 * 3) / 4, MAXTIME); // 2
        escrow.createLock(TOKEN_1 / 4, MAXTIME); // 3
        uint256 expectedLockTime = escrow.lockedEnd(1);
        uint256 veloSupply = escrow.supply();

        (uint256 splitTokenId1, uint256 splitTokenId2) = escrow.split(1, TOKEN_1 / 4);
        assertEq(splitTokenId1, 4);
        assertEq(splitTokenId2, 5);
        assertEq(escrow.supply(), veloSupply);

        // check new veNFTs have correct amount and locktime
        IVotingEscrow.LockedBalance memory lockedOld = escrow.locked(splitTokenId1);
        assertEq(uint256(uint128(lockedOld.amount)), (TOKEN_1 * 3) / 4);
        assertEq(lockedOld.end, expectedLockTime);
        assertEq(escrow.ownerOf(splitTokenId1), address(owner));

        IVotingEscrow.LockedBalance memory lockedNew = escrow.locked(splitTokenId2);
        assertEq(uint256(uint128(lockedNew.amount)), TOKEN_1 / 4);
        assertEq(lockedNew.end, expectedLockTime);
        assertEq(escrow.ownerOf(splitTokenId2), address(owner));

        // check modified veNFTs are equivalent to brand new veNFTs created with same amount and locktime
        assertEq(escrow.balanceOfNFT(splitTokenId1), escrow.balanceOfNFT(2));
        assertEq(escrow.balanceOfNFT(splitTokenId2), escrow.balanceOfNFT(3));

        // compare point history of first split veNFT and 2
        uint256 lastEpochStored;
        lastEpochStored = escrow.userPointEpoch(splitTokenId1);
        IVotingEscrow.Point memory origPoint = escrow.userPointHistory(splitTokenId1, lastEpochStored);
        lastEpochStored = escrow.userPointEpoch(2);
        IVotingEscrow.Point memory cmpPoint = escrow.userPointHistory(2, lastEpochStored);
        assertEq(origPoint.bias, cmpPoint.bias);
        assertEq(origPoint.slope, cmpPoint.slope);
        assertEq(origPoint.ts, cmpPoint.ts);
        assertEq(origPoint.blk, cmpPoint.blk);

        // compare point history of second split veNFT and 3
        lastEpochStored = escrow.userPointEpoch(splitTokenId2);
        IVotingEscrow.Point memory splitPoint = escrow.userPointHistory(splitTokenId2, lastEpochStored);
        lastEpochStored = escrow.userPointEpoch(3);
        cmpPoint = escrow.userPointHistory(3, lastEpochStored);
        assertEq(splitPoint.bias, cmpPoint.bias);
        assertEq(splitPoint.slope, cmpPoint.slope);
        assertEq(splitPoint.ts, cmpPoint.ts);
        assertEq(splitPoint.blk, cmpPoint.blk);
    }

    function testSplitWhenSplitPublic() public {
        skip(1 weeks / 2);

        escrow.enableSplitForAll();

        VELO.approve(address(escrow), type(uint256).max);
        escrow.createLock(TOKEN_1, MAXTIME); // 1

        // generate new nfts with same amounts / locktime
        escrow.createLock((TOKEN_1 * 3) / 4, MAXTIME); // 2
        escrow.createLock(TOKEN_1 / 4, MAXTIME); // 3
        uint256 expectedLockTime = escrow.lockedEnd(1);
        uint256 veloSupply = escrow.supply();

        (uint256 splitTokenId1, uint256 splitTokenId2) = escrow.split(1, TOKEN_1 / 4);
        assertEq(splitTokenId1, 4);
        assertEq(splitTokenId2, 5);
        assertEq(escrow.supply(), veloSupply);

        // check new veNFTs have correct amount and locktime
        IVotingEscrow.LockedBalance memory lockedOld = escrow.locked(splitTokenId1);
        assertEq(uint256(uint128(lockedOld.amount)), (TOKEN_1 * 3) / 4);
        assertEq(lockedOld.end, expectedLockTime);
        assertEq(escrow.ownerOf(splitTokenId1), address(owner));

        IVotingEscrow.LockedBalance memory lockedNew = escrow.locked(splitTokenId2);
        assertEq(uint256(uint128(lockedNew.amount)), TOKEN_1 / 4);
        assertEq(lockedNew.end, expectedLockTime);
        assertEq(escrow.ownerOf(splitTokenId2), address(owner));

        // check modified veNFTs are equivalent to brand new veNFTs created with same amount and locktime
        assertEq(escrow.balanceOfNFT(splitTokenId1), escrow.balanceOfNFT(2));
        assertEq(escrow.balanceOfNFT(splitTokenId2), escrow.balanceOfNFT(3));

        // compare point history of first split veNFT and 2
        uint256 lastEpochStored;
        lastEpochStored = escrow.userPointEpoch(1);
        IVotingEscrow.Point memory origPoint = escrow.userPointHistory(splitTokenId1, lastEpochStored);
        lastEpochStored = escrow.userPointEpoch(2);
        IVotingEscrow.Point memory cmpPoint = escrow.userPointHistory(2, lastEpochStored);
        assertEq(origPoint.bias, cmpPoint.bias);
        assertEq(origPoint.slope, cmpPoint.slope);
        assertEq(origPoint.ts, cmpPoint.ts);
        assertEq(origPoint.blk, cmpPoint.blk);

        // compare point history of second split veNFT and 3
        lastEpochStored = escrow.userPointEpoch(splitTokenId2);
        IVotingEscrow.Point memory splitPoint = escrow.userPointHistory(splitTokenId2, lastEpochStored);
        lastEpochStored = escrow.userPointEpoch(3);
        cmpPoint = escrow.userPointHistory(3, lastEpochStored);
        assertEq(splitPoint.bias, cmpPoint.bias);
        assertEq(splitPoint.slope, cmpPoint.slope);
        assertEq(splitPoint.ts, cmpPoint.ts);
        assertEq(splitPoint.blk, cmpPoint.blk);
    }

    function testDelegateVotingPower() public {
        // timestamp: 604801
        VELO.approve(address(escrow), type(uint256).max);
        escrow.createLock(TOKEN_1, MAXTIME);

        vm.startPrank(address(owner2));
        VELO.approve(address(escrow), type(uint256).max);
        escrow.createLock(TOKEN_1, MAXTIME);
        escrow.createLock(TOKEN_1, MAXTIME);
        vm.stopPrank();

        skipAndRoll(1); // 604802

        uint256[] memory tokenIds = escrow.getTokenIdsAt(address(owner), 604801);
        assertEq(tokenIds.length, 1);
        assertEq(tokenIds[0], 1);

        vm.prank(address(owner2));
        escrow.delegate(address(owner));

        tokenIds = escrow.getTokenIdsAt(address(owner), 604802);
        assertEq(tokenIds.length, 3);
        assertEq(tokenIds[0], 1);
        assertEq(tokenIds[1], 2);
        assertEq(tokenIds[2], 3);
        assertEq(escrow.delegates(address(owner2)), address(owner));
        assertEq(escrow.getVotes(address(owner)), 2991780773997936030);
        assertEq(escrow.getVotes(address(owner2)), 0);
        assertEq(escrow.getPastTotalSupply(604802), 2991780773997936030);
    }

    function testMergeAutoDelegatesVotingPower() public {
        vm.startPrank(address(owner2));
        VELO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME);
        vm.stopPrank();

        vm.startPrank(address(owner3));
        VELO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME);
        vm.stopPrank();
        uint256 pre2 = escrow.getVotes(address(owner2));
        uint256 pre3 = escrow.getVotes(address(owner3));

        skipAndRoll(1);

        // merge
        vm.startPrank(address(owner3));
        escrow.approve(address(owner2), 2);
        escrow.transferFrom(address(owner3), address(owner2), 2);
        vm.stopPrank();

        skipAndRoll(1);

        vm.prank(address(owner2));
        escrow.merge(2, 1);

        // assert vote balances
        uint256 post2 = escrow.getVotes(address(owner2));
        assertApproxEqRel(pre2 + pre3, post2, 1e12);
    }
}

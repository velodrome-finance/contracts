pragma solidity 0.8.13;

import "./BaseTest.sol";

contract ManagedNftTest is BaseTest {
    LockedManagedReward lockedManagedReward;
    FreeManagedReward freeManagedReward;

    event DepositManaged(
        address indexed _owner,
        uint256 indexed _tokenId,
        uint256 indexed _mTokenId,
        uint256 _weight,
        uint256 _ts
    );
    event WithdrawManaged(
        address indexed _owner,
        uint256 indexed _tokenId,
        uint256 indexed _mTokenId,
        uint256 _weight,
        uint256 _ts
    );

    function assertNeq(address a, address b) internal {
        if (a == b) {
            emit log("Error: a != b not satisfied [address]");
            emit log_named_address("  Expected", b);
            emit log_named_address("    Actual", a);
            fail();
        }
    }

    function testCreateManagedLockFor() public {
        uint256 mTokenId = escrow.createManagedLockFor(address(owner));

        uint256 expectedTime = ((block.timestamp + MAXTIME) / WEEK) * WEEK;

        assertEq(
            keccak256(abi.encodePacked(escrow.escrowType(mTokenId))),
            keccak256(abi.encodePacked(IVotingEscrow.EscrowType.MANAGED))
        );
        assertEq(escrow.tokenId(), 1);
        assertEq(escrow.ownerOf(1), address(owner));
        assertEq(escrow.balanceOf(address(owner)), 1);
        assertEq(escrow.supply(), 0);
        IVotingEscrow.LockedBalance memory locked = escrow.locked(1);
        assertEq(uint256(uint128(locked.amount)), 0);
        assertEq(locked.end, expectedTime);

        // check locked / free rewards addresses have been set
        assertNeq(escrow.managedToLocked(1), address(0));
        assertNeq(escrow.managedToFree(1), address(0));
        assertFalse(escrow.deactivated(mTokenId));
    }

    function testCannotDepositManagedIfNotVoter() public {
        uint256 mTokenId = escrow.createManagedLockFor(address(owner2));

        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        assertEq(escrow.lockedEnd(tokenId), 126403200);
        uint256 supply = escrow.supply();
        uint256 totalSupply = escrow.totalSupply();

        skip(1 weeks);
        vm.expectRevert("VotingEscrow: not voter");
        escrow.depositManaged(tokenId, mTokenId);
    }

    function testDepositManaged() public {
        uint256 mTokenId = escrow.createManagedLockFor(address(owner2));

        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        assertEq(escrow.lockedEnd(tokenId), 126403200);
        uint256 supply = escrow.supply();
        uint256 totalSupply = escrow.totalSupply();

        skip(1 weeks);
        uint256 timestamp = block.timestamp;
        vm.expectEmit(true, false, false, false, address(escrow));
        emit DepositManaged(address(owner), tokenId, mTokenId, TOKEN_1, timestamp);
        voter.depositManaged(tokenId, mTokenId);

        // updates balance of managed nft
        assertEq(voter.lastVoted(tokenId), timestamp);
        assertEq(escrow.idToManaged(tokenId), mTokenId);
        assertEq(escrow.weights(tokenId, mTokenId), TOKEN_1);
        assertEq(
            keccak256(abi.encodePacked(escrow.escrowType(tokenId))),
            keccak256(abi.encodePacked(IVotingEscrow.EscrowType.LOCKED))
        );

        IVotingEscrow.LockedBalance memory locked;

        // zero out existing deposit
        locked = escrow.locked(tokenId);
        assertEq(uint256(uint128(locked.amount)), 0);
        assertEq(locked.end, 0);

        // transfer deposit to managed nft, max lock
        locked = escrow.locked(mTokenId);
        assertEq(uint256(uint128(locked.amount)), TOKEN_1);
        assertEq(locked.end, 127008000);

        // check deposit represented in ve
        assertEq(escrow.balanceOfNFT(mTokenId), 997260265926760005);
        assertEq(escrow.balanceOfNFT(tokenId), 0);
        assertEq(escrow.ownerOf(tokenId), address(owner));
        assertEq(escrow.supply(), supply);
        assertEq(escrow.totalSupply(), totalSupply);

        // check deposit represented in locked / free managed rewards
        lockedManagedReward = LockedManagedReward(escrow.managedToLocked(mTokenId));
        assertEq(lockedManagedReward.balanceOf(tokenId), TOKEN_1);
        assertEq(lockedManagedReward.totalSupply(), TOKEN_1);
        freeManagedReward = FreeManagedReward(escrow.managedToFree(mTokenId));
        assertEq(freeManagedReward.balanceOf(tokenId), TOKEN_1);
        assertEq(freeManagedReward.totalSupply(), TOKEN_1);
    }

    function testCannotDepositManagedIntoNonManagedNft() public {
        VELO.approve(address(escrow), type(uint256).max);
        escrow.createLock(TOKEN_1, MAXTIME);
        escrow.createLock(TOKEN_1, MAXTIME);

        vm.expectRevert("VotingEscrow: can only deposit into managed nft");
        voter.depositManaged(1, 2);
    }

    function testCannotDepositManagedWithManagedNft() public {
        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        uint256 mTokenId2 = escrow.createManagedLockFor(address(owner));

        vm.expectRevert("VotingEscrow: can only deposit normal nft");
        voter.depositManaged(mTokenId2, mTokenId);
    }

    function testCannotDepositManagedWithAlreadyLockedNft() public {
        uint256 mTokenId = escrow.createManagedLockFor(address(owner));

        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        voter.depositManaged(tokenId, mTokenId);

        skipToNextEpoch(1);

        vm.expectRevert("VotingEscrow: can only deposit normal nft");
        voter.depositManaged(tokenId, mTokenId);
    }

    function testCannotDepositManagedWithAlreadyVotedNft() public {
        skip(1 hours + 1);

        VELO.approve(address(escrow), type(uint256).max);
        escrow.createLock(TOKEN_1, MAXTIME);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pair);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        voter.vote(1, pools, weights);

        escrow.createManagedLockFor(address(owner));

        skip(1 hours);

        vm.expectRevert("Voter: already voted or deposited this epoch");
        voter.depositManaged(1, 2);
    }

    function testCannotDepositManagedWithExpiredNft() public {
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, 1 weeks);
        uint256 mTokenId = escrow.createManagedLockFor(address(owner));

        skip(2 weeks);

        vm.expectRevert("VotingEscrow: no balance to deposit");
        voter.depositManaged(tokenId, mTokenId);
    }

    function testCannotDepositManagedWithFlashLoanedNft() public {
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        uint256 mTokenId = escrow.createManagedLockFor(address(owner));

        // simulate flashloan by transferring, but not modifying time / block number
        escrow.transferFrom(address(owner), address(owner2), tokenId);

        vm.prank(address(owner2));
        vm.expectRevert("VotingEscrow: flash nft protection");
        voter.depositManaged(tokenId, mTokenId);
    }

    function testCannotWithdrawManagedIfNotLocked() public {
        escrow.createManagedLockFor(address(owner));
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        vm.expectRevert("VotingEscrow: nft not locked");
        voter.withdrawManaged(tokenId);
    }

    function testCannotWithdrawManagedIfNotVoter() public {
        uint256 mTokenId = escrow.createManagedLockFor(address(owner2));
        escrow.createManagedLockFor(address(owner));
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        voter.depositManaged(tokenId, mTokenId);

        skipToNextEpoch(1);

        vm.expectRevert("VotingEscrow: not voter");
        escrow.withdrawManaged(tokenId);
    }

    function testWithdrawManagedWithZeroReward() public {
        uint256 mTokenId = escrow.createManagedLockFor(address(owner2));
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        voter.depositManaged(tokenId, mTokenId);
        uint256 supply = escrow.supply();
        uint256 totalSupply = escrow.totalSupply();

        skip(2 weeks);
        vm.expectEmit(true, false, false, false, address(escrow));
        emit WithdrawManaged(address(owner), tokenId, mTokenId, TOKEN_1, block.timestamp);
        voter.withdrawManaged(tokenId);

        IVotingEscrow.LockedBalance memory locked;

        /// on withdraw, re-lock for max-lock time rounded down by week
        // start time: 126403200
        // lock time = start time + two epochs = 126403200 + 604800 * 2 = 127612800
        locked = escrow.locked(tokenId);
        assertEq(uint256(uint128(locked.amount)), TOKEN_1);
        assertEq(locked.end, 127612800);

        locked = escrow.locked(mTokenId);
        assertEq(uint256(uint128(locked.amount)), 0);
        assertEq(locked.end, 127612800);

        assertEq(escrow.balanceOfNFT(mTokenId), 0);
        assertEq(escrow.balanceOfNFT(tokenId), 997260265926760005);
        assertEq(escrow.idToManaged(tokenId), 0);
        assertEq(escrow.weights(tokenId, mTokenId), 0);
        assertEq(escrow.supply(), supply);
        assertEq(escrow.totalSupply(), totalSupply);
        assertEq(
            keccak256(abi.encodePacked(escrow.escrowType(tokenId))),
            keccak256(abi.encodePacked(IVotingEscrow.EscrowType.NORMAL))
        );

        // check withdrawal represented in locked / free managed rewards
        lockedManagedReward = LockedManagedReward(escrow.managedToLocked(mTokenId));
        assertEq(lockedManagedReward.balanceOf(tokenId), 0);
        assertEq(lockedManagedReward.totalSupply(), 0);
        freeManagedReward = FreeManagedReward(escrow.managedToFree(mTokenId));
        assertEq(freeManagedReward.balanceOf(tokenId), 0);
        assertEq(freeManagedReward.totalSupply(), 0);
    }

    function testWithdrawManagedWithLockedReward() public {
        uint256 mTokenId = escrow.createManagedLockFor(address(owner2));
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        voter.depositManaged(tokenId, mTokenId);
        uint256 supply = escrow.supply();

        // locked rewards initially empty
        lockedManagedReward = LockedManagedReward(escrow.managedToLocked(mTokenId));
        assertEq(VELO.balanceOf(address(lockedManagedReward)), 0);
        freeManagedReward = FreeManagedReward(escrow.managedToFree(mTokenId));
        assertEq(VELO.balanceOf(address(freeManagedReward)), 0);

        // simulate locked rewards (i.e. rebase / compound) via increaseAmount
        vm.startPrank(address(owner2));
        VELO.approve(address(escrow), TOKEN_1);
        escrow.increaseAmount(mTokenId, TOKEN_1);
        vm.stopPrank();
        supply += TOKEN_1;
        uint256 totalSupply = escrow.totalSupply();

        assertEq(escrow.supply(), supply);
        uint256 epochStart = _getEpochStart(block.timestamp);
        assertEq(VELO.balanceOf(address(lockedManagedReward)), TOKEN_1);
        assertEq(lockedManagedReward.tokenRewardsPerEpoch(address(VELO), epochStart), TOKEN_1);

        skip(2 weeks);
        vm.expectEmit(true, false, false, false, address(escrow));
        emit WithdrawManaged(address(owner), tokenId, mTokenId, TOKEN_1, block.timestamp);
        voter.withdrawManaged(tokenId);

        IVotingEscrow.LockedBalance memory locked;

        /// on withdraw, re-lock for max-lock time rounded down by week
        // start time: 126403200
        // lock time = start time + two epochs = 126403200 + 604800 * 2 = 127612800
        locked = escrow.locked(tokenId);
        assertEq(uint256(uint128(locked.amount)), TOKEN_1 * 2);
        assertEq(locked.end, 127612800);

        locked = escrow.locked(mTokenId);
        assertLt(uint256(uint128(locked.amount)), 1e6);
        assertEq(locked.end, 127612800);

        assertEq(escrow.balanceOfNFT(mTokenId), 0);
        assertEq(escrow.balanceOfNFT(tokenId), 1994520531979318409);
        assertEq(escrow.idToManaged(tokenId), 0);
        assertEq(escrow.weights(tokenId, mTokenId), 0);
        assertEq(escrow.supply(), supply);
        assertEq(escrow.totalSupply(), totalSupply);
        assertEq(
            keccak256(abi.encodePacked(escrow.escrowType(tokenId))),
            keccak256(abi.encodePacked(IVotingEscrow.EscrowType.NORMAL))
        );

        // check withdrawal represented in locked managed rewards
        assertEq(lockedManagedReward.balanceOf(tokenId), 0);
        assertEq(lockedManagedReward.totalSupply(), 0);
        assertEq(freeManagedReward.balanceOf(tokenId), 0);
        assertEq(freeManagedReward.totalSupply(), 0);

        assertEq(VELO.balanceOf(address(escrow)), TOKEN_1 * 2);
        assertEq(VELO.balanceOf(address(lockedManagedReward)), 0);
    }

    function testWithdrawManagedWithFreeReward() public {
        uint256 mTokenId = escrow.createManagedLockFor(address(owner2));
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        voter.depositManaged(tokenId, mTokenId);
        uint256 supply = escrow.supply();

        // locked rewards initially empty
        lockedManagedReward = LockedManagedReward(escrow.managedToLocked(mTokenId));
        assertEq(VELO.balanceOf(address(lockedManagedReward)), 0);
        freeManagedReward = FreeManagedReward(escrow.managedToFree(mTokenId));
        assertEq(VELO.balanceOf(address(freeManagedReward)), 0);

        // simulate free rewards via notifyRewardAmount
        VELO.approve(address(freeManagedReward), TOKEN_1);
        freeManagedReward.notifyRewardAmount(address(VELO), TOKEN_1);

        assertEq(escrow.supply(), supply);
        uint256 epochStart = _getEpochStart(block.timestamp);
        assertEq(VELO.balanceOf(address(freeManagedReward)), TOKEN_1);
        assertEq(freeManagedReward.tokenRewardsPerEpoch(address(VELO), epochStart), TOKEN_1);

        skip(2 weeks);
        vm.expectEmit(true, false, false, false, address(escrow));
        emit WithdrawManaged(address(owner), tokenId, mTokenId, TOKEN_1, block.timestamp);
        voter.withdrawManaged(tokenId);

        IVotingEscrow.LockedBalance memory locked;

        /// on withdraw, re-lock for max-lock time rounded down by week
        // start time: 126403200
        // lock time = start time + two epochs = 126403200 + 604800 * 2 = 127612800
        locked = escrow.locked(tokenId);
        assertEq(uint256(uint128(locked.amount)), TOKEN_1);
        assertEq(locked.end, 127612800);

        locked = escrow.locked(mTokenId);
        assertLt(uint256(uint128(locked.amount)), 1e6);
        assertEq(locked.end, 127612800);

        assertEq(escrow.balanceOfNFT(mTokenId), 0);
        assertEq(escrow.balanceOfNFT(tokenId), 997260265926760005);
        assertEq(escrow.idToManaged(tokenId), 0);
        assertEq(escrow.weights(tokenId, mTokenId), 0);
        assertEq(escrow.supply(), supply);
        assertEq(
            keccak256(abi.encodePacked(escrow.escrowType(tokenId))),
            keccak256(abi.encodePacked(IVotingEscrow.EscrowType.NORMAL))
        );

        // check withdrawal represented in locked managed rewards
        assertEq(lockedManagedReward.balanceOf(tokenId), 0);
        assertEq(lockedManagedReward.totalSupply(), 0);
        assertEq(freeManagedReward.balanceOf(tokenId), 0);
        assertEq(freeManagedReward.totalSupply(), 0);

        assertEq(VELO.balanceOf(address(escrow)), TOKEN_1);
        assertEq(VELO.balanceOf(address(lockedManagedReward)), 0);

        skip(1 hours);
        // collect reward after withdrawal
        address[] memory rewards = new address[](1);
        rewards[0] = address(VELO);
        uint256 pre = VELO.balanceOf(address(owner));
        freeManagedReward.getReward(tokenId, rewards);
        uint256 post = VELO.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1);
    }

    /// check locked nft cannot be modified
    function testCannotIncreaseAmountWithLockedNft() public {
        uint256 mTokenId = escrow.createManagedLockFor(address(owner2));

        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        voter.depositManaged(tokenId, mTokenId);

        vm.expectRevert("VotingEscrow: nft locked");
        escrow.increaseAmount(tokenId, TOKEN_1);
    }

    function testCannotIncreaseUnlockTimeWithLockedNft() public {
        uint256 mTokenId = escrow.createManagedLockFor(address(owner2));

        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        voter.depositManaged(tokenId, mTokenId);

        vm.expectRevert("VotingEscrow: nft locked");
        escrow.increaseUnlockTime(tokenId, MAXTIME);
    }

    function testCannotWithdrawLockedVeNft() public {
        // lock for four weeks
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, 4 * 7 * 86400);

        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        voter.depositManaged(tokenId, mTokenId);

        skip(8 weeks);

        vm.expectRevert("VotingEscrow: can only withdraw from normal nft");
        escrow.withdraw(tokenId);
    }

    function testCannotMergeFromLockedNft() public {
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        uint256 tokenId2 = escrow.createLock(TOKEN_1, MAXTIME);

        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        voter.depositManaged(tokenId, mTokenId);

        vm.expectRevert("VotingEscrow: can only merge normal from nft");
        escrow.merge(tokenId, tokenId2);
    }

    function testCannotMergeToLockedNft() public {
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        uint256 tokenId2 = escrow.createLock(TOKEN_1, MAXTIME);

        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        voter.depositManaged(tokenId, mTokenId);

        vm.expectRevert("VotingEscrow: can only merge normal to nft");
        escrow.merge(tokenId2, tokenId);
    }

    function testCannotTransferLockedVeNft() public {
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        voter.depositManaged(tokenId, mTokenId);

        vm.expectRevert("VotingEscrow: nft locked");
        escrow.transferFrom(address(this), address(owner2), tokenId);
    }

    function testCannotMergeFromManagedNft() public {
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        uint256 tokenId2 = escrow.createLock(TOKEN_1, MAXTIME);

        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        voter.depositManaged(tokenId, mTokenId);

        vm.expectRevert("VotingEscrow: can only merge normal from nft");
        escrow.merge(mTokenId, tokenId2);
    }

    function testCannotMergeToManagedNft() public {
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        uint256 tokenId2 = escrow.createLock(TOKEN_1, MAXTIME);

        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        voter.depositManaged(tokenId, mTokenId);

        vm.expectRevert("VotingEscrow: can only merge normal to nft");
        escrow.merge(tokenId2, mTokenId);
    }

    function testTransferManagedNft() public {
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        voter.depositManaged(tokenId, mTokenId);

        skip(1 hours);

        escrow.transferFrom(address(owner), address(owner2), mTokenId);

        assertEq(escrow.ownerOf(mTokenId), address(owner2));
    }

    function testCannotWithdrawManagedNft() public {
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, 4 * 7 * 86400);

        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        voter.depositManaged(tokenId, mTokenId);

        skip(400 weeks);

        vm.expectRevert("VotingEscrow: can only withdraw from normal nft");
        escrow.withdraw(mTokenId);
    }

    function testCreateManagedLockForAccessControl() public {
        address allowedManager = escrow.allowedManager();
        assertEq(voter.governor(), address(governor));
        assertEq(allowedManager, address(owner));

        uint256 mTokenId;
        // governor can create managed veNFT - no revert
        vm.prank(address(governor));
        mTokenId = escrow.createManagedLockFor(address(owner3));
        assertEq(mTokenId, 1);
        // owner2 cannot create managed veNFT
        vm.expectRevert("VotingEscrow: not allowed");
        vm.prank(address(owner2));
        escrow.createManagedLockFor(address(owner3));

        // change the allowedManager
        vm.prank(address(governor));
        escrow.setAllowedManager(address(owner2));

        // now both governor and owner2 (aka allowedManager) can create managed veNFTs
        vm.prank(address(governor));
        mTokenId = escrow.createManagedLockFor(address(owner3));
        assertEq(mTokenId, 2);
        vm.prank(address(owner2));
        mTokenId = escrow.createManagedLockFor(address(owner3));
        assertEq(mTokenId, 3);
        // only governor / owner2 have access
        vm.expectRevert("VotingEscrow: not allowed");
        vm.prank(address(owner3));
        escrow.createManagedLockFor(address(owner3));
    }

    function testCannotSetAllowedManagerWithSameAddress() public {
        vm.prank(address(governor));
        escrow.setAllowedManager(address(owner2));

        assertEq(escrow.allowedManager(), address(owner2));

        vm.prank(address(governor));
        vm.expectRevert("VotingEscrow: same address");
        escrow.setAllowedManager(address(owner2));
    }

    function testCannotSetAllowedManagerWithZeroAddress() public {
        vm.prank(address(governor));
        vm.expectRevert("VotingEscrow: zero address");
        escrow.setAllowedManager(address(0));
    }

    function testSetAllowedManager() public {
        assertEq(escrow.allowedManager(), address(owner));
        // Voter.governor can change the allowedManager to a new address
        vm.prank(address(governor));
        escrow.setAllowedManager(address(owner2));
        assertEq(escrow.allowedManager(), address(owner2));

        // new address does not have permissions to modify the allowedManager
        vm.expectRevert("VotingEscrow: not governor");
        vm.prank(address(owner2));
        escrow.setAllowedManager(address(owner3));

        // governor can still change the allowedManager
        vm.prank(address(governor));
        escrow.setAllowedManager(address(owner3));
        assertEq(escrow.allowedManager(), address(owner3));
    }

    function testCannotSetManagedStateWithSameState() public {
        uint256 mTokenId = escrow.createManagedLockFor(address(owner));

        vm.expectRevert("VotingEscrow: same state");
        escrow.setManagedState(mTokenId, false);
    }

    function testCannotSetManagedStateWithNotManagedNFT() public {
        VELO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        vm.expectRevert("VotingEscrow: can only modify managed nft state");
        escrow.setManagedState(tokenId, false);
    }

    function testCannotSetManagedStateIfNotEmergencyCouncilOrGovernor() public {
        uint256 mTokenId = escrow.createManagedLockFor(address(owner));

        vm.expectRevert("VotingEscrow: not emergency council");
        vm.prank(address(owner2));
        escrow.setManagedState(mTokenId, false);
    }

    function testSetManagedStateWithEmergencyCouncil() public {
        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        assertFalse(escrow.deactivated(mTokenId));

        skipAndRoll(1);

        escrow.setManagedState(mTokenId, true);
        assertTrue(escrow.deactivated(mTokenId));

        skipAndRoll(1);

        escrow.setManagedState(mTokenId, false);
        assertFalse(escrow.deactivated(mTokenId));
    }

    function testSetManagedStateWithGovernor() public {
        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        assertFalse(escrow.deactivated(mTokenId));

        skipAndRoll(1);

        vm.prank(address(governor));
        escrow.setManagedState(mTokenId, true);
        assertTrue(escrow.deactivated(mTokenId));

        skipAndRoll(1);

        vm.prank(address(governor));
        escrow.setManagedState(mTokenId, false);
        assertFalse(escrow.deactivated(mTokenId));
    }
}

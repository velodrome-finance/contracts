// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "test/BaseTest.sol";
import {DelegationHelperLibrary} from "contracts/libraries/DelegationHelperLibrary.sol";

contract GetVotesTest is BaseTest {
    using DelegationHelperLibrary for IVotingEscrow;
    using SafeCastLibrary for int128;

    uint256 public tokenId;
    uint256 public tokenId2; // lock to be used for delegations
    uint256 public mTokenId;
    uint256 public proposalId;
    uint256 public snapshotTime;

    uint256 public snapshotBeforeDepositManaged;

    function _setUp() public override {
        VELO.approve(address(escrow), 150 * TOKEN_1);
        tokenId = escrow.createLock(100 * TOKEN_1, MAXTIME);
        tokenId2 = escrow.createLock(50 * TOKEN_1, MAXTIME);
        mTokenId = escrow.createManagedLockFor(address(owner));

        proposalId = governor.propose(tokenId, new address[](1), new uint256[](1), new bytes[](1), "");
        snapshotTime = governor.proposalSnapshot(proposalId);

        skipAndRoll(2);
    }

    function test_GivenVeNFTIsManagedEscrowType() external {
        assertTrue(escrow.escrowType(mTokenId) == IVotingEscrow.EscrowType.MANAGED);
        // It should revert with "Governor: managed nft cannot vote"
        vm.expectRevert("Governor: managed nft cannot vote");
        governor.getVotes(mTokenId, snapshotTime);
    }

    function test_GivenVeNFTIsNormalEscrowType() external view {
        assertTrue(escrow.escrowType(tokenId) == IVotingEscrow.EscrowType.NORMAL);
        // It should return Voting Weight at Proposal Snapshot
        uint256 weightAtSnapshot = escrow.getPastVotes(address(this), tokenId, snapshotTime);
        assertEq(governor.getVotes(tokenId, snapshotTime), weightAtSnapshot);
        assertGt(weightAtSnapshot, 0);
    }

    modifier givenVeNFTIsLockedEscrowType() {
        skip(1 hours); // Skip distribute window
        snapshotBeforeDepositManaged = vm.snapshot(); // Snapshot state before Deposit

        assertGt(escrow.getPastVotes(address(this), tokenId, snapshotTime), 0);

        voter.depositManaged(tokenId, mTokenId);
        assertTrue(escrow.escrowType(tokenId) == IVotingEscrow.EscrowType.LOCKED);

        // Balance at snapshot set to 0 after `depositManaged`
        assertEq(escrow.getPastVotes(address(this), tokenId, snapshotTime), 0);
        _;
    }

    function test_GivenTheUnderlyingMveNFTIsDelegating() external givenVeNFTIsLockedEscrowType {
        VELO.approve(address(escrow), TOKEN_1);
        uint256 delegateTokenId = escrow.createLock(TOKEN_1, MAXTIME);
        escrow.delegate(mTokenId, delegateTokenId);

        // Check delegatee in last checkpoint
        uint48 index = escrow.numCheckpoints(mTokenId) - 1;
        uint256 delegatee = escrow.checkpoints(mTokenId, index).delegatee;
        assertEq(delegatee, delegateTokenId);

        uint256 weightAtSnapshot = escrow.getPastVotes(address(this), tokenId, snapshotTime);
        assertEq(weightAtSnapshot, 0); // Voting Weight at snapshot is 0 after `depositManaged`
        // It should return Voting Weight at Proposal Snapshot
        assertEq(governor.getVotes(tokenId, snapshotTime), weightAtSnapshot);
    }

    modifier givenTheUnderlyingMveNFTIsNotDelegating() {
        uint48 index = escrow.numCheckpoints(mTokenId) - 1;
        assertEq(escrow.checkpoints(mTokenId, index).delegatee, 0);
        _;
    }

    function test_GivenDepositIntoManagedAfterSnapshotTimestamp()
        external
        givenVeNFTIsLockedEscrowType
        givenTheUnderlyingMveNFTIsNotDelegating
    {
        vm.revertTo(snapshotBeforeDepositManaged); // Rollback before `depositManaged`
        assertTrue(escrow.escrowType(tokenId) == IVotingEscrow.EscrowType.NORMAL);

        // Fast forward to snapshot time + 1 block (12 seconds), so that the snapshot becomes finalized
        vm.warp(snapshotTime + 12 seconds);

        uint256 weightAtSnapshot = escrow.getPastVotes(address(this), tokenId, snapshotTime);
        assertGt(weightAtSnapshot, 0);

        voter.depositManaged(tokenId, mTokenId);

        // Lock was deposited into managed after snapshot time
        assertTrue(escrow.escrowType(tokenId) == IVotingEscrow.EscrowType.LOCKED);
        assertGt(escrow.userPointHistory(tokenId, escrow.userPointEpoch(tokenId)).ts, snapshotTime);
        // Voting Weight should remain the same since `depositManaged` was called after `snapshotTime`
        assertEq(weightAtSnapshot, escrow.getPastVotes(address(this), tokenId, snapshotTime));

        // It should return Voting Weight at Proposal Snapshot
        assertEq(governor.getVotes(tokenId, snapshotTime), weightAtSnapshot);
    }

    modifier givenDepositIntoManagedBeforeOrAtSnapshotTimestamp() {
        // Original lock was deposited before snapshotTime
        assertTrue(escrow.escrowType(tokenId) == IVotingEscrow.EscrowType.LOCKED);
        uint256 depositTimestamp = escrow.userPointHistory(tokenId, escrow.userPointEpoch(tokenId)).ts;
        assertLe(depositTimestamp, snapshotTime);
        // Voting Power at Snapshot should be 0, since `depositManaged` was called before or at Snapshot Timestamp
        assertEq(escrow.getPastVotes(address(this), tokenId, snapshotTime), 0);
        _;
    }

    function test_WhenAccountIsNotOwnerInLastCheckpoint()
        external
        givenVeNFTIsLockedEscrowType
        givenTheUnderlyingMveNFTIsNotDelegating
        givenDepositIntoManagedBeforeOrAtSnapshotTimestamp
    {
        uint48 index = escrow.numCheckpoints(tokenId) - 1;
        IVotingEscrow.Checkpoint memory lastCheckpoint = escrow.checkpoints(tokenId, index);
        address newOwner = makeAddr("testAddr");
        assertNotEq(lastCheckpoint.owner, newOwner);

        // It should return 0
        assertEq(governor.getVotes(newOwner, tokenId, snapshotTime), 0);
    }

    function test_WhenAccountIsOwnerInLastCheckpoint()
        external
        givenVeNFTIsLockedEscrowType
        givenTheUnderlyingMveNFTIsNotDelegating
        givenDepositIntoManagedBeforeOrAtSnapshotTimestamp
    {
        uint48 index = escrow.numCheckpoints(tokenId) - 1;
        IVotingEscrow.Checkpoint memory lastCheckpoint = escrow.checkpoints(tokenId, index);
        assertEq(lastCheckpoint.owner, address(this));

        // Initial Contribution to mVeNFT should be accounted for
        uint256 initialContribution = escrow.weights(tokenId, mTokenId);
        assertEq(governor.getVotes(tokenId, snapshotTime), initialContribution);

        // Delegate to `tokenId` from another lock
        escrow.lockPermanent(tokenId2);
        escrow.delegate(tokenId2, tokenId);
        uint256 delegatedBalance = escrow.locked(tokenId2).amount.toUint256();
        // Voting Power delegated to `tokenId` should be accounted for
        assertEq(governor.getVotes(tokenId, snapshotTime), initialContribution + delegatedBalance);

        // Simulate rebase/compound to accumulate `earned`, via `increaseAmount`
        assertEq(IVotingEscrow(escrow).earned(mTokenId, tokenId, snapshotTime), 0);

        uint256 amountEarned = 10 * TOKEN_1;
        VELO.approve(address(escrow), amountEarned);
        escrow.increaseAmount(mTokenId, amountEarned);

        assertEq(IVotingEscrow(escrow).earned(mTokenId, tokenId, snapshotTime), amountEarned);

        // It should return the initial contribution to mveNFT + accrued locked rewards + delegated balance
        assertEq(governor.getVotes(tokenId, snapshotTime), initialContribution + amountEarned + delegatedBalance);
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "test/BaseTest.sol";
import {VelodromeTimeLibrary} from "contracts/libraries/VelodromeTimeLibrary.sol";
import {DelegationHelperLibrary} from "contracts/libraries/DelegationHelperLibrary.sol";

contract GetVotesFuzzTest is BaseTest {
    using DelegationHelperLibrary for IVotingEscrow;
    using SafeCastLibrary for int128;

    uint256 public tokenId;
    uint256 public tokenId2; // lock to be used for delegations
    uint256 public mTokenId;
    uint256 public proposalId;
    uint256 public snapshotTime;

    uint256 public snapshotBeforeDepositManaged;

    // Maximum number of tokens to be used in fuzzing
    uint256 public constant MAX_TOKENS = type(uint128).max / 2; // Lock amount cannot exceed type(int128).max

    function _setUp() public override {
        VELO.approve(address(escrow), 150 * TOKEN_1);
        tokenId = escrow.createLock(100 * TOKEN_1, MAXTIME);
        tokenId2 = escrow.createLock(50 * TOKEN_1, MAXTIME);
        mTokenId = escrow.createManagedLockFor(address(owner));

        proposalId = governor.propose(tokenId, new address[](1), new uint256[](1), new bytes[](1), "");
        snapshotTime = governor.proposalSnapshot(proposalId);

        skipAndRoll(2);
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

    modifier givenTheUnderlyingMveNFTIsNotDelegating() {
        uint48 index = escrow.numCheckpoints(mTokenId) - 1;
        assertEq(escrow.checkpoints(mTokenId, index).delegatee, 0);
        _;
    }

    function testFuzz_GivenDepositIntoManagedAfterSnapshotTimestamp(uint40 timeskip)
        external
        givenVeNFTIsLockedEscrowType
        givenTheUnderlyingMveNFTIsNotDelegating
    {
        vm.revertTo(snapshotBeforeDepositManaged); // Rollback before `depositManaged`
        assertTrue(escrow.escrowType(tokenId) == IVotingEscrow.EscrowType.NORMAL);

        // Fast forward to snapshot time + 1 block (12 seconds), so that the snapshot becomes finalized
        vm.warp(snapshotTime + 12 seconds);
        timeskip = uint40(bound(timeskip, 1, VelodromeTimeLibrary.epochVoteEnd(block.timestamp) - block.timestamp));
        skip(timeskip); // Skip anywhere within the allowed deposit window

        assertTrue(escrow.escrowType(tokenId) == IVotingEscrow.EscrowType.NORMAL);
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

    modifier givenDepositIntoManagedBeforeOrAtSnapshotTimestamp(uint40 timeskip) {
        vm.revertTo(snapshotBeforeDepositManaged); // Rollback before `depositManaged`
        assertTrue(escrow.escrowType(tokenId) == IVotingEscrow.EscrowType.NORMAL);

        // Skip somewhere before Snapshot Timestamp
        timeskip = uint40(bound(timeskip, 0, snapshotTime - block.timestamp));
        skip(timeskip);

        voter.depositManaged(tokenId, mTokenId);
        assertTrue(escrow.escrowType(tokenId) == IVotingEscrow.EscrowType.LOCKED);

        // Original lock was deposited before or at snapshotTime
        assertTrue(escrow.escrowType(tokenId) == IVotingEscrow.EscrowType.LOCKED);
        uint256 depositTimestamp = escrow.userPointHistory(tokenId, escrow.userPointEpoch(tokenId)).ts;
        assertLe(depositTimestamp, snapshotTime);
        // Voting Power at Snapshot should be 0, since `depositManaged` was called before or at Snapshot Timestamp
        assertEq(escrow.getPastVotes(address(this), tokenId, snapshotTime), 0);
        _;
    }

    function testFuzz_WhenAccountIsNotOwnerInLastCheckpoint(
        address newOwner,
        uint40 timeskip,
        uint40 delegationTimestamp
    )
        external
        givenVeNFTIsLockedEscrowType
        givenTheUnderlyingMveNFTIsNotDelegating
        givenDepositIntoManagedBeforeOrAtSnapshotTimestamp(timeskip)
    {
        vm.assume(newOwner != address(this));
        // Overwrite `fromTimestamp` in last delegation checkpoint to be equal or smaller than `snapshotTime`
        delegationTimestamp = uint40(bound(delegationTimestamp, 0, snapshotTime));
        IVotingEscrow.Checkpoint memory lastCheckpoint = escrow.checkpoints(tokenId, escrow.numCheckpoints(tokenId) - 1);
        vm.mockCall(
            address(escrow),
            abi.encodeWithSelector(VotingEscrow.checkpoints.selector, tokenId, escrow.numCheckpoints(tokenId) - 1),
            abi.encode(
                delegationTimestamp, lastCheckpoint.owner, lastCheckpoint.delegatedBalance, lastCheckpoint.delegatee
            )
        );

        lastCheckpoint = escrow.checkpoints(tokenId, escrow.numCheckpoints(tokenId) - 1);
        assertLe(lastCheckpoint.fromTimestamp, snapshotTime);
        assertNotEq(lastCheckpoint.owner, newOwner);

        // It should return 0
        assertEq(governor.getVotes(newOwner, tokenId, snapshotTime), 0);
    }

    function testFuzz_WhenAccountIsOwnerInLastCheckpoint(
        uint256 delegatedBalance,
        uint256 amountEarned,
        uint40 timeskip,
        uint40 delegationTimestamp
    )
        external
        givenVeNFTIsLockedEscrowType
        givenTheUnderlyingMveNFTIsNotDelegating
        givenDepositIntoManagedBeforeOrAtSnapshotTimestamp(timeskip)
    {
        // Overwrite `fromTimestamp` in last delegation checkpoint to be equal or smaller than `snapshotTime`
        delegationTimestamp = uint40(bound(delegationTimestamp, 0, snapshotTime));
        IVotingEscrow.Checkpoint memory lastCheckpoint = escrow.checkpoints(tokenId, escrow.numCheckpoints(tokenId) - 1);
        vm.mockCall(
            address(escrow),
            abi.encodeWithSelector(VotingEscrow.checkpoints.selector, tokenId, escrow.numCheckpoints(tokenId) - 1),
            abi.encode(
                delegationTimestamp, lastCheckpoint.owner, lastCheckpoint.delegatedBalance, lastCheckpoint.delegatee
            )
        );

        lastCheckpoint = escrow.checkpoints(tokenId, escrow.numCheckpoints(tokenId) - 1);
        assertLe(lastCheckpoint.fromTimestamp, snapshotTime);
        assertEq(lastCheckpoint.owner, address(this));

        amountEarned = bound(amountEarned, 1, MAX_TOKENS / 2);
        delegatedBalance = bound(delegatedBalance, 1, MAX_TOKENS / 2);
        deal(address(VELO), address(this), delegatedBalance + amountEarned);

        // Initial Contribution to mVeNFT should be accounted for
        uint256 initialContribution = escrow.weights(tokenId, mTokenId);
        assertEq(governor.getVotes(tokenId, snapshotTime), initialContribution);

        // Delegate to `tokenId` from a new lock
        VELO.approve(address(escrow), delegatedBalance);
        uint256 delegateTokenId = escrow.createLock(delegatedBalance, MAXTIME);
        escrow.lockPermanent(delegateTokenId);
        escrow.delegate(delegateTokenId, tokenId);
        // Voting Power delegated to `tokenId` should be accounted for
        assertEq(governor.getVotes(tokenId, snapshotTime), initialContribution + delegatedBalance);

        // Simulate rebase/compound to accumulate `earned`, via `increaseAmount`
        assertEq(IVotingEscrow(escrow).earned(mTokenId, tokenId, snapshotTime), 0);

        VELO.approve(address(escrow), amountEarned);
        escrow.increaseAmount(mTokenId, amountEarned);

        assertEq(IVotingEscrow(escrow).earned(mTokenId, tokenId, snapshotTime), amountEarned);

        // It should return the initial contribution to mveNFT + accrued locked rewards + delegated balance
        assertEq(governor.getVotes(tokenId, snapshotTime), initialContribution + amountEarned + delegatedBalance);
    }
}

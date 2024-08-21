// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../BaseTest.sol";
import "contracts/libraries/VelodromeTimeLibrary.sol";

contract ManagedNftVotingTest is BaseTest {
    address public token;

    // Maximum number of tokens to be used in fuzzing
    uint256 public constant MAX_TOKENS = type(uint128).max / 2; // Lock amount cannot exceed type(int128).max

    function _setUp() public override {
        VELO.approve(address(escrow), 97 * TOKEN_1);
        escrow.createLock(97 * TOKEN_1, MAXTIME); // 1

        skipAndRoll(2);

        token = address(new MockERC20("TEST", "TEST", 18));
    }

    function testCastVoteAfterDepositIntoManagedVeNFTNotDelegating() public {
        // Test Flow: Deposit Managed => Vote
        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        escrow.lockPermanent(tokenId);

        uint256 pid = createProposal();
        uint256 snapshotTime = governor.proposalSnapshot(pid);

        // Fast forward 1 block (2 seconds) so the snapshot checkpoint is now finalized
        skipAndRoll(2);

        assertEq(governor.getVotes(tokenId, snapshotTime), TOKEN_1);
        voter.depositManaged(tokenId, mTokenId);
        // Voting Power remains the same after deposit into managed
        assertEq(governor.getVotes(tokenId, snapshotTime), TOKEN_1);

        governor.castVote(pid, tokenId, 1);
        (, uint256 votes,) = governor.proposalVotes(pid);

        assertEq(votes, TOKEN_1);
    }

    function testCannotDoubleVoteAfterDepositAndWithdrawIntoManagedVeNFTNotDelegating() public {
        // Test Flow: Deposit Managed => Vote => Withdraw => Vote

        // Warp to 2 days and 2 hours before next epoch, to be able to deposit and withdraw
        vm.warp(VelodromeTimeLibrary.epochStart(block.timestamp) + 5 days - 2 hours);

        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        escrow.lockPermanent(tokenId);

        uint256 pid = createProposal();
        uint256 snapshotTime = governor.proposalSnapshot(pid);

        // Fast forward 1 block (2 seconds) so the snapshot checkpoint is now finalized
        skipAndRoll(2);

        assertEq(governor.getVotes(tokenId, snapshotTime), TOKEN_1);
        voter.depositManaged(tokenId, mTokenId);
        // Voting Power remains the same after deposit into managed
        assertEq(governor.getVotes(tokenId, snapshotTime), TOKEN_1);

        governor.castVote(pid, tokenId, 1);
        (, uint256 votes,) = governor.proposalVotes(pid);

        assertEq(votes, TOKEN_1);

        // Fast forward 4 hours so the Voter's epoch ends and we can withdraw from managed locks
        skip(4 hours);
        voter.withdrawManaged(tokenId);

        vm.expectRevert("GovernorVotingSimple: vote already cast");
        governor.castVote(pid, tokenId, 1);
    }

    function testCannotCastVoteDepositIntoManagedVeNFTThenVoteAgain() public {
        // Test Flow: Vote => Deposit Managed => Vote
        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        escrow.lockPermanent(tokenId);

        uint256 pid = createProposal();
        uint256 snapshotTime = governor.proposalSnapshot(pid);

        // Fast forward 1 block (2 seconds) so the snapshot checkpoint is now finalized
        skipAndRoll(2);

        governor.castVote(pid, tokenId, 1);

        assertEq(governor.getVotes(tokenId, snapshotTime), TOKEN_1);

        voter.depositManaged(tokenId, mTokenId);

        // Voting Power remains the same after deposit into managed
        assertEq(governor.getVotes(tokenId, snapshotTime), TOKEN_1);

        (, uint256 votes,) = governor.proposalVotes(pid);
        assertEq(votes, TOKEN_1);

        vm.expectRevert("GovernorVotingSimple: vote already cast");
        governor.castVote(pid, tokenId, 1);
    }

    function testCastSecondVoteAfterMerge() public {
        // Test Flow: Vote with tokenId => Merge into tokenId2 => Vote with tokenId2
        VELO.approve(address(escrow), type(uint256).max);

        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        uint256 tokenId2VotingPower = 1 wei;
        uint256 tokenId2 = escrow.createLock(tokenId2VotingPower, MAXTIME);
        escrow.lockPermanent(tokenId2);

        uint256 pid = createProposal();
        uint256 snapshotTime = governor.proposalSnapshot(pid);

        uint256 tokenIdVotingPower = governor.getVotes(tokenId, snapshotTime);

        // Fast forward 1 block (2 seconds) so the snapshot checkpoint is now finalized
        skipAndRoll(2);

        // Cast all tokenId's voting power
        governor.castVote(pid, tokenId, 1);

        assertEq(governor.getVotes(tokenId2, snapshotTime), tokenId2VotingPower);

        vm.prank(address(owner));
        escrow.merge(tokenId, tokenId2);

        // Voting Power remains the same after merging
        assertEq(governor.getVotes(tokenId2, snapshotTime), tokenId2VotingPower);

        governor.castVote(pid, tokenId2, 1);
        (, uint256 votes,) = governor.proposalVotes(pid);

        assertEq(votes, tokenIdVotingPower + tokenId2VotingPower);
    }

    function testCastVoteAfterMergeAndDepositIntoManagedVeNFTNotDelegating() public {
        // Test Flow: Vote with tokenId => Merge into tokenId2 => DepositManaged => Vote tokenId2
        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        VELO.approve(address(escrow), type(uint256).max);

        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        uint256 tokenId2VotingPower = 1 wei;
        uint256 tokenId2 = escrow.createLock(tokenId2VotingPower, MAXTIME);
        escrow.lockPermanent(tokenId2);

        uint256 pid = createProposal();
        uint256 snapshotTime = governor.proposalSnapshot(pid);

        uint256 tokenIdVotingPower = governor.getVotes(tokenId, snapshotTime);

        // Fast forward 1 block (2 seconds) so the snapshot checkpoint is now finalized
        skipAndRoll(2);

        governor.castVote(pid, tokenId, 1);

        vm.prank(address(owner));
        escrow.merge(tokenId, tokenId2);

        assertEq(governor.getVotes(tokenId2, snapshotTime), tokenId2VotingPower);
        voter.depositManaged(tokenId2, mTokenId);

        // Voting Power remains the same after deposit into managed
        assertEq(governor.getVotes(tokenId2, snapshotTime), tokenId2VotingPower);

        governor.castVote(pid, tokenId2, 1);
        (, uint256 votes,) = governor.proposalVotes(pid);

        assertEq(votes, tokenIdVotingPower + tokenId2VotingPower);
    }

    function testFuzzCastVoteAfterDepositIntoManagedVeNFTNotDelegating(uint24 timeskip, uint256 amount) public {
        // Test Flow: Deposit Managed => Vote
        amount = bound(amount, TOKEN_1, MAX_TOKENS);
        deal(address(VELO), address(owner), amount);

        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(amount, MAXTIME);
        escrow.lockPermanent(tokenId);

        uint256 pid = createProposal();
        uint256 snapshotTime = governor.proposalSnapshot(pid);

        // Fast forward at least 1 block (2 seconds) so the snapshot checkpoint is now finalized
        uint256 epochVoteEnd = VelodromeTimeLibrary.epochVoteEnd(block.timestamp);
        timeskip = uint24(bound(timeskip, 2, epochVoteEnd - block.timestamp));
        skipAndRoll(timeskip);

        assertEq(governor.getVotes(tokenId, snapshotTime), amount);
        voter.depositManaged(tokenId, mTokenId);
        // Voting Power remains the same after deposit into managed
        assertEq(governor.getVotes(tokenId, snapshotTime), amount);

        governor.castVote(pid, tokenId, 1);
        (, uint256 votes,) = governor.proposalVotes(pid);

        assertEq(votes, amount);
    }

    function testFuzzCannotDoubleVoteAfterDepositAndWithdrawIntoManagedVeNFTNotDelegating(
        uint24 timeskip,
        uint24 timeskip2,
        uint256 amount
    ) public {
        // Test Flow: Deposit Managed => Vote => Withdraw => Vote
        amount = bound(amount, TOKEN_1, MAX_TOKENS);
        deal(address(VELO), address(owner), amount);

        // Warp to 2 days and 2 hours before next epoch, to be able to deposit and withdraw
        vm.warp(VelodromeTimeLibrary.epochStart(block.timestamp) + 5 days - 2 hours);

        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(amount, MAXTIME);
        escrow.lockPermanent(tokenId);

        uint256 pid = createProposal();
        uint256 snapshotTime = governor.proposalSnapshot(pid);

        // Fast forward at least 1 block (2 seconds) so the snapshot checkpoint is now finalized
        uint256 epochVoteEnd = VelodromeTimeLibrary.epochVoteEnd(block.timestamp);
        timeskip = uint24(bound(timeskip, 2, epochVoteEnd - block.timestamp));
        skipAndRoll(timeskip);

        assertEq(governor.getVotes(tokenId, snapshotTime), amount);
        voter.depositManaged(tokenId, mTokenId);
        // Voting Power remains the same after deposit into managed
        assertEq(governor.getVotes(tokenId, snapshotTime), amount);

        governor.castVote(pid, tokenId, 1);
        (, uint256 votes,) = governor.proposalVotes(pid);

        assertEq(votes, amount);

        // Fast forward into next Epoch's voting period
        uint256 nextEpochVoteStart = VelodromeTimeLibrary.epochVoteStart(block.timestamp) + WEEK + 1;
        timeskip2 = uint24(
            bound(
                timeskip2, nextEpochVoteStart - block.timestamp, snapshotTime + governor.votingDelay() - block.timestamp
            )
        );
        skipAndRoll(timeskip2);

        voter.withdrawManaged(tokenId);

        vm.expectRevert("GovernorVotingSimple: vote already cast");
        governor.castVote(pid, tokenId, 1);
    }

    function testFuzzCannotCastVoteDepositIntoManagedVeNFTThenVoteAgain(uint24 timeskip, uint256 amount) public {
        // Test Flow: Vote => Deposit Managed => Vote
        amount = bound(amount, TOKEN_1, MAX_TOKENS);
        deal(address(VELO), address(owner), amount);

        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(amount, MAXTIME);
        escrow.lockPermanent(tokenId);

        uint256 pid = createProposal();
        uint256 snapshotTime = governor.proposalSnapshot(pid);

        // Fast forward at least 1 block (2 seconds) so the snapshot checkpoint is now finalized
        uint256 epochVoteEnd = VelodromeTimeLibrary.epochVoteEnd(block.timestamp);
        timeskip = uint24(bound(timeskip, 2, epochVoteEnd - block.timestamp));
        skipAndRoll(timeskip);

        governor.castVote(pid, tokenId, 1);

        assertEq(governor.getVotes(tokenId, snapshotTime), amount);

        voter.depositManaged(tokenId, mTokenId);

        // Voting Power remains the same after deposit into managed
        assertEq(governor.getVotes(tokenId, snapshotTime), amount);

        (, uint256 votes,) = governor.proposalVotes(pid);
        assertEq(votes, amount);

        vm.expectRevert("GovernorVotingSimple: vote already cast");
        governor.castVote(pid, tokenId, 1);
    }

    function testFuzzCastSecondVoteAfterMerge(uint24 timeskip, uint256 amount) public {
        // Test Flow: Vote with tokenId => Merge into tokenId2 => Vote with tokenId2
        uint256 tokenId2VotingPower = 1 wei;
        amount = bound(amount, TOKEN_1, MAX_TOKENS - tokenId2VotingPower); // avoid exceeding int128 limit
        deal(address(VELO), address(owner), amount + tokenId2VotingPower);
        VELO.approve(address(escrow), type(uint256).max);

        uint256 tokenId = escrow.createLock(amount, MAXTIME);

        uint256 tokenId2 = escrow.createLock(tokenId2VotingPower, MAXTIME);
        escrow.lockPermanent(tokenId2);

        uint256 pid = createProposal();
        uint256 snapshotTime = governor.proposalSnapshot(pid);

        uint256 tokenIdVotingPower = governor.getVotes(tokenId, snapshotTime);

        // Fast forward 1 block (2 seconds) so the snapshot checkpoint is now finalized
        uint256 epochVoteEnd = VelodromeTimeLibrary.epochVoteEnd(block.timestamp);
        timeskip = uint24(bound(timeskip, 2, epochVoteEnd - block.timestamp));
        skipAndRoll(timeskip);

        // Cast all tokenId's voting power
        governor.castVote(pid, tokenId, 1);

        assertEq(governor.getVotes(tokenId2, snapshotTime), tokenId2VotingPower);

        vm.prank(address(owner));
        escrow.merge(tokenId, tokenId2);

        // Voting Power remains the same after merging
        assertEq(governor.getVotes(tokenId2, snapshotTime), tokenId2VotingPower);

        governor.castVote(pid, tokenId2, 1);
        (, uint256 votes,) = governor.proposalVotes(pid);

        assertEq(votes, tokenIdVotingPower + tokenId2VotingPower);
    }

    function testFuzzCastVoteAfterMergeAndDepositIntoManagedVeNFTNotDelegating(uint24 timeskip, uint256 amount)
        public
    {
        // Test Flow: Vote with tokenId => Merge into tokenId2 => DepositManaged => Vote tokenId2
        uint256 tokenId2VotingPower = 1 wei;
        amount = bound(amount, TOKEN_1, MAX_TOKENS - tokenId2VotingPower); // avoid exceeding int128 limit
        deal(address(VELO), address(owner), amount + tokenId2VotingPower);

        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        VELO.approve(address(escrow), type(uint256).max);

        uint256 tokenId = escrow.createLock(amount, MAXTIME);

        uint256 tokenId2 = escrow.createLock(tokenId2VotingPower, MAXTIME);
        escrow.lockPermanent(tokenId2);

        uint256 pid = createProposal();
        uint256 snapshotTime = governor.proposalSnapshot(pid);

        uint256 tokenIdVotingPower = governor.getVotes(tokenId, snapshotTime);

        // Fast forward at least 1 block (2 seconds) so the snapshot checkpoint is now finalized
        uint256 epochVoteEnd = VelodromeTimeLibrary.epochVoteEnd(block.timestamp);
        timeskip = uint24(bound(timeskip, 2, epochVoteEnd - block.timestamp));
        skipAndRoll(timeskip);

        governor.castVote(pid, tokenId, 1);

        vm.prank(address(owner));
        escrow.merge(tokenId, tokenId2);

        assertEq(governor.getVotes(tokenId2, snapshotTime), tokenId2VotingPower);
        voter.depositManaged(tokenId2, mTokenId);

        // Voting Power remains the same after deposit into managed
        assertEq(governor.getVotes(tokenId2, snapshotTime), tokenId2VotingPower);

        governor.castVote(pid, tokenId2, 1);
        (, uint256 votes,) = governor.proposalVotes(pid);

        assertEq(votes, tokenIdVotingPower + tokenId2VotingPower);
    }

    // creates a proposal so we can vote on it for testing and skip to snapshot time
    // voting start time is 1 second after snapshot
    // proposal will always be to whitelist a token
    function createProposal() internal returns (uint256 pid) {
        address[] memory targets = new address[](1);
        targets[0] = address(voter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(voter.whitelistToken.selector, token, true);
        string memory description = "Whitelist Token";

        // propose
        pid = governor.propose(1, targets, values, calldatas, description);

        skipAndRoll(2 days);
    }
}

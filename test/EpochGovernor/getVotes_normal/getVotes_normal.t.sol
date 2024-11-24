// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "test/BaseTest.sol";
import {DelegationHelperLibrary} from "contracts/libraries/DelegationHelperLibrary.sol";

contract GetVotesNormalTest is BaseTest {
    using DelegationHelperLibrary for IVotingEscrow;
    using SafeCastLibrary for int128;

    uint256 public tokenId;
    uint256 public mTokenId;
    uint256 public delegateId;
    uint256 public proposalId;
    uint256 public snapshotTime;

    function _setUp() public override {
        VELO.approve(address(escrow), 350 * TOKEN_1);
        tokenId = escrow.createLock(100 * TOKEN_1, MAXTIME);
        mTokenId = escrow.createManagedLockFor(address(owner));
        delegateId = escrow.createLock(50 * TOKEN_1, MAXTIME);
        escrow.lockPermanent(delegateId);

        skipAndRoll(1 hours + 1);

        address[] memory targets = new address[](1);
        targets[0] = address(minter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(minter.nudge.selector);
        string memory description = "";

        vm.prank(address(owner));
        proposalId = epochGovernor.propose(1, targets, values, calldatas, description);
        snapshotTime = epochGovernor.proposalSnapshot(proposalId);
    }

    modifier whenVeNFTWasNeverLocked() {
        _;
    }

    modifier whenVeNFTIsNotDelegating() {
        _;
    }

    function test_WhenVeNFTIsNotBeingDelegatedTo() external view whenVeNFTWasNeverLocked whenVeNFTIsNotDelegating {
        // It should return balance of nft at snapshot
        assertEq(epochGovernor.getVotes(tokenId, snapshotTime), escrow.balanceOfNFTAt(tokenId, snapshotTime));
    }

    modifier whenVeNFTIsBeingDelegatedTo() {
        _;
    }

    function test_WhenVeNFTReceivedDelegatedBalanceBeforeOrAtProposalSnapshot()
        external
        whenVeNFTWasNeverLocked
        whenVeNFTIsNotDelegating
        whenVeNFTIsBeingDelegatedTo
    {
        // It should return balance of nft at snapshot + delegated balance
        escrow.delegate(delegateId, tokenId);
        uint256 delegatedBalance = escrow.locked(delegateId).amount.toUint256();

        assertEq(
            epochGovernor.getVotes(tokenId, snapshotTime),
            escrow.balanceOfNFTAt(tokenId, snapshotTime) + delegatedBalance
        );
    }

    function test_WhenVeNFTReceivedDelegatedBalanceAfterProposalSnapshot()
        external
        whenVeNFTWasNeverLocked
        whenVeNFTIsNotDelegating
        whenVeNFTIsBeingDelegatedTo
    {
        // It should return balance of nft at snapshot
        vm.warp({newTimestamp: snapshotTime + 1});
        escrow.delegate(delegateId, tokenId);

        assertEq(epochGovernor.getVotes(tokenId, snapshotTime), escrow.balanceOfNFTAt(tokenId, snapshotTime));
    }

    modifier whenVeNFTIsDelegating() {
        _;
    }

    modifier whenVeNFTDelegatedBeforeOrAtProposalSnapshot() {
        escrow.lockPermanent(tokenId);
        escrow.delegate(tokenId, mTokenId);
        _;
    }

    function test_WhenVeNFTIsNotBeingDelegatedTo_()
        external
        whenVeNFTWasNeverLocked
        whenVeNFTIsDelegating
        whenVeNFTDelegatedBeforeOrAtProposalSnapshot
    {
        // It should return 0
        assertEq(epochGovernor.getVotes(tokenId, snapshotTime), 0);
    }

    modifier whenVeNFTIsBeingDelegatedTo_() {
        _;
    }

    function test_WhenVeNFTReceivedDelegatedBalanceBeforeOrAtProposalSnapshot_()
        external
        whenVeNFTWasNeverLocked
        whenVeNFTIsDelegating
        whenVeNFTDelegatedBeforeOrAtProposalSnapshot
        whenVeNFTIsBeingDelegatedTo_
    {
        // It should return delegated balance
        escrow.delegate(delegateId, tokenId);
        uint256 delegatedBalance = escrow.locked(delegateId).amount.toUint256();

        assertEq(epochGovernor.getVotes(tokenId, snapshotTime), delegatedBalance);
    }

    function test_WhenVeNFTReceivedDelegatedBalanceAfterProposalSnapshot_()
        external
        whenVeNFTWasNeverLocked
        whenVeNFTIsDelegating
        whenVeNFTDelegatedBeforeOrAtProposalSnapshot
        whenVeNFTIsBeingDelegatedTo_
    {
        // It should return 0
        vm.warp({newTimestamp: snapshotTime + 1});
        escrow.delegate(delegateId, tokenId);

        assertEq(epochGovernor.getVotes(tokenId, snapshotTime), 0);
    }

    modifier whenVeNFTDelegatedAfterProposalSnapshot() {
        _;
    }

    function test_WhenVeNFTIsNotBeingDelegatedTo__()
        external
        whenVeNFTWasNeverLocked
        whenVeNFTIsDelegating
        whenVeNFTDelegatedAfterProposalSnapshot
    {
        // It should return balance of nft at snapshot
        vm.warp({newTimestamp: snapshotTime + 1});
        escrow.lockPermanent(tokenId);
        escrow.delegate(tokenId, mTokenId);

        assertEq(epochGovernor.getVotes(tokenId, snapshotTime), escrow.balanceOfNFTAt(tokenId, snapshotTime));
    }

    modifier whenVeNFTIsBeingDelegatedTo__() {
        _;
    }

    function test_WhenVeNFTReceivedDelegatedBalanceBeforeOrAtProposalSnapshot__()
        external
        whenVeNFTWasNeverLocked
        whenVeNFTIsDelegating
        whenVeNFTDelegatedAfterProposalSnapshot
        whenVeNFTIsBeingDelegatedTo__
    {
        // It should return balance of nft at snapshot + delegated balance
        escrow.delegate(delegateId, tokenId);
        vm.warp({newTimestamp: snapshotTime + 1});
        escrow.lockPermanent(tokenId);
        escrow.delegate(tokenId, mTokenId);

        uint256 delegatedBalance = escrow.locked(delegateId).amount.toUint256();

        assertEq(
            epochGovernor.getVotes(tokenId, snapshotTime),
            escrow.balanceOfNFTAt(tokenId, snapshotTime) + delegatedBalance
        );
    }

    function test_WhenVeNFTReceivedDelegatedBalanceAfterProposalSnapshot__()
        external
        whenVeNFTWasNeverLocked
        whenVeNFTIsDelegating
        whenVeNFTDelegatedAfterProposalSnapshot
        whenVeNFTIsBeingDelegatedTo__
    {
        // It should return balance of nft at snapshot
        vm.warp({newTimestamp: snapshotTime + 1});
        escrow.lockPermanent(tokenId);
        escrow.delegate(tokenId, mTokenId);
        escrow.delegate(delegateId, tokenId);

        assertEq(epochGovernor.getVotes(tokenId, snapshotTime), escrow.balanceOfNFTAt(tokenId, snapshotTime));
    }

    modifier whenVeNFTHasBeenLockedBefore() {
        _;
    }

    modifier whenManagedWithdrawHappenedBeforeOrAtProposalSnapshot() {
        voter.depositManaged(tokenId, mTokenId);

        skipToNextEpoch(1 hours + 1);

        voter.withdrawManaged(tokenId);
        // create new proposal after withdrawing from managed
        address[] memory targets = new address[](1);
        targets[0] = address(minter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(minter.nudge.selector);
        string memory description = "";

        vm.prank(address(owner));
        proposalId = epochGovernor.propose(1, targets, values, calldatas, description);
        snapshotTime = epochGovernor.proposalSnapshot(proposalId);
        _;
    }

    modifier whenVeNFTIsNotDelegating_() {
        _;
    }

    function test_WhenVeNFTIsNotBeingDelegatedTo___()
        external
        whenVeNFTHasBeenLockedBefore
        whenManagedWithdrawHappenedBeforeOrAtProposalSnapshot
        whenVeNFTIsNotDelegating_
    {
        // It should return balance of nft at snapshot
        assertEq(epochGovernor.getVotes(tokenId, snapshotTime), escrow.balanceOfNFTAt(tokenId, snapshotTime));
    }

    modifier whenVeNFTIsBeingDelegatedTo___() {
        _;
    }

    function test_WhenVeNFTReceivedDelegatedBalanceBeforeOrAtProposalSnapshot___()
        external
        whenVeNFTHasBeenLockedBefore
        whenManagedWithdrawHappenedBeforeOrAtProposalSnapshot
        whenVeNFTIsNotDelegating_
        whenVeNFTIsBeingDelegatedTo___
    {
        // It should return balance of nft at snapshot + delegated balance
        escrow.delegate(delegateId, tokenId);
        uint256 delegatedBalance = escrow.locked(delegateId).amount.toUint256();

        assertEq(
            epochGovernor.getVotes(tokenId, snapshotTime),
            escrow.balanceOfNFTAt(tokenId, snapshotTime) + delegatedBalance
        );
    }

    function test_WhenVeNFTReceivedDelegatedBalanceAfterProposalSnapshot___()
        external
        whenVeNFTHasBeenLockedBefore
        whenManagedWithdrawHappenedBeforeOrAtProposalSnapshot
        whenVeNFTIsNotDelegating_
        whenVeNFTIsBeingDelegatedTo___
    {
        // It should return balance of nft at snapshot
        vm.warp({newTimestamp: snapshotTime + 1});
        escrow.delegate(delegateId, tokenId);

        assertEq(epochGovernor.getVotes(tokenId, snapshotTime), escrow.balanceOfNFTAt(tokenId, snapshotTime));
    }

    modifier whenVeNFTIsDelegating_() {
        _;
    }

    modifier whenVeNFTDelegatedBeforeOrAtProposalSnapshot_() {
        escrow.lockPermanent(tokenId);
        escrow.delegate(tokenId, mTokenId);
        _;
    }

    function test_WhenVeNFTIsNotBeingDelegatedTo____()
        external
        whenVeNFTHasBeenLockedBefore
        whenManagedWithdrawHappenedBeforeOrAtProposalSnapshot
        whenVeNFTIsDelegating_
        whenVeNFTDelegatedBeforeOrAtProposalSnapshot_
    {
        // It should return 0
        assertEq(epochGovernor.getVotes(tokenId, snapshotTime), 0);
    }

    modifier whenVeNFTIsBeingDelegatedTo____() {
        _;
    }

    function test_WhenVeNFTReceivedDelegatedBalanceBeforeOrAtProposalSnapshot____()
        external
        whenVeNFTHasBeenLockedBefore
        whenManagedWithdrawHappenedBeforeOrAtProposalSnapshot
        whenVeNFTIsDelegating_
        whenVeNFTDelegatedBeforeOrAtProposalSnapshot_
        whenVeNFTIsBeingDelegatedTo____
    {
        // It should return delegated balance
        escrow.delegate(delegateId, tokenId);
        uint256 delegatedBalance = escrow.locked(delegateId).amount.toUint256();

        assertEq(epochGovernor.getVotes(tokenId, snapshotTime), delegatedBalance);
    }

    function test_WhenVeNFTReceivedDelegatedBalanceAfterProposalSnapshot____()
        external
        whenVeNFTHasBeenLockedBefore
        whenManagedWithdrawHappenedBeforeOrAtProposalSnapshot
        whenVeNFTIsDelegating_
        whenVeNFTDelegatedBeforeOrAtProposalSnapshot_
        whenVeNFTIsBeingDelegatedTo____
    {
        // It should return 0
        vm.warp({newTimestamp: snapshotTime + 1});
        escrow.delegate(delegateId, tokenId);

        assertEq(epochGovernor.getVotes(tokenId, snapshotTime), 0);
    }

    modifier whenVeNFTDelegatedAfterProposalSnapshot_() {
        _;
    }

    function test_WhenVeNFTIsNotBeingDelegatedTo_____()
        external
        whenVeNFTHasBeenLockedBefore
        whenManagedWithdrawHappenedBeforeOrAtProposalSnapshot
        whenVeNFTIsDelegating_
        whenVeNFTDelegatedAfterProposalSnapshot_
    {
        // It should return balance of nft at snapshot
        vm.warp({newTimestamp: snapshotTime + 1});
        escrow.lockPermanent(tokenId);
        escrow.delegate(tokenId, mTokenId);

        assertEq(epochGovernor.getVotes(tokenId, snapshotTime), escrow.balanceOfNFTAt(tokenId, snapshotTime));
    }

    modifier whenVeNFTIsBeingDelegatedTo_____() {
        _;
    }

    function test_WhenVeNFTReceivedDelegatedBalanceBeforeOrAtProposalSnapshot_____()
        external
        whenVeNFTHasBeenLockedBefore
        whenManagedWithdrawHappenedBeforeOrAtProposalSnapshot
        whenVeNFTIsDelegating_
        whenVeNFTDelegatedAfterProposalSnapshot_
        whenVeNFTIsBeingDelegatedTo_____
    {
        // It should return balance of nft at snapshot + delegated balance
        escrow.delegate(delegateId, tokenId);
        vm.warp({newTimestamp: snapshotTime + 1});
        escrow.lockPermanent(tokenId);
        escrow.delegate(tokenId, mTokenId);

        uint256 delegatedBalance = escrow.locked(delegateId).amount.toUint256();

        assertEq(
            epochGovernor.getVotes(tokenId, snapshotTime),
            escrow.balanceOfNFTAt(tokenId, snapshotTime) + delegatedBalance
        );
    }

    function test_WhenVeNFTReceivedDelegatedBalanceAfterProposalSnapshot_____()
        external
        whenVeNFTHasBeenLockedBefore
        whenManagedWithdrawHappenedBeforeOrAtProposalSnapshot
        whenVeNFTIsDelegating_
        whenVeNFTDelegatedAfterProposalSnapshot_
        whenVeNFTIsBeingDelegatedTo_____
    {
        // It should return balance of nft at snapshot
        vm.warp({newTimestamp: snapshotTime + 1});
        escrow.lockPermanent(tokenId);
        escrow.delegate(tokenId, mTokenId);
        escrow.delegate(delegateId, tokenId);

        assertEq(epochGovernor.getVotes(tokenId, snapshotTime), escrow.balanceOfNFTAt(tokenId, snapshotTime));
    }

    modifier whenManagedWithdrawHappenedAfterProposalSnapshot() {
        voter.depositManaged(tokenId, mTokenId);

        skipToNextEpoch(1 hours + 1);

        // create new proposal after withdrawing from managed
        address[] memory targets = new address[](1);
        targets[0] = address(minter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(minter.nudge.selector);
        string memory description = "";

        vm.prank(address(owner));
        proposalId = epochGovernor.propose(1, targets, values, calldatas, description);
        snapshotTime = epochGovernor.proposalSnapshot(proposalId);
        _;
    }

    function test_WhenVeNFTIsNotBeingDelegatedTo______()
        external
        whenVeNFTHasBeenLockedBefore
        whenManagedWithdrawHappenedAfterProposalSnapshot
    {
        // It should return 0
        vm.warp({newTimestamp: snapshotTime + 1});
        voter.withdrawManaged(tokenId);

        assertEq(epochGovernor.getVotes(tokenId, snapshotTime), 0);
    }

    modifier whenVeNFTIsBeingDelegatedTo______() {
        _;
    }

    function test_WhenVeNFTReceivedDelegatedBalanceBeforeOrAtProposalSnapshot______()
        external
        whenVeNFTHasBeenLockedBefore
        whenManagedWithdrawHappenedAfterProposalSnapshot
        whenVeNFTIsBeingDelegatedTo______
    {
        // It should return delegated balance
        escrow.delegate(delegateId, tokenId);
        vm.warp({newTimestamp: snapshotTime + 1});
        voter.withdrawManaged(tokenId);

        uint256 delegatedBalance = escrow.locked(delegateId).amount.toUint256();

        assertEq(epochGovernor.getVotes(tokenId, snapshotTime), delegatedBalance);
    }

    function test_WhenVeNFTReceivedDelegatedBalanceAfterProposalSnapshot______()
        external
        whenVeNFTHasBeenLockedBefore
        whenManagedWithdrawHappenedAfterProposalSnapshot
        whenVeNFTIsBeingDelegatedTo______
    {
        // It should return 0
        vm.warp({newTimestamp: snapshotTime + 1});
        voter.withdrawManaged(tokenId);
        escrow.delegate(delegateId, tokenId);

        assertEq(epochGovernor.getVotes(tokenId, snapshotTime), 0);
    }
}

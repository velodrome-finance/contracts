// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "test/BaseTest.sol";
import {DelegationHelperLibrary} from "contracts/libraries/DelegationHelperLibrary.sol";

contract GetVotesManagedTest is BaseTest {
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

    modifier whenVeNFTIsNotDelegating() {
        _;
    }

    function test_WhenVeNFTIsNotBeingDelegatedTo() external view whenVeNFTIsNotDelegating {
        // It should return balance of nft at snapshot
        assertEq(epochGovernor.getVotes(mTokenId, snapshotTime), escrow.balanceOfNFTAt(mTokenId, snapshotTime));
    }

    modifier whenVeNFTIsBeingDelegatedTo() {
        _;
    }

    function test_WhenVeNFTReceivedDelegatedBalanceBeforeOrAtProposalSnapshot()
        external
        whenVeNFTIsNotDelegating
        whenVeNFTIsBeingDelegatedTo
    {
        // It should return balance of nft at snapshot + delegated balance
        escrow.delegate(delegateId, mTokenId);
        uint256 delegatedBalance = escrow.locked(delegateId).amount.toUint256();

        assertEq(
            epochGovernor.getVotes(mTokenId, snapshotTime),
            escrow.balanceOfNFTAt(mTokenId, snapshotTime) + delegatedBalance
        );
    }

    function test_WhenVeNFTReceivedDelegatedBalanceAfterProposalSnapshot()
        external
        whenVeNFTIsNotDelegating
        whenVeNFTIsBeingDelegatedTo
    {
        // It should return balance of nft at snapshot
        vm.warp({newTimestamp: snapshotTime + 1});
        escrow.delegate(delegateId, mTokenId);

        assertEq(epochGovernor.getVotes(mTokenId, snapshotTime), escrow.balanceOfNFTAt(mTokenId, snapshotTime));
    }

    modifier whenVeNFTIsDelegating() {
        _;
    }

    modifier whenVeNFTDelegatedBeforeOrAtProposalSnapshot() {
        escrow.delegate(mTokenId, tokenId);
        _;
    }

    function test_WhenVeNFTIsNotBeingDelegatedTo_()
        external
        whenVeNFTIsDelegating
        whenVeNFTDelegatedBeforeOrAtProposalSnapshot
    {
        // It should return 0
        assertEq(epochGovernor.getVotes(mTokenId, snapshotTime), 0);
    }

    modifier whenVeNFTIsBeingDelegatedTo_() {
        _;
    }

    function test_WhenVeNFTReceivedDelegatedBalanceBeforeOrAtProposalSnapshot_()
        external
        whenVeNFTIsDelegating
        whenVeNFTDelegatedBeforeOrAtProposalSnapshot
        whenVeNFTIsBeingDelegatedTo_
    {
        // It should return delegated balance
        escrow.delegate(delegateId, mTokenId);
        uint256 delegatedBalance = escrow.locked(delegateId).amount.toUint256();

        assertEq(epochGovernor.getVotes(mTokenId, snapshotTime), delegatedBalance);
    }

    function test_WhenVeNFTReceivedDelegatedBalanceAfterProposalSnapshot_()
        external
        whenVeNFTIsDelegating
        whenVeNFTDelegatedBeforeOrAtProposalSnapshot
        whenVeNFTIsBeingDelegatedTo_
    {
        // It should return 0
        vm.warp({newTimestamp: snapshotTime + 1});
        escrow.delegate(delegateId, mTokenId);

        assertEq(epochGovernor.getVotes(mTokenId, snapshotTime), 0);
    }

    modifier whenVeNFTDelegatedAfterProposalSnapshot() {
        _;
    }

    function test_WhenVeNFTIsNotBeingDelegatedTo__()
        external
        whenVeNFTIsDelegating
        whenVeNFTDelegatedAfterProposalSnapshot
    {
        // It should return balance of nft at snapshot
        vm.warp({newTimestamp: snapshotTime + 1});
        escrow.delegate(mTokenId, tokenId);

        assertEq(epochGovernor.getVotes(mTokenId, snapshotTime), escrow.balanceOfNFTAt(mTokenId, snapshotTime));
    }

    modifier whenVeNFTIsBeingDelegatedTo__() {
        _;
    }

    function test_WhenVeNFTReceivedDelegatedBalanceBeforeOrAtProposalSnapshot__()
        external
        whenVeNFTIsDelegating
        whenVeNFTDelegatedAfterProposalSnapshot
        whenVeNFTIsBeingDelegatedTo__
    {
        // It should return balance of nft at snapshot + delegated balance
        escrow.delegate(delegateId, mTokenId);

        vm.warp({newTimestamp: snapshotTime + 1});
        escrow.delegate(mTokenId, tokenId);
        uint256 delegatedBalance = escrow.locked(delegateId).amount.toUint256();

        assertEq(
            epochGovernor.getVotes(mTokenId, snapshotTime),
            escrow.balanceOfNFTAt(mTokenId, snapshotTime) + delegatedBalance
        );
    }

    function test_WhenVeNFTReceivedDelegatedBalanceAfterProposalSnapshot__()
        external
        whenVeNFTIsDelegating
        whenVeNFTDelegatedAfterProposalSnapshot
        whenVeNFTIsBeingDelegatedTo__
    {
        // It should return balance of nft at snapshot
        vm.warp({newTimestamp: snapshotTime + 1});
        escrow.delegate(delegateId, mTokenId);
        escrow.delegate(mTokenId, tokenId);

        assertEq(epochGovernor.getVotes(mTokenId, snapshotTime), escrow.balanceOfNFTAt(mTokenId, snapshotTime));
    }
}

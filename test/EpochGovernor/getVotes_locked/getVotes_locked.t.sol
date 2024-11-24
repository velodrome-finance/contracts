// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "test/BaseTest.sol";
import {DelegationHelperLibrary} from "contracts/libraries/DelegationHelperLibrary.sol";

contract GetVotesLockedTest is BaseTest {
    using DelegationHelperLibrary for IVotingEscrow;
    using SafeCastLibrary for int128;

    uint256 public lockedId;
    uint256 public mTokenId;
    uint256 public delegateId;
    uint256 public proposalId;
    uint256 public snapshotTime;

    function _setUp() public override {
        VELO.approve(address(escrow), 350 * TOKEN_1);
        lockedId = escrow.createLock(200 * TOKEN_1, MAXTIME);
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

    modifier whenManagedDepositHappenedBeforeOrAtProposalSnapshot() {
        voter.depositManaged(lockedId, mTokenId);
        _;
    }

    function test_WhenVeNFTIsNotBeingDelegatedTo() external whenManagedDepositHappenedBeforeOrAtProposalSnapshot {
        // It should return 0
        assertEq(epochGovernor.getVotes(lockedId, snapshotTime), 0);
    }

    modifier whenVeNFTIsBeingDelegatedTo() {
        _;
    }

    function test_WhenVeNFTReceivedDelegatedBalanceBeforeOrAtProposalSnapshot()
        external
        whenManagedDepositHappenedBeforeOrAtProposalSnapshot
        whenVeNFTIsBeingDelegatedTo
    {
        // It should return delegated balance
        escrow.delegate(delegateId, lockedId);
        uint256 delegatedBalance = escrow.locked(delegateId).amount.toUint256();

        assertEq(epochGovernor.getVotes(lockedId, snapshotTime), delegatedBalance);
    }

    function test_WhenVeNFTReceivedDelegatedBalanceAfterProposalSnapshot()
        external
        whenManagedDepositHappenedBeforeOrAtProposalSnapshot
        whenVeNFTIsBeingDelegatedTo
    {
        // It should return 0
        vm.warp({newTimestamp: snapshotTime + 1});
        escrow.delegate(delegateId, lockedId);

        assertEq(epochGovernor.getVotes(lockedId, snapshotTime), 0);
    }

    modifier whenManagedDepositHappenedAfterProposalSnapshot() {
        _;
    }

    function test_WhenVeNFTIsNotBeingDelegatedTo_() external whenManagedDepositHappenedAfterProposalSnapshot {
        // It should return balance of nft at snapshot
        vm.warp({newTimestamp: snapshotTime + 1});
        voter.depositManaged(lockedId, mTokenId);

        assertEq(epochGovernor.getVotes(lockedId, snapshotTime), escrow.balanceOfNFTAt(lockedId, snapshotTime));
    }

    modifier whenVeNFTIsBeingDelegatedTo_() {
        _;
    }

    function test_WhenVeNFTReceivedDelegatedBalanceBeforeOrAtProposalSnapshot_()
        external
        whenManagedDepositHappenedAfterProposalSnapshot
        whenVeNFTIsBeingDelegatedTo_
    {
        // It should return balance of nft at snapshot + delegated balance
        escrow.delegate(delegateId, lockedId);
        vm.warp({newTimestamp: snapshotTime + 1});
        voter.depositManaged(lockedId, mTokenId);
        uint256 delegatedBalance = escrow.locked(delegateId).amount.toUint256();

        assertEq(
            epochGovernor.getVotes(lockedId, snapshotTime),
            escrow.balanceOfNFTAt(lockedId, snapshotTime) + delegatedBalance
        );
    }

    function test_WhenVeNFTReceivedDelegatedBalanceAfterProposalSnapshot_()
        external
        whenManagedDepositHappenedAfterProposalSnapshot
        whenVeNFTIsBeingDelegatedTo_
    {
        // It should return balance of nft at snapshot
        vm.warp({newTimestamp: snapshotTime + 1});
        voter.depositManaged(lockedId, mTokenId);
        escrow.delegate(delegateId, lockedId);

        assertEq(epochGovernor.getVotes(lockedId, snapshotTime), escrow.balanceOfNFTAt(lockedId, snapshotTime));
    }
}

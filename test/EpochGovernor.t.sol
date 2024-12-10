// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "./BaseTest.sol";
import {IGovernor as OZGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IGovernor} from "contracts/governance/IGovernor.sol";
import {EpochGovernorCountingFractional} from "contracts/governance/EpochGovernorCountingFractional.sol";
import {GovernorSimpleVotes} from "contracts/governance/GovernorSimpleVotes.sol";

contract EpochGovernorTest is BaseTest {
    using stdStorage for StdStorage;

    function _setUp() public override {
        VELO.approve(address(escrow), 2 * TOKEN_1);
        escrow.createLock(2 * TOKEN_1, MAXTIME); // 1
        vm.roll(block.number + 1);

        vm.startPrank(address(owner2));
        VELO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME); // 2
        vm.stopPrank();
        vm.roll(block.number + 1);

        vm.startPrank(address(owner3));
        VELO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME); // 3
        vm.stopPrank();
        vm.roll(block.number + 1);

        vm.startPrank(address(owner4));
        VELO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME); // 4
        vm.stopPrank();
        vm.roll(block.number + 1);

        stdstore.target(address(minter)).sig("weekly()").checked_write(4_999_999 * 1e18);
    }

    function testInitialState() public view {
        assertEq(epochGovernor.votingDelay(), 2);
        assertEq(epochGovernor.votingPeriod(), 1 weeks);
    }

    function testSupportInterfacesExcludesCancel() public view {
        assertTrue(epochGovernor.supportsInterface(type(IGovernor).interfaceId ^ OZGovernor.cancel.selector));
        assertFalse(epochGovernor.supportsInterface(OZGovernor.cancel.selector));
        assertTrue(epochGovernor.supportsInterface(type(IERC1155Receiver).interfaceId));
    }

    function testCannotProposeWithOtherTarget() public {
        address[] memory targets = new address[](1);
        targets[0] = address(0);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(minter.nudge.selector);
        string memory description = "";

        vm.expectRevert(
            abi.encodeWithSelector(IGovernor.GovernorInvalidTargetOrCalldata.selector, targets[0], bytes4(calldatas[0]))
        );
        epochGovernor.propose(1, targets, values, calldatas, description);
    }

    function testCannotProposeWithOtherCalldata() public {
        address[] memory targets = new address[](1);
        targets[0] = address(minter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(minter.updatePeriod.selector);
        string memory description = "";

        vm.expectRevert(
            abi.encodeWithSelector(IGovernor.GovernorInvalidTargetOrCalldata.selector, targets[0], bytes4(calldatas[0]))
        );
        epochGovernor.propose(1, targets, values, calldatas, description);
    }

    function testEpochGovernorCanExecuteSucceeded() public {
        assertEq(minter.tailEmissionRate(), 30);

        address[] memory targets = new address[](1);
        targets[0] = address(minter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(minter.nudge.selector);
        string memory description = "";

        // propose
        uint256 pid = epochGovernor.propose(1, targets, values, calldatas, description);

        skipAndRoll(2);
        assertEq(escrow.balanceOfNFT(1), 1994520500269526427); // voting power at proposal start
        assertEq(escrow.balanceOfNFT(2), 997260250071864015); // voting power at proposal start
        vm.expectPartialRevert(IGovernor.GovernorUnexpectedProposalState.selector);
        epochGovernor.castVote(pid, 1, 1);
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Pending));

        skipAndRoll(1 hours);
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Active));

        // vote
        epochGovernor.castVote(pid, 1, 1); // for: 2
        assertEq(epochGovernor.hasVoted(pid, 1), true);
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = epochGovernor.proposalVotes(pid);
        assertEq(againstVotes, 0);
        assertEq(forVotes, 1994463438498854818);
        assertEq(abstainVotes, 0);
        vm.prank(address(owner2));
        epochGovernor.castVote(pid, 2, 0); // against: 1
        assertEq(epochGovernor.hasVoted(pid, 2), true);
        (againstVotes, forVotes, abstainVotes) = epochGovernor.proposalVotes(pid);
        assertEq(againstVotes, 997231719186530010);
        assertEq(forVotes, 1994463438498854818);
        assertEq(abstainVotes, 0);
        vm.prank(address(owner3));
        epochGovernor.castVote(pid, 3, 2); // abstain: 1
        assertEq(epochGovernor.hasVoted(pid, 3), true);
        (againstVotes, forVotes, abstainVotes) = epochGovernor.proposalVotes(pid);
        assertEq(againstVotes, 997231719186530010);
        assertEq(forVotes, 1994463438498854818);
        assertEq(abstainVotes, 997231719186530010);
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Active));
        assertEq(epochGovernor.hasVoted(pid, 4), false);

        skipToNextEpoch(0);
        // rewind 30 minutes so we are in the blackout window
        rewind(30 minutes);
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Succeeded));

        // execute
        epochGovernor.execute(targets, values, calldatas, keccak256(bytes(description)));
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Executed));
        assertEq(uint256(epochGovernor.result()), uint256(IGovernor.ProposalState.Succeeded));

        assertEq(minter.tailEmissionRate(), 31);
    }

    function testEpochGovernorCanExecuteDefeated() public {
        assertEq(minter.tailEmissionRate(), 30);

        address[] memory targets = new address[](1);
        targets[0] = address(minter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(minter.nudge.selector);
        string memory description = "";

        // propose
        uint256 pid = epochGovernor.propose(1, targets, values, calldatas, description);

        skipAndRoll(2);
        assertEq(escrow.balanceOfNFT(1), 1994520500269526427); // voting power at proposal start
        assertEq(escrow.balanceOfNFT(2), 997260250071864015); // voting power at proposal start
        vm.expectPartialRevert(IGovernor.GovernorUnexpectedProposalState.selector);
        epochGovernor.castVote(pid, 1, 1);
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Pending));

        skipAndRoll(1 hours);
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Active));

        // vote
        epochGovernor.castVote(pid, 1, 0); // against: 2
        assertEq(epochGovernor.hasVoted(pid, 1), true);
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = epochGovernor.proposalVotes(pid);
        assertEq(againstVotes, 1994463438498854818);
        assertEq(forVotes, 0);
        assertEq(abstainVotes, 0);
        vm.prank(address(owner2));
        epochGovernor.castVote(pid, 2, 1); // for: 1
        assertEq(epochGovernor.hasVoted(pid, 2), true);
        (againstVotes, forVotes, abstainVotes) = epochGovernor.proposalVotes(pid);
        assertEq(againstVotes, 1994463438498854818);
        assertEq(forVotes, 997231719186530010);
        assertEq(abstainVotes, 0);
        vm.prank(address(owner3));
        epochGovernor.castVote(pid, 3, 2); // abstain: 1
        assertEq(epochGovernor.hasVoted(pid, 3), true);
        (againstVotes, forVotes, abstainVotes) = epochGovernor.proposalVotes(pid);
        assertEq(againstVotes, 1994463438498854818);
        assertEq(forVotes, 997231719186530010);
        assertEq(abstainVotes, 997231719186530010);
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Active));
        assertEq(epochGovernor.hasVoted(pid, 4), false);

        skipToNextEpoch(0);
        // rewind 30 minutes so we are in the blackout window
        rewind(30 minutes);
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Defeated));

        // execute
        epochGovernor.execute(targets, values, calldatas, keccak256(bytes(description)));
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Executed));
        assertEq(uint256(epochGovernor.result()), uint256(IGovernor.ProposalState.Defeated));

        assertEq(minter.tailEmissionRate(), 29);
    }

    function testEpochGovernorCanExecuteExpired() public {
        assertEq(minter.tailEmissionRate(), 30);

        address[] memory targets = new address[](1);
        targets[0] = address(minter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(minter.nudge.selector);
        string memory description = "";

        // propose
        uint256 pid = epochGovernor.propose(1, targets, values, calldatas, description);

        skipAndRoll(2);
        assertEq(escrow.balanceOfNFT(2), 997260250071864015); // voting power at proposal start
        vm.expectPartialRevert(IGovernor.GovernorUnexpectedProposalState.selector);
        epochGovernor.castVote(pid, 1, 1);
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Pending));

        skipAndRoll(1 hours);
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Active));

        // vote
        vm.prank(address(owner2));
        epochGovernor.castVote(pid, 2, 0); // against: 1
        assertEq(epochGovernor.hasVoted(pid, 2), true);
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = epochGovernor.proposalVotes(pid);
        assertEq(againstVotes, 997231719186530010);
        assertEq(forVotes, 0);
        assertEq(abstainVotes, 0);
        vm.prank(address(owner3));
        epochGovernor.castVote(pid, 3, 1); // for: 1
        assertEq(epochGovernor.hasVoted(pid, 3), true);
        (againstVotes, forVotes, abstainVotes) = epochGovernor.proposalVotes(pid);
        assertEq(againstVotes, 997231719186530010);
        assertEq(forVotes, 997231719186530010);
        assertEq(abstainVotes, 0);
        vm.prank(address(owner4));
        epochGovernor.castVote(pid, 4, 2); // abstain: 1
        assertEq(epochGovernor.hasVoted(pid, 4), true);
        (againstVotes, forVotes, abstainVotes) = epochGovernor.proposalVotes(pid);
        assertEq(againstVotes, 997231719186530010);
        assertEq(forVotes, 997231719186530010);
        assertEq(abstainVotes, 997231719186530010);
        // tie: should still expire
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Active));
        assertEq(epochGovernor.hasVoted(pid, 1), false);

        skipToNextEpoch(0);
        // rewind 30 minutes so we are in the blackout window
        rewind(30 minutes);
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Expired));

        // execute
        epochGovernor.execute(targets, values, calldatas, keccak256(bytes(description)));
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Executed));
        assertEq(uint256(epochGovernor.result()), uint256(IGovernor.ProposalState.Expired));

        assertEq(minter.tailEmissionRate(), 30);
    }

    function testEpochGovernorCanExecuteSucceededWithDelegation() public {
        assertEq(minter.tailEmissionRate(), 30);

        vm.startPrank(address(owner4));
        escrow.lockPermanent(4);
        escrow.delegate(4, 1);
        vm.stopPrank();

        address[] memory targets = new address[](1);
        targets[0] = address(minter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(minter.nudge.selector);
        string memory description = "";

        // propose
        uint256 pid = epochGovernor.propose(1, targets, values, calldatas, description);

        skipAndRoll(2);
        assertEq(escrow.balanceOfNFT(1), 1994520500269526427); // voting power at proposal start
        assertEq(escrow.getPastVotes(address(owner), 1, block.timestamp), TOKEN_1 + 1994520500269526427);
        assertEq(escrow.balanceOfNFT(4), TOKEN_1);
        assertEq(escrow.getPastVotes(address(owner4), 4, block.timestamp), 0);
        assertEq(escrow.balanceOfNFT(2), 997260250071864015); // voting power at proposal start
        vm.expectPartialRevert(IGovernor.GovernorUnexpectedProposalState.selector);
        epochGovernor.castVote(pid, 1, 1);
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Pending));

        skipAndRoll(1 hours);
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Active));

        // vote
        epochGovernor.castVote(pid, 1, 1); // for: 2
        assertEq(epochGovernor.hasVoted(pid, 1), true);
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = epochGovernor.proposalVotes(pid);
        assertEq(againstVotes, 0);
        assertEq(forVotes, TOKEN_1 + 1994463438498854818);
        assertEq(abstainVotes, 0);
        vm.prank(address(owner2));
        epochGovernor.castVote(pid, 2, 0); // against: 1
        assertEq(epochGovernor.hasVoted(pid, 2), true);
        (againstVotes, forVotes, abstainVotes) = epochGovernor.proposalVotes(pid);
        assertEq(againstVotes, 997231719186530010);
        assertEq(forVotes, TOKEN_1 + 1994463438498854818);
        assertEq(abstainVotes, 0);
        vm.prank(address(owner3));
        epochGovernor.castVote(pid, 3, 2); // abstain: 1
        assertEq(epochGovernor.hasVoted(pid, 3), true);
        (againstVotes, forVotes, abstainVotes) = epochGovernor.proposalVotes(pid);
        assertEq(againstVotes, 997231719186530010);
        assertEq(forVotes, TOKEN_1 + 1994463438498854818);
        assertEq(abstainVotes, 997231719186530010);
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Active));
        assertEq(epochGovernor.hasVoted(pid, 4), false);

        skipToNextEpoch(0);
        // rewind 30 minutes so we are in the blackout window
        rewind(30 minutes);
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Succeeded));

        // execute
        epochGovernor.execute(targets, values, calldatas, keccak256(bytes(description)));
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Executed));
        assertEq(uint256(epochGovernor.result()), uint256(IGovernor.ProposalState.Succeeded));

        assertEq(minter.tailEmissionRate(), 31);
    }

    function testCannotProposeWithAnExistingProposal() public {
        skip(epochGovernor.proposalWindow()); // skip proposal window to allow proposal creation
        assertEq(minter.tailEmissionRate(), 30);

        address[] memory targets = new address[](1);
        targets[0] = address(minter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(minter.nudge.selector);
        string memory description = "";

        // propose
        epochGovernor.propose(1, targets, values, calldatas, description);

        vm.prank(address(owner2));
        vm.expectPartialRevert(IGovernor.GovernorUnexpectedProposalState.selector);
        epochGovernor.propose(2, targets, values, calldatas, description);
    }

    function testCastVoteWithLockedManagedVeNFTNotDelegating() public {
        // mveNFT not delegating, so vote with locked nft > 0, vote with mveNFT != 0
        skip(1 hours);

        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        voter.depositManaged(tokenId, mTokenId);
        uint256 tokenId2 = escrow.createLock(TOKEN_1 * 2, MAXTIME);
        voter.depositManaged(tokenId2, mTokenId);
        // delegate to increase locked voting power
        uint256 delegateTokenId = escrow.createLock(TOKEN_1 * 5, MAXTIME);
        escrow.lockPermanent(delegateTokenId);
        uint256 delegateTokenId2 = escrow.createLock(TOKEN_1 * 3, MAXTIME);
        escrow.lockPermanent(delegateTokenId2);
        escrow.delegate(delegateTokenId, tokenId);
        escrow.delegate(delegateTokenId2, tokenId2);

        skipToNextEpoch(0);
        uint256 pid = createProposal();
        skip(1 hours + 2); // allow voting

        epochGovernor.castVote(pid, tokenId, 1);
        // voting balances 0, but votes process on epochGovernor
        assertEq(escrow.balanceOfNFT(tokenId), 0);
        // voting power of locked nft is delegated balance
        assertEq(escrow.getPastVotes(address(owner), tokenId, block.timestamp - 1), TOKEN_1 * 5);
        assertProposalVotes(pid, 0, TOKEN_1 * 5, 0);
        assertEq(epochGovernor.hasVoted(pid, tokenId), true);

        epochGovernor.castVote(pid, tokenId2, 1);
        // voting balances 0, but votes process on epochGovernor
        assertEq(escrow.balanceOfNFT(tokenId2), 0);
        // voting power of locked nft is delegated balance
        assertEq(escrow.getPastVotes(address(owner), tokenId2, block.timestamp - 1), TOKEN_1 * 3);
        assertProposalVotes(pid, 0, TOKEN_1 * 8, 0); // increment by TOKEN_1 * 3
        assertEq(epochGovernor.hasVoted(pid, tokenId2), true);
    }

    function testCastVoteWithLockedManagedVeNFTNotDelegatingWithLockedRewardsExactlyOnFollowingEpochFlip() public {
        // mveNFT not delegating, so vote with locked nft > 0, vote with mveNFT != 0
        skip(1 hours);

        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        voter.depositManaged(tokenId, mTokenId);
        uint256 tokenId2 = escrow.createLock(TOKEN_1 * 2, MAXTIME);
        voter.depositManaged(tokenId2, mTokenId);
        // delegate to increase locked voting power
        uint256 delegateTokenId = escrow.createLock(TOKEN_1 * 5, MAXTIME);
        escrow.lockPermanent(delegateTokenId);
        uint256 delegateTokenId2 = escrow.createLock(TOKEN_1 * 3, MAXTIME);
        escrow.lockPermanent(delegateTokenId2);
        escrow.delegate(delegateTokenId, tokenId);
        escrow.delegate(delegateTokenId2, tokenId2);

        LockedManagedReward lmr = LockedManagedReward(escrow.managedToLocked(mTokenId));

        // seed locked rewards, then skip to just before next epoch
        VELO.approve(address(escrow), TOKEN_1);
        escrow.increaseAmount(mTokenId, TOKEN_1);
        skipToNextEpoch(0);
        rewind(1); // trigger proposal snapshot exactly on epoch flip

        skipToNextEpoch(0);
        uint256 pid = createProposal();
        skip(1 hours + 2); // allow voting

        epochGovernor.castVote(pid, tokenId, 1);
        // voting balances 0, but votes process on epochGovernor
        assertEq(escrow.balanceOfNFT(tokenId), 0);
        // voting power of locked nft is delegated balance
        assertEq(escrow.getPastVotes(address(owner), tokenId, block.timestamp - 1), TOKEN_1 * 5);
        assertEq(lmr.earned(address(VELO), tokenId), TOKEN_1 / 3);
        assertProposalVotes(pid, 0, TOKEN_1 * 5, 0); // accrued managed rewards are not accounted for
        assertEq(epochGovernor.hasVoted(pid, tokenId), true);

        epochGovernor.castVote(pid, tokenId2, 1);
        // voting balances 0, but votes process on epochGovernor
        assertEq(escrow.balanceOfNFT(tokenId2), 0);
        // voting power of locked nft is delegated balance
        assertEq(escrow.getPastVotes(address(owner), tokenId2, block.timestamp - 1), TOKEN_1 * 3);
        assertEq(lmr.earned(address(VELO), tokenId2), (TOKEN_1 * 2) / 3);
        assertProposalVotes(pid, 0, TOKEN_1 * 8, 0); // increment by TOKEN_1 * 3
        assertEq(epochGovernor.hasVoted(pid, tokenId2), true);
    }

    function testCastVoteWithLockedManagedVeNFTNotDelegatingWithLockedRewardsPriorToEpochFlip() public {
        // mveNFT not delegating, so vote with locked nft > 0, vote with mveNFT != 0
        skip(1 hours);

        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        voter.depositManaged(tokenId, mTokenId);
        uint256 tokenId2 = escrow.createLock(TOKEN_1 * 2, MAXTIME);
        voter.depositManaged(tokenId2, mTokenId);
        // delegate to increase locked voting power
        uint256 delegateTokenId = escrow.createLock(TOKEN_1 * 5, MAXTIME);
        escrow.lockPermanent(delegateTokenId);
        uint256 delegateTokenId2 = escrow.createLock(TOKEN_1 * 3, MAXTIME);
        escrow.lockPermanent(delegateTokenId2);
        escrow.delegate(delegateTokenId, tokenId);
        escrow.delegate(delegateTokenId2, tokenId2);

        LockedManagedReward lmr = LockedManagedReward(escrow.managedToLocked(mTokenId));

        // seed locked rewards, then skip to just before next epoch
        VELO.approve(address(escrow), TOKEN_1);
        escrow.increaseAmount(mTokenId, TOKEN_1);
        skipToNextEpoch(0);
        rewind(1 + 1);
        // as it is not a new epoch, locked rewards do not contribute to votes

        skipToNextEpoch(0);
        uint256 pid = createProposal();
        skip(1 hours + 2); // allow voting

        epochGovernor.castVote(pid, tokenId, 1);
        // voting balances 0, but votes process on epochGovernor
        assertEq(escrow.balanceOfNFT(tokenId), 0);
        // voting power of locked nft is delegated balance
        assertEq(escrow.getPastVotes(address(owner), tokenId, block.timestamp - 1), TOKEN_1 * 5);
        assertEq(lmr.earned(address(VELO), tokenId), TOKEN_1 / 3);
        assertProposalVotes(pid, 0, TOKEN_1 * 5, 0); // accrued managed rewards are not accounted for
        assertEq(epochGovernor.hasVoted(pid, tokenId), true);

        epochGovernor.castVote(pid, tokenId2, 1);
        // voting balances 0, but votes process on epochGovernor
        assertEq(escrow.balanceOfNFT(tokenId2), 0);
        // voting balances 0, but votes process on epochGovernor
        assertEq(escrow.getPastVotes(address(owner), tokenId2, block.timestamp - 1), TOKEN_1 * 3);
        assertEq(lmr.earned(address(VELO), tokenId2), (TOKEN_1 * 2) / 3);
        assertProposalVotes(pid, 0, TOKEN_1 * 8, 0); // increment by TOKEN_1 * 3
        assertEq(epochGovernor.hasVoted(pid, tokenId2), true);
    }

    function testCastVoteWithLockedManagedVeNFTDelegatingToOther() public {
        // mveNFT delegating to someone else, vote with locked nft == 0, vote with mveNFT != 0
        skip(1 hours);

        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        VELO.approve(address(escrow), type(uint256).max);
        uint256 depositTokenId = escrow.createLock(TOKEN_1, MAXTIME);
        voter.depositManaged(depositTokenId, mTokenId);
        uint256 delegateTokenId = escrow.createLock(TOKEN_1, MAXTIME);
        escrow.lockPermanent(delegateTokenId);

        escrow.delegate(mTokenId, delegateTokenId);

        skipToNextEpoch(0);
        uint256 pid = createProposal();
        skip(1 hours + 2); // allow voting

        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorAlreadyCastVote.selector, depositTokenId));
        epochGovernor.castVote(pid, depositTokenId, 1);
        assertEq(epochGovernor.hasVoted(pid, depositTokenId), false);

        epochGovernor.castVote(pid, delegateTokenId, 1);
        assertEq(escrow.balanceOfNFT(delegateTokenId), TOKEN_1);
        assertEq(escrow.getPastVotes(address(owner), delegateTokenId, block.timestamp - 1), TOKEN_1 * 2);
        assertProposalVotes(pid, 0, TOKEN_1 * 2, 0);
        assertEq(epochGovernor.hasVoted(pid, delegateTokenId), true);
    }

    function testCastVoteWithLockedManagedVeNFTDelegatingToOtherWithAdditionalDelegate() public {
        // mveNFT delegating to someone else, vote with locked nft == 0, vote with mveNFT != 0
        // mveNFT => delegateTokenId
        // delegateTokenId => depositTokenId
        skip(1 hours);

        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        VELO.approve(address(escrow), type(uint256).max);
        uint256 depositTokenId = escrow.createLock(TOKEN_1, MAXTIME);
        voter.depositManaged(depositTokenId, mTokenId);
        uint256 delegateTokenId = escrow.createLock(TOKEN_1, MAXTIME);
        escrow.lockPermanent(delegateTokenId);

        escrow.delegate(mTokenId, delegateTokenId);
        escrow.delegate(delegateTokenId, depositTokenId);

        skipToNextEpoch(0);
        uint256 pid = createProposal();
        skip(1 hours + 2); // allow voting

        // reward voting balance == 0
        // governance voting balance == TOKEN_1 from delegateTokenId delegation
        epochGovernor.castVote(pid, depositTokenId, 1);
        assertEq(escrow.balanceOfNFT(depositTokenId), 0);
        assertEq(escrow.getPastVotes(address(owner), depositTokenId, block.timestamp - 1), TOKEN_1);
        assertProposalVotes(pid, 0, TOKEN_1 * 1, 0);
        assertEq(epochGovernor.hasVoted(pid, depositTokenId), true);

        // reward voting balance == TOKEN_1
        // governance voting balance == TOKEN_1 from delegateTokenId delegation
        epochGovernor.castVote(pid, delegateTokenId, 1);
        assertEq(escrow.balanceOfNFT(delegateTokenId), TOKEN_1);
        assertEq(escrow.getPastVotes(address(owner), delegateTokenId, block.timestamp - 1), TOKEN_1);
        assertProposalVotes(pid, 0, TOKEN_1 * 2, 0);
        assertEq(epochGovernor.hasVoted(pid, delegateTokenId), true);
    }

    function testCastVoteWithLockedManagedVeNFTDelegatingToVoterWithAdditionalDelegate() public {
        // mveNFT delegating to voter, vote with locked nft == mveNFT + delegate balance
        // other user also delegating to voter
        skip(1 hours);

        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        VELO.approve(address(escrow), type(uint256).max);
        uint256 depositTokenId = escrow.createLock(TOKEN_1, MAXTIME);
        voter.depositManaged(depositTokenId, mTokenId);
        uint256 otherTokenId = escrow.createLock(TOKEN_1, MAXTIME);
        escrow.lockPermanent(otherTokenId);

        escrow.delegate(mTokenId, depositTokenId);
        escrow.delegate(otherTokenId, depositTokenId);

        skipToNextEpoch(0);
        uint256 pid = createProposal();
        skip(1 hours + 2); // allow voting

        epochGovernor.castVote(pid, depositTokenId, 1);
        assertEq(escrow.balanceOfNFT(depositTokenId), 0);
        assertEq(escrow.getPastVotes(address(owner), depositTokenId, block.timestamp - 1), TOKEN_1 * 2);
        assertProposalVotes(pid, 0, TOKEN_1 * 2, 0);
        assertEq(epochGovernor.hasVoted(pid, depositTokenId), true);
    }

    function testCastVoteWithLockedManagedVeNFTDelegatingBeforeProposalWithLockedRewards() public {
        // delegation occurs on the snapshot boundary, mveNFT is considered delegating
        skip(1 hours);

        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        VELO.approve(address(escrow), type(uint256).max);
        uint256 depositTokenId = escrow.createLock(TOKEN_1, MAXTIME);
        voter.depositManaged(depositTokenId, mTokenId);
        uint256 delegateTokenId = escrow.createLock(TOKEN_1, MAXTIME);
        escrow.lockPermanent(delegateTokenId);

        // seed locked rewards, then skip to next epoch
        VELO.approve(address(escrow), TOKEN_1);
        escrow.increaseAmount(mTokenId, TOKEN_1);

        skipToNextEpoch(0);

        uint256 pid = createProposal();
        escrow.delegate(mTokenId, delegateTokenId); // delegate on snapshot boundary
        skip(1 hours + 2); // allow voting

        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorAlreadyCastVote.selector, depositTokenId));
        epochGovernor.castVote(pid, depositTokenId, 1);
        assertEq(epochGovernor.hasVoted(pid, depositTokenId), false);

        epochGovernor.castVote(pid, delegateTokenId, 1);
        assertEq(escrow.balanceOfNFT(delegateTokenId), TOKEN_1);
        assertEq(escrow.getPastVotes(address(owner), delegateTokenId, block.timestamp - 1), TOKEN_1 * 3);
        assertProposalVotes(pid, 0, TOKEN_1 * 3, 0);
        assertEq(epochGovernor.hasVoted(pid, delegateTokenId), true);
    }

    function testCastVoteWithLockedManagedVeNFTDelegatingAfterProposalWithLockedRewards() public {
        // as delegation occurs after the snapshot, mveNFT is considered not delegating
        skip(1 hours);

        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        VELO.approve(address(escrow), type(uint256).max);
        uint256 depositTokenId = escrow.createLock(TOKEN_1, MAXTIME);
        voter.depositManaged(depositTokenId, mTokenId);
        uint256 delegateTokenId = escrow.createLock(TOKEN_1, MAXTIME);
        escrow.lockPermanent(delegateTokenId);
        uint256 delegateTokenId2 = escrow.createLock(TOKEN_1 * 3, MAXTIME);
        escrow.lockPermanent(delegateTokenId2);
        escrow.delegate(delegateTokenId2, depositTokenId);

        // seed locked rewards, then skip to next epoch
        VELO.approve(address(escrow), TOKEN_1);
        escrow.increaseAmount(mTokenId, TOKEN_1);

        skipToNextEpoch(0);

        uint256 pid = createProposal();
        skip(1 hours + 2); // allow voting

        escrow.delegate(mTokenId, delegateTokenId);

        // mveNFT not considered delegating, so locked depositor can vote
        epochGovernor.castVote(pid, depositTokenId, 1);
        assertEq(escrow.balanceOfNFT(depositTokenId), 0);
        // voting power of locked nft is delegated balance
        assertEq(escrow.getPastVotes(address(owner), depositTokenId, block.timestamp - 1), TOKEN_1 * 3);
        assertProposalVotes(pid, 0, TOKEN_1 * 3, 0);
        assertEq(epochGovernor.hasVoted(pid, depositTokenId), true);

        // mveNFT not considered delegating, so delegatee does not receive votes
        epochGovernor.castVote(pid, delegateTokenId, 1);
        assertEq(escrow.balanceOfNFT(delegateTokenId), TOKEN_1);
        // voting power of locked nft is delegated balance
        assertEq(escrow.getPastVotes(address(owner), delegateTokenId, block.timestamp - 1), TOKEN_1);
        assertProposalVotes(pid, 0, TOKEN_1 * 4, 0);
        assertEq(epochGovernor.hasVoted(pid, delegateTokenId), true);
    }

    // creates a proposal so we can vote on it for testing and skip to snapshot time
    // voting start time is 2 second after snapshot
    function createProposal() internal returns (uint256 pid) {
        address[] memory targets = new address[](1);
        targets[0] = address(minter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(minter.nudge.selector);
        string memory description = "";

        // propose
        pid = epochGovernor.propose(1, targets, values, calldatas, description);

        skipAndRoll(2);
    }

    function assertProposalVotes(uint256 pid, uint256 againstVotes, uint256 forVotes, uint256 abstainVotes)
        internal
        view
    {
        (uint256 _againstVotes, uint256 _forVotes, uint256 _abstainVotes) = epochGovernor.proposalVotes(pid);
        assertApproxEqAbs(_againstVotes, againstVotes, 1);
        assertApproxEqAbs(_forVotes, forVotes, 1);
        assertApproxEqAbs(_abstainVotes, abstainVotes, 1);
    }
}

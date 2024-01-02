// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./BaseTest.sol";
import {IVetoGovernor} from "contracts/governance/IVetoGovernor.sol";
import {VeloGovernor} from "contracts/VeloGovernor.sol";

contract VeloGovernorTest is BaseTest {
    event ProposalVetoed(uint256 proposalId);
    event AcceptTeam(address indexed newTeam);
    event AcceptVetoer(address indexed vetoer);
    event SetCommentWeighting(uint256 commentWeighting);
    event SetProposalNumerator(uint256 indexed proposalNumerator);
    event RenounceVetoer();
    event Comment(uint256 indexed proposalId, address indexed account, uint256 indexed tokenId, string comment);

    address public token;

    function _setUp() public override {
        VELO.approve(address(escrow), 97 * TOKEN_1);
        escrow.createLock(97 * TOKEN_1, MAXTIME); // 1

        // owner2 owns less than quorum, 2%
        vm.startPrank(address(owner2));
        VELO.approve(address(escrow), 2 * TOKEN_1);
        escrow.createLock(2 * TOKEN_1, MAXTIME); // 2
        vm.stopPrank();

        // owner3 owns exactly 1% (threshold)
        // but due to decay, cannot propose
        vm.startPrank(address(owner3));
        VELO.approve(address(escrow), TOKEN_1 - 1);
        escrow.createLock(TOKEN_1 - 1, MAXTIME); // 3
        vm.stopPrank();

        skipAndRoll(1);

        token = address(new MockERC20("TEST", "TEST", 18));
    }

    function testInitialState() public {
        assertEq(governor.votingDelay(), 2 days);
        assertEq(governor.votingPeriod(), 5 days);
        assertEq(governor.quorumNumerator(), 25);
        assertEq(governor.proposalNumerator(), 100);
        assertEq(governor.lateQuorumVoteExtension(), 2 days);
        assertEq(governor.commentWeighting(), 4_000);
        assertEq(governor.COMMENT_DENOMINATOR(), 1_000_000_000);
    }

    function testCannotSetTeamToZeroAddress() public {
        vm.expectRevert(VeloGovernor.ZeroAddress.selector);
        governor.setTeam(address(0));
    }

    function testCannotSetTeamIfNotTeam() public {
        vm.prank(address(owner2));
        vm.expectRevert(VeloGovernor.NotTeam.selector);
        governor.setTeam(address(owner2));
    }

    function testSetTeam() public {
        governor.setTeam(address(owner2));

        assertEq(governor.pendingTeam(), address(owner2));
    }

    function testCannotAcceptTeamIfNotPendingTeam() public {
        governor.setTeam(address(owner2));

        vm.prank(address(owner3));
        vm.expectRevert(VeloGovernor.NotPendingTeam.selector);
        governor.acceptTeam();
    }

    function testAcceptTeam() public {
        governor.setTeam(address(owner2));

        vm.prank(address(owner2));
        vm.expectEmit(true, false, false, false);
        emit AcceptTeam(address(owner2));
        governor.acceptTeam();

        assertEq(governor.team(), address(owner2));
    }

    function testCannotSetVetoerToZeroAddress() public {
        vm.prank(governor.vetoer());
        vm.expectRevert(VeloGovernor.ZeroAddress.selector);
        governor.setVetoer(address(0));
    }

    function testCannotSetVetoerIfNotVetoer() public {
        vm.prank(address(owner2));
        vm.expectRevert(VeloGovernor.NotVetoer.selector);
        governor.setVetoer(address(owner2));
    }

    function testSetVetoer() public {
        governor.setVetoer(address(owner2));

        assertEq(governor.pendingVetoer(), address(owner2));
    }

    function testCannotRenounceVetoerIfNotVetoer() public {
        vm.prank(address(owner2));
        vm.expectRevert(VeloGovernor.NotVetoer.selector);
        governor.renounceVetoer();
    }

    function testRenounceVetoer() public {
        vm.expectEmit(false, false, false, false);
        emit RenounceVetoer();
        governor.renounceVetoer();

        assertEq(governor.vetoer(), address(0));
    }

    function testCannotAcceptVetoerIfNotPendingVetoer() public {
        governor.setVetoer(address(owner2));

        vm.prank(address(owner3));
        vm.expectRevert(VeloGovernor.NotPendingVetoer.selector);
        governor.acceptVetoer();
    }

    function testAcceptVetoer() public {
        governor.setVetoer(address(owner2));

        vm.prank(address(owner2));
        vm.expectEmit(true, false, false, false);
        emit AcceptVetoer(address(owner2));
        governor.acceptVetoer();

        assertEq(governor.vetoer(), address(owner2));
    }

    function testCannotVetoIfNotVetoer() public {
        address[] memory targets = new address[](1);
        targets[0] = address(voter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(voter.whitelistToken.selector, address(USDC));
        string memory description = "Whitelist USDC";

        uint256 pid = governor.propose(1, targets, values, calldatas, description);

        vm.prank(address(owner2));
        vm.expectRevert(VeloGovernor.NotVetoer.selector);
        governor.veto(pid);
    }

    function testVetoProposal() public {
        address[] memory targets = new address[](1);
        targets[0] = address(voter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(voter.whitelistToken.selector, address(USDC));
        string memory description = "Whitelist USDC";

        uint256 pid = governor.propose(1, targets, values, calldatas, description);

        skipAndRoll(2 days + 1);

        governor.castVote(pid, 1, 1);
        uint256 proposalStart = governor.proposalSnapshot(pid);
        assertGt(governor.getVotes(address(owner), 1, proposalStart), governor.quorum(proposalStart)); // check quorum

        skipAndRoll(1 weeks / 2);

        vm.expectEmit(true, false, false, true, address(governor));
        emit ProposalVetoed(pid);
        governor.veto(pid);

        assertEq(uint256(governor.state(pid)), uint256(IVetoGovernor.ProposalState.Vetoed));

        vm.expectRevert("Governor: proposal not successful");
        governor.execute(targets, values, calldatas, keccak256(bytes(description)), address(owner));
    }

    function testGovernorCanCreateGaugesForAnyAddress() public {
        vm.prank(address(governor));
        voter.createGauge(address(factory), address(1));
    }

    function testCannotSetProposalNumeratorAboveMaximum() public {
        vm.expectRevert(VeloGovernor.ProposalNumeratorTooHigh.selector);
        governor.setProposalNumerator(501);
    }

    function testCannotSetProposalNumeratorIfNotTeam() public {
        vm.prank(address(owner2));
        vm.expectRevert(VeloGovernor.NotTeam.selector);
        governor.setProposalNumerator(1);
    }

    function testSetProposalNumerator() public {
        vm.expectEmit(true, false, false, false);
        emit SetProposalNumerator(50);
        governor.setProposalNumerator(50);
        assertEq(governor.proposalNumerator(), 50);
    }

    function testCannotProposeWithoutSufficientBalance() public {
        address[] memory targets = new address[](1);
        targets[0] = address(voter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(voter.whitelistToken.selector, address(USDC), true);
        string memory description = "Whitelist USDC";

        vm.prank(address(owner3));
        vm.expectRevert("Governor: proposer votes below proposal threshold");
        governor.propose(3, targets, values, calldatas, description);
    }

    function testCannotExecuteWithoutQuorum() public {
        assertFalse(voter.isWhitelistedToken(token));

        address[] memory targets = new address[](1);
        targets[0] = address(voter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(voter.whitelistToken.selector, token, true);
        string memory description = "Whitelist Token";

        // propose
        uint256 pid = governor.propose(1, targets, values, calldatas, description);

        skipAndRoll(2 days);
        vm.expectRevert("Governor: vote not currently active");
        governor.castVote(pid, 1, 1);
        assertEq(uint256(governor.state(pid)), uint256(IVetoGovernor.ProposalState.Pending));

        skipAndRoll(1);
        // vote
        vm.prank(address(owner2));
        governor.castVote(pid, 2, 1);

        skipAndRoll(5 days);

        // execute
        vm.prank(address(owner));
        vm.expectRevert("Governor: proposal not successful");
        governor.execute(targets, values, calldatas, keccak256(bytes(description)), address(owner));
    }

    function testProposalHasQuorum() public {
        assertFalse(voter.isWhitelistedToken(token));

        address[] memory targets = new address[](1);
        targets[0] = address(voter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(voter.whitelistToken.selector, token, true);
        string memory description = "Whitelist Token";

        // propose
        uint256 pid = governor.propose(1, targets, values, calldatas, description);

        skipAndRoll(2 days);
        assertEq(escrow.balanceOfNFT(1), 96601368325052202388); // voting power at proposal start
        assertEq(escrow.getPastVotes(address(owner), 1, block.timestamp), 96601368325052202388);
        vm.expectRevert("Governor: vote not currently active");
        governor.castVote(pid, 1, 1);
        assertEq(uint256(governor.state(pid)), uint256(IVetoGovernor.ProposalState.Pending));

        skipAndRoll(1);
        assertEq(uint256(governor.state(pid)), uint256(IVetoGovernor.ProposalState.Active));

        // vote
        governor.castVote(pid, 1, 1);
        assertEq(governor.hasVoted(pid, 1), true);
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(pid);
        assertEq(againstVotes, 0);
        assertEq(forVotes, 96601368325052202388);
        assertEq(abstainVotes, 0);
        assertEq(uint256(governor.state(pid)), uint256(IVetoGovernor.ProposalState.Active));

        skipAndRoll(1);
        // cannot vote twice
        vm.expectRevert("GovernorVotingSimple: vote already cast");
        governor.castVote(pid, 1, 2);

        skipAndRoll(1);
        // cannot vote with voting weight that is not yours
        vm.expectRevert("GovernorVotingSimple: zero voting weight");
        governor.castVote(pid, 2, 1);

        skipAndRoll(5 days);
        assertEq(uint256(governor.state(pid)), uint256(IVetoGovernor.ProposalState.Succeeded));

        // execute
        governor.execute(targets, values, calldatas, keccak256(bytes(description)), address(owner));
        assertEq(uint256(governor.state(pid)), uint256(IVetoGovernor.ProposalState.Executed));
        assertTrue(voter.isWhitelistedToken(token));
    }

    function testProposalHasQuorumWithDelegatedVotes() public {
        vm.startPrank(address(owner3));
        VELO.approve(address(escrow), TOKEN_1 * 100);
        escrow.createLock(TOKEN_1 * 100, MAXTIME); // 4
        escrow.lockPermanent(4);
        escrow.delegate(4, 3);
        vm.stopPrank();
        skipAndRoll(1);

        assertFalse(voter.isWhitelistedToken(token));

        address[] memory targets = new address[](1);
        targets[0] = address(voter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(voter.whitelistToken.selector, token, true);
        string memory description = "Whitelist Token";

        // propose
        uint256 pid = governor.propose(1, targets, values, calldatas, description);

        skipAndRoll(2 days);
        assertEq(escrow.balanceOfNFT(3), 995890387058328015); // voting power at proposal start
        assertEq(escrow.getPastVotes(address(owner3), 3, block.timestamp), 995890387058328015 + TOKEN_1 * 100);
        assertEq(escrow.balanceOfNFT(4), TOKEN_1 * 100);
        assertEq(escrow.getPastVotes(address(owner3), 4, block.timestamp), 0);
        vm.expectRevert("Governor: vote not currently active");
        governor.castVote(pid, 3, 1);
        assertEq(uint256(governor.state(pid)), uint256(IVetoGovernor.ProposalState.Pending));

        skipAndRoll(1);
        assertEq(uint256(governor.state(pid)), uint256(IVetoGovernor.ProposalState.Active));

        // vote
        vm.prank(address(owner3));
        governor.castVote(pid, 3, 1);
        assertEq(governor.hasVoted(pid, 3), true);
        assertEq(governor.hasVoted(pid, 4), false);
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(pid);
        assertEq(againstVotes, 0);
        assertEq(forVotes, 995890387058328015 + TOKEN_1 * 100);
        assertEq(abstainVotes, 0);
        assertEq(uint256(governor.state(pid)), uint256(IVetoGovernor.ProposalState.Active));

        skipAndRoll(1);
        // cannot vote twice
        vm.prank(address(owner3));
        vm.expectRevert("GovernorVotingSimple: vote already cast");
        governor.castVote(pid, 3, 2);

        skipAndRoll(1);
        // cannot vote with voting weight that is not yours
        vm.expectRevert("GovernorVotingSimple: zero voting weight");
        governor.castVote(pid, 4, 1);

        skipAndRoll(5 days);
        assertEq(uint256(governor.state(pid)), uint256(IVetoGovernor.ProposalState.Succeeded));

        // execute
        governor.execute(targets, values, calldatas, keccak256(bytes(description)), address(owner));
        assertEq(uint256(governor.state(pid)), uint256(IVetoGovernor.ProposalState.Executed));
        assertTrue(voter.isWhitelistedToken(token));
    }

    function testProposeWithUniqueProposals() public {
        assertFalse(voter.isWhitelistedToken(token));

        address[] memory targets = new address[](1);
        targets[0] = address(voter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(voter.whitelistToken.selector, token);
        string memory description = "Whitelist Token";

        // a user creates a proposal
        // another user frontruns the initial proposal creation, and then cancels the proposal
        uint256 pid = governor.propose(1, targets, values, calldatas, description); // frontrun

        vm.prank(address(owner2));
        uint256 pid2 = governor.propose(2, targets, values, calldatas, description); // will revert if pids not unique

        assertFalse(pid == pid2);
    }

    function testCastVoteWithLateQuorumExtendsDeadline() public {
        assertFalse(voter.isWhitelistedToken(token));

        address[] memory targets = new address[](1);
        targets[0] = address(voter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(voter.whitelistToken.selector, token, true);
        string memory description = "Whitelist Token";

        // propose
        uint256 pid = governor.propose(1, targets, values, calldatas, description);
        assertEq(governor.proposalDeadline(pid), block.timestamp + 7 days);

        skip(5 days + 1);

        governor.castVote(pid, 1, 1);
        uint256 newDeadline = governor.proposalDeadline(pid);

        assertEq(newDeadline, block.timestamp + 2 days);
    }

    function testCastVoteWithLateQuorumDoesNotExtendDeadline() public {
        assertFalse(voter.isWhitelistedToken(token));

        address[] memory targets = new address[](1);
        targets[0] = address(voter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(voter.whitelistToken.selector, token, true);
        string memory description = "Whitelist Token";

        // propose
        uint256 pid = governor.propose(1, targets, values, calldatas, description);

        skip(5 days);

        uint256 deadline = governor.proposalDeadline(pid);
        governor.castVote(pid, 1, 1);
        uint256 newDeadline = governor.proposalDeadline(pid);

        assertEq(newDeadline, deadline);
    }

    function testCannotCastVoteIfManagedVeNFT() public {
        skip(1 hours);

        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        VELO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        voter.depositManaged(tokenId, mTokenId);

        uint256 pid = createProposal();
        skip(1); // allow voting

        vm.expectRevert("Governor: managed nft cannot vote");
        vm.prank(address(owner));
        governor.castVote(pid, mTokenId, 1);
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

        uint256 pid = createProposal();
        skip(1); // allow voting

        governor.castVote(pid, tokenId, 1);
        // voting balances 0, but votes process on governor
        assertEq(escrow.balanceOfNFT(tokenId), 0);
        assertEq(escrow.getPastVotes(address(owner), tokenId, block.timestamp - 1), 0);
        assertProposalVotes(pid, 0, TOKEN_1, 0);
        assertEq(governor.hasVoted(pid, tokenId), true);

        governor.castVote(pid, tokenId2, 1);
        // voting balances 0, but votes process on governor
        assertEq(escrow.balanceOfNFT(tokenId2), 0);
        assertEq(escrow.getPastVotes(address(owner), tokenId2, block.timestamp - 1), 0);
        assertProposalVotes(pid, 0, TOKEN_1 * 3, 0); // increment by TOKEN_1 * 2
        assertEq(governor.hasVoted(pid, tokenId2), true);
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

        LockedManagedReward lmr = LockedManagedReward(escrow.managedToLocked(mTokenId));

        // seed locked rewards, then skip to just before next epoch
        VELO.approve(address(escrow), TOKEN_1);
        escrow.increaseAmount(mTokenId, TOKEN_1);
        skipToNextEpoch(0);
        rewind(2 days); // trigger proposal snapshot exactly on epoch flip

        uint256 pid = createProposal();
        skip(1); // allow voting

        governor.castVote(pid, tokenId, 1);
        // voting balances 0, but votes process on governor
        assertEq(escrow.balanceOfNFT(tokenId), 0);
        assertEq(escrow.getPastVotes(address(owner), tokenId, block.timestamp - 1), 0);
        assertEq(lmr.earned(address(VELO), tokenId), TOKEN_1 / 3);
        assertProposalVotes(pid, 0, TOKEN_1 + TOKEN_1 / 3, 0);
        assertEq(governor.hasVoted(pid, tokenId), true);

        governor.castVote(pid, tokenId2, 1);
        // voting balances 0, but votes process on governor
        assertEq(escrow.balanceOfNFT(tokenId2), 0);
        assertEq(escrow.getPastVotes(address(owner), tokenId2, block.timestamp - 1), 0);
        assertEq(lmr.earned(address(VELO), tokenId2), (TOKEN_1 * 2) / 3);
        assertProposalVotes(pid, 0, TOKEN_1 * 4, 0); // increment by TOKEN_1 * 2 + TOKEN_1 * 2 /3
        assertEq(governor.hasVoted(pid, tokenId2), true);
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

        LockedManagedReward lmr = LockedManagedReward(escrow.managedToLocked(mTokenId));

        // seed locked rewards, then skip to just before next epoch
        VELO.approve(address(escrow), TOKEN_1);
        escrow.increaseAmount(mTokenId, TOKEN_1);
        skipToNextEpoch(0);
        rewind(2 days + 1);
        // as it is not a new epoch, locked rewards do not contribute to votes

        uint256 pid = createProposal();
        skip(1); // allow voting

        governor.castVote(pid, tokenId, 1);
        // voting balances 0, but votes process on governor
        assertEq(escrow.balanceOfNFT(tokenId), 0);
        assertEq(escrow.getPastVotes(address(owner), tokenId, block.timestamp - 1), 0);
        assertEq(lmr.earned(address(VELO), tokenId), TOKEN_1 / 3);
        assertProposalVotes(pid, 0, TOKEN_1 + TOKEN_1 / 3, 0);
        assertEq(governor.hasVoted(pid, tokenId), true);

        governor.castVote(pid, tokenId2, 1);
        // voting balances 0, but votes process on governor
        assertEq(escrow.balanceOfNFT(tokenId2), 0);
        assertEq(escrow.getPastVotes(address(owner), tokenId2, block.timestamp - 1), 0);
        assertEq(lmr.earned(address(VELO), tokenId2), (TOKEN_1 * 2) / 3);
        assertProposalVotes(pid, 0, TOKEN_1 * 4, 0); // increment by TOKEN_1 * 2 + TOKEN_1 * 2 / 3
        assertEq(governor.hasVoted(pid, tokenId2), true);
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

        uint256 pid = createProposal();
        skip(1); // allow voting

        vm.expectRevert("GovernorVotingSimple: zero voting weight");
        governor.castVote(pid, depositTokenId, 1);
        assertEq(governor.hasVoted(pid, depositTokenId), false);

        governor.castVote(pid, delegateTokenId, 1);
        assertEq(escrow.balanceOfNFT(delegateTokenId), TOKEN_1);
        assertEq(escrow.getPastVotes(address(owner), delegateTokenId, block.timestamp - 1), TOKEN_1 * 2);
        assertProposalVotes(pid, 0, TOKEN_1 * 2, 0);
        assertEq(governor.hasVoted(pid, delegateTokenId), true);
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

        uint256 pid = createProposal();
        skip(1); // allow voting

        // reward voting balance == 0
        // governance voting balance == TOKEN_1 from delegateTokenId delegation
        governor.castVote(pid, depositTokenId, 1);
        assertEq(escrow.balanceOfNFT(depositTokenId), 0);
        assertEq(escrow.getPastVotes(address(owner), depositTokenId, block.timestamp - 1), TOKEN_1);
        assertProposalVotes(pid, 0, TOKEN_1 * 1, 0);
        assertEq(governor.hasVoted(pid, depositTokenId), true);

        // reward voting balance == TOKEN_1
        // governance voting balance == TOKEN_1 from delegateTokenId delegation
        governor.castVote(pid, delegateTokenId, 1);
        assertEq(escrow.balanceOfNFT(delegateTokenId), TOKEN_1);
        assertEq(escrow.getPastVotes(address(owner), delegateTokenId, block.timestamp - 1), TOKEN_1);
        assertProposalVotes(pid, 0, TOKEN_1 * 2, 0);
        assertEq(governor.hasVoted(pid, delegateTokenId), true);
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

        uint256 pid = createProposal();
        skip(1); // allow voting

        governor.castVote(pid, depositTokenId, 1);
        assertEq(escrow.balanceOfNFT(depositTokenId), 0);
        assertEq(escrow.getPastVotes(address(owner), depositTokenId, block.timestamp - 1), TOKEN_1 * 2);
        assertProposalVotes(pid, 0, TOKEN_1 * 2, 0);
        assertEq(governor.hasVoted(pid, depositTokenId), true);
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
        rewind(2 days); // trigger proposal snapshot exactly on epoch flip

        uint256 pid = createProposal();
        escrow.delegate(mTokenId, delegateTokenId); // delegate on snapshot boundary
        skip(1); // allow voting

        vm.expectRevert("GovernorVotingSimple: zero voting weight");
        governor.castVote(pid, depositTokenId, 1);
        assertEq(governor.hasVoted(pid, depositTokenId), false);

        governor.castVote(pid, delegateTokenId, 1);
        assertEq(escrow.balanceOfNFT(delegateTokenId), TOKEN_1);
        assertEq(escrow.getPastVotes(address(owner), delegateTokenId, block.timestamp - 1), TOKEN_1 * 3);
        assertProposalVotes(pid, 0, TOKEN_1 * 3, 0);
        assertEq(governor.hasVoted(pid, delegateTokenId), true);
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

        // seed locked rewards, then skip to next epoch
        VELO.approve(address(escrow), TOKEN_1);
        escrow.increaseAmount(mTokenId, TOKEN_1);

        skipToNextEpoch(0);
        rewind(2 days); // trigger proposal snapshot exactly on epoch flip

        uint256 pid = createProposal();
        skip(1); // allow voting

        escrow.delegate(mTokenId, delegateTokenId);

        // mveNFT not considered delegating, so locked depositor can vote
        governor.castVote(pid, depositTokenId, 1);
        assertEq(escrow.balanceOfNFT(depositTokenId), 0);
        assertEq(escrow.getPastVotes(address(owner), depositTokenId, block.timestamp - 1), 0);
        assertProposalVotes(pid, 0, TOKEN_1 * 2, 0);
        assertEq(governor.hasVoted(pid, depositTokenId), true);

        // mveNFT not considered delegating, so delegatee does not receive votes
        governor.castVote(pid, delegateTokenId, 1);
        assertEq(escrow.balanceOfNFT(delegateTokenId), TOKEN_1);
        assertEq(escrow.getPastVotes(address(owner), delegateTokenId, block.timestamp - 1), TOKEN_1);
        assertProposalVotes(pid, 0, TOKEN_1 * 3, 0);
        assertEq(governor.hasVoted(pid, delegateTokenId), true);
    }

    function testCastVoteWithLockedManagedVeNFTDelegatingToManaged() public {
        skip(1 hours);

        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        uint256 mTokenId2 = escrow.createManagedLockFor(address(owner));
        VELO.approve(address(escrow), type(uint256).max);
        uint256 depositTokenId = escrow.createLock(TOKEN_1, MAXTIME);
        voter.depositManaged(depositTokenId, mTokenId);

        escrow.delegate(mTokenId, mTokenId2);

        uint256 pid = createProposal();
        skip(1); // allow voting

        vm.expectRevert("GovernorVotingSimple: zero voting weight");
        governor.castVote(pid, depositTokenId, 1);
        assertEq(governor.hasVoted(pid, depositTokenId), false);

        vm.expectRevert("Governor: managed nft cannot vote");
        governor.castVote(pid, mTokenId, 1);
        assertEq(escrow.getPastVotes(address(owner), mTokenId, block.timestamp - 1), 0);
        assertEq(governor.hasVoted(pid, mTokenId), false);

        vm.expectRevert("Governor: managed nft cannot vote");
        governor.castVote(pid, mTokenId2, 1);
        assertEq(escrow.getPastVotes(address(owner), mTokenId2, block.timestamp - 1), TOKEN_1);
        assertEq(governor.hasVoted(pid, mTokenId2), false);
    }

    function testCastVoteWithLockedManagedVeNFTDelegatingToNormalToManaged() public {
        // delegation chain: managed => normal, normal => another managed
        skip(1 hours);

        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        uint256 mTokenId2 = escrow.createManagedLockFor(address(owner));
        VELO.approve(address(escrow), type(uint256).max);
        uint256 depositTokenId = escrow.createLock(TOKEN_1, MAXTIME);
        voter.depositManaged(depositTokenId, mTokenId);
        uint256 delegateTokenId = escrow.createLock(TOKEN_1 * 2, MAXTIME);
        escrow.lockPermanent(delegateTokenId);

        skip(1);
        escrow.delegate(mTokenId, delegateTokenId);
        skip(1);
        escrow.delegate(delegateTokenId, mTokenId2);
        skip(1);

        uint256 pid = createProposal();
        skip(1); // allow voting

        vm.expectRevert("GovernorVotingSimple: zero voting weight");
        governor.castVote(pid, depositTokenId, 1);
        assertEq(governor.hasVoted(pid, depositTokenId), false);

        vm.expectRevert("Governor: managed nft cannot vote");
        governor.castVote(pid, mTokenId, 1);
        assertEq(escrow.getPastVotes(address(owner), mTokenId, block.timestamp - 1), 0);
        assertEq(governor.hasVoted(pid, mTokenId), false);

        vm.expectRevert("Governor: managed nft cannot vote");
        governor.castVote(pid, mTokenId2, 1);
        assertEq(escrow.getPastVotes(address(owner), mTokenId2, block.timestamp - 1), TOKEN_1 * 2);
        assertEq(governor.hasVoted(pid, mTokenId2), false);

        governor.castVote(pid, delegateTokenId, 1);
        assertEq(escrow.balanceOfNFT(delegateTokenId), TOKEN_1 * 2);
        assertEq(escrow.getPastVotes(address(owner), delegateTokenId, block.timestamp - 1), TOKEN_1);
        assertProposalVotes(pid, 0, TOKEN_1, 0); // votes with delegated power from mveNFT
        assertEq(governor.hasVoted(pid, delegateTokenId), true);
    }

    function testCastVoteWithLockedManagedVeNFTDelegatingToNormalToSameManaged() public {
        // delegation chain: managed => normal, normal => same managed
        skip(1 hours);

        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        VELO.approve(address(escrow), type(uint256).max);
        uint256 depositTokenId = escrow.createLock(TOKEN_1, MAXTIME);
        voter.depositManaged(depositTokenId, mTokenId);
        uint256 delegateTokenId = escrow.createLock(TOKEN_1 * 2, MAXTIME);
        escrow.lockPermanent(delegateTokenId);

        skip(1);
        escrow.delegate(mTokenId, delegateTokenId);
        skip(1);
        escrow.delegate(delegateTokenId, mTokenId);
        skip(1);

        uint256 pid = createProposal();
        skip(1); // allow voting

        vm.expectRevert("GovernorVotingSimple: zero voting weight");
        governor.castVote(pid, depositTokenId, 1);
        assertEq(governor.hasVoted(pid, depositTokenId), false);

        vm.expectRevert("Governor: managed nft cannot vote");
        governor.castVote(pid, mTokenId, 1);
        assertEq(escrow.getPastVotes(address(owner), mTokenId, block.timestamp - 1), TOKEN_1 * 2);
        assertEq(governor.hasVoted(pid, mTokenId), false);

        governor.castVote(pid, delegateTokenId, 1);
        assertEq(escrow.balanceOfNFT(delegateTokenId), TOKEN_1 * 2);
        assertEq(escrow.getPastVotes(address(owner), delegateTokenId, block.timestamp - 1), TOKEN_1);
        assertProposalVotes(pid, 0, TOKEN_1, 0); // votes with delegated power from mveNFT
        assertEq(governor.hasVoted(pid, delegateTokenId), true);
    }

    function testCastVoteWithLockedManagedVeNFTDelegatingToNormalToLocked() public {
        // delegation chain: managed => normal, normal => locked
        skip(1 hours);

        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        VELO.approve(address(escrow), type(uint256).max);
        uint256 depositTokenId = escrow.createLock(TOKEN_1, MAXTIME);
        voter.depositManaged(depositTokenId, mTokenId);
        uint256 delegateTokenId = escrow.createLock(TOKEN_1 * 2, MAXTIME);
        escrow.lockPermanent(delegateTokenId);

        skip(1);
        escrow.delegate(mTokenId, delegateTokenId);
        skip(1);
        escrow.delegate(delegateTokenId, depositTokenId);
        skip(1);

        uint256 pid = createProposal();
        skip(1); // allow voting

        governor.castVote(pid, depositTokenId, 1);
        assertEq(escrow.balanceOfNFT(depositTokenId), 0);
        assertEq(escrow.getPastVotes(address(owner), depositTokenId, block.timestamp - 1), TOKEN_1 * 2);
        assertProposalVotes(pid, 0, TOKEN_1 * 2, 0); // votes with delegated power from delegateTokenId
        assertEq(governor.hasVoted(pid, depositTokenId), true);

        vm.expectRevert("Governor: managed nft cannot vote");
        governor.castVote(pid, mTokenId, 1);
        assertEq(escrow.getPastVotes(address(owner), mTokenId, block.timestamp - 1), 0);
        assertEq(governor.hasVoted(pid, mTokenId), false);

        governor.castVote(pid, delegateTokenId, 1);
        assertEq(escrow.balanceOfNFT(delegateTokenId), TOKEN_1 * 2);
        assertEq(escrow.getPastVotes(address(owner), delegateTokenId, block.timestamp - 1), TOKEN_1);
        assertProposalVotes(pid, 0, TOKEN_1 * 3, 0); // votes with delegated power from mveNFT
        assertEq(governor.hasVoted(pid, delegateTokenId), true);
    }

    function testCastVoteWithLockedManagedVeNFTDelegatingToNormalDepositingIntoManaged() public {
        skip(1 hours);

        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        uint256 mTokenId2 = escrow.createManagedLockFor(address(owner));
        VELO.approve(address(escrow), type(uint256).max);
        uint256 depositTokenId = escrow.createLock(TOKEN_1, MAXTIME);
        voter.depositManaged(depositTokenId, mTokenId);
        uint256 depositTokenId2 = escrow.createLock(TOKEN_1 * 2, MAXTIME);

        escrow.delegate(mTokenId, depositTokenId2);
        skip(1);
        voter.depositManaged(depositTokenId2, mTokenId2);

        uint256 pid = createProposal();
        skip(1); // allow voting

        vm.expectRevert("GovernorVotingSimple: zero voting weight");
        governor.castVote(pid, depositTokenId, 1);
        assertEq(governor.hasVoted(pid, depositTokenId), false);

        governor.castVote(pid, depositTokenId2, 1);
        assertEq(escrow.balanceOfNFT(depositTokenId2), 0);
        assertEq(escrow.getPastVotes(address(owner), depositTokenId2, block.timestamp - 1), TOKEN_1);
        assertProposalVotes(pid, 0, TOKEN_1 * 3, 0); // votes with delegated power from mveNFT + locked contribution to mTokenId2
        assertEq(governor.hasVoted(pid, depositTokenId2), true);

        vm.expectRevert("Governor: managed nft cannot vote");
        governor.castVote(pid, mTokenId, 1);
        assertEq(escrow.getPastVotes(address(owner), mTokenId, block.timestamp - 1), 0);
        assertEq(governor.hasVoted(pid, mTokenId), false);

        vm.expectRevert("Governor: managed nft cannot vote");
        governor.castVote(pid, mTokenId2, 1);
        assertEq(escrow.getPastVotes(address(owner), mTokenId2, block.timestamp - 1), TOKEN_1 * 2);
        assertEq(governor.hasVoted(pid, mTokenId2), false);
    }

    function testCastVoteWithLockedManagedVeNFTDelegatingToNormalDepositingIntoSameManaged() public {
        skip(1 hours);

        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        VELO.approve(address(escrow), type(uint256).max);
        uint256 depositTokenId = escrow.createLock(TOKEN_1, MAXTIME);
        voter.depositManaged(depositTokenId, mTokenId);
        uint256 depositTokenId2 = escrow.createLock(TOKEN_1 * 2, MAXTIME);

        escrow.delegate(mTokenId, depositTokenId2);
        skip(1);
        voter.depositManaged(depositTokenId2, mTokenId);

        uint256 pid = createProposal();
        skip(1); // allow voting

        vm.expectRevert("GovernorVotingSimple: zero voting weight");
        governor.castVote(pid, depositTokenId, 1);
        assertEq(governor.hasVoted(pid, depositTokenId), false);

        governor.castVote(pid, depositTokenId2, 1);
        assertEq(escrow.balanceOfNFT(depositTokenId2), 0);
        assertEq(escrow.getPastVotes(address(owner), depositTokenId2, block.timestamp - 1), TOKEN_1 * 3);
        assertProposalVotes(pid, 0, TOKEN_1 * 3, 0); // votes with delegated power from mveNFT
        assertEq(governor.hasVoted(pid, depositTokenId2), true);

        vm.expectRevert("Governor: managed nft cannot vote");
        governor.castVote(pid, mTokenId, 1);
        assertEq(escrow.getPastVotes(address(owner), mTokenId, block.timestamp - 1), 0);
        assertEq(governor.hasVoted(pid, mTokenId), false);
    }

    function testCannotSetCommentWeightingTooHigh() public {
        vm.prank(voter.governor());
        vm.expectRevert(VeloGovernor.CommentWeightingTooHigh.selector);
        governor.setCommentWeighting(1_000_000_000 + 1);
    }

    function testCannotSetCommentWeightingIfNotGovernor() public {
        vm.prank(address(owner2));
        vm.expectRevert(VeloGovernor.NotGovernor.selector);
        governor.setCommentWeighting(0);
    }

    function testSetCommentWeighting() public {
        // test as if being triggered by governor
        address[] memory targets = new address[](1);
        targets[0] = address(governor);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(governor.setCommentWeighting.selector, 0);
        string memory description = "Set Comment Weighting to 0.";

        uint256 pid = governor.propose(1, targets, values, calldatas, description);
        skipAndRoll(2 days + 1);

        governor.castVote(pid, 1, 1);
        skipAndRoll(1 weeks);

        vm.expectEmit(false, false, false, true, address(governor));
        emit SetCommentWeighting(0);
        governor.execute(targets, values, calldatas, keccak256(bytes(description)), address(owner));
        assertEq(governor.commentWeighting(), 0);
    }

    function testCannotCommentIfInsufficientVotingPower() public {
        uint256 pid = createProposal();

        // owner3 owns less than required
        vm.startPrank(address(owner3));
        VELO.approve(address(escrow), 1);
        uint256 tokenId = escrow.createLock(1, MAXTIME);

        vm.expectRevert("Governor: insufficient voting power");
        governor.comment(pid, tokenId, "test");
    }

    function testMinimumWeightIsAcceptable() public {
        uint256 pid = createProposal();

        vm.startPrank(address(owner3));
        VELO.approve(address(escrow), 1);
        escrow.increaseAmount(3, 1);
        vm.stopPrank();

        //total supply of locked tokens is now 100
        vm.prank(escrow.team());
        escrow.toggleSplit(address(this), true);
        (, uint256 tokenId) = escrow.split(1, 4e14 + 11e7);

        governor.comment(pid, tokenId, "test");
    }

    function testBelowMinimumAcceptableWeight() public {
        uint256 pid = createProposal();

        vm.startPrank(address(owner3));
        VELO.approve(address(escrow), 1);
        escrow.increaseAmount(3, 1);
        vm.stopPrank();

        //total supply of locked tokens is now 100
        vm.prank(escrow.team());
        escrow.toggleSplit(address(this), true);
        (, uint256 tokenId) = escrow.split(1, 4e14);

        vm.expectRevert("Governor: insufficient voting power");
        governor.comment(pid, tokenId, "test");
    }

    function testCannotCommentIfProposalNotActiveOrPending() public {
        uint256 pid = createProposal();

        // skipped 2 days when creating proposal
        // skip 5 days to end of period
        // skip 1 to exit active state
        skipAndRoll(5 days + 1);

        vm.expectRevert("Governor: not active or pending");
        governor.comment(pid, 1, "test");
    }

    function testComment() public {
        uint256 pid = createProposal();

        vm.expectEmit(true, true, true, true, address(governor));
        emit Comment(pid, address(this), 1, "test");
        governor.comment(pid, 1, "test");
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

    function assertProposalVotes(uint256 pid, uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) internal {
        (uint256 _againstVotes, uint256 _forVotes, uint256 _abstainVotes) = governor.proposalVotes(pid);
        assertApproxEqAbs(_againstVotes, againstVotes, 1);
        assertApproxEqAbs(_forVotes, forVotes, 1);
        assertApproxEqAbs(_abstainVotes, abstainVotes, 1);
    }
}

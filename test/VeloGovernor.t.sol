pragma solidity 0.8.13;

import "./BaseTest.sol";
import {IVetoGovernor} from "contracts/governance/IVetoGovernor.sol";

contract VeloGovernorTest is BaseTest {
    event ProposalVetoed(uint256 proposalId);

    function _setUp() public override {
        VELO.approve(address(escrow), 97 * TOKEN_1);
        escrow.createLock(97 * TOKEN_1, MAXTIME);

        // owner2 owns less than quorum, 3%
        vm.startPrank(address(owner2));
        VELO.approve(address(escrow), 3 * TOKEN_1);
        escrow.createLock(3 * TOKEN_1, MAXTIME);
        vm.stopPrank();
        skipAndRoll(1);
    }

    function testCannotSetVetoerWithZeroAddress() public {
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

        uint256 pid = governor.propose(targets, values, calldatas, description);

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

        uint256 pid = governor.propose(targets, values, calldatas, description);

        skipAndRoll(15 minutes + 1);

        governor.castVote(pid, 1);
        uint256 proposalStart = governor.proposalSnapshot(pid);
        assertGt(governor.getVotes(address(owner), proposalStart), governor.quorum(proposalStart)); // check quorum

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
        voter.createGauge(address(factory), address(votingRewardsFactory), address(gaugeFactory), address(1));
    }

    function testCannotSetTeamIfNotTeam() public {
        vm.prank(address(owner2));
        vm.expectRevert(VeloGovernor.NotTeam.selector);
        governor.setTeam(address(owner2));
    }

    function testSetTeam() public {
        governor.setTeam(address(owner2));

        assertEq(governor.team(), address(owner2));
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
        governor.propose(targets, values, calldatas, description);
    }

    function testCannotExecuteWithoutQuorum() public {
        address token = address(new MockERC20("TEST", "TEST", 18));
        assertFalse(voter.isWhitelistedToken(token));

        address[] memory targets = new address[](1);
        targets[0] = address(voter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(voter.whitelistToken.selector, token, true);
        string memory description = "Whitelist Token";

        // propose
        uint256 pid = governor.propose(targets, values, calldatas, description);

        skipAndRoll(15 minutes);
        vm.expectRevert("Governor: vote not currently active");
        governor.castVote(pid, 1);
        assertEq(uint256(governor.state(pid)), uint256(IVetoGovernor.ProposalState.Pending));

        skipAndRoll(1);
        // vote
        vm.prank(address(owner2));
        governor.castVote(pid, 1);

        skip(1 weeks);

        // execute
        vm.prank(address(owner));
        vm.expectRevert("Governor: proposal not successful");
        governor.execute(targets, values, calldatas, keccak256(bytes(description)), address(owner));
    }

    function testProposalHasQuorum() public {
        address token = address(new MockERC20("TEST", "TEST", 18));
        assertFalse(voter.isWhitelistedToken(token));

        address[] memory targets = new address[](1);
        targets[0] = address(voter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(voter.whitelistToken.selector, token, true);
        string memory description = "Whitelist Token";

        // propose
        uint256 pid = governor.propose(targets, values, calldatas, description);

        skipAndRoll(15 minutes);
        vm.expectRevert("Governor: vote not currently active");
        governor.castVote(pid, 1);
        assertEq(uint256(governor.state(pid)), uint256(IVetoGovernor.ProposalState.Pending));

        skipAndRoll(1);
        assertEq(uint256(governor.state(pid)), uint256(IVetoGovernor.ProposalState.Active));

        // vote
        governor.castVote(pid, 1);
        assertEq(uint256(governor.state(pid)), uint256(IVetoGovernor.ProposalState.Active));
        skipAndRoll(1 weeks);
        assertEq(uint256(governor.state(pid)), uint256(IVetoGovernor.ProposalState.Succeeded));

        // execute
        governor.execute(targets, values, calldatas, keccak256(bytes(description)), address(owner));
        assertEq(uint256(governor.state(pid)), uint256(IVetoGovernor.ProposalState.Executed));
        assertTrue(voter.isWhitelistedToken(token));
    }

    function testProposeWithUniqueProposals() public {
        address token = address(new MockERC20("TEST", "TEST", 18));
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
        uint256 pid = governor.propose(targets, values, calldatas, description); // frontrun

        vm.prank(address(owner2));
        uint256 pid2 = governor.propose(targets, values, calldatas, description); // will revert if pids not unique

        assertFalse(pid == pid2);
    }
}

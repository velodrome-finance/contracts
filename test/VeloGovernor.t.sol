pragma solidity 0.8.13;

import "./BaseTest.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

contract VeloGovernorTest is BaseTest {
    function _setUp() public override {
        VELO.approve(address(escrow), 97 * TOKEN_1);
        escrow.createLock(97 * TOKEN_1, MAXTIME);
        vm.roll(block.number + 1);

        // owner2 owns less than quorum, 3%
        vm.startPrank(address(owner2));
        VELO.approve(address(escrow), 3 * TOKEN_1);
        escrow.createLock(3 * TOKEN_1, MAXTIME);
        vm.roll(block.number + 1);
        vm.stopPrank();
    }

    function testGovernorCanCreateGaugesForAnyAddress() public {
        vm.prank(address(governor));
        voter.createGauge(address(factory), address(votingRewardsFactory), address(gaugeFactory), address(1));
    }

    function testCannotSetTeamIfNotTeam() public {
        vm.prank(address(owner2));
        vm.expectRevert("VeloGovernor: not team");
        governor.setTeam(address(owner2));
    }

    function testSetTeam() public {
        governor.setTeam(address(owner2));

        assertEq(governor.team(), address(owner2));
    }

    function testCannotSetProposalNumeratorAboveMaximum() public {
        vm.expectRevert("VeloGovernor: numerator too high");
        governor.setProposalNumerator(51);
    }

    function testCannotSetProposalNumeratorIfNotTeam() public {
        vm.prank(address(owner2));
        vm.expectRevert("VeloGovernor: not team");
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
        calldatas[0] = abi.encodeWithSelector(voter.whitelistToken.selector, address(USDC));
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
        calldatas[0] = abi.encodeWithSelector(voter.whitelistToken.selector, token);
        string memory description = "Whitelist Token";

        // propose
        vm.prank(address(owner));
        uint256 pid = governor.propose(targets, values, calldatas, description);

        vm.roll(block.number + 101); // voting delay period

        // vote
        vm.prank(address(owner2));
        governor.castVote(pid, 1);

        vm.roll(block.number + 302400); // voting period

        // execute
        vm.prank(address(owner));
        vm.expectRevert("Governor: proposal not successful");
        governor.execute(targets, values, calldatas, keccak256(bytes(description)));
    }

    function testProposalHasQuorum() public {
        address token = address(new MockERC20("TEST", "TEST", 18));
        assertFalse(voter.isWhitelistedToken(token));

        address[] memory targets = new address[](1);
        targets[0] = address(voter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(voter.whitelistToken.selector, token);
        string memory description = "Whitelist Token";

        // propose
        uint256 pid = governor.propose(targets, values, calldatas, description);

        vm.expectRevert("Governor: vote not currently active");
        governor.castVote(pid, 1);
        assertEq(uint256(governor.state(pid)), uint256(IGovernor.ProposalState.Pending));

        vm.roll(block.number + 101); // voting delay period
        assertEq(uint256(governor.state(pid)), uint256(IGovernor.ProposalState.Active));

        // vote
        governor.castVote(pid, 1);
        assertEq(uint256(governor.state(pid)), uint256(IGovernor.ProposalState.Active));
        vm.roll(block.number + 302400); // voting period
        assertEq(uint256(governor.state(pid)), uint256(IGovernor.ProposalState.Succeeded));

        // execute
        governor.execute(targets, values, calldatas, keccak256(bytes(description)));
        assertEq(uint256(governor.state(pid)), uint256(IGovernor.ProposalState.Executed));
        assertTrue(voter.isWhitelistedToken(token));
    }
}

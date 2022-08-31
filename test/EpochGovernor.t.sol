pragma solidity 0.8.13;

import "./BaseTest.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

contract EpochGovernorTest is BaseTest {
    using stdStorage for StdStorage;

    function _setUp() public override {
        VELO.approve(address(escrow), 2 * TOKEN_1);
        escrow.createLock(2 * TOKEN_1, MAXTIME);
        vm.roll(block.number + 1);

        vm.startPrank(address(owner2));
        VELO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME);
        vm.stopPrank();
        vm.roll(block.number + 1);

        vm.startPrank(address(owner3));
        VELO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME);
        vm.stopPrank();
        vm.roll(block.number + 1);

        vm.startPrank(address(owner4));
        VELO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME);
        vm.stopPrank();
        vm.roll(block.number + 1);

        stdstore.target(address(minter)).sig("tail()").checked_write(true);
    }

    function testCannotProposeWithOtherTarget() public {
        address[] memory targets = new address[](1);
        targets[0] = address(0);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(minter.nudge.selector);
        string memory description = "";

        vm.expectRevert("GovernorSimple: only minter allowed");
        epochGovernor.propose(targets, values, calldatas, description);
    }

    function testCannotProposeWithOtherCalldata() public {
        address[] memory targets = new address[](1);
        targets[0] = address(minter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(minter.update_period.selector);
        string memory description = "";

        vm.expectRevert("GovernorSimple: only nudge allowed");
        epochGovernor.propose(targets, values, calldatas, description);
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
        uint256 pid = epochGovernor.propose(targets, values, calldatas, description);

        vm.expectRevert("GovernorSimple: vote not currently active");
        epochGovernor.castVote(pid, 1);
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Pending));

        vm.roll(block.number + 101);
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Active));

        // vote
        epochGovernor.castVote(pid, 1); // for: 2
        vm.prank(address(owner2));
        epochGovernor.castVote(pid, 0); // against: 1
        vm.prank(address(owner3));
        epochGovernor.castVote(pid, 2); // abstain: 1
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Active));

        skipToNextEpoch(1);
        vm.roll(block.number + 302400); // voting period
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
        uint256 pid = epochGovernor.propose(targets, values, calldatas, description);

        vm.expectRevert("GovernorSimple: vote not currently active");
        epochGovernor.castVote(pid, 1);
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Pending));

        vm.roll(block.number + 101);
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Active));

        // vote
        epochGovernor.castVote(pid, 0); // against: 2
        vm.prank(address(owner2));
        epochGovernor.castVote(pid, 1); // for: 1
        vm.prank(address(owner3));
        epochGovernor.castVote(pid, 2); // abstain: 1
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Active));

        skipToNextEpoch(1);
        vm.roll(block.number + 302400); // voting period
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
        uint256 pid = epochGovernor.propose(targets, values, calldatas, description);

        vm.expectRevert("GovernorSimple: vote not currently active");
        epochGovernor.castVote(pid, 1);
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Pending));

        vm.roll(block.number + 101);
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Active));

        // vote
        vm.prank(address(owner2));
        epochGovernor.castVote(pid, 0); // for: 1
        vm.prank(address(owner3));
        epochGovernor.castVote(pid, 1); // against: 1
        vm.prank(address(owner4));
        epochGovernor.castVote(pid, 2); // abstain: 1
        // tie: should still expire
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Active));

        skipToNextEpoch(1);
        vm.roll(block.number + 302400); // voting period
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Expired));

        // execute
        epochGovernor.execute(targets, values, calldatas, keccak256(bytes(description)));
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Executed));
        assertEq(uint256(epochGovernor.result()), uint256(IGovernor.ProposalState.Expired));

        assertEq(minter.tailEmissionRate(), 30);
    }

    function testCannotProposeWithAnExistingProposal() public {
        assertEq(minter.tailEmissionRate(), 30);

        address[] memory targets = new address[](1);
        targets[0] = address(minter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(minter.nudge.selector);
        string memory description = "";

        // propose
        epochGovernor.propose(targets, values, calldatas, description);

        vm.prank(address(owner2));
        vm.expectRevert("GovernorSimple: proposal already exists");
        epochGovernor.propose(targets, values, calldatas, description);
    }
}

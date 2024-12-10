// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import {IGovernor} from "contracts/governance/IGovernor.sol";

import "test/BaseTest.sol";

contract CommentTest is BaseTest {
    uint256 pid;

    function _setUp() public override {
        VELO.approve(address(escrow), 2 * TOKEN_1);
        escrow.createLock(2 * TOKEN_1, MAXTIME); // 1
        vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        targets[0] = address(minter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(minter.nudge.selector);
        string memory description = "";

        pid = epochGovernor.propose(1, targets, values, calldatas, description);
    }

    function test_WhenProposalIsNotActiveOrPending() external {
        // It reverts with {GovernorUnexpectedProposalState}

        skipToNextEpoch(0);

        vm.expectPartialRevert(IGovernor.GovernorUnexpectedProposalState.selector);
        epochGovernor.comment(pid, 1, "test");
    }

    modifier whenProposalIsActiveOrPending() {
        _;
    }

    function test_WhenVoterHasInsufficientVotingPower() external whenProposalIsActiveOrPending {
        // It should revert with {GovernorInsufficientVotingPower}

        vm.startPrank(address(owner2));
        VELO.approve(address(escrow), 1);
        uint256 tokenId = escrow.createLock(1, MAXTIME);

        vm.expectPartialRevert(IGovernor.GovernorInsufficientVotingPower.selector);
        epochGovernor.comment(pid, tokenId, "test");
    }

    function test_WhenVoterHasEnoughVotingPower() external whenProposalIsActiveOrPending {
        // It should emit a {Comment} event

        vm.expectEmit(true, true, true, true, address(epochGovernor));
        emit IGovernor.Comment(pid, address(this), 1, "test");
        epochGovernor.comment(pid, 1, "test");
    }
}

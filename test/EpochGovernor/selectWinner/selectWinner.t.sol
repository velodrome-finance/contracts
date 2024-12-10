// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "test/BaseTest.sol";

contract SelectWinnerTest is BaseTest {
    address[] public targets;
    uint256[] public values;
    bytes[] public calldatas;
    string public description;
    uint256 pid;
    uint256 tokenId;
    uint256 tokenId2;
    uint256 tokenId3;

    function _setUp() public override {
        VELO.approve(address(escrow), 2 * TOKEN_1);
        tokenId = escrow.createLock(2 * TOKEN_1, MAXTIME); // 1
        vm.roll(block.number + 1);

        vm.startPrank(address(owner2));
        VELO.approve(address(escrow), TOKEN_1);
        tokenId2 = escrow.createLock(TOKEN_1, MAXTIME); // 2
        vm.stopPrank();
        vm.roll(block.number + 1);

        vm.startPrank(address(owner3));
        VELO.approve(address(escrow), TOKEN_1);
        tokenId3 = escrow.createLock(TOKEN_1, MAXTIME); // 3
        vm.stopPrank();
        vm.roll(block.number + 1);

        skipToNextEpoch(0);

        targets = new address[](1);
        targets[0] = address(minter);

        values = new uint256[](1);
        values[0] = 0;

        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(minter.nudge.selector);

        description = "";

        pid = epochGovernor.propose(1, targets, values, calldatas, description);

        skipAndRoll(1 hours + 3);
    }

    function test_WhenAgainstVotesAreTheHighest() external {
        // It should return Defeated

        epochGovernor.castVote(pid, tokenId, 0); // against 2
        vm.prank(address(owner2));
        epochGovernor.castVote(pid, tokenId2, 1); // for 1

        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Active));

        skipToNextEpoch(0);
        // rewind 30 minutes so we are in the blackout window
        rewind(30 minutes);
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Defeated));
    }

    function test_WhenForVotesAreTheHighest() external {
        // It should return Succeeded

        epochGovernor.castVote(pid, tokenId, 1); // for 2
        vm.prank(address(owner2));
        epochGovernor.castVote(pid, tokenId2, 0); // against 1

        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Active));

        skipToNextEpoch(0);
        // rewind 30 minutes so we are in the blackout window
        rewind(30 minutes);
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Succeeded));
    }

    function test_WhenAbstainVotesAreTheHighest() external {
        // It should return Expired
        epochGovernor.castVote(pid, tokenId, 2); // abstain 2
        vm.prank(address(owner2));
        epochGovernor.castVote(pid, tokenId2, 0); // against 1

        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Active));

        skipToNextEpoch(0);
        // rewind 30 minutes so we are in the blackout window
        rewind(30 minutes);
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Expired));
    }

    function test_WhenForAndAgainstVotesAreTheSame() external {
        // It should return Expired

        vm.prank(address(owner2));
        epochGovernor.castVote(pid, tokenId2, 1); // for 1
        vm.prank(address(owner3));
        epochGovernor.castVote(pid, tokenId3, 0); // against 1

        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Active));

        skipToNextEpoch(0);
        // rewind 30 minutes so we are in the blackout window
        rewind(30 minutes);
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Expired));
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "test/BaseTest.sol";

contract SetProposalWindowTest is BaseTest {
    function test_WhenCallerIsNotOwner() external {
        // It should revert with {OwnableUnauthorizedAccount}
        vm.prank(address(owner2));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(owner2)));
        epochGovernor.setProposalWindow({_proposalWindow: 1});
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(epochGovernor.owner());
        _;
    }

    function test_WhenProposalWindowIsGreaterThanOneDay() external whenCallerIsOwner {
        // It should revert with {InvalidProposalWindow}
        vm.expectRevert(IGovernorProposalWindow.InvalidProposalWindow.selector);
        epochGovernor.setProposalWindow({_proposalWindow: 25});
    }

    function test_WhenProposalWindowIsSmallerThanOrEqualToOneDay() external whenCallerIsOwner {
        // It should set the proposal window length
        // It should emit a {ProposalWindowSet} event
        vm.expectEmit(address(epochGovernor));
        emit IGovernorProposalWindow.ProposalWindowSet({oldProposalWindow: 24, newProposalWindow: 20});
        epochGovernor.setProposalWindow({_proposalWindow: 20});
        assertEq(epochGovernor.proposalWindow(), 20 hours);
    }
}

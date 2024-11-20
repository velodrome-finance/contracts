// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "test/BaseTest.sol";

contract SetCommentWeightingTest is BaseTest {
    function test_WhenCallerIsNotOwner() external {
        // It should revert with {OwnableUnauthorizedAccount}
        vm.prank(address(owner2));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(owner2)));
        epochGovernor.setCommentWeighting({_commentWeighting: 1});
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(epochGovernor.owner());
        _;
    }

    function test_WhenCommentWeightingIsHigherThanCommentDenominator() external whenCallerIsOwner {
        // It should revert with {CommentWeightingTooHigh}
        vm.expectRevert(IGovernorCommentable.CommentWeightingTooHigh.selector);
        epochGovernor.setCommentWeighting({_commentWeighting: 1_000_000_001});
    }

    function test_WhenCommentIsSmallerOrEqualToCommentDenominator() external whenCallerIsOwner {
        // It should set comment weighting
        // It should emit a {SetCommentWeighting} event
        vm.expectEmit(address(epochGovernor));
        emit IGovernorCommentable.SetCommentWeighting({_commentWeighting: 1_000_000_000});
        epochGovernor.setCommentWeighting({_commentWeighting: 1_000_000_000});
        assertEq(epochGovernor.commentWeighting(), 1_000_000_000);
    }
}

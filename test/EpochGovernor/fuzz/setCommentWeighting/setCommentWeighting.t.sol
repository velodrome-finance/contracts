// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "test/BaseTest.sol";

contract SetCommentWeightingFuzzTest is BaseTest {
    function testFuzz_WhenCallerIsNotOwner(address caller) external {
        // It should revert with {OwnableUnauthorizedAccount}
        vm.assume(caller != epochGovernor.owner());
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
        epochGovernor.setCommentWeighting({_commentWeighting: 1});
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(epochGovernor.owner());
        _;
    }

    function testFuzz_WhenCommentWeightingIsHigherThanCommentDenominator(uint256 commentWeighting)
        external
        whenCallerIsOwner
    {
        // It should revert with {CommentWeightingTooHigh}
        commentWeighting = bound(commentWeighting, 1_000_000_001, type(uint256).max);
        vm.expectRevert(IGovernorCommentable.CommentWeightingTooHigh.selector);
        epochGovernor.setCommentWeighting({_commentWeighting: commentWeighting});
    }

    function testFuzz_WhenCommentIsSmallerOrEqualToCommentDenominator(uint256 commentWeighting)
        external
        whenCallerIsOwner
    {
        // It should set comment weighting
        // It should emit a {CommentWeightingSet} event
        commentWeighting = bound(commentWeighting, 0, 1_000_000_000);
        vm.expectEmit(address(epochGovernor));
        emit IGovernorCommentable.CommentWeightingSet({_commentWeighting: commentWeighting});
        epochGovernor.setCommentWeighting({_commentWeighting: commentWeighting});
        assertEq(epochGovernor.commentWeighting(), commentWeighting);
    }
}

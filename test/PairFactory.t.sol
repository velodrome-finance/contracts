pragma solidity 0.8.13;

import "./BaseTest.sol";

contract PairFactoryTest is BaseTest {
    function testCannotSetNextManagerIfNotFeeManager() public {
        vm.prank(address(owner2));
        vm.expectRevert(IPairFactory.NotFeeManager.selector);
        factory.setFeeManager(address(owner));
    }

    function testFeeManagerCanSetNextManager() public {
        factory.setFeeManager(address(owner2));
        assertEq(factory.feeManager(), address(owner2));
    }

    function testNonPauserCannotSetNextPauser() public {
        vm.prank(address(owner2));
        vm.expectRevert(IPairFactory.NotPauser.selector);
        factory.setPauser(address(owner2));
    }

    function testPauserCanSetNextPauser() public {
        factory.setPauser(address(owner2));
        assertEq(factory.pauser(), address(owner2));
    }

    function testNonPauserCannotPause() public {
        vm.prank(address(owner2));
        vm.expectRevert(IPairFactory.NotPauser.selector);
        factory.setPauseState(true);
    }

    function testPauserCanPause() public {
        assertEq(factory.isPaused(), false);
        factory.setPauseState(true);
        assertEq(factory.isPaused(), true);
    }

    function testCannotChangeFeesIfNotFeeManager() public {
        vm.prank(address(owner2));
        vm.expectRevert(IPairFactory.NotFeeManager.selector);
        factory.setFee(true, 2);

        vm.prank(address(owner2));
        vm.expectRevert(IPairFactory.NotFeeManager.selector);
        factory.setCustomFee(address(pair), 5);
    }

    function testCannotSetFeeAboveMax() public {
        vm.expectRevert(IPairFactory.FeeTooHigh.selector);
        factory.setFee(true, 101); // 101 bps = 1.01%

        vm.expectRevert(IPairFactory.FeeTooHigh.selector);
        factory.setCustomFee(address(pair), 101); // 101 bps = 1.01%
    }

    function testCannotSetZeroFee() public {
        vm.expectRevert(IPairFactory.ZeroFee.selector);
        factory.setFee(true, 0);
    }

    function testFeeManagerCanSetMaxValues() public {
        // Can set to 420 to indicate 0% fee
        factory.setCustomFee(address(pair), 420);
        assertEq(factory.getFee(address(pair), true), 0);
        // Can set to 1%
        factory.setCustomFee(address(pair), 100);
        assertEq(factory.getFee(address(pair), true), 100);
        assertEq(factory.getFee(address(pair), false), 100);
        // does not impact regular fee of other pair
        assertEq(factory.getFee(address(pair2), true), 1);
        assertEq(factory.getFee(address(pair2), false), 1);

        factory.setFee(true, 100);
        assertEq(factory.getFee(address(pair2), true), 100);
        assertEq(factory.getFee(address(pair2), false), 1);
        factory.setFee(false, 100);
        assertEq(factory.getFee(address(pair2), false), 100);

        factory.setCustomFee(address(pair), 420);
        assertEq(factory.getFee(address(pair), true), 0);
    }

    function testSetCustomFee() external {
        // differentiate fees for stable / non-stable
        factory.setFee(true, 42);
        factory.setFee(false, 69);

        // pair does not have custom fees- return fee correlating to boolean
        assertEq(factory.getFee(address(pair), true), 42);
        assertEq(factory.getFee(address(pair), false), 69);

        factory.setCustomFee(address(pair), 11);
        assertEq(factory.getFee(address(pair), true), 11);
        assertEq(factory.getFee(address(pair), false), 11);

        // setting custom fee back to 0 gives default stable / non-stable fees
        factory.setCustomFee(address(pair), 0);
        assertEq(factory.getFee(address(pair), true), 42);
        assertEq(factory.getFee(address(pair), false), 69);

        // setting custom fee to 420 indicates there is 0% fee for the pair
        factory.setCustomFee(address(pair), 420);
        assertEq(factory.getFee(address(pair), true), 0);
        assertEq(factory.getFee(address(pair), false), 0);
    }

    function testCannotSetCustomFeeForNonExistentPair() external {
        vm.expectRevert(IPairFactory.InvalidPair.selector);
        factory.setCustomFee(address(1), 5);
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {SafeCastLibrary} from "contracts/libraries/SafeCastLibrary.sol";

import "forge-std/Test.sol";

contract SafeCastLibraryTest is Test {
    using SafeCastLibrary for uint256;
    using SafeCastLibrary for int128;

    function testToInt128WithoutOverflow(uint256 _value) public {
        vm.assume(_value <= uint128(type(int128).max));
        assertEq(_value.toInt128(), int128(uint128(_value)));
    }

    function testToInt128WithOverflow(uint256 _value) public {
        vm.assume(_value > uint128(type(int128).max));
        vm.expectRevert(SafeCastLibrary.SafeCastOverflow.selector);
        _value.toInt128();
    }

    function testToUint256WithoutUnderflow(int128 _value) public {
        vm.assume(_value >= 0);
        assertEq(_value.toUint256(), uint256(int256(_value)));
    }

    function testToUint256WithUnderflow(int128 _value) public {
        vm.assume(_value < 0);
        vm.expectRevert(SafeCastLibrary.SafeCastUnderflow.selector);
        _value.toUint256();
    }
}

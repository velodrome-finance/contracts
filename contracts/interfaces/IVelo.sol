// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IVelo is IERC20 {
    error NotMinter();
    error NotOwner();
    error NotMinterOrSinkManager();
    error SinkManagerAlreadySet();

    function mint(address, uint256) external returns (bool);

    function minter() external returns (address);
}

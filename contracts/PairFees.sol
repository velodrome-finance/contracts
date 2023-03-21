// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Contract used as 1:1 pair relationship to split out fees. Ensures curve does not need to be modified for LP shares.
contract PairFees {
    using SafeERC20 for IERC20;
    address internal immutable pair; // The pair it is bonded to
    address internal immutable token0; // token0 of pair, saved localy and statically for gas optimization
    address internal immutable token1; // Token1 of pair, saved localy and statically for gas optimization

    error NotPair();

    constructor(address _token0, address _token1) {
        pair = msg.sender;
        token0 = _token0;
        token1 = _token1;
    }

    /// @notice Allow the pair to transfer fees to users
    function claimFeesFor(
        address _recipient,
        uint256 _amount0,
        uint256 _amount1
    ) external {
        if (msg.sender != pair) revert NotPair();
        if (_amount0 > 0) IERC20(token0).safeTransfer(_recipient, _amount0);
        if (_amount1 > 0) IERC20(token1).safeTransfer(_recipient, _amount1);
    }
}

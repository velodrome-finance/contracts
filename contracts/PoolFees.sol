// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title PoolFees
/// @notice Contract used as 1:1 pool relationship to split out fees.
/// @notice Ensures curve does not need to be modified for LP shares.
contract PoolFees {
    using SafeERC20 for IERC20;
    address internal immutable pool; // The pool it is bonded to
    address internal immutable token0; // token0 of pool, saved localy and statically for gas optimization
    address internal immutable token1; // Token1 of pool, saved localy and statically for gas optimization

    error NotPool();

    constructor(address _token0, address _token1) {
        pool = msg.sender;
        token0 = _token0;
        token1 = _token1;
    }

    /// @notice Allow the pool to transfer fees to users
    function claimFeesFor(address _recipient, uint256 _amount0, uint256 _amount1) external {
        if (msg.sender != pool) revert NotPool();
        if (_amount0 > 0) IERC20(token0).safeTransfer(_recipient, _amount0);
        if (_amount1 > 0) IERC20(token1).safeTransfer(_recipient, _amount1);
    }
}

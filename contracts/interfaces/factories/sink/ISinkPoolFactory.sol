// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISinkPoolFactory {
    event PoolCreated(address indexed token0, address indexed token1, bool indexed stable, address pool, uint256);

    /// @notice Return the sink pool created by this factory
    function pool() external view returns (address);

    /// @notice Always returns false. The SinkPool is not functional.
    /// @dev Called by voter when creating a gauge. Kept for backwards compatibility.
    /// @param .
    function isPair(address) external view returns (bool);

    /// @notice Always returns false. The SinkPool is not functional.
    /// @dev Called by voter when creating a gauge.
    /// @param .
    function isPool(address) external view returns (bool);
}

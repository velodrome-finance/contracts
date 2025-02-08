// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISinkGaugeFactory {
    /// @notice Get the address of the SinkGauge
    function gauge() external view returns (address);

    /// @notice Returns the address of the SinkGauge
    /// @dev Dummy function to return the address of the SinkGauge
    /// and keep compatibility with functions called by voter when creating gauges.
    function createGauge(address, address, address, address, bool) external view returns (address);
}

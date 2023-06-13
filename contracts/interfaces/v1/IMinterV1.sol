// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IMinterV1 {
    /// @notice Calculates rebases according to the formula
    ///         weekly * (ve.totalSupply / velo.totalSupply) ^ 3 / 2
    ///         Note that ve.totalSupply is the locked ve supply
    ///         velo.totalSupply is the total ve supply minted
    /// @return _growth Rebases
    function calculate_growth(uint256 _minted) external view returns (uint256 _growth);

    /// @notice Processes emissions and rebases. Callable once per epoch (1 week).
    /// @return _period Start of current epoch.
    function update_period() external returns (uint256 _period);
}

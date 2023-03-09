pragma solidity 0.8.13;

interface IMinter {
    event Mint(address indexed _sender, uint256 _weekly, uint256 _circulating_supply, bool _tail);

    event Nudge(uint256 _period, uint256 _oldRate, uint256 _newRate);

    /// @notice Allows epoch governor to modify the tail emission rate by at most 1 basis point
    ///         per epoch to a maximum of 100 basis points or to a minimum of 1 basis point.
    ///         Note: the very first nudge proposal must take place the week prior
    ///         to the tail emission schedule starting.
    /// @dev Throws if not epoch governor.
    ///      Throws if not currently in tail emission schedule.
    ///      Throws if already nudged this epoch.
    ///      Throws if nudging above maximum rate.
    ///      Throws if nudging below minimum rate.
    ///      This contract is coupled to EpochGovernor as it requires three option simple majority voting.
    function nudge() external;

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

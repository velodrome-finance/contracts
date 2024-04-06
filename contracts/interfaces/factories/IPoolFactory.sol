// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPoolFactory {
    event SetFeeManager(address indexed feeManager);
    event SetPauser(address indexed pauser);
    event SetPauseState(bool indexed state);
    event SetPoolAdmin(address indexed poolAdmin);
    event PoolCreated(address indexed token0, address indexed token1, bool indexed stable, address pool, uint256);
    event SetCustomFee(address indexed pool, uint256 fee);

    error FeeInvalid();
    error FeeTooHigh();
    error InvalidPool();
    error NotFeeManager();
    error NotPauser();
    error NotPoolAdmin();
    error PoolAlreadyExists();
    error SameAddress();
    error ZeroFee();
    error ZeroAddress();

    /// @notice Returns all pools created by this factory
    /// @return Array of pool addresses
    function allPools() external view returns (address[] memory);

    /// @notice returns the number of pools created from this factory
    function allPoolsLength() external view returns (uint256);

    /// @notice Is a valid pool created by this factory.
    /// @param .
    function isPool(address pool) external view returns (bool);

    /// @notice Return address of pool created by this factory
    /// @param tokenA .
    /// @param tokenB .
    /// @param stable True if stable, false if volatile
    function getPool(address tokenA, address tokenB, bool stable) external view returns (address);

    /// @notice Support for v3-style pools which wraps around getPool(tokenA,tokenB,stable)
    /// @dev fee is converted to stable boolean.
    /// @param tokenA .
    /// @param tokenB .
    /// @param fee  1 if stable, 0 if volatile, else returns address(0)
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address);

    /// @notice Set pool administrator
    /// @dev Allowed to change the name and symbol of any pool created by this factory
    /// @param _poolAdmin Address of the pool administrator
    function setPoolAdmin(address _poolAdmin) external;

    /// @notice Set the pauser for the factory contract
    /// @dev The pauser can pause swaps on pools associated with the factory. Liquidity will always be withdrawable.
    /// @dev Must be called by the pauser
    /// @param _pauser Address of the pauser
    function setPauser(address _pauser) external;

    /// @notice Pause or unpause swaps on pools associated with the factory
    /// @param _state True to pause, false to unpause
    function setPauseState(bool _state) external;

    /// @notice Set the fee manager for the factory contract
    /// @dev The fee manager can set fees on pools associated with the factory.
    /// @dev Must be called by the fee manager
    /// @param _feeManager Address of the fee manager
    function setFeeManager(address _feeManager) external;

    /// @notice Set default fee for stable and volatile pools.
    /// @dev Throws if higher than maximum fee.
    ///      Throws if fee is zero.
    /// @param _stable Stable or volatile pool.
    /// @param _fee .
    function setFee(bool _stable, uint256 _fee) external;

    /// @notice Set overriding fee for a pool from the default
    /// @dev A custom fee of zero means the default fee will be used.
    function setCustomFee(address _pool, uint256 _fee) external;

    /// @notice Returns fee for a pool, as custom fees are possible.
    function getFee(address _pool, bool _stable) external view returns (uint256);

    /// @notice Create a pool given two tokens and if they're stable/volatile
    /// @dev token order does not matter
    /// @param tokenA .
    /// @param tokenB .
    /// @param stable .
    function createPool(address tokenA, address tokenB, bool stable) external returns (address pool);

    /// @notice Support for v3-style pools which wraps around createPool(tokena,tokenB,stable)
    /// @dev fee is converted to stable boolean
    /// @dev token order does not matter
    /// @param tokenA .
    /// @param tokenB .
    /// @param fee 1 if stable, 0 if volatile, else revert
    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool);

    /// @notice The pool implementation used to create pools
    /// @return Address of pool implementation
    function implementation() external view returns (address);

    /// @notice Whether the pools associated with the factory are paused or not.
    /// @dev Pause only pauses swaps, liquidity will always be withdrawable.
    function isPaused() external view returns (bool);

    /// @notice The address of the pauser, can pause swaps on pools associated with factory.
    /// @return Address of the pauser
    function pauser() external view returns (address);

    /// @notice The default fee for all stable pools
    /// @return Default stable fee
    function stableFee() external view returns (uint256);

    /// @notice The default fee for all volatile pools
    /// @return Default volatile fee
    function volatileFee() external view returns (uint256);

    /// @notice Maximum possible fee for default stable or volatile fee
    /// @return 3%
    function MAX_FEE() external view returns (uint256);

    /// @dev Override to indicate there is custom 0% fee - as a 0 value in the
    /// @dev customFee mapping indicates that no custom fee rate has been set
    function ZERO_FEE_INDICATOR() external view returns (uint256);

    /// @notice Address of the fee manager, can set fees on pools associated with factory.
    /// @notice This overrides the default fee for that pool.
    /// @return Address of the fee manager
    function feeManager() external view returns (address);

    /// @notice Address of the pool administrator, can change the name and symbol of pools created by factory.
    /// @return Address of the pool administrator
    function poolAdmin() external view returns (address);

    /// @notice Returns the custom fee for a pool
    /// @param _pool Address of the pool
    /// @return Custom fee for the pool
    function customFee(address _pool) external view returns (uint256);
}

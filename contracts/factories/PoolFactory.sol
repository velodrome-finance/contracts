// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import {IPoolFactory} from "../interfaces/factories/IPoolFactory.sol";
import {IPool} from "../interfaces/IPool.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

contract PoolFactory is IPoolFactory {
    /// @inheritdoc IPoolFactory
    address public immutable implementation;

    /// @inheritdoc IPoolFactory
    bool public isPaused;
    /// @inheritdoc IPoolFactory
    address public pauser;

    /// @inheritdoc IPoolFactory
    uint256 public stableFee;
    /// @inheritdoc IPoolFactory
    uint256 public volatileFee;
    /// @inheritdoc IPoolFactory
    uint256 public constant MAX_FEE = 300; // 3%
    /// @inheritdoc IPoolFactory
    uint256 public constant ZERO_FEE_INDICATOR = 420;
    /// @inheritdoc IPoolFactory
    address public feeManager;
    /// @inheritdoc IPoolFactory
    address public poolAdmin;

    mapping(address => mapping(address => mapping(bool => address))) private _getPool;
    address[] internal _allPools;
    /// @dev simplified check if its a pool, given that `stable` flag might not be available in peripherals
    mapping(address => bool) private _isPool;
    /// @inheritdoc IPoolFactory
    mapping(address => uint256) public customFee; // override for custom fees

    constructor(address _implementation) {
        implementation = _implementation;
        poolAdmin = msg.sender;
        pauser = msg.sender;
        feeManager = msg.sender;
        isPaused = false;
        stableFee = 5; // 0.05%
        volatileFee = 30; // 0.3%
    }

    /// @inheritdoc IPoolFactory
    function allPools() external view returns (address[] memory) {
        return _allPools;
    }

    /// @inheritdoc IPoolFactory
    function allPoolsLength() external view returns (uint256) {
        return _allPools.length;
    }

    /// @inheritdoc IPoolFactory
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address) {
        return fee > 1 ? address(0) : fee == 1 ? _getPool[tokenA][tokenB][true] : _getPool[tokenA][tokenB][false];
    }

    /// @inheritdoc IPoolFactory
    function getPool(address tokenA, address tokenB, bool stable) external view returns (address) {
        return _getPool[tokenA][tokenB][stable];
    }

    /// @inheritdoc IPoolFactory
    function isPool(address pool) external view returns (bool) {
        return _isPool[pool];
    }

    /// @inheritdoc IPoolFactory
    function setPoolAdmin(address _poolAdmin) external {
        if (msg.sender != poolAdmin) revert NotPoolAdmin();
        if (_poolAdmin == address(0)) revert ZeroAddress();
        poolAdmin = _poolAdmin;
        emit SetPoolAdmin(_poolAdmin);
    }

    /// @inheritdoc IPoolFactory
    function setPauser(address _pauser) external {
        if (msg.sender != pauser) revert NotPauser();
        if (_pauser == address(0)) revert ZeroAddress();
        pauser = _pauser;
        emit SetPauser(_pauser);
    }

    /// @inheritdoc IPoolFactory
    function setPauseState(bool _state) external {
        if (msg.sender != pauser) revert NotPauser();
        isPaused = _state;
        emit SetPauseState(_state);
    }

    /// @inheritdoc IPoolFactory
    function setFeeManager(address _feeManager) external {
        if (msg.sender != feeManager) revert NotFeeManager();
        if (_feeManager == address(0)) revert ZeroAddress();
        feeManager = _feeManager;
        emit SetFeeManager(_feeManager);
    }

    /// @inheritdoc IPoolFactory
    function setFee(bool _stable, uint256 _fee) external {
        if (msg.sender != feeManager) revert NotFeeManager();
        if (_fee > MAX_FEE) revert FeeTooHigh();
        if (_fee == 0) revert ZeroFee();
        if (_stable) {
            stableFee = _fee;
        } else {
            volatileFee = _fee;
        }
    }

    /// @inheritdoc IPoolFactory
    function setCustomFee(address pool, uint256 fee) external {
        if (msg.sender != feeManager) revert NotFeeManager();
        if (fee > MAX_FEE && fee != ZERO_FEE_INDICATOR) revert FeeTooHigh();
        if (!_isPool[pool]) revert InvalidPool();

        customFee[pool] = fee;
        emit SetCustomFee(pool, fee);
    }

    /// @inheritdoc IPoolFactory
    function getFee(address pool, bool _stable) public view returns (uint256) {
        uint256 fee = customFee[pool];
        return fee == ZERO_FEE_INDICATOR ? 0 : fee != 0 ? fee : _stable ? stableFee : volatileFee;
    }

    /// @inheritdoc IPoolFactory
    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool) {
        if (fee > 1) revert FeeInvalid();
        bool stable = fee == 1;
        return createPool(tokenA, tokenB, stable);
    }

    /// @inheritdoc IPoolFactory
    function createPool(address tokenA, address tokenB, bool stable) public returns (address pool) {
        if (tokenA == tokenB) revert SameAddress();
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (token0 == address(0)) revert ZeroAddress();
        if (_getPool[token0][token1][stable] != address(0)) revert PoolAlreadyExists();
        bytes32 salt = keccak256(abi.encodePacked(token0, token1, stable)); // salt includes stable as well, 3 parameters
        pool = Clones.cloneDeterministic(implementation, salt);
        IPool(pool).initialize(token0, token1, stable);
        _getPool[token0][token1][stable] = pool;
        _getPool[token1][token0][stable] = pool; // populate mapping in the reverse direction
        _allPools.push(pool);
        _isPool[pool] = true;
        emit PoolCreated(token0, token1, stable, pool, _allPools.length);
    }
}

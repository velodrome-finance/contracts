// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IPairFactory} from "../interfaces/IPairFactory.sol";
import {IPair} from "../interfaces/IPair.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

contract PairFactory is IPairFactory {
    address public immutable implementation;

    bool public isPaused;
    address public pauser;

    uint256 public stableFee;
    uint256 public volatileFee;
    uint256 public constant MAX_FEE = 100; // 1%
    // Override to indicate there is custom 0% fee - as a 0 value in the customFee mapping indicates
    // that no custom fee rate has been set
    uint256 public constant ZERO_FEE_INDICATOR = 420;
    address public feeManager;

    /// @dev used to change the name/symbol of the pair by calling emergencyCouncil
    address public voter;

    /// @dev used to enable Router conversion of v1 => v2 VEL0
    address public velo;
    address public veloV2;
    address public sinkConverter;

    mapping(address => mapping(address => mapping(bool => address))) public getPair;
    address[] public allPairs;
    mapping(address => bool) public isPair; // simplified check if its a pair, given that `stable` flag might not be available in peripherals
    mapping(address => uint256) public customFee; // override for custom fees

    address internal _temp0;
    address internal _temp1;
    bool internal _temp;

    constructor(address _implementation) {
        implementation = _implementation;
        voter = msg.sender;
        pauser = msg.sender;
        feeManager = msg.sender;
        sinkConverter = msg.sender;
        isPaused = false;
        stableFee = 2; // 0.02%
        volatileFee = 2;
    }

    /// @inheritdoc IPairFactory
    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    /// @inheritdoc IPairFactory
    function setVoter(address _voter) external {
        if (msg.sender != voter) revert NotVoter();
        voter = _voter;
        emit SetVoter(_voter);
    }

    /// @inheritdoc IPairFactory
    function setSinkConverter(
        address _sinkConverter,
        address _velo,
        address _veloV2
    ) external {
        if (msg.sender != sinkConverter) revert NotSinkConverter();
        sinkConverter = _sinkConverter;
        velo = _velo;
        veloV2 = _veloV2;

        // Follow logic of createPair() - except add getPair values for both volatile
        // and stable so there is no way to create an additional velo => veloV2 pair
        (address token0, address token1) = _velo < _veloV2 ? (_velo, _veloV2) : (_veloV2, _velo);
        getPair[token0][token1][true] = sinkConverter;
        getPair[token1][token0][true] = sinkConverter;
        getPair[token0][token1][false] = sinkConverter;
        getPair[token1][token0][false] = sinkConverter;
        allPairs.push(sinkConverter);
        isPair[sinkConverter] = true;

        // emit two events - for both the "stable" and "volatile" pair being created
        emit PairCreated(token0, token1, true, sinkConverter, allPairs.length);
        emit PairCreated(token0, token1, false, sinkConverter, allPairs.length);
    }

    function setPauser(address _pauser) external {
        if (msg.sender != pauser) revert NotPauser();
        if (_pauser == address(0)) revert ZeroAddress();
        pauser = _pauser;
        emit SetPauser(_pauser);
    }

    function setPauseState(bool _state) external {
        if (msg.sender != pauser) revert NotPauser();
        isPaused = _state;
        emit SetPauseState(_state);
    }

    function setFeeManager(address _feeManager) external {
        if (msg.sender != feeManager) revert NotFeeManager();
        if (_feeManager == address(0)) revert ZeroAddress();
        feeManager = _feeManager;
        emit SetFeeManager(_feeManager);
    }

    /// @inheritdoc IPairFactory
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

    /// @inheritdoc IPairFactory
    function setCustomFee(address pair, uint256 fee) external {
        if (msg.sender != feeManager) revert NotFeeManager();
        if (fee > MAX_FEE && fee != ZERO_FEE_INDICATOR) revert FeeTooHigh();
        if (!isPair[pair]) revert InvalidPair();

        customFee[pair] = fee;
        emit SetCustomFee(pair, fee);
    }

    /// @inheritdoc IPairFactory
    function getFee(address pair, bool _stable) public view returns (uint256) {
        uint256 fee = customFee[pair];
        return fee == ZERO_FEE_INDICATOR ? 0 : fee != 0 ? fee : _stable ? stableFee : volatileFee;
    }

    function createPair(
        address tokenA,
        address tokenB,
        bool stable
    ) external returns (address pair) {
        if (tokenA == tokenB) revert SameAddress();
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (token0 == address(0)) revert ZeroAddress();
        if (getPair[token0][token1][stable] != address(0)) revert PairAlreadyExists();
        bytes32 salt = keccak256(abi.encodePacked(token0, token1, stable)); // salt includes stable as well, 3 parameters
        pair = Clones.cloneDeterministic(implementation, salt);
        IPair(pair).initialize(token0, token1, stable);
        getPair[token0][token1][stable] = pair;
        getPair[token1][token0][stable] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        isPair[pair] = true;
        emit PairCreated(token0, token1, stable, pair, allPairs.length);
    }
}

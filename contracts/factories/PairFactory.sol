// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {IPairFactory} from "../interfaces/IPairFactory.sol";
import {Pair} from "../Pair.sol";

contract PairFactory is IPairFactory {
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

    constructor() {
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
        require(msg.sender == voter);
        voter = _voter;
    }

    /// @inheritdoc IPairFactory
    function setSinkConverter(
        address _sinkConverter,
        address _velo,
        address _veloV2
    ) external {
        require(msg.sender == sinkConverter);
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
        require(msg.sender == pauser, "PairFactory: not pauser");
        pauser = _pauser;
    }

    function setPauseState(bool _state) external {
        require(msg.sender == pauser, "PairFactory: not pauser");
        isPaused = _state;
    }

    function setFeeManager(address _feeManager) external {
        require(msg.sender == feeManager, "PairFactory: not fee manager");
        feeManager = _feeManager;
    }

    /// @inheritdoc IPairFactory
    function setFee(bool _stable, uint256 _fee) external {
        require(msg.sender == feeManager, "PairFactory: not fee manager");
        require(_fee <= MAX_FEE, "PairFactory: fee too high");
        require(_fee != 0, "PairFactory: fee must be non-zero");
        if (_stable) {
            stableFee = _fee;
        } else {
            volatileFee = _fee;
        }
    }

    /// @inheritdoc IPairFactory
    function setCustomFee(address pair, uint256 fee) external {
        require(msg.sender == feeManager, "PairFactory: not fee manager");
        require(fee <= MAX_FEE || fee == ZERO_FEE_INDICATOR, "PairFactory: fee too high");
        require(isPair[pair], "PairFactory: not a pair");

        customFee[pair] = fee;
        emit SetCustomFee(pair, fee);
    }

    function getFee(address pair, bool _stable) public view returns (uint256) {
        uint256 fee = customFee[pair];
        return fee == ZERO_FEE_INDICATOR ? 0 : fee != 0 ? fee : _stable ? stableFee : volatileFee;
    }

    /// @inheritdoc IPairFactory
    function pairCodeHash() external pure returns (bytes32) {
        return keccak256(type(Pair).creationCode);
    }

    function getInitializable()
        external
        view
        returns (
            address,
            address,
            bool
        )
    {
        return (_temp0, _temp1, _temp);
    }

    function createPair(
        address tokenA,
        address tokenB,
        bool stable
    ) external returns (address pair) {
        require(tokenA != tokenB, "PairFactory: identical addresses");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "PairFactory: zero address");
        require(getPair[token0][token1][stable] == address(0), "PairFactory: pair already exists");
        bytes32 salt = keccak256(abi.encodePacked(token0, token1, stable)); // salt includes stable as well, 3 parameters
        (_temp0, _temp1, _temp) = (token0, token1, stable);
        pair = address(new Pair{salt: salt}());
        getPair[token0][token1][stable] = pair;
        getPair[token1][token0][stable] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        isPair[pair] = true;
        emit PairCreated(token0, token1, stable, pair, allPairs.length);
    }
}

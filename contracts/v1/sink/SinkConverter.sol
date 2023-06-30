// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IVelo} from "../../interfaces/IVelo.sol";
import {IPool} from "../../interfaces/IPool.sol";
import {ISinkManager} from "../../interfaces/ISinkManager.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @notice Fake pool used which enables routers to swap v1 VELO to v2 VELO
/// @dev Used in voter v2
/// @author velodrome.finance, @pegahcarter
contract SinkConverter is ERC20, IPool, ReentrancyGuard {
    error SinkConverter_NotImplemented();

    ISinkManager public immutable sinkManager;
    IVelo public immutable velo;
    IVelo public immutable veloV2;

    /// @inheritdoc IPool
    address public immutable token0;
    /// @inheritdoc IPool
    address public immutable token1;

    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );

    constructor(address _sinkManager) ERC20("Velodrome V1/V2 Converter", "sCONV-VELOv1/VELOv2") {
        // Set state
        sinkManager = ISinkManager(_sinkManager);
        veloV2 = sinkManager.veloV2();
        velo = sinkManager.velo();

        // approve transfers of the sinkManager for sending VELO v1
        velo.approve(_sinkManager, type(uint256).max);

        // sort tokens just like in PoolFactory - needed as Router._swap()
        // sorts the token route
        (token0, token1) = address(velo) < address(veloV2)
            ? (address(velo), address(veloV2))
            : (address(veloV2), address(velo));
    }

    /// @dev override as there is a 1:1 conversion rate of VELO v1 => v2
    function getAmountOut(uint256 amountIn, address tokenIn) external view returns (uint256) {
        if (tokenIn != address(velo)) return 0;
        return amountIn;
    }

    /// @dev low-level function which works like Pool.swap() which assumes
    ///         that the tokenIn has already been transferred to the pool
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata /* data */) external nonReentrant {
        // Only allow amount out of veloV2
        uint256 amountOut = token0 == address(veloV2) ? amount0Out : amount1Out;
        require(amountOut > 0, "SinkConverter: nothing to convert");

        // convert velo v1 to v2
        sinkManager.convertVELO(amountOut);

        // transfer velo v2 to recipient
        veloV2.transfer(to, amountOut);

        // Swap event to follow convention of Swap() from Pool.sol
        uint256 amount0In;
        uint256 amount1In;
        // Note; amountIn will only ever be velo v1 token
        (amount0In, amount1In) = token0 == address(veloV2) ? (uint256(0), amountOut) : (amountOut, uint256(0));
        emit Swap(_msgSender(), to, amount0In, amount1In, amount0Out, amount1Out);
    }

    // --------------------------------------------------------------
    // IPool overrides for interface support
    // --------------------------------------------------------------

    function mint(address) external pure returns (uint256) {
        revert SinkConverter_NotImplemented();
    }

    function burn(address) external pure returns (uint256, uint256) {
        revert SinkConverter_NotImplemented();
    }

    function claimable0(address) external pure returns (uint256) {
        return 0;
    }

    function claimable1(address) external pure returns (uint256) {
        return 0;
    }

    function claimFees() external pure returns (uint256, uint256) {
        revert SinkConverter_NotImplemented();
    }

    function currentCumulativePrices() external pure returns (uint256, uint256, uint256) {
        revert SinkConverter_NotImplemented();
    }

    function getReserves() external pure returns (uint256, uint256, uint256) {
        revert SinkConverter_NotImplemented();
    }

    function initialize(address, address, bool) external pure {
        revert SinkConverter_NotImplemented();
    }

    function metadata()
        external
        view
        returns (uint256 dec0, uint256 dec1, uint256 r0, uint256 r1, bool st, address t0, address t1)
    {
        return (18, 18, 0, 0, true, token0, token1);
    }

    function quote(address, uint256, uint256) external pure returns (uint256) {
        revert SinkConverter_NotImplemented();
    }

    function reserve0() external pure returns (uint256) {
        return 0;
    }

    function reserve1() external pure returns (uint256) {
        return 0;
    }

    function prices(address, uint256, uint256) external pure returns (uint256[] memory) {
        revert SinkConverter_NotImplemented();
    }

    function sample(address, uint256, uint256, uint256) external pure returns (uint256[] memory) {
        revert SinkConverter_NotImplemented();
    }

    function skim(address) external pure {
        revert SinkConverter_NotImplemented();
    }

    function stable() external pure returns (bool) {
        return true;
    }

    function sync() external pure {
        revert SinkConverter_NotImplemented();
    }

    function tokens() external view returns (address, address) {
        return (token0, token1);
    }

    function blockTimestampLast() external pure returns (uint256) {
        revert SinkConverter_NotImplemented();
    }

    function factory() external pure returns (address) {
        revert SinkConverter_NotImplemented();
    }

    function lastObservation() external pure returns (Observation memory) {
        revert SinkConverter_NotImplemented();
    }

    function observationLength() external pure returns (uint256) {
        revert SinkConverter_NotImplemented();
    }

    function periodSize() external pure returns (uint256) {
        revert SinkConverter_NotImplemented();
    }

    function poolFees() external pure returns (address) {
        revert SinkConverter_NotImplemented();
    }

    function reserve0CumulativeLast() external pure returns (uint256) {
        revert SinkConverter_NotImplemented();
    }

    function reserve1CumulativeLast() external pure returns (uint256) {
        revert SinkConverter_NotImplemented();
    }

    function setName(string calldata) external pure {
        revert SinkConverter_NotImplemented();
    }

    function setSymbol(string calldata) external pure {
        revert SinkConverter_NotImplemented();
    }

    function supplyIndex0(address) external pure returns (uint256) {
        revert SinkConverter_NotImplemented();
    }

    function supplyIndex1(address) external pure returns (uint256) {
        revert SinkConverter_NotImplemented();
    }

    function index0() external pure returns (uint256) {
        revert SinkConverter_NotImplemented();
    }

    function index1() external pure returns (uint256) {
        revert SinkConverter_NotImplemented();
    }
}

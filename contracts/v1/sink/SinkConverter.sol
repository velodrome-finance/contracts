// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IVelo} from "../../interfaces/IVelo.sol";
import {ISinkManager} from "../../interfaces/ISinkManager.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @notice Fake pair used which enables routers to swap v1 VELO to v2 VELO
/// @dev Used in voter v2
/// @author Carter Carlson (@pegahcarter)
contract SinkConverter is ERC20, ReentrancyGuard {
    ISinkManager public immutable sinkManager;
    IVelo public immutable velo;
    IVelo public immutable veloV2;

    /// @dev public variables found in Pair.sol
    address public immutable token0;
    address public immutable token1;

    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );

    constructor(address _sinkManager) ERC20("SinkConverter", "CONV") {
        // Set state
        sinkManager = ISinkManager(_sinkManager);
        veloV2 = sinkManager.veloV2();
        velo = sinkManager.velo();

        // approve transfers of the sinkManager for sending VELO v1
        velo.approve(_sinkManager, type(uint256).max);

        // sort tokens just like in PairFactory - needed as Router._swap()
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

    /// @dev low-level function which works like Pair.swap() which assumes
    ///         that the tokenIn has already been transferred to the pair
    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata /* data */
    ) external nonReentrant {
        // Only allow amount out of veloV2
        uint256 amountOut = token0 == address(veloV2) ? amount0Out : amount1Out;
        require(amountOut > 0, "SinkConverter: nothing to convert");

        // convert velo v1 to v2
        sinkManager.convertVELO(amountOut);

        // transfer velo v2 to recipient
        veloV2.transfer(to, amountOut);

        // Swap event to follow convention of Swap() from Pair.sol
        uint256 amount0In;
        uint256 amount1In;
        // Note; amountIn will only ever be velo v1 token
        (amount0In, amount1In) = token0 == address(veloV2) ? (uint256(0), amountOut) : (amountOut, uint256(0));
        emit Swap(_msgSender(), amount0In, amount1In, amount0Out, amount1Out, to);
    }
}

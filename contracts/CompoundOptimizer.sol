// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IRouter} from "./interfaces/IRouter.sol";
import {IPoolFactory} from "./interfaces/factories/IPoolFactory.sol";
import {IVotingEscrow} from "./interfaces/IVotingEscrow.sol";
import {ICompoundOptimizer} from "./interfaces/ICompoundOptimizer.sol";
import {IVoter} from "./interfaces/IVoter.sol";
import {IPool} from "./interfaces/IPool.sol";

/// @notice Storage for all AutoCompounders to call to calculate optimal amountOut into VELO
/// @author velodrome.finance, @pegahcarter
contract CompoundOptimizer is ICompoundOptimizer {
    address public immutable weth;
    address public immutable usdc;
    address public immutable op;
    address public immutable velo;
    address public immutable factory;
    IRouter public immutable router;

    constructor(address _usdc, address _weth, address _op, address _velo, address _factory, address _router) {
        weth = _weth;
        usdc = _usdc;
        op = _op;
        velo = _velo;
        factory = _factory;
        router = IRouter(_router);
    }

    function _getRoutesTokenToVelo(address token) internal view returns (IRouter.Route[2][5] memory routesTokenToVelo) {
        // caching
        address _usdc = usdc;
        address _weth = weth;
        address _op = op;
        address _velo = velo;
        address _factory = factory;

        // Create routes for routesTokenToVelo
        // from <> USDC <> VELO

        // from <stable v2> USDC <> VELO
        routesTokenToVelo[0][0] = IRouter.Route(token, _usdc, true, _factory);
        // from <volatile v2> USDC <> VELO
        routesTokenToVelo[1][0] = IRouter.Route(token, _usdc, false, _factory);

        routesTokenToVelo[0][1] = IRouter.Route(_usdc, _velo, false, _factory);
        routesTokenToVelo[1][1] = IRouter.Route(_usdc, _velo, false, _factory);

        // from <> WETH <> VELO

        // from <stable v2> WETH <> VELO
        routesTokenToVelo[2][0] = IRouter.Route(token, _weth, true, _factory);
        // from <volatile v2> WETH <> VELO
        routesTokenToVelo[3][0] = IRouter.Route(token, _weth, false, _factory);

        routesTokenToVelo[2][1] = IRouter.Route(_weth, _velo, false, _factory);
        routesTokenToVelo[3][1] = IRouter.Route(_weth, _velo, false, _factory);

        // from <> OP <> VELO

        // from <volatile v2> OP <> VELO
        routesTokenToVelo[4][0] = IRouter.Route(token, _op, false, _factory);
        routesTokenToVelo[4][1] = IRouter.Route(_op, _velo, false, _factory);
    }

    /// @inheritdoc ICompoundOptimizer
    function getOptimalTokenToVeloRoute(
        address token,
        uint256 amountIn
    ) external view returns (IRouter.Route[] memory) {
        // Get best route from multi-route paths
        uint256 index;
        uint256 optimalAmountOut;
        IRouter.Route[] memory routes = new IRouter.Route[](2);
        uint256[] memory amountsOut;

        IRouter.Route[2][5] memory routesTokenToVelo = _getRoutesTokenToVelo(token);
        // loop through multi-route paths
        for (uint256 i = 0; i < 5; i++) {
            routes[0] = routesTokenToVelo[i][0];
            routes[1] = routesTokenToVelo[i][1];

            // Go to next route if a trading pool does not exist
            if (IPoolFactory(routes[0].factory).getPair(routes[0].from, routes[0].to, routes[0].stable) == address(0))
                continue;

            amountsOut = router.getAmountsOut(amountIn, routes);
            // amountOut is in the third index - 0 is amountIn and 1 is the first route output
            uint256 amountOut = amountsOut[2];
            if (amountOut > optimalAmountOut) {
                // store the index and amount of the optimal amount out
                optimalAmountOut = amountOut;
                index = i;
            }
        }
        // use the optimal route determined from the loop
        routes[0] = routesTokenToVelo[index][0];
        routes[1] = routesTokenToVelo[index][1];

        // Get amountOut from a direct route to VELO
        IRouter.Route[] memory route = new IRouter.Route[](1);
        route[0] = IRouter.Route(token, velo, false, factory);
        amountsOut = router.getAmountsOut(amountIn, route);
        uint256 singleSwapAmountOut = amountsOut[1];

        // compare output and return the best result
        return singleSwapAmountOut > optimalAmountOut ? route : routes;
    }

    /// @inheritdoc ICompoundOptimizer
    function getOptimalAmountOutMin(
        IRouter.Route[] calldata routes,
        uint256 amountIn,
        uint256 points,
        uint256 slippage
    ) external view returns (uint256 amountOutMin) {
        if (points < 2) revert NotEnoughPoints();
        uint256 length = routes.length;

        for (uint256 i = 0; i < length; i++) {
            IRouter.Route memory route = routes[i];
            if (route.factory == address(0)) route.factory = factory;
            address pool = IPoolFactory(route.factory).getPair(route.from, route.to, route.stable);
            // Return 0 if the pool does not exist
            if (pool == address(0)) return 0;
            uint256 amountOut = IPool(pool).quote(route.from, amountIn, points);
            // Overwrite amountIn assuming we're using the TWAP for the next route swap
            amountIn = amountOut;
        }

        // At this point, amountIn is actually amountOut as we finished the loop
        amountOutMin = (amountIn * (10_000 - slippage)) / 10_000;
    }
}

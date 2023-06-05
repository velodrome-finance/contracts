pragma solidity ^0.8.0;

import {IRouter} from "./IRouter.sol";

interface ICompoundOptimizer {
    error NoRouteFound();

    /// @notice Given a token and the amountIn, return the route to return the most VELO given 10 potential routes
    ///             of v1 and v2 Velodrome pools
    /// @dev The potential routes are stored in the CompoundOptimizer
    /// @param token    Address of token to swap from
    /// @param amountIn Amount of token to swap
    /// @return IRouter.Route[] Array of optimal route path to swap
    function getOptimalTokenToVeloRoute(address token, uint256 amountIn) external view returns (IRouter.Route[] memory);
}

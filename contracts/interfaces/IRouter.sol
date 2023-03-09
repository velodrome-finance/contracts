pragma solidity 0.8.13;

interface IRouter {
    struct Route {
        address from;
        address to;
        bool stable;
        address factory;
    }

    /// @dev Struct containing information necessary to zap in and out of pools
    /// @param tokenA .
    /// @param tokenB .
    /// @param stable  Stable or volatile pool
    /// @param factory factory of pool
    /// @param amountOutMinA Minimum amount expected from swap leg of zap via routesA
    /// @param amountOutMinB Minimum amount expected from swap leg of zap via routesB
    /// @param amountAMin Minimum amount of tokenA expected from liquidity leg of zap
    /// @param amountBMin Minimum amount of tokenB expected from liquidity leg of zap
    struct Zap {
        address tokenA;
        address tokenB;
        bool stable;
        address factory;
        uint256 amountOutMinA;
        uint256 amountOutMinB;
        uint256 amountAMin;
        uint256 amountBMin;
    }

    function pairFor(
        address tokenA,
        address tokenB,
        bool stable,
        address factory
    ) external view returns (address pair);

    function getReserves(
        address tokenA,
        address tokenB,
        bool stable,
        address factory
    ) external view returns (uint256 reserveA, uint256 reserveB);

    function getAmountsOut(uint256 amountIn, Route[] memory routes) external view returns (uint256[] memory amounts);

    // **** ADD LIQUIDITY ****

    function quoteAddLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        address _factory,
        uint256 amountADesired,
        uint256 amountBDesired
    )
        external
        view
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        );

    function quoteRemoveLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        address _factory,
        uint256 liquidity
    ) external view returns (uint256 amountA, uint256 amountB);

    function addLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        );

    function addLiquidityETH(
        address token,
        bool stable,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        );

    // **** REMOVE LIQUIDITY ****

    function removeLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    function removeLiquidityETH(
        address token,
        bool stable,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountToken, uint256 amountETH);

    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        bool stable,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountETH);

    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        bool stable,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountETH);

    // **** SWAP ****

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactETHForTokens(
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function UNSAFE_swapExactTokensForTokens(
        uint256[] memory amounts,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory);

    // **** SWAP (supporting fee-on-transfer tokens) ****
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external;

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external payable;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external;

    /// @notice Zap a token A into a pool (B, C). (A can be equal to B or C).
    ///         Slippage is required for the initial swap.
    ///         Additional slippage may be required when adding liquidity as the
    ///         price of the token may have changed.
    /// @param tokenIn Token you are zapping in from (i.e. input token).
    /// @param amountInA Amount of input token you wish to send down routesA
    /// @param amountInB Amount of input token you wish to send down routesB
    /// @param zapInPair Contains zap struct information. See Zap struct.
    /// @param routesA Route used to convert input token to tokenA
    /// @param routesB Route used to convert input token to tokenB
    /// @param to Address you wish to mint liquidity to.
    /// @param stake Auto-stake liquidity in corresponding gauge.
    /// @return liquidity Amount of LP tokens created from zapping in.
    function zapIn(
        address tokenIn,
        uint256 amountInA,
        uint256 amountInB,
        Zap calldata zapInPair,
        Route[] calldata routesA,
        Route[] calldata routesB,
        address to,
        bool stake
    ) external payable returns (uint256 liquidity);

    /// @notice Zap out a pool (B, C) into A.
    ///         Slippage is required for the removal of liquidity.
    ///         Additional slippage may be required on the swap as the
    ///         price of the token may have changed.
    /// @param tokenOut Token you are zapping out to (i.e. output token).
    /// @param liquidity Amount of liquidity you wish to remove.
    /// @param zapOutPair Contains zap struct information. See Zap struct.
    /// @param routesA Route used to convert tokenA into output token.
    /// @param routesB Route used to convert tokenB into output token.
    function zapOut(
        address tokenOut,
        uint256 liquidity,
        Zap calldata zapOutPair,
        Route[] calldata routesA,
        Route[] calldata routesB
    ) external;

    /// @notice Used to generate params required for zapping in.
    ///         Zap in => remove liquidity then swap.
    ///         Apply slippage to expected swap values to account for changes in reserves in between.
    /// @dev Output token refers to the token you want to zap in from.
    /// @param tokenA .
    /// @param tokenB .
    /// @param stable .
    /// @param _factory .
    /// @param amountInA Amount of input token you wish to send down routesA
    /// @param amountInB Amount of input token you wish to send down routesB
    /// @param routesA Route used to convert input token to tokenA
    /// @param routesB Route used to convert input token to tokenB
    /// @return amountOutMinA Minimum output expected from swapping input token to tokenA.
    /// @return amountOutMinB Minimum output expected from swapping input token to tokenB.
    /// @return amountAMin Minimum amount of tokenA expected from depositing liquidity.
    /// @return amountBMin Minimum amount of tokenB expected from depositing liquidity.
    function generateZapInParams(
        address tokenA,
        address tokenB,
        bool stable,
        address _factory,
        uint256 amountInA,
        uint256 amountInB,
        Route[] calldata routesA,
        Route[] calldata routesB
    )
        external
        view
        returns (
            uint256 amountOutMinA,
            uint256 amountOutMinB,
            uint256 amountAMin,
            uint256 amountBMin
        );

    /// @notice Used to generate params required for zapping out.
    ///         Zap out => swap then add liquidity.
    ///         Apply slippage to expected liquidity values to account for changes in reserves in between.
    /// @dev Output token refers to the token you want to zap out of.
    /// @param tokenA .
    /// @param tokenB .
    /// @param stable .
    /// @param _factory .
    /// @param liquidity Amount of liquidity being zapped out of into a given output token.
    /// @param routesA Route used to convert tokenA into output token.
    /// @param routesB Route used to convert tokenB into output token.
    /// @return amountOutMinA Minimum output expected from swapping tokenA into output token.
    /// @return amountOutMinB Minimum output expected from swapping tokenB into output token.
    /// @return amountAMin Minimum amount of tokenA expected from withdrawing liquidity.
    /// @return amountBMin Minimum amount of tokenB expected from withdrawing liquidity.
    function generateZapOutParams(
        address tokenA,
        address tokenB,
        bool stable,
        address _factory,
        uint256 liquidity,
        Route[] calldata routesA,
        Route[] calldata routesB
    )
        external
        view
        returns (
            uint256 amountOutMinA,
            uint256 amountOutMinB,
            uint256 amountAMin,
            uint256 amountBMin
        );

    /// @notice Used by zapper to determine appropriate ratio of A to B to deposit liquidity. Assumes stable pair.
    /// @dev Returns stable liquidity ratio of B to (A + B).
    ///      E.g. if ratio is 0.4, it means there is more of A than there is of B.
    ///      Therefore you should deposit more of token A than B.
    /// @param tokenA tokenA of stable pair you are zapping into.
    /// @param tokenB tokenB of stable pair you are zapping into.
    /// @param factory Factory that created stable pair.
    /// @return ratio Ratio of token0 to token1 required to deposit into zap.
    function quoteStableLiquidityRatio(
        address tokenA,
        address tokenB,
        address factory
    ) external view returns (uint256 ratio);
}

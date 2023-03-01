// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IPair} from "./interfaces/IPair.sol";
import {IPairFactory} from "./interfaces/IPairFactory.sol";
import {IRouter} from "./interfaces/IRouter.sol";
import {IVoter} from "./interfaces/IVoter.sol";
import {IGauge} from "./interfaces/IGauge.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";

/// @notice Router allows routes through any pairs created by any factory adhering to univ2 interface.
/// @dev Zapping and swapping support both v1 and v2. Adding liquidity supports v2 only.
contract Router is IRouter, Context {
    using SafeERC20 for IERC20;

    /// @dev v2 default pair factory
    address public immutable defaultFactory;
    address public immutable voter;
    IWETH public immutable weth;
    bytes32 public immutable pairCodeHash;
    uint256 internal constant MINIMUM_LIQUIDITY = 10**3;
    /// @dev Represents Ether. Used by zapper to determine whether to return assets as ETH/WETH.
    address public constant ETHER = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "Router: expired");
        _;
    }

    constructor(
        address _factory,
        address _voter,
        address _weth
    ) {
        defaultFactory = _factory;
        voter = _voter;
        pairCodeHash = IPairFactory(_factory).pairCodeHash();
        weth = IWETH(_weth);
    }

    receive() external payable {
        require(msg.sender == address(weth), "Router: only accepts ETH from WETH contract");
    }

    function sortTokens(address tokenA, address tokenB) public pure returns (address token0, address token1) {
        require(tokenA != tokenB, "Router: identical addresses");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "Router: zero address");
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(
        address tokenA,
        address tokenB,
        bool stable,
        address _factory
    ) public view returns (address pair) {
        address factory = _factory == address(0) ? defaultFactory : _factory;
        bytes32 pairCodeHash_ = factory == defaultFactory ? pairCodeHash : IPairFactory(factory).pairCodeHash();

        // override for SinkConverter
        if (factory == defaultFactory) {
            if ((tokenA == IPairFactory(defaultFactory).velo()) && (tokenB == IPairFactory(defaultFactory).veloV2())) {
                return IPairFactory(defaultFactory).sinkConverter();
            }
        }

        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            factory,
                            keccak256(abi.encodePacked(token0, token1, stable)),
                            pairCodeHash_ // init code hash
                        )
                    )
                )
            )
        );
    }

    /// @dev given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    /// @dev this only accounts for volatile pairs and may return insufficient liquidity for stable pairs - hence
    /// why in adding/removing liquidity there is a skim() to ensure no imbalance in liquidity provided
    function quoteLiquidity(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) internal pure returns (uint256 amountB) {
        require(amountA > 0, "Router: insufficient amount");
        require(reserveA > 0 && reserveB > 0, "Router: insufficient liquidity");
        amountB = (amountA * reserveB) / reserveA;
    }

    // fetches and sorts the reserves for a pair
    function getReserves(
        address tokenA,
        address tokenB,
        bool stable,
        address _factory
    ) public view returns (uint256 reserveA, uint256 reserveB) {
        (address token0, ) = sortTokens(tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1, ) = IPair(pairFor(tokenA, tokenB, stable, _factory)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    // performs chained getAmountOut calculations on any number of pairs
    function getAmountsOut(uint256 amountIn, Route[] memory routes) public view returns (uint256[] memory amounts) {
        require(routes.length >= 1, "Router: INVALID_PATH");
        amounts = new uint256[](routes.length + 1);
        amounts[0] = amountIn;
        for (uint256 i = 0; i < routes.length; i++) {
            address factory = routes[i].factory == address(0) ? defaultFactory : routes[i].factory; // default to v2
            address pair = pairFor(routes[i].from, routes[i].to, routes[i].stable, factory);
            if (IPairFactory(factory).isPair(pair)) {
                amounts[i + 1] = IPair(pair).getAmountOut(amounts[i], routes[i].from);
            }
        }
    }

    /// @dev v2 only
    function quoteAddLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        address _factory,
        uint256 amountADesired,
        uint256 amountBDesired
    )
        public
        view
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        )
    {
        // create the pair if it doesn't exist yet
        address _pair = IPairFactory(_factory).getPair(tokenA, tokenB, stable);
        (uint256 reserveA, uint256 reserveB) = (0, 0);
        uint256 _totalSupply = 0;
        if (_pair != address(0)) {
            _totalSupply = IERC20(_pair).totalSupply();
            (reserveA, reserveB) = getReserves(tokenA, tokenB, stable, _factory);
        }
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
            liquidity = Math.sqrt(amountA * amountB) - MINIMUM_LIQUIDITY;
        } else {
            uint256 amountBOptimal = quoteLiquidity(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                (amountA, amountB) = (amountADesired, amountBOptimal);
                liquidity = Math.min((amountA * _totalSupply) / reserveA, (amountB * _totalSupply) / reserveB);
            } else {
                uint256 amountAOptimal = quoteLiquidity(amountBDesired, reserveB, reserveA);
                (amountA, amountB) = (amountAOptimal, amountBDesired);
                liquidity = Math.min((amountA * _totalSupply) / reserveA, (amountB * _totalSupply) / reserveB);
            }
        }
    }

    function quoteRemoveLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        address _factory,
        uint256 liquidity
    ) public view returns (uint256 amountA, uint256 amountB) {
        // create the pair if it doesn't exist yet
        address _pair = IPairFactory(_factory).getPair(tokenA, tokenB, stable);

        if (_pair == address(0)) {
            return (0, 0);
        }

        (uint256 reserveA, uint256 reserveB) = getReserves(tokenA, tokenB, stable, _factory);
        uint256 _totalSupply = IERC20(_pair).totalSupply();

        amountA = (liquidity * reserveA) / _totalSupply; // using balances ensures pro-rata distribution
        amountB = (liquidity * reserveB) / _totalSupply; // using balances ensures pro-rata distribution
    }

    function _addLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal returns (uint256 amountA, uint256 amountB) {
        require(amountADesired >= amountAMin);
        require(amountBDesired >= amountBMin);
        // create the pair if it doesn't exist yet
        address _pair = IPairFactory(defaultFactory).getPair(tokenA, tokenB, stable);
        if (_pair == address(0)) {
            _pair = IPairFactory(defaultFactory).createPair(tokenA, tokenB, stable);
        }
        (uint256 reserveA, uint256 reserveB) = getReserves(tokenA, tokenB, stable, defaultFactory);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = quoteLiquidity(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, "Router: insufficient B amount");
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = quoteLiquidity(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, "Router: insufficient A amount");
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

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
        public
        ensure(deadline)
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        )
    {
        (amountA, amountB) = _addLiquidity(
            tokenA,
            tokenB,
            stable,
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin
        );
        address pair = pairFor(tokenA, tokenB, stable, defaultFactory);
        _safeTransferFrom(tokenA, _msgSender(), pair, amountA);
        _safeTransferFrom(tokenB, _msgSender(), pair, amountB);
        liquidity = IPair(pair).mint(to);
        IPair(pair).skim(to);
    }

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
        ensure(deadline)
        returns (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        )
    {
        (amountToken, amountETH) = _addLiquidity(
            token,
            address(weth),
            stable,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountETHMin
        );
        address pair = pairFor(token, address(weth), stable, defaultFactory);
        _safeTransferFrom(token, _msgSender(), pair, amountToken);
        weth.deposit{value: amountETH}();
        assert(weth.transfer(pair, amountETH));
        liquidity = IPair(pair).mint(to);
        // refund dust eth, if any
        if (msg.value > amountETH) _safeTransferETH(_msgSender(), msg.value - amountETH);
    }

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
    ) public ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = pairFor(tokenA, tokenB, stable, defaultFactory);
        require(IERC20(pair).transferFrom(_msgSender(), pair, liquidity)); // send liquidity to pair
        (uint256 amount0, uint256 amount1) = IPair(pair).burn(to);
        IPair(pair).skim(to);
        (address token0, ) = sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, "Router: insufficient A amount");
        require(amountB >= amountBMin, "Router: insufficient B amount");
    }

    function removeLiquidityETH(
        address token,
        bool stable,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) public ensure(deadline) returns (uint256 amountToken, uint256 amountETH) {
        (amountToken, amountETH) = removeLiquidity(
            token,
            address(weth),
            stable,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        _safeTransfer(token, to, amountToken);
        weth.withdraw(amountETH);
        _safeTransferETH(to, amountETH);
    }

    // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens) ****
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        bool stable,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) public ensure(deadline) returns (uint256 amountETH) {
        (, amountETH) = removeLiquidity(
            token,
            address(weth),
            stable,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        _safeTransfer(token, to, IERC20(token).balanceOf(address(this)));
        weth.withdraw(amountETH);
        _safeTransferETH(to, amountETH);
    }

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
    ) external returns (uint256 amountETH) {
        address pair = pairFor(token, address(weth), stable, address(0));
        uint256 value = approveMax ? type(uint256).max : liquidity;
        IERC20Permit(pair).permit(_msgSender(), address(this), value, deadline, v, r, s);
        amountETH = removeLiquidityETHSupportingFeeOnTransferTokens(
            token,
            stable,
            liquidity,
            amountTokenMin,
            amountETHMin,
            to,
            deadline
        );
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(
        uint256[] memory amounts,
        Route[] memory routes,
        address _to
    ) internal virtual {
        for (uint256 i = 0; i < routes.length; i++) {
            (address token0, ) = sortTokens(routes[i].from, routes[i].to);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = routes[i].from == token0
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));
            address to = i < routes.length - 1
                ? pairFor(routes[i + 1].from, routes[i + 1].to, routes[i + 1].stable, routes[i + 1].factory)
                : _to;
            IPair(pairFor(routes[i].from, routes[i].to, routes[i].stable, routes[i].factory)).swap(
                amount0Out,
                amount1Out,
                to,
                new bytes(0)
            );
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        amounts = getAmountsOut(amountIn, routes);
        require(amounts[amounts.length - 1] >= amountOutMin, "Router: insufficient output amount");
        _safeTransferFrom(
            routes[0].from,
            _msgSender(),
            pairFor(routes[0].from, routes[0].to, routes[0].stable, routes[0].factory),
            amounts[0]
        );
        _swap(amounts, routes, to);
    }

    function swapExactETHForTokens(
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external payable ensure(deadline) returns (uint256[] memory amounts) {
        require(routes[0].from == address(weth), "Router: INVALID_PATH");
        amounts = getAmountsOut(msg.value, routes);
        require(amounts[amounts.length - 1] >= amountOutMin, "Router: insufficient output amount");
        weth.deposit{value: amounts[0]}();
        assert(weth.transfer(pairFor(routes[0].from, routes[0].to, routes[0].stable, routes[0].factory), amounts[0]));
        _swap(amounts, routes, to);
    }

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        require(routes[routes.length - 1].to == address(weth), "Router: invalid path");
        amounts = getAmountsOut(amountIn, routes);
        require(amounts[amounts.length - 1] >= amountOutMin, "Router: insufficient output amount");
        _safeTransferFrom(
            routes[0].from,
            _msgSender(),
            pairFor(routes[0].from, routes[0].to, routes[0].stable, routes[0].factory),
            amounts[0]
        );
        _swap(amounts, routes, address(this));
        weth.withdraw(amounts[amounts.length - 1]);
        _safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function UNSAFE_swapExactTokensForTokens(
        uint256[] memory amounts,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory) {
        _safeTransferFrom(
            routes[0].from,
            _msgSender(),
            pairFor(routes[0].from, routes[0].to, routes[0].stable, routes[0].factory),
            amounts[0]
        );
        _swap(amounts, routes, to);
        return amounts;
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(Route[] memory routes, address _to) internal virtual {
        for (uint256 i; i < routes.length; i++) {
            (address token0, ) = sortTokens(routes[i].from, routes[i].to);
            address pair = pairFor(routes[i].from, routes[i].to, routes[i].stable, routes[i].factory);
            uint256 amountInput;
            uint256 amountOutput;
            {
                // stack too deep
                (uint256 reserve0, uint256 reserve1) = getReserves(
                    routes[i].from,
                    routes[i].to,
                    routes[i].stable,
                    routes[i].factory
                );
                uint256 reserveInput = routes[i].from == token0 ? reserve0 : reserve1;
                amountInput = IERC20(routes[i].from).balanceOf(pair) - reserveInput;
            }
            amountOutput = IPair(pair).getAmountOut(amountInput, routes[i].from);
            (uint256 amount0Out, uint256 amount1Out) = routes[i].from == token0
                ? (uint256(0), amountOutput)
                : (amountOutput, uint256(0));
            address to = i < routes.length - 1
                ? pairFor(routes[i + 1].from, routes[i + 1].to, routes[i + 1].stable, routes[i + 1].factory)
                : _to;
            IPair(pair).swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external ensure(deadline) {
        _safeTransferFrom(
            routes[0].from,
            _msgSender(),
            pairFor(routes[0].from, routes[0].to, routes[0].stable, routes[0].factory),
            amountIn
        );
        uint256 balanceBefore = IERC20(routes[routes.length - 1].to).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(routes, to);
        require(
            IERC20(routes[routes.length - 1].to).balanceOf(to) - balanceBefore >= amountOutMin,
            "Router: insufficient output amount"
        );
    }

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external payable ensure(deadline) {
        require(routes[0].from == address(weth), "Router: invalid path");
        uint256 amountIn = msg.value;
        weth.deposit{value: amountIn}();
        assert(weth.transfer(pairFor(routes[0].from, routes[0].to, routes[0].stable, routes[0].factory), amountIn));
        uint256 balanceBefore = IERC20(routes[routes.length - 1].to).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(routes, to);
        require(
            IERC20(routes[routes.length - 1].to).balanceOf(to) - balanceBefore >= amountOutMin,
            "Router: insufficient output amount"
        );
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external ensure(deadline) {
        require(routes[routes.length - 1].to == address(weth), "Router: invalid path");
        _safeTransferFrom(
            routes[0].from,
            _msgSender(),
            pairFor(routes[0].from, routes[0].to, routes[0].stable, routes[0].factory),
            amountIn
        );
        _swapSupportingFeeOnTransferTokens(routes, address(this));
        uint256 amountOut = weth.balanceOf(address(this));
        require(amountOut >= amountOutMin, "Router: insufficient output amount");
        weth.withdraw(amountOut);
        _safeTransferETH(to, amountOut);
    }

    /// @inheritdoc IRouter
    function zapIn(
        address tokenIn,
        uint256 amountInA,
        uint256 amountInB,
        Zap calldata zapInPair,
        Route[] calldata routesA,
        Route[] calldata routesB,
        address to,
        bool stake
    ) external payable returns (uint256 liquidity) {
        uint256 amountIn = amountInA + amountInB;
        address _tokenIn = tokenIn;
        uint256 value = msg.value;
        if (tokenIn == ETHER) {
            require(amountIn == value, "Router: incorrect amountIn for eth deposit");
            _tokenIn = address(weth);
            weth.deposit{value: value}();
        } else {
            require(value == 0, "Router: invalid tokenIn address for eth deposit");
            _safeTransferFrom(_tokenIn, _msgSender(), address(this), amountIn);
        }

        _zapSwap(_tokenIn, amountInA, amountInB, zapInPair, routesA, routesB);
        _zapInLiquidity(zapInPair);
        address pair = pairFor(zapInPair.tokenA, zapInPair.tokenB, zapInPair.stable, zapInPair.factory);

        if (stake) {
            liquidity = IPair(pair).mint(address(this));
            address gauge = IVoter(voter).gauges(pair);
            IERC20(pair).safeApprove(address(gauge), liquidity);
            IGauge(gauge).deposit(liquidity, to);
            IERC20(pair).safeApprove(address(gauge), 0);
        } else {
            liquidity = IPair(pair).mint(to);
        }

        _returnAssets(tokenIn);
        _returnAssets(zapInPair.tokenA);
        _returnAssets(zapInPair.tokenB);
    }

    /// @dev Handles swap leg of zap in (i.e. convert tokenIn into tokenA and tokenB).
    function _zapSwap(
        address tokenIn,
        uint256 amountInA,
        uint256 amountInB,
        Zap calldata zapInPair,
        Route[] calldata routesA,
        Route[] calldata routesB
    ) internal {
        address tokenA = zapInPair.tokenA;
        address tokenB = zapInPair.tokenB;
        bool stable = zapInPair.stable;
        address factory = zapInPair.factory;
        address pair = pairFor(tokenA, tokenB, stable, factory);

        {
            (uint256 reserve0, uint256 reserve1, ) = IPair(pair).getReserves();
            require(reserve0 > MINIMUM_LIQUIDITY && reserve1 > MINIMUM_LIQUIDITY, "Router: pair does not exist");
        }

        if (tokenIn != tokenA) {
            require(routesA[routesA.length - 1].to == tokenA, "Router: invalid routeA");
            _internalSwap(tokenIn, amountInA, zapInPair.amountOutMinA, routesA);
        }
        if (tokenIn != tokenB) {
            require(routesB[routesB.length - 1].to == tokenB, "Router: invalid routeB");
            _internalSwap(tokenIn, amountInB, zapInPair.amountOutMinB, routesB);
        }
    }

    /// @dev Handles liquidity adding component of zap in.
    function _zapInLiquidity(Zap calldata zapInPair) internal {
        address tokenA = zapInPair.tokenA;
        address tokenB = zapInPair.tokenB;
        bool stable = zapInPair.stable;
        address factory = zapInPair.factory;
        address pair = pairFor(tokenA, tokenB, stable, factory);
        (uint256 amountA, uint256 amountB) = _quoteZapLiquidity(
            tokenA,
            tokenB,
            stable,
            factory,
            IERC20(tokenA).balanceOf(address(this)),
            IERC20(tokenB).balanceOf(address(this)),
            zapInPair.amountAMin,
            zapInPair.amountBMin
        );
        _safeTransfer(tokenA, pair, amountA);
        _safeTransfer(tokenB, pair, amountB);
    }

    /// @dev Similar to _addLiquidity. Assumes a pair exists, and accepts a factory argument.
    function _quoteZapLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        address _factory,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal view returns (uint256 amountA, uint256 amountB) {
        require(amountADesired >= amountAMin);
        require(amountBDesired >= amountBMin);
        (uint256 reserveA, uint256 reserveB) = getReserves(tokenA, tokenB, stable, _factory);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = quoteLiquidity(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, "Router: insufficient B amount");
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = quoteLiquidity(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, "Router: insufficient A amount");
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    /// @dev Handles swaps internally for zaps.
    function _internalSwap(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin,
        Route[] memory routes
    ) internal {
        uint256[] memory amounts = getAmountsOut(amountIn, routes);
        require(amounts[amounts.length - 1] >= amountOutMin, "Router: insufficient output amount for zap");
        address pair = pairFor(routes[0].from, routes[0].to, routes[0].stable, routes[0].factory);
        _safeTransfer(tokenIn, pair, amountIn);
        _swap(amounts, routes, address(this));
    }

    /// @inheritdoc IRouter
    function zapOut(
        address tokenOut,
        uint256 liquidity,
        Zap calldata zapOutPair,
        Route[] calldata routesA,
        Route[] calldata routesB
    ) external {
        address tokenA = zapOutPair.tokenA;
        address tokenB = zapOutPair.tokenB;
        address _tokenOut = (tokenOut == ETHER) ? address(weth) : tokenOut;
        _zapOutLiquidity(liquidity, zapOutPair);

        uint256 balance;
        if (tokenA != _tokenOut) {
            balance = IERC20(tokenA).balanceOf(address(this));
            require(routesA[routesA.length - 1].to == _tokenOut, "Router: invalid routeA");
            _internalSwap(tokenA, balance, zapOutPair.amountOutMinA, routesA);
        }
        if (tokenB != _tokenOut) {
            balance = IERC20(tokenB).balanceOf(address(this));
            require(routesB[routesB.length - 1].to == _tokenOut, "Router: invalid routeB");
            _internalSwap(tokenB, balance, zapOutPair.amountOutMinB, routesB);
        }

        _returnAssets(tokenOut);
    }

    /// @dev Handles liquidity removing component of zap out.
    function _zapOutLiquidity(uint256 liquidity, Zap calldata zapOutPair) internal {
        address tokenA = zapOutPair.tokenA;
        address tokenB = zapOutPair.tokenB;
        address pair = pairFor(tokenA, tokenB, zapOutPair.stable, zapOutPair.factory);
        require(IERC20(pair).transferFrom(msg.sender, pair, liquidity));
        (address token0, ) = sortTokens(tokenA, tokenB);
        (uint256 amount0, uint256 amount1) = IPair(pair).burn(address(this));
        (uint256 amountA, uint256 amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= zapOutPair.amountAMin, "Router: insufficient A amount");
        require(amountB >= zapOutPair.amountBMin, "Router: insufficient B amount");
    }

    /// @inheritdoc IRouter
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
        )
    {
        amountOutMinA = amountInA;
        amountOutMinB = amountInB;
        uint256[] memory amounts;
        if (routesA.length > 0) {
            amounts = getAmountsOut(amountInA, routesA);
            amountOutMinA = amounts[amounts.length - 1];
        }
        if (routesB.length > 0) {
            amounts = getAmountsOut(amountInB, routesB);
            amountOutMinB = amounts[amounts.length - 1];
        }
        (amountAMin, amountBMin, ) = quoteAddLiquidity(tokenA, tokenB, stable, _factory, amountOutMinA, amountOutMinB);
    }

    /// @inheritdoc IRouter
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
        )
    {
        (amountAMin, amountBMin) = quoteRemoveLiquidity(tokenA, tokenB, stable, _factory, liquidity);
        amountOutMinA = amountAMin;
        amountOutMinB = amountBMin;
        uint256[] memory amounts;
        if (routesA.length > 0) {
            amounts = getAmountsOut(amountAMin, routesA);
            amountOutMinA = amounts[amounts.length - 1];
        }
        if (routesB.length > 0) {
            amounts = getAmountsOut(amountBMin, routesB);
            amountOutMinB = amounts[amounts.length - 1];
        }
    }

    /// @dev Return residual assets from zapping.
    /// @param token token to return, put `ETHER` if you want Ether back.
    function _returnAssets(address token) internal {
        address sender = _msgSender();
        uint256 balance;
        if (token == ETHER) {
            balance = IERC20(weth).balanceOf(address(this));
            if (balance > 0) {
                IWETH(weth).withdraw(balance);
                _safeTransferETH(sender, balance);
            }
        } else {
            balance = IERC20(token).balanceOf(address(this));
            if (balance > 0) {
                IERC20(token).safeTransfer(sender, balance);
            }
        }
    }

    /// @inheritdoc IRouter
    function quoteStableLiquidityRatio(
        address tokenA,
        address tokenB,
        address _factory
    ) external view returns (uint256 ratio) {
        IPair pair = IPair(pairFor(tokenA, tokenB, true, _factory));

        uint256 investment = 10**IERC20Metadata(tokenA).decimals();
        uint256 out = pair.getAmountOut(investment, tokenA);
        (uint256 amountA, uint256 amountB, ) = quoteAddLiquidity(tokenA, tokenB, true, _factory, investment, out);

        amountA = (amountA * 1e18) / 10**IERC20Metadata(tokenA).decimals();
        amountB = (amountB * 1e18) / 10**IERC20Metadata(tokenB).decimals();
        out = (out * 1e18) / 10**IERC20Metadata(tokenB).decimals();
        investment = (investment * 1e18) / 10**IERC20Metadata(tokenA).decimals();

        ratio = (((out * 1e18) / investment) * amountA) / amountB;

        return (investment * 1e18) / (ratio + 1e18);
    }

    function _safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, "Router: ETH transfer failed");
    }

    function _safeTransfer(
        address token,
        address to,
        uint256 value
    ) internal {
        require(token.code.length > 0);
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }

    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        require(token.code.length > 0);
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./BaseTest.sol";
import {MockERC20WithTransferFee} from "utils/MockERC20WithTransferFee.sol";

contract RouterForkTest is BaseTest {
    Pool _pool;
    Pool poolFee;
    MockERC20WithTransferFee erc20Fee;

    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );

    constructor() {
        deploymentType = Deployment.FORK;
    }

    function _setUp() public override {
        uint256[] memory amounts = new uint256[](5);
        amounts[0] = 1e25;
        amounts[1] = 1e25;
        amounts[2] = 1e25;
        amounts[3] = 1e25;
        amounts[4] = 1e25;
        dealETH(owners, amounts);

        erc20Fee = new MockERC20WithTransferFee("Mock Token", "FEE", 18);
        erc20Fee.mint(address(owner), TOKEN_100K);

        _seedPoolsWithLiquidity();
    }

    function _seedPoolsWithLiquidity() internal {
        USDC.approve(address(router), USDC_100K);
        router.addLiquidityETH{value: TOKEN_100K}(
            address(USDC),
            false,
            USDC_100K,
            USDC_100K,
            TOKEN_100K,
            address(owner),
            block.timestamp
        );
        vm.startPrank(address(owner2));
        USDC.approve(address(router), USDC_100K);
        router.addLiquidityETH{value: TOKEN_100K}(
            address(USDC),
            false,
            USDC_100K,
            USDC_100K,
            TOKEN_100K,
            address(owner),
            block.timestamp
        );
        vm.stopPrank();

        // create pool for transfer fee token
        erc20Fee.approve(address(router), TOKEN_100K);
        router.addLiquidityETH{value: TOKEN_100K}(
            address(erc20Fee),
            false,
            TOKEN_100K,
            TOKEN_100K,
            TOKEN_100K,
            address(owner),
            block.timestamp
        );

        _pool = Pool(factory.getPair(address(USDC), address(WETH), false));
        poolFee = Pool(factory.getPair(address(erc20Fee), address(WETH), false));
    }

    /// @dev ensures routes are using the correct v1 / v2 route
    function buildSwapListeners(IRouter.Route[] memory routes) internal {
        for (uint256 i = 0; i < routes.length; i++) {
            // get address of factory since default of address(0) signifies v2 factory
            address factory_ = routes[i].factory == address(0) ? address(factory) : routes[i].factory;
            address expectedPool = router.poolFor(routes[i].from, routes[i].to, routes[i].stable, factory_);
            assertEq(IPoolFactory(factory_).getPair(routes[i].from, routes[i].to, routes[i].stable), expectedPool);
        }
    }

    function _swapExactTokensForTokensAndAssert(IRouter.Route[] memory routes) internal {
        address from = routes[0].from;
        address to = routes[routes.length - 1].to;

        // swap 100 of amount
        uint256 amount = from == address(USDC) ? 100 * USDC_1 : 100 * TOKEN_1;

        uint256[] memory expectedOutputArr = router.getAmountsOut(amount, routes);
        uint256 expectedOutput = expectedOutputArr[expectedOutputArr.length - 1];
        assertGt(expectedOutput, 0);

        uint256 balanceBefore = IERC20(to).balanceOf(address(owner));

        IERC20(from).approve(address(router), amount);
        buildSwapListeners(routes);
        router.swapExactTokensForTokens(amount, expectedOutput, routes, address(owner), block.timestamp);

        uint256 actualOutput = IERC20(to).balanceOf(address(owner)) - balanceBefore;
        assertEq(expectedOutput, actualOutput);
    }

    function _swapExactETHForTokensAndAssert(IRouter.Route[] memory routes) internal {
        address to = routes[routes.length - 1].to;

        // swap 1 ETH
        uint256 amount = TOKEN_1;

        uint256[] memory expectedOutputArr = router.getAmountsOut(amount, routes);
        uint256 expectedOutput = expectedOutputArr[expectedOutputArr.length - 1];
        assertGt(expectedOutput, 0);

        uint256 balanceBefore = IERC20(to).balanceOf(address(owner));

        buildSwapListeners(routes);
        router.swapExactETHForTokens{value: amount}(expectedOutput, routes, address(owner), block.timestamp);

        uint256 actualOutput = IERC20(to).balanceOf(address(owner)) - balanceBefore;
        assertEq(expectedOutput, actualOutput);
    }

    function _swapExactTokensForETHAndAssert(IRouter.Route[] memory routes) internal {
        address from = routes[0].from;

        // swap 100 of amount
        uint256 amount = from == address(USDC) ? 100 * USDC_1 : 100 * TOKEN_1;

        uint256[] memory expectedOutputArr = router.getAmountsOut(amount, routes);
        uint256 expectedOutput = expectedOutputArr[expectedOutputArr.length - 1];
        assertGt(expectedOutput, 0);

        uint256 balanceBefore = address(owner).balance;

        IERC20(from).approve(address(router), amount);
        buildSwapListeners(routes);
        router.swapExactTokensForETH(amount, expectedOutput, routes, address(owner), block.timestamp);

        uint256 actualOutput = address(owner).balance - balanceBefore;
        assertEq(expectedOutput, actualOutput);
    }

    // swapExactTokensForTokens tests

    function testRouterSwapExactTokensForTokensV2ToV1() public {
        // Test route of USDC -> WETH on v2 and then WETH -> DAI on v1
        IRouter.Route[] memory routes = new IRouter.Route[](2);
        routes[0] = IRouter.Route(address(USDC), address(WETH), false, address(0));
        routes[1] = IRouter.Route(address(WETH), address(DAI), false, address(vFactory));

        _swapExactTokensForTokensAndAssert(routes);
    }

    function testRouterSwapExactTokensForTokensV1ToV2() public {
        // Test route of DAI -> WETH on v1 and then WETH -> USDC on v2
        IRouter.Route[] memory routes = new IRouter.Route[](2);
        routes[0] = IRouter.Route(address(DAI), address(WETH), false, address(vFactory));
        routes[1] = IRouter.Route(address(WETH), address(USDC), false, address(0));

        _swapExactTokensForTokensAndAssert(routes);
    }

    function testRouterSwapExactTokensForTokensV2ToV1ToV2() public {
        // Test route of USDC -> WETH on v2 and then WETH -> DAI on v1 and then DAI -> FRAX on v2
        IRouter.Route[] memory routes = new IRouter.Route[](3);
        routes[0] = IRouter.Route(address(USDC), address(WETH), false, address(0));
        routes[1] = IRouter.Route(address(WETH), address(DAI), false, address(vFactory));
        routes[2] = IRouter.Route(address(DAI), address(FRAX), true, address(0));

        _swapExactTokensForTokensAndAssert(routes);
    }

    // swapExactETHForTokens tests

    function testRouterSwapExactETHForTokensV2ToV1() public {
        // Test route of ETH -> USDC on v2 and then USDC -> WETH on v1
        IRouter.Route[] memory routes = new IRouter.Route[](2);
        routes[0] = IRouter.Route(address(WETH), address(USDC), false, address(0));
        routes[1] = IRouter.Route(address(USDC), address(WETH), false, address(vFactory));

        _swapExactETHForTokensAndAssert(routes);
    }

    function testRouterSwapExactETHForTokensV1ToV2() public {
        // Test route of ETH -> DAI on v1 and then DAI -> FRAX on v2
        IRouter.Route[] memory routes = new IRouter.Route[](2);
        routes[0] = IRouter.Route(address(WETH), address(DAI), false, address(vFactory));
        routes[1] = IRouter.Route(address(DAI), address(FRAX), true, address(0));

        _swapExactETHForTokensAndAssert(routes);
    }

    function testRouterSwapExactETHForTokensV2ToV1ToV2() public {
        // Test route of WETH -> USDC on v2 and then USDC -> DAI on v1 and then DAI -> FRAX on v2
        IRouter.Route[] memory routes = new IRouter.Route[](3);
        routes[0] = IRouter.Route(address(WETH), address(USDC), false, address(0));
        routes[1] = IRouter.Route(address(USDC), address(DAI), true, address(vFactory));
        routes[2] = IRouter.Route(address(DAI), address(FRAX), true, address(0));

        _swapExactETHForTokensAndAssert(routes);
    }

    // swapExactTokensForETH tests

    function testRouterSwapExactTokensForETHV2ToV1() public {
        // Test route of FRAX -> DAI on v2 and then DAI -> ETH on v1
        IRouter.Route[] memory routes = new IRouter.Route[](2);
        routes[0] = IRouter.Route(address(FRAX), address(DAI), true, address(0));
        routes[1] = IRouter.Route(address(DAI), address(WETH), false, address(vFactory));

        _swapExactTokensForETHAndAssert(routes);
    }

    function testRouterSwapExactTokensForETHV1ToV2() public {
        // Test route of DAI -> USDC on v1 and then USDC -> ETH on v2
        IRouter.Route[] memory routes = new IRouter.Route[](2);
        routes[0] = IRouter.Route(address(DAI), address(USDC), true, address(vFactory));
        routes[1] = IRouter.Route(address(USDC), address(WETH), false, address(0));

        _swapExactTokensForETHAndAssert(routes);
    }

    function testRouterSwapExactTokensForETHV2ToV1ToV2() public {
        // Test route of FRAX -> DAI on v2 and then DAI -> USDC on v1 and then USDC -> ETH on v2
        IRouter.Route[] memory routes = new IRouter.Route[](3);
        routes[0] = IRouter.Route(address(FRAX), address(DAI), true, address(0));
        routes[1] = IRouter.Route(address(DAI), address(USDC), true, address(vFactory));
        routes[2] = IRouter.Route(address(USDC), address(WETH), false, address(0));

        _swapExactTokensForETHAndAssert(routes);
    }

    function testSwapExactTokensForTokensV1() public {
        // Test route of DAI -> WETH on v1
        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route(address(DAI), address(WETH), false, address(vFactory));

        _swapExactTokensForTokensAndAssert(routes);
    }

    // Swap with fees

    function testRouterSwapExactTokensForTokensFeesV2ToV1() public {
        // Test route of fee Token -> WETH on v2 and then WETH -> DAI on v1
        IRouter.Route[] memory routes = new IRouter.Route[](2);
        routes[0] = IRouter.Route(address(erc20Fee), address(WETH), false, address(0));
        routes[1] = IRouter.Route(address(WETH), address(DAI), false, address(vFactory));

        // first add the token balance to user to swap
        erc20Fee.mint(address(owner), TOKEN_1 * 100);

        // swap 100 fee token
        uint256 amount = 100 * TOKEN_1;
        uint256[] memory expectedOutputArr = router.getAmountsOut(amount - erc20Fee.fee() * 2, routes);
        uint256 expectedOutput = expectedOutputArr[expectedOutputArr.length - 1];
        assertGt(expectedOutput, 0);

        uint256 balanceBefore = DAI.balanceOf(address(owner));

        erc20Fee.approve(address(router), amount);
        buildSwapListeners(routes);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amount,
            expectedOutput,
            routes,
            address(owner),
            block.timestamp
        );

        assertApproxEqRel(DAI.balanceOf(address(owner)) - balanceBefore, expectedOutput, 1e4);
    }

    function testCannotConvertV2ToV1Velo() public {
        vm.expectRevert(IRouter.ConversionFromV2ToV1VeloProhibited.selector);
        router.poolFor(address(VELO), address(vVELO), false, address(0));
    }
}

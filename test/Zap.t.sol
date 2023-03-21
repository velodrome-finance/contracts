pragma solidity 0.8.13;

import "./BaseTest.sol";

contract ZapTest is BaseTest {
    Router _router;
    Pair vPair;
    Gauge vGauge;
    Pair sPair;
    Gauge sGauge;
    uint256 constant feeRate = 2; // .02% fee on mainnet

    /// @dev Volatile slippage (.5%)
    uint256 constant vSLIPPAGE = 50;
    /// @dev Stable slippage (.2%)
    uint256 constant sSLIPPAGE = 20;
    /// @dev ETH price at block 70m
    uint256 constant ETH_PRICE = 1638;

    constructor() {
        deploymentType = Deployment.FORK;
        BLOCK_NUMBER = 70_000_000; // pin block so pool state is static
    }

    function _setUp() public override {
        // Current State:
        // 1.25m USDC, 763.8 WETH, current WETH price ~$1638
        // Pool has slightly more USDC than WETH
        vPair = Pair(0x79c912FEF520be002c2B6e57EC4324e260f38E50);
        /// Current State:
        /// ~295k FRAX, ~356k USDC
        /// Pool has more USDC than FRAX
        sPair = Pair(0xAdF902b11e4ad36B227B84d856B229258b0b0465);

        deal(address(USDC), address(owner2), USDC_100K);
        vm.deal(address(owner2), TOKEN_100K);

        _router = new Router(address(factory), address(voter), address(WETH));
        factoryRegistry.approve(address(vFactory), address(votingRewardsFactory), address(gaugeFactory));
        vGauge = Gauge(
            voter.createGauge(address(vFactory), address(votingRewardsFactory), address(gaugeFactory), address(vPair))
        );
        sGauge = Gauge(
            voter.createGauge(address(vFactory), address(votingRewardsFactory), address(gaugeFactory), address(sPair))
        );

        vm.label(address(vPair), "vAMM WETH/USDC");
        vm.label(address(sPair), "sAMM FRAX/USDC");
        vm.label(address(vGauge), "vAMM Gauge");
        vm.label(address(sGauge), "sAMM Gauge");
        vm.label(address(_router), "Router");
    }

    function testZapInWithStablePair() public {
        vm.startPrank(address(owner2));
        USDC.approve(address(_router), type(uint256).max);

        uint256 usdcPairPreBal = USDC.balanceOf(address(sPair));
        uint256 usdcOwnerPreBal = USDC.balanceOf(address(owner2));
        uint256 fraxOwnerPreBal = FRAX.balanceOf(address(owner2));
        assertEq(sPair.balanceOf(address(owner2)), 0);

        uint256 ratio = _router.quoteStableLiquidityRatio(address(FRAX), address(USDC), address(vFactory));
        IRouter.Route[] memory routesA = new IRouter.Route[](1);
        routesA[0] = IRouter.Route(address(USDC), address(FRAX), true, address(vFactory));
        IRouter.Route[] memory routesB = new IRouter.Route[](0);
        IRouter.Zap memory zapInPair = _createZapInParams(
            address(FRAX),
            address(USDC),
            true,
            address(vFactory),
            (USDC_10K * (1e18 - ratio)) / 1e18,
            (USDC_10K * ratio) / 1e18,
            routesA,
            routesB
        );

        _router.zapIn(
            address(USDC),
            (USDC_10K * (1e18 - ratio)) / 1e18,
            (USDC_10K * ratio) / 1e18,
            zapInPair,
            routesA,
            routesB,
            address(owner2),
            false
        );

        uint256 usdcPairPostBal = USDC.balanceOf(address(sPair));
        uint256 usdcOwnerPostBal = USDC.balanceOf(address(owner2));
        uint256 fraxOwnerPostBal = FRAX.balanceOf(address(owner2));

        assertApproxEqAbs(usdcPairPostBal - usdcPairPreBal, USDC_10K, USDC_1);
        assertApproxEqAbs(usdcOwnerPreBal - usdcOwnerPostBal, USDC_10K, USDC_1);
        assertLt(fraxOwnerPostBal - fraxOwnerPreBal, (TOKEN_100K * 150) / MAX_BPS);
        assertGt(sPair.balanceOf(address(owner2)), 0);
        assertEq(USDC.balanceOf(address(_router)), 0);
        assertEq(FRAX.balanceOf(address(_router)), 0);
        vm.stopPrank();
    }

    function testZapAndStakeWithStablePair() public {
        vm.startPrank(address(owner2));
        USDC.approve(address(_router), type(uint256).max);

        uint256 usdcPairPreBal = USDC.balanceOf(address(sPair));
        uint256 usdcOwnerPreBal = USDC.balanceOf(address(owner2));
        uint256 fraxOwnerPreBal = FRAX.balanceOf(address(owner2));
        assertEq(sPair.balanceOf(address(owner2)), 0);
        assertEq(sPair.balanceOf(address(sGauge)), 0);
        assertEq(sGauge.balanceOf(address(owner2)), 0);

        uint256 ratio = _router.quoteStableLiquidityRatio(address(FRAX), address(USDC), address(vFactory));
        IRouter.Route[] memory routesA = new IRouter.Route[](1);
        routesA[0] = IRouter.Route(address(USDC), address(FRAX), true, address(vFactory));
        IRouter.Route[] memory routesB = new IRouter.Route[](0);
        IRouter.Zap memory zapInPair = _createZapInParams(
            address(FRAX),
            address(USDC),
            true,
            address(vFactory),
            (USDC_10K * (1e18 - ratio)) / 1e18,
            (USDC_10K * ratio) / 1e18,
            routesA,
            routesB
        );

        _router.zapIn(
            address(USDC),
            (USDC_10K * (1e18 - ratio)) / 1e18,
            (USDC_10K * ratio) / 1e18,
            zapInPair,
            routesA,
            routesB,
            address(owner2),
            true
        );

        uint256 usdcPairPostBal = USDC.balanceOf(address(sPair));
        uint256 usdcOwnerPostBal = USDC.balanceOf(address(owner2));
        uint256 fraxOwnerPostBal = FRAX.balanceOf(address(owner2));

        assertApproxEqAbs(usdcPairPostBal - usdcPairPreBal, USDC_10K, USDC_1);
        assertApproxEqAbs(usdcOwnerPreBal - usdcOwnerPostBal, USDC_10K, USDC_1);
        assertLt(fraxOwnerPostBal - fraxOwnerPreBal, (TOKEN_100K * 150) / MAX_BPS);
        assertEq(sPair.balanceOf(address(owner2)), 0);
        assertGt(sPair.balanceOf(address(sGauge)), 0);
        assertGt(sGauge.balanceOf(address(owner2)), 0);
        assertEq(USDC.balanceOf(address(_router)), 0);
        assertEq(FRAX.balanceOf(address(_router)), 0);
        assertEq(sPair.allowance(address(_router), address(sGauge)), 0);
        vm.stopPrank();
    }

    function testCannotZapWithETHWithInvalidParameters() public {
        vm.startPrank(address(owner2));
        USDC.approve(address(_router), type(uint256).max);

        IRouter.Route[] memory routesA = new IRouter.Route[](1);
        IRouter.Route[] memory routesB = new IRouter.Route[](1);
        IRouter.Zap memory zapInPair = IRouter.Zap(address(WETH), address(USDC), false, address(vFactory), 0, 0, 0, 0);

        // tokenIn != WETH
        vm.expectRevert(IRouter.InvalidTokenInForETHDeposit.selector);
        _router.zapIn{value: TOKEN_1}(
            address(0),
            TOKEN_1 / 2,
            TOKEN_1 / 2,
            zapInPair,
            routesA,
            routesB,
            address(owner2),
            true
        );

        // msg.value != zapAmount
        vm.expectRevert(IRouter.InvalidAmountInForETHDeposit.selector);
        _router.zapIn{value: TOKEN_1}(
            ETHER,
            TOKEN_1 / 2,
            TOKEN_1 / 4,
            zapInPair,
            routesA,
            routesB,
            address(owner2),
            true
        );

        vm.stopPrank();
    }

    function testZapInWithVolatilePair() public {
        vm.startPrank(address(owner2));
        USDC.approve(address(_router), type(uint256).max);

        uint256 usdcPairPreBal = USDC.balanceOf(address(vPair));
        uint256 wethPairPreBal = WETH.balanceOf(address(vPair));
        uint256 usdcOwnerPreBal = USDC.balanceOf(address(owner2));
        uint256 wethOwnerPreBal = WETH.balanceOf(address(owner2));
        uint256 ethOwnerPreBal = address(owner2).balance;
        assertEq(vPair.balanceOf(address(owner2)), 0);
        assertEq(vPair.balanceOf(address(owner3)), 0);

        IRouter.Route[] memory routesA = new IRouter.Route[](1);
        routesA[0] = IRouter.Route(address(USDC), address(WETH), false, address(vFactory));
        IRouter.Route[] memory routesB = new IRouter.Route[](0);
        IRouter.Zap memory zapInPair = _createZapInParams(
            address(WETH),
            address(USDC),
            false,
            address(vFactory),
            USDC_10K / 2,
            USDC_10K / 2,
            routesA,
            routesB
        );

        _router.zapIn(address(USDC), USDC_10K / 2, USDC_10K / 2, zapInPair, routesA, routesB, address(owner3), false);

        uint256 fee = ((USDC_10K / 2) * feeRate) / MAX_BPS;
        uint256 slippage = ((((USDC_10K / 2) * 1e12) / ETH_PRICE) * vSLIPPAGE) / MAX_BPS;

        assertEq(USDC.balanceOf(address(vPair)) - usdcPairPreBal, USDC_10K - fee);
        assertEq(usdcOwnerPreBal - USDC.balanceOf(address(owner2)), USDC_10K);
        assertLt(wethPairPreBal - WETH.balanceOf(address(vPair)), slippage);
        assertEq(address(owner2).balance, ethOwnerPreBal);
        assertLt(WETH.balanceOf(address(owner2)) - wethOwnerPreBal, slippage);
        assertEq(vPair.balanceOf(address(owner2)), 0);
        assertGt(vPair.balanceOf(address(owner3)), 0);
        assertEq(USDC.balanceOf(address(_router)), 0);
        assertEq(WETH.balanceOf(address(_router)), 0);
        vm.stopPrank();
    }

    function testZapInWithVolatilePairAndETH() public {
        vm.startPrank(address(owner2));
        USDC.approve(address(_router), type(uint256).max);

        uint256 usdcPairPreBal = USDC.balanceOf(address(vPair));
        uint256 wethPairPreBal = WETH.balanceOf(address(vPair));
        uint256 usdcOwnerPreBal = USDC.balanceOf(address(owner2));
        uint256 wethOwnerPreBal = WETH.balanceOf(address(owner2));
        uint256 ethOwnerPreBal = address(owner2).balance;
        assertEq(vPair.balanceOf(address(owner2)), 0);

        uint256 zapAmount = TOKEN_1 * 5;
        IRouter.Route[] memory routesA = new IRouter.Route[](0);
        IRouter.Route[] memory routesB = new IRouter.Route[](1);
        routesB[0] = IRouter.Route(address(WETH), address(USDC), false, address(vFactory));
        IRouter.Zap memory zapInPair = _createZapInParams(
            address(WETH),
            address(USDC),
            false,
            address(vFactory),
            zapAmount / 2,
            zapAmount / 2,
            routesA,
            routesB
        );

        _router.zapIn{value: zapAmount}(
            ETHER,
            zapAmount / 2,
            zapAmount / 2,
            zapInPair,
            routesA,
            routesB,
            address(owner2),
            false
        );

        uint256 fee = ((zapAmount / 2) * feeRate) / MAX_BPS;
        uint256 slippage = ((zapAmount / 2 / 1e12) * ETH_PRICE * vSLIPPAGE) / MAX_BPS;

        assertEq(WETH.balanceOf(address(vPair)) - wethPairPreBal, 5 * TOKEN_1 - fee);
        assertLt(usdcPairPreBal - USDC.balanceOf(address(vPair)), slippage);
        assertLt(USDC.balanceOf(address(owner2)) - usdcOwnerPreBal, slippage);
        assertEq(ethOwnerPreBal - address(owner2).balance, 5 * TOKEN_1);
        assertEq(WETH.balanceOf(address(owner2)), wethOwnerPreBal);
        assertGt(vPair.balanceOf(address(owner2)), 0);
        assertEq(USDC.balanceOf(address(_router)), 0);
        assertEq(WETH.balanceOf(address(_router)), 0);
        vm.stopPrank();
    }

    function testZapAndStakeWithVolatilePair() public {
        vm.startPrank(address(owner2));
        USDC.approve(address(_router), type(uint256).max);

        uint256 usdcPairPreBal = USDC.balanceOf(address(vPair));
        uint256 wethPairPreBal = WETH.balanceOf(address(vPair));
        uint256 usdcOwnerPreBal = USDC.balanceOf(address(owner2));
        uint256 wethOwnerPreBal = WETH.balanceOf(address(owner2));
        uint256 ethOwnerPreBal = address(owner2).balance;
        assertEq(vPair.balanceOf(address(owner2)), 0);
        assertEq(vPair.balanceOf(address(vGauge)), 0);
        assertEq(vGauge.balanceOf(address(owner2)), 0);

        IRouter.Route[] memory routesA = new IRouter.Route[](1);
        routesA[0] = IRouter.Route(address(USDC), address(WETH), false, address(vFactory));
        IRouter.Route[] memory routesB = new IRouter.Route[](0);
        IRouter.Zap memory zapInPair = _createZapInParams(
            address(WETH),
            address(USDC),
            false,
            address(vFactory),
            USDC_10K / 2,
            USDC_10K / 2,
            routesA,
            routesB
        );

        _router.zapIn(address(USDC), USDC_10K / 2, USDC_10K / 2, zapInPair, routesA, routesB, address(owner2), true);

        uint256 fee = ((USDC_10K / 2) * feeRate) / MAX_BPS;
        uint256 slippage = ((((USDC_10K / 2) * 1e12) / ETH_PRICE) * vSLIPPAGE) / MAX_BPS;

        assertEq(USDC.balanceOf(address(vPair)) - usdcPairPreBal, USDC_10K - fee);
        assertEq(usdcOwnerPreBal - USDC.balanceOf(address(owner2)), USDC_10K);
        assertLt(wethPairPreBal - WETH.balanceOf(address(vPair)), slippage);
        assertEq(address(owner2).balance, ethOwnerPreBal);
        assertLt(WETH.balanceOf(address(owner2)) - wethOwnerPreBal, slippage);
        assertEq(vPair.balanceOf(address(owner2)), 0);
        assertGt(vPair.balanceOf(address(vGauge)), 0);
        assertGt(vGauge.balanceOf(address(owner2)), 0);
        assertEq(USDC.balanceOf(address(_router)), 0);
        assertEq(WETH.balanceOf(address(_router)), 0);
        assertEq(vPair.allowance(address(_router), address(vGauge)), 0);
        vm.stopPrank();
    }

    function testZapAndStakeWithVolatilePairAndETH() public {
        vm.startPrank(address(owner2));
        USDC.approve(address(_router), type(uint256).max);

        uint256 usdcPairPreBal = USDC.balanceOf(address(vPair));
        uint256 wethPairPreBal = WETH.balanceOf(address(vPair));
        uint256 usdcOwnerPreBal = USDC.balanceOf(address(owner2));
        uint256 wethOwnerPreBal = WETH.balanceOf(address(owner2));
        uint256 ethOwnerPreBal = address(owner2).balance;
        assertEq(vPair.balanceOf(address(owner2)), 0);
        assertEq(vPair.balanceOf(address(vGauge)), 0);
        assertEq(vGauge.balanceOf(address(owner2)), 0);

        uint256 zapAmount = TOKEN_1 * 5;
        IRouter.Route[] memory routesA = new IRouter.Route[](0);
        IRouter.Route[] memory routesB = new IRouter.Route[](1);
        routesB[0] = IRouter.Route(address(WETH), address(USDC), false, address(vFactory));
        IRouter.Zap memory zapInPair = _createZapInParams(
            address(WETH),
            address(USDC),
            false,
            address(vFactory),
            zapAmount / 2,
            zapAmount / 2,
            routesA,
            routesB
        );

        _router.zapIn{value: zapAmount}(
            ETHER,
            zapAmount / 2,
            zapAmount / 2,
            zapInPair,
            routesA,
            routesB,
            address(owner2),
            true
        );

        uint256 fee = ((zapAmount / 2) * feeRate) / MAX_BPS;
        uint256 slippage = ((zapAmount / 2 / 1e12) * ETH_PRICE * vSLIPPAGE) / MAX_BPS;

        assertEq(WETH.balanceOf(address(vPair)) - wethPairPreBal, 5 * TOKEN_1 - fee);
        assertLt(usdcPairPreBal - USDC.balanceOf(address(vPair)), slippage);
        assertLt(USDC.balanceOf(address(owner2)) - usdcOwnerPreBal, slippage);
        assertEq(WETH.balanceOf(address(owner2)), wethOwnerPreBal);
        assertEq(ethOwnerPreBal - address(owner2).balance, 5 * TOKEN_1);
        assertEq(vPair.balanceOf(address(owner2)), 0);
        assertGt(vPair.balanceOf(address(vGauge)), 0);
        assertGt(vGauge.balanceOf(address(owner2)), 0);
        assertEq(USDC.balanceOf(address(_router)), 0);
        assertEq(WETH.balanceOf(address(_router)), 0);
        assertEq(vPair.allowance(address(_router), address(vGauge)), 0);
        vm.stopPrank();
    }

    function testZapOutWithVolatilePairWithTokenInPair() public {
        vm.startPrank(address(owner2));
        USDC.approve(address(_router), type(uint256).max);
        assertEq(vPair.balanceOf(address(owner2)), 0);

        IRouter.Route[] memory routesA = new IRouter.Route[](0);
        IRouter.Route[] memory routesB = new IRouter.Route[](1);
        routesB[0] = IRouter.Route(address(USDC), address(WETH), false, address(vFactory));
        IRouter.Zap memory zap = _createZapInParams(
            address(USDC),
            address(WETH),
            false,
            address(vFactory),
            USDC_10K / 2,
            USDC_10K / 2,
            routesA,
            routesB
        );

        _router.zapIn(address(USDC), USDC_10K / 2, USDC_10K / 2, zap, routesA, routesB, address(owner2), false);
        uint256 liquidity = vPair.balanceOf(address(owner2));
        assertGt(liquidity, 0);

        uint256 amount = vPair.balanceOf(address(owner2));
        uint256 usdcPairPreBal = USDC.balanceOf(address(vPair));
        uint256 wethPairPreBal = WETH.balanceOf(address(vPair));
        uint256 usdcOwnerPreBal = USDC.balanceOf(address(owner2));
        uint256 wethOwnerPreBal = WETH.balanceOf(address(owner2));
        uint256 ethOwnerPreBal = address(owner2).balance;

        routesB[0] = IRouter.Route(address(WETH), address(USDC), false, address(vFactory));
        zap = _createZapOutParams(address(USDC), address(WETH), false, address(vFactory), liquidity, routesA, routesB);
        vPair.approve(address(_router), type(uint256).max);
        _router.zapOut(address(USDC), amount, zap, routesA, routesB);

        uint256 slippage = ((USDC_10K / 2) * vSLIPPAGE) / MAX_BPS;

        // experience slippage twice as we zap in and out
        assertEq(address(owner2).balance, ethOwnerPreBal);
        assertGt(USDC.balanceOf(address(owner2)) - usdcOwnerPreBal, USDC_10K - 2 * slippage);
        assertGt(usdcPairPreBal - USDC.balanceOf(address(vPair)), USDC_10K - 2 * slippage);
        assertLt(wethPairPreBal - WETH.balanceOf(address(vPair)), TOKEN_1 / 100);
        assertEq(WETH.balanceOf(address(owner2)), wethOwnerPreBal);
        assertEq(vPair.balanceOf(address(owner2)), 0);
        assertEq(USDC.balanceOf(address(_router)), 0);
        assertEq(WETH.balanceOf(address(_router)), 0);
        vm.stopPrank();
    }

    function testZapOutWithVolatilePairWithTokenInPairWithETH() public {
        vm.startPrank(address(owner2));
        USDC.approve(address(_router), type(uint256).max);
        assertEq(vPair.balanceOf(address(owner2)), 0);

        IRouter.Route[] memory routesA = new IRouter.Route[](0);
        IRouter.Route[] memory routesB = new IRouter.Route[](1);
        routesB[0] = IRouter.Route(address(USDC), address(WETH), false, address(vFactory));
        IRouter.Zap memory zap = _createZapInParams(
            address(USDC),
            address(WETH),
            false,
            address(vFactory),
            USDC_10K / 2,
            USDC_10K / 2,
            routesA,
            routesB
        );

        _router.zapIn(address(USDC), USDC_10K / 2, USDC_10K / 2, zap, routesA, routesB, address(owner2), false);

        uint256 liquidity = vPair.balanceOf(address(owner2));
        assertGt(liquidity, 0);

        uint256 usdcPairPreBal = USDC.balanceOf(address(vPair));
        uint256 wethPairPreBal = WETH.balanceOf(address(vPair));
        uint256 usdcOwnerPreBal = USDC.balanceOf(address(owner2));
        uint256 wethOwnerPreBal = WETH.balanceOf(address(owner2));
        uint256 ethOwnerPreBal = address(owner2).balance;
        // approximate return value
        uint256 expectedETH = vPair.getAmountOut(USDC_10K, address(USDC));

        delete routesB[0];
        routesA = new IRouter.Route[](1);
        routesB = new IRouter.Route[](0);
        routesA[0] = IRouter.Route(address(USDC), address(WETH), false, address(vFactory));
        zap = _createZapOutParams(address(USDC), address(WETH), false, address(vFactory), liquidity, routesA, routesB);

        // request WETH
        vPair.approve(address(_router), type(uint256).max);
        _router.zapOut(ETHER, liquidity, zap, routesA, routesB);

        uint256 slippage = ((((USDC_10K / 2) * 1e12) / ETH_PRICE) * vSLIPPAGE) / MAX_BPS;

        assertGt(address(owner2).balance - ethOwnerPreBal, expectedETH - 2 * slippage);
        assertEq(USDC.balanceOf(address(owner2)), usdcOwnerPreBal);
        assertLt(usdcPairPreBal - USDC.balanceOf(address(vPair)), USDC_1);
        assertApproxEqRel(wethPairPreBal - WETH.balanceOf(address(vPair)), expectedETH, 1e16);
        assertEq(WETH.balanceOf(address(owner2)), wethOwnerPreBal); // no change in WETH balance
        assertEq(vPair.balanceOf(address(owner2)), 0);
        assertEq(USDC.balanceOf(address(_router)), 0);
        assertEq(WETH.balanceOf(address(_router)), 0);
        vm.stopPrank();
    }

    function testZapOutWithVolatilePairWithTokenInPairWithWETH() public {
        vm.startPrank(address(owner2));
        USDC.approve(address(_router), type(uint256).max);
        assertEq(vPair.balanceOf(address(owner2)), 0);

        IRouter.Route[] memory routesA = new IRouter.Route[](0);
        IRouter.Route[] memory routesB = new IRouter.Route[](1);
        routesB[0] = IRouter.Route(address(USDC), address(WETH), false, address(vFactory));
        IRouter.Zap memory zap = _createZapInParams(
            address(USDC),
            address(WETH),
            false,
            address(vFactory),
            USDC_10K / 2,
            USDC_10K / 2,
            routesA,
            routesB
        );

        _router.zapIn(address(USDC), USDC_10K / 2, USDC_10K / 2, zap, routesA, routesB, address(owner2), false);
        uint256 liquidity = vPair.balanceOf(address(owner2));
        assertGt(liquidity, 0);

        uint256 usdcPairPreBal = USDC.balanceOf(address(vPair));
        uint256 wethPairPreBal = WETH.balanceOf(address(vPair));
        uint256 usdcOwnerPreBal = USDC.balanceOf(address(owner2));
        uint256 wethOwnerPreBal = WETH.balanceOf(address(owner2));
        uint256 ethOwnerPreBal = address(owner2).balance;
        // approximate return value
        uint256 expectedETH = vPair.getAmountOut(USDC_10K, address(USDC));

        delete routesB;
        routesA = new IRouter.Route[](1);
        routesB = new IRouter.Route[](0);
        routesA[0] = IRouter.Route(address(USDC), address(WETH), false, address(vFactory));
        zap = _createZapOutParams(address(USDC), address(WETH), false, address(vFactory), liquidity, routesA, routesB);

        // request WETH
        vPair.approve(address(_router), type(uint256).max);
        _router.zapOut(address(WETH), liquidity, zap, routesA, routesB);

        uint256 slippage = ((((USDC_10K / 2) * 1e12) / ETH_PRICE) * vSLIPPAGE) / MAX_BPS;

        assertGt(WETH.balanceOf(address(owner2)) - wethOwnerPreBal, expectedETH - 2 * slippage);
        assertEq(USDC.balanceOf(address(owner2)), usdcOwnerPreBal);
        assertLt(usdcPairPreBal - USDC.balanceOf(address(vPair)), USDC_1);
        assertApproxEqRel(wethPairPreBal - WETH.balanceOf(address(vPair)), expectedETH, 1e16);
        assertEq(address(owner2).balance, ethOwnerPreBal); // no change in ETH balance
        assertEq(vPair.balanceOf(address(owner2)), 0);
        assertEq(USDC.balanceOf(address(_router)), 0);
        assertEq(WETH.balanceOf(address(_router)), 0);
        vm.stopPrank();
    }

    function _createZapInParams(
        address tokenA,
        address tokenB,
        bool stable,
        address _factory,
        uint256 amountInA,
        uint256 amountInB,
        IRouter.Route[] memory routesA,
        IRouter.Route[] memory routesB
    ) internal view returns (IRouter.Zap memory zap) {
        // use 300 bps slippage for the smaller stable pool
        uint256 slippage = (stable == true) ? 300 : 50;
        (uint256 amountOutMinA, uint256 amountOutMinB, uint256 amountAMin, uint256 amountBMin) = _router
            .generateZapInParams(tokenA, tokenB, stable, _factory, amountInA, amountInB, routesA, routesB);

        amountAMin = (amountAMin * (MAX_BPS - slippage)) / MAX_BPS;
        amountBMin = (amountBMin * (MAX_BPS - slippage)) / MAX_BPS;
        return IRouter.Zap(tokenA, tokenB, stable, _factory, amountOutMinA, amountOutMinB, amountAMin, amountBMin);
    }

    function _createZapOutParams(
        address tokenA,
        address tokenB,
        bool stable,
        address _factory,
        uint256 liquidity,
        IRouter.Route[] memory routesA,
        IRouter.Route[] memory routesB
    ) internal view returns (IRouter.Zap memory zap) {
        // use 300 bps slippage for the smaller stable pool
        uint256 slippage = (stable == true) ? 300 : 50;
        (uint256 amountOutMinA, uint256 amountOutMinB, uint256 amountAMin, uint256 amountBMin) = _router
            .generateZapOutParams(tokenA, tokenB, stable, _factory, liquidity, routesA, routesB);
        amountOutMinA = (amountOutMinA * (MAX_BPS - slippage)) / MAX_BPS;
        amountOutMinB = (amountOutMinB * (MAX_BPS - slippage)) / MAX_BPS;
        return IRouter.Zap(tokenA, tokenB, stable, _factory, amountOutMinA, amountOutMinB, amountAMin, amountBMin);
    }
}

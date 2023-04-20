// 1:1 with Hardhat test
pragma solidity 0.8.13;

import "./BaseTest.sol";

contract OracleTest is BaseTest {
    constructor() {
        deploymentType = Deployment.CUSTOM;
    }

    function deployBaseCoins() public {
        deployOwners();
        deployCoins();
        mintStables();
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1e25;
        mintToken(address(VELO), owners, amounts);
        escrow = VotingEscrow(address(VELO));
    }

    function confirmTokensForFraxUsdc() public {
        deployBaseCoins();
        deployFactories();

        escrow = new VotingEscrow(address(forwarder), address(VELO), address(factoryRegistry));
        VeArtProxy artProxy = new VeArtProxy(address(escrow));
        escrow.setArtProxy(address(artProxy));
        voter = new Voter(address(forwarder), address(escrow), address(factoryRegistry));
        router = new Router(address(forwarder), address(factory), address(voter), address(WETH));
        deployPairWithOwner(address(owner));

        (address token0, address token1) = router.sortTokens(address(USDC), address(FRAX));
        assertEq((pair.token0()), token0);
        assertEq((pair.token1()), token1);
    }

    function mintAndBurnTokensForPairFraxUsdc() public {
        confirmTokensForFraxUsdc();

        USDC.transfer(address(pair), USDC_1);
        FRAX.transfer(address(pair), TOKEN_1);
        pair.mint(address(owner));
        assertEq(pair.getAmountOut(USDC_1, address(USDC)), 945128557522723966);
    }

    function routerAddLiquidity() public {
        mintAndBurnTokensForPairFraxUsdc();

        USDC.approve(address(router), USDC_100K);
        FRAX.approve(address(router), TOKEN_100K);
        router.addLiquidity(
            address(FRAX),
            address(USDC),
            true,
            TOKEN_100K,
            USDC_100K,
            TOKEN_100K,
            USDC_100K,
            address(owner),
            block.timestamp
        );
        USDC.approve(address(router), USDC_100K);
        FRAX.approve(address(router), TOKEN_100K);
        router.addLiquidity(
            address(FRAX),
            address(USDC),
            false,
            TOKEN_100K,
            USDC_100K,
            TOKEN_100K,
            USDC_100K,
            address(owner),
            block.timestamp
        );
        DAI.approve(address(router), TOKEN_100M);
        FRAX.approve(address(router), TOKEN_100M);
        router.addLiquidity(
            address(FRAX),
            address(DAI),
            true,
            TOKEN_100M,
            TOKEN_100M,
            0,
            0,
            address(owner),
            block.timestamp
        );
    }

    function routerPair1GetAmountsOutAndSwapExactTokensForTokens() public {
        routerAddLiquidity();

        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route(address(USDC), address(FRAX), true, address(0));

        assertEq(router.getAmountsOut(USDC_1, routes)[1], pair.getAmountOut(USDC_1, address(USDC)));

        uint256[] memory asserted_output = router.getAmountsOut(USDC_1, routes);
        USDC.approve(address(router), USDC_1);
        router.swapExactTokensForTokens(USDC_1, asserted_output[1], routes, address(owner), block.timestamp);
        skip(1801);
        vm.roll(block.number + 1);
        USDC.approve(address(router), USDC_1);
        router.swapExactTokensForTokens(USDC_1, 0, routes, address(owner), block.timestamp);
        skip(1801);
        vm.roll(block.number + 1);
        USDC.approve(address(router), USDC_1);
        router.swapExactTokensForTokens(USDC_1, 0, routes, address(owner), block.timestamp);
        skip(1801);
        vm.roll(block.number + 1);
        USDC.approve(address(router), USDC_1);
        router.swapExactTokensForTokens(USDC_1, 0, routes, address(owner), block.timestamp);
        address pairFees = pair.pairFees();
        assertEq(USDC.balanceOf(pairFees), 400);
        uint256 b = USDC.balanceOf(address(owner));
        pair.claimFees();
        assertGt(USDC.balanceOf(address(owner)), b);
    }

    function testOracle() public {
        routerPair1GetAmountsOutAndSwapExactTokensForTokens();

        assertEq(pair.quote(address(USDC), 1e9, 1), 999999494004424240546);
        assertEq(pair.quote(address(FRAX), 1e21, 1), 999999506);
    }
}

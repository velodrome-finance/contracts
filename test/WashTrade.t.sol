// 1:1 with Hardhat test
pragma solidity 0.8.13;

import "./BaseTest.sol";

contract WashTradeTest is BaseTest {
    constructor() {
        deploymentType = Deployment.CUSTOM;
    }

    function deployBaseCoins() public {
        skip(1 weeks);

        deployOwners();
        deployCoins();
        mintStables();
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1e25;
        mintToken(address(VELO), owners, amounts);

        escrow = new VotingEscrow(address(forwarder), address(VELO), address(factoryRegistry));
        VeArtProxy artProxy = new VeArtProxy(address(escrow));
        escrow.setArtProxy(address(artProxy));
    }

    function createLock() public {
        deployBaseCoins();

        VELO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME);
        vm.roll(block.number + 1); // fwd 1 block because escrow.balanceOfNFT() returns 0 in same block
        assertGt(escrow.balanceOfNFT(1), 995063075414519385);
        assertEq(VELO.balanceOf(address(escrow)), TOKEN_1);
    }

    function votingEscrowMerge() public {
        createLock();

        VELO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME);
        skipAndRoll(1);
        assertGt(escrow.balanceOfNFT(2), 995063075414519385);
        assertEq(VELO.balanceOf(address(escrow)), 2 * TOKEN_1);
        escrow.merge(2, 1);
        assertGt(escrow.balanceOfNFT(1), 1990039602248405587);
        assertEq(escrow.balanceOfNFT(2), 0);
    }

    function confirmTokensForFraxUsdc() public {
        votingEscrowMerge();
        deployFactories();
        voter = new Voter(address(forwarder), address(escrow), address(factoryRegistry));
        router = new Router(address(forwarder), address(factory), address(voter), address(WETH));
        deployPairWithOwner(address(owner));

        (address token0, address token1) = router.sortTokens(address(USDC), address(FRAX));
        assertEq(pair.token0(), token0);
        assertEq(pair.token1(), token1);
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

    function deployVoter() public {
        routerAddLiquidity();

        voter = new Voter(address(forwarder), address(escrow), address(factoryRegistry));
        address[] memory tokens = new address[](4);
        tokens[0] = address(USDC);
        tokens[1] = address(FRAX);
        tokens[2] = address(DAI);
        tokens[3] = address(VELO);
        voter.initialize(tokens, address(owner));

        assertEq(voter.length(), 0);
    }

    function deployPairFactoryGauge() public {
        deployVoter();

        VELO.approve(address(gaugeFactory), 5 * TOKEN_100K);
        voter.createGauge(address(factory), address(votingRewardsFactory), address(gaugeFactory), address(pair3));
        assertFalse(voter.gauges(address(pair3)) == address(0));

        address gaugeAddr3 = voter.gauges(address(pair3));
        address feesVotingRewardAddr3 = voter.gaugeToFees(gaugeAddr3);

        gauge3 = Gauge(gaugeAddr3);

        feesVotingReward3 = FeesVotingReward(feesVotingRewardAddr3);
        uint256 total = pair3.balanceOf(address(owner));
        pair3.approve(address(gauge3), total);
        gauge3.deposit(total);
        assertEq(gauge3.totalSupply(), total);
        assertEq(gauge3.earned(address(owner)), 0);
    }

    function routerPair3GetAmountsOutAndSwapExactTokensForTokens() public {
        deployPairFactoryGauge();

        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route(address(FRAX), address(DAI), true, address(0));
        IRouter.Route[] memory routes2 = new IRouter.Route[](1);
        routes2[0] = IRouter.Route(address(DAI), address(FRAX), true, address(0));

        uint256 i;
        for (i = 0; i < 10; i++) {
            assertEq(router.getAmountsOut(TOKEN_1M, routes)[1], pair3.getAmountOut(TOKEN_1M, address(FRAX)));

            uint256[] memory expectedOutput = router.getAmountsOut(TOKEN_1M, routes);
            FRAX.approve(address(router), TOKEN_1M);
            router.swapExactTokensForTokens(TOKEN_1M, expectedOutput[1], routes, address(owner), block.timestamp);

            assertEq(router.getAmountsOut(TOKEN_1M, routes2)[1], pair3.getAmountOut(TOKEN_1M, address(DAI)));

            uint256[] memory expectedOutput2 = router.getAmountsOut(TOKEN_1M, routes2);
            DAI.approve(address(router), TOKEN_1M);
            router.swapExactTokensForTokens(TOKEN_1M, expectedOutput2[1], routes2, address(owner), block.timestamp);
        }
    }

    function voterReset() public {
        routerPair3GetAmountsOutAndSwapExactTokensForTokens();

        distributor = new RewardsDistributor(address(escrow));
        escrow.setVoterAndDistributor(address(voter), address(distributor));
        skip(1 hours);
        voter.reset(1);
    }

    function voterPokeSelf() public {
        voterReset();

        voter.poke(1);
    }

    function voterVoteAndFeesVotingRewardBalanceOf() public {
        voterPokeSelf();

        skipToNextEpoch(1 hours + 1);

        address[] memory pairs = new address[](2);
        pairs[0] = address(pair3);
        pairs[1] = address(pair2);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 5000;
        weights[1] = 5000;
        voter.vote(1, pairs, weights);
        assertFalse(voter.totalWeight() == 0);
        assertFalse(feesVotingReward3.balanceOf(1) == 0);
    }

    function feesVotingRewardClaimRewards() public {
        voterVoteAndFeesVotingRewardBalanceOf();

        address[] memory tokens = new address[](2);
        tokens[0] = address(FRAX);
        tokens[1] = address(DAI);
        feesVotingReward3.getReward(1, tokens);
        skip(8 days);
        vm.roll(block.number + 1);
        feesVotingReward3.getReward(1, tokens);
    }

    function distributeAndClaimFees() public {
        feesVotingRewardClaimRewards();

        skip(8 days);
        vm.roll(block.number + 1);
        address[] memory tokens = new address[](2);
        tokens[0] = address(FRAX);
        tokens[1] = address(DAI);
        feesVotingReward3.getReward(1, tokens);

        address[] memory gauges = new address[](1);
        gauges[0] = address(gauge3);
    }

    function testBribeClaimRewards() public {
        distributeAndClaimFees();

        console2.log(feesVotingReward3.earned(address(FRAX), 1));
        console2.log(FRAX.balanceOf(address(owner)));
        console2.log(FRAX.balanceOf(address(feesVotingReward3)));
        address[] memory tokens = new address[](2);
        tokens[0] = address(FRAX);
        tokens[1] = address(DAI);
        feesVotingReward3.getReward(1, tokens);
        skip(8 days);
        vm.roll(block.number + 1);
        console2.log(feesVotingReward3.earned(address(FRAX), 1));
        console2.log(FRAX.balanceOf(address(owner)));
        console2.log(FRAX.balanceOf(address(feesVotingReward3)));
        feesVotingReward3.getReward(1, tokens);
        console2.log(feesVotingReward3.earned(address(FRAX), 1));
        console2.log(FRAX.balanceOf(address(owner)));
        console2.log(FRAX.balanceOf(address(feesVotingReward3)));
    }
}

// 1:1 with Hardhat test
pragma solidity 0.8.13;

import "./BaseTest.sol";

contract PairTest is BaseTest {
    constructor() {
        deploymentType = Deployment.CUSTOM;
    }

    function deployPairCoins() public {
        skip(1 weeks);

        deployOwners();
        deployCoins();
        mintStables();
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 2e25;
        amounts[1] = 1e25;
        amounts[2] = 1e25;
        mintToken(address(VELO), owners, amounts);
        mintToken(address(LR), owners, amounts);
        deployFactories();

        VeArtProxy artProxy = new VeArtProxy();
        escrow = new VotingEscrow(address(VELO), address(artProxy), address(factoryRegistry), address(owner));
        distributor = new RewardsDistributor(address(escrow));
        voter = new Voter(address(escrow), address(factoryRegistry));
        router = new Router(address(factory), address(voter), address(WETH));

        escrow.setVoterAndDistributor(address(voter), address(distributor));
        factory.setVoter(address(voter));

        deployPairWithOwner(address(owner));
        deployPairWithOwner(address(owner2));
    }

    function createLock() public {
        deployPairCoins();

        VELO.approve(address(escrow), 5e17);
        escrow.createLock(5e17, MAXTIME);
        vm.roll(block.number + 1); // fwd 1 block because escrow.balanceOfNFT() returns 0 in same block
        assertGt(escrow.balanceOfNFT(1), 495063075414519385);
        assertEq(VELO.balanceOf(address(escrow)), 5e17);
    }

    function increaseLock() public {
        createLock();

        VELO.approve(address(escrow), 5e17);
        escrow.increaseAmount(1, 5e17);
        vm.expectRevert(abi.encodePacked("VotingEscrow: can only increase lock duration"));
        escrow.increaseUnlockTime(1, MAXTIME);
        assertGt(escrow.balanceOfNFT(1), 995063075414519385);
        assertEq(VELO.balanceOf(address(escrow)), TOKEN_1);
    }

    function votingEscrowViews() public {
        increaseLock();

        uint256 block_ = block.number;
        assertEq(escrow.balanceOfAtNFT(1, block_), escrow.balanceOfNFT(1));
        assertEq(escrow.totalSupplyAt(block_), escrow.totalSupply());

        assertGt(escrow.balanceOfNFT(1), 995063075414519385);
        assertEq(VELO.balanceOf(address(escrow)), TOKEN_1);
    }

    function stealNFT() public {
        votingEscrowViews();

        vm.startPrank(address(owner2));
        vm.expectRevert();
        escrow.transferFrom(address(owner), address(owner2), 1);
        vm.expectRevert();
        escrow.approve(address(owner2), 1);
        vm.expectRevert("VotingEscrow: invalid permissions (from)");
        escrow.merge(1, 2);
        vm.stopPrank();
    }

    function votingEscrowMerge() public {
        stealNFT();

        VELO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME);
        assertGt(escrow.balanceOfNFT(2), 995063075414519385);
        assertEq(VELO.balanceOf(address(escrow)), 2 * TOKEN_1);

        escrow.merge(2, 1);
        assertGt(escrow.balanceOfNFT(1), 1990063075414519385);
        assertEq(escrow.balanceOfNFT(2), 0);

        IVotingEscrow.LockedBalance memory locked;

        locked = escrow.locked(2);
        assertEq(locked.amount, 0);
        assertEq(escrow.ownerOf(2), address(0));

        VELO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME);
        assertGt(escrow.balanceOfNFT(3), 995063075414519385);
        assertEq(VELO.balanceOf(address(escrow)), 3 * TOKEN_1);

        escrow.merge(3, 1);
        assertGt(escrow.balanceOfNFT(1), 1990063075414519385);
        assertEq(escrow.balanceOfNFT(3), 0);

        locked = escrow.locked(3);
        assertEq(locked.amount, 0);
        assertEq(escrow.ownerOf(3), address(0));
    }

    function confirmTokensForFraxUsdc() public {
        votingEscrowMerge();

        (address token0, address token1) = router.sortTokens(address(USDC), address(FRAX));
        assertEq(pair.token0(), token0);
        assertEq(pair.token1(), token1);
    }

    function mintAndBurnTokensForPairFraxUsdc() public {
        confirmTokensForFraxUsdc();

        USDC.transfer(address(pair), USDC_1);
        FRAX.transfer(address(pair), TOKEN_1);
        pair.mint(address(owner));
        assertEq(pair.getAmountOut(USDC_1, address(USDC)), 982117769725505988);
    }

    function mintAndBurnTokensForPairFraxUsdcOwner2() public {
        mintAndBurnTokensForPairFraxUsdc();

        vm.startPrank(address(owner2));
        USDC.transfer(address(pair), USDC_1);
        FRAX.transfer(address(pair), TOKEN_1);
        pair.mint(address(owner2));
        vm.stopPrank();

        assertEq(pair.getAmountOut(USDC_1, address(USDC)), 992220948146798746);
    }

    function routerAddLiquidity() public {
        mintAndBurnTokensForPairFraxUsdcOwner2();

        _addLiquidityToPool(address(owner), address(router), address(USDC), address(FRAX), true, USDC_100K, TOKEN_100K);
        _addLiquidityToPool(
            address(owner),
            address(router),
            address(USDC),
            address(FRAX),
            false,
            USDC_100K,
            TOKEN_100K
        );
        _addLiquidityToPool(address(owner), address(router), address(DAI), address(FRAX), true, TOKEN_100M, TOKEN_100M);
    }

    function routerRemoveLiquidity() public {
        routerAddLiquidity();

        USDC.approve(address(router), USDC_100K);
        FRAX.approve(address(router), TOKEN_100K);
        router.quoteAddLiquidity(address(FRAX), address(USDC), true, address(factory), TOKEN_100K, USDC_100K);
        router.quoteRemoveLiquidity(address(FRAX), address(USDC), true, address(factory), USDC_100K);
    }

    function routerAddLiquidityOwner2() public {
        routerRemoveLiquidity();

        _addLiquidityToPool(
            address(owner2),
            address(router),
            address(USDC),
            address(FRAX),
            true,
            USDC_100K,
            TOKEN_100K
        );
        _addLiquidityToPool(
            address(owner2),
            address(router),
            address(USDC),
            address(FRAX),
            false,
            USDC_100K,
            TOKEN_100K
        );
        _addLiquidityToPool(
            address(owner2),
            address(router),
            address(DAI),
            address(FRAX),
            true,
            TOKEN_100M,
            TOKEN_100M
        );
    }

    function routerPair1GetAmountsOutAndSwapExactTokensForTokens() public {
        routerAddLiquidityOwner2();

        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route(address(USDC), address(FRAX), true, address(0));

        assertEq(router.getAmountsOut(USDC_1, routes)[1], pair.getAmountOut(USDC_1, address(USDC)));

        uint256[] memory assertedOutput = router.getAmountsOut(USDC_1, routes);
        USDC.approve(address(router), USDC_1);
        router.swapExactTokensForTokens(USDC_1, assertedOutput[1], routes, address(owner), block.timestamp);
        skip(1801);
        vm.roll(block.number + 1);
        address pairFees = pair.pairFees();
        assertEq(USDC.balanceOf(pairFees), 100);
        uint256 b = USDC.balanceOf(address(owner));
        pair.claimFees();
        assertGt(USDC.balanceOf(address(owner)), b);
    }

    function routerPair1GetAmountsOutAndSwapExactTokensForTokensOwner2() public {
        routerPair1GetAmountsOutAndSwapExactTokensForTokens();

        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route(address(USDC), address(FRAX), true, address(0));

        assertEq(router.getAmountsOut(USDC_1, routes)[1], pair.getAmountOut(USDC_1, address(USDC)));

        uint256[] memory expectedOutput = router.getAmountsOut(USDC_1, routes);
        vm.startPrank(address(owner2));
        owner2.approve(address(USDC), address(router), USDC_1);
        router.swapExactTokensForTokens(USDC_1, expectedOutput[1], routes, address(owner2), block.timestamp);
        vm.stopPrank();
        address pairFees = pair.pairFees();
        assertEq(USDC.balanceOf(pairFees), 101);
        uint256 b = USDC.balanceOf(address(owner));
        vm.prank(address(owner2));
        pair.claimFees();
        assertEq(USDC.balanceOf(address(owner)), b);
    }

    function routerPair2GetAmountsOutAndSwapExactTokensForTokens() public {
        routerPair1GetAmountsOutAndSwapExactTokensForTokensOwner2();

        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route(address(USDC), address(FRAX), false, address(0));

        assertEq(router.getAmountsOut(USDC_1, routes)[1], pair2.getAmountOut(USDC_1, address(USDC)));

        uint256[] memory expectedOutput = router.getAmountsOut(USDC_1, routes);
        USDC.approve(address(router), USDC_1);
        router.swapExactTokensForTokens(USDC_1, expectedOutput[1], routes, address(owner), block.timestamp);
    }

    function routerPair3GetAmountsOutAndSwapExactTokensForTokens() public {
        routerPair2GetAmountsOutAndSwapExactTokensForTokens();

        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route(address(FRAX), address(DAI), true, address(0));

        assertEq(router.getAmountsOut(TOKEN_1M, routes)[1], pair3.getAmountOut(TOKEN_1M, address(FRAX)));

        uint256[] memory expectedOutput = router.getAmountsOut(TOKEN_1M, routes);
        FRAX.approve(address(router), TOKEN_1M);
        router.swapExactTokensForTokens(TOKEN_1M, expectedOutput[1], routes, address(owner), block.timestamp);
    }

    function deployMinter() public {
        routerAddLiquidity();

        distributor = new RewardsDistributor(address(escrow));

        minter = new Minter(address(voter), address(escrow), address(distributor));
        distributor.setDepositor(address(minter));
        VELO.setMinter(address(minter));
        address[] memory tokens = new address[](5);
        tokens[0] = address(USDC);
        tokens[1] = address(FRAX);
        tokens[2] = address(DAI);
        tokens[3] = address(VELO);
        tokens[4] = address(LR);
        voter.initialize(tokens, address(minter));
    }

    function deployPairFactoryGauge() public {
        deployMinter();

        VELO.approve(address(gaugeFactory), 15 * TOKEN_100K);
        voter.createGauge(address(factory), address(votingRewardsFactory), address(gaugeFactory), address(pair));
        voter.createGauge(address(factory), address(votingRewardsFactory), address(gaugeFactory), address(pair2));
        voter.createGauge(address(factory), address(votingRewardsFactory), address(gaugeFactory), address(pair3));
        assertFalse(voter.gauges(address(pair)) == address(0));

        address gaugeAddress = voter.gauges(address(pair));
        address feesVotingRewardAddress = voter.gaugeToFees(gaugeAddress);
        address bribeVotingRewardAddress = voter.gaugeToBribe(gaugeAddress);

        address gaugeAddress2 = voter.gauges(address(pair2));
        address feesVotingRewardAddress2 = voter.gaugeToFees(gaugeAddress2);

        address gaugeAddress3 = voter.gauges(address(pair3));
        address feesVotingRewardAddress3 = voter.gaugeToFees(gaugeAddress3);

        gauge = Gauge(gaugeAddress);
        gauge2 = Gauge(gaugeAddress2);
        gauge3 = Gauge(gaugeAddress3);

        feesVotingReward = FeesVotingReward(feesVotingRewardAddress);
        bribeVotingReward = BribeVotingReward(bribeVotingRewardAddress);
        feesVotingReward2 = FeesVotingReward(feesVotingRewardAddress2);
        feesVotingReward3 = FeesVotingReward(feesVotingRewardAddress3);

        pair.approve(address(gauge), PAIR_1);
        pair2.approve(address(gauge2), PAIR_1);
        pair3.approve(address(gauge3), PAIR_1);
        gauge.deposit(PAIR_1);
        gauge2.deposit(PAIR_1);
        gauge3.deposit(PAIR_1);
        assertEq(gauge.totalSupply(), PAIR_1);
        assertEq(gauge.earned(address(owner)), 0);
    }

    function deployPairFactoryGaugeOwner2() public {
        deployPairFactoryGauge();

        owner2.approve(address(pair), address(gauge), PAIR_1);
        owner2.deposit(address(gauge), PAIR_1);
        assertEq(gauge.totalSupply(), 2 * PAIR_1);
        assertEq(gauge.earned(address(owner2)), 0);
    }

    function withdrawGaugeStake() public {
        deployPairFactoryGaugeOwner2();

        gauge.withdraw(gauge.balanceOf(address(owner)));
        owner2.withdrawGauge(address(gauge), gauge.balanceOf(address(owner2)));
        gauge2.withdraw(gauge2.balanceOf(address(owner)));
        gauge3.withdraw(gauge3.balanceOf(address(owner)));
        assertEq(gauge.totalSupply(), 0);
        assertEq(gauge2.totalSupply(), 0);
        assertEq(gauge3.totalSupply(), 0);
    }

    function addGaugeAndVotingRewards() public {
        withdrawGaugeStake();

        _addRewardToGauge(address(voter), address(gauge), PAIR_1);

        VELO.approve(address(bribeVotingReward), PAIR_1);

        bribeVotingReward.notifyRewardAmount(address(VELO), PAIR_1);

        assertEq(gauge.rewardRate(), 1653);
    }

    function exitAndGetRewardGaugeStake() public {
        addGaugeAndVotingRewards();

        uint256 supply = pair.balanceOf(address(owner));
        pair.approve(address(gauge), supply);
        gauge.deposit(supply);
        gauge.withdraw(gauge.balanceOf(address(owner)));
        assertEq(gauge.totalSupply(), 0);
        pair.approve(address(gauge), supply);
        gauge.deposit(PAIR_1);
    }

    function voterReset() public {
        exitAndGetRewardGaugeStake();

        skip(1 weeks);
        voter.reset(1);
    }

    function voterPokeSelf() public {
        voterReset();

        voter.poke(1);
    }

    function createLock2() public {
        voterPokeSelf();

        VELO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME);
        skip(1);
        assertGt(escrow.balanceOfNFT(1), 995063075414519385);
        assertEq(VELO.balanceOf(address(escrow)), 4 * TOKEN_1);
    }

    function voteHacking() public {
        createLock2();

        address[] memory pools = new address[](1);
        pools[0] = address(pair);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 5000;
        skip(1 weeks + 1 hours + 1);

        voter.vote(1, pools, weights);
        assertEq(voter.usedWeights(1), escrow.balanceOfNFT(1)); // within 1000
        assertEq(feesVotingReward.balanceOf(1), uint256(voter.votes(1, address(pair))));
        skip(1 weeks);

        voter.reset(1);
        assertLt(voter.usedWeights(1), escrow.balanceOfNFT(1));
        assertEq(voter.usedWeights(1), 0);
        assertEq(feesVotingReward.balanceOf(1), uint256(voter.votes(1, address(pair))));
        assertEq(feesVotingReward.balanceOf(1), 0);
    }

    function gaugePokeHacking() public {
        voteHacking();

        assertEq(voter.usedWeights(1), 0);
        assertEq(voter.votes(1, address(pair)), 0);
        voter.poke(1);
        assertEq(voter.usedWeights(1), 0);
        assertEq(voter.votes(1, address(pair)), 0);
    }

    function gaugeVoteAndBribeBalanceOf() public {
        gaugePokeHacking();

        address[] memory pools = new address[](2);
        pools[0] = address(pair);
        pools[1] = address(pair2);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 5000;
        weights[1] = 5000;
        skip(1 weeks + 1 hours + 1);

        voter.vote(1, pools, weights);
        weights[0] = 50000;
        weights[1] = 50000;

        voter.vote(4, pools, weights);
        assertFalse(voter.totalWeight() == 0);
        assertFalse(feesVotingReward.balanceOf(1) == 0);
    }

    function gaugePokeHacking2() public {
        gaugeVoteAndBribeBalanceOf();

        uint256 weightBefore = voter.usedWeights(1);
        uint256 votesBefore = voter.votes(1, address(pair));
        voter.poke(1);
        assertEq(voter.usedWeights(1), weightBefore);
        assertEq(voter.votes(1, address(pair)), votesBefore);
    }

    function voteHackingBreakMint() public {
        gaugePokeHacking2();

        address[] memory pools = new address[](2);
        pools[0] = address(pair);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 5000;
        skip(1 weeks);

        voter.vote(1, pools, weights);

        assertEq(voter.usedWeights(1), escrow.balanceOfNFT(1)); // within 1000
        assertEq(feesVotingReward.balanceOf(1), uint256(voter.votes(1, address(pair))));
    }

    function gaugePokeHacking3() public {
        voteHackingBreakMint();

        assertEq(voter.usedWeights(1), uint256(voter.votes(1, address(pair))));
        voter.poke(1);
        assertEq(voter.usedWeights(1), uint256(voter.votes(1, address(pair))));
    }

    function gaugeDistributeBasedOnVoting() public {
        gaugePokeHacking3();

        deal(address(VELO), address(minter), PAIR_1);

        vm.startPrank(address(minter));
        VELO.approve(address(voter), PAIR_1);
        voter.notifyRewardAmount(PAIR_1);
        vm.stopPrank();

        voter.updateFor(0, voter.length());
        voter.distribute(0, voter.length());
    }

    function feesVotingRewardClaimRewards() public {
        gaugeDistributeBasedOnVoting();

        address[] memory rewards = new address[](1);
        rewards[0] = address(VELO);
        feesVotingReward.getReward(1, rewards);
        skip(8 days);
        vm.roll(block.number + 1);
        feesVotingReward.getReward(1, rewards);
    }

    function routerPair1GetAmountsOutAndSwapExactTokensForTokens2() public {
        feesVotingRewardClaimRewards();

        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route(address(USDC), address(FRAX), true, address(0));

        uint256[] memory expectedOutput = router.getAmountsOut(USDC_1, routes);
        USDC.approve(address(router), USDC_1);
        router.swapExactTokensForTokens(USDC_1, expectedOutput[1], routes, address(owner), block.timestamp);
    }

    function routerPair2GetAmountsOutAndSwapExactTokensForTokens2() public {
        routerPair1GetAmountsOutAndSwapExactTokensForTokens2();

        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route(address(USDC), address(FRAX), false, address(0));

        uint256[] memory expectedOutput = router.getAmountsOut(USDC_1, routes);
        USDC.approve(address(router), USDC_1);
        router.swapExactTokensForTokens(USDC_1, expectedOutput[1], routes, address(owner), block.timestamp);
    }

    function routerPair1GetAmountsOutAndSwapExactTokensForTokens2Again() public {
        routerPair2GetAmountsOutAndSwapExactTokensForTokens2();

        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route(address(FRAX), address(USDC), false, address(0));

        uint256[] memory expectedOutput = router.getAmountsOut(TOKEN_1, routes);
        FRAX.approve(address(router), TOKEN_1);
        router.swapExactTokensForTokens(TOKEN_1, expectedOutput[1], routes, address(owner), block.timestamp);
    }

    function routerPair2GetAmountsOutAndSwapExactTokensForTokens2Again() public {
        routerPair1GetAmountsOutAndSwapExactTokensForTokens2Again();

        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route(address(FRAX), address(USDC), false, address(0));

        uint256[] memory expectedOutput = router.getAmountsOut(TOKEN_1, routes);
        FRAX.approve(address(router), TOKEN_1);
        router.swapExactTokensForTokens(TOKEN_1, expectedOutput[1], routes, address(owner), block.timestamp);
    }

    function routerPair1Pair2GetAmountsOutAndSwapExactTokensForTokens() public {
        routerPair2GetAmountsOutAndSwapExactTokensForTokens2Again();

        IRouter.Route[] memory route = new IRouter.Route[](2);
        route[0] = IRouter.Route(address(FRAX), address(USDC), false, address(0));
        route[1] = IRouter.Route(address(USDC), address(FRAX), true, address(0));

        uint256 before = FRAX.balanceOf(address(owner)) - TOKEN_1;

        uint256[] memory expectedOutput = router.getAmountsOut(TOKEN_1, route);
        FRAX.approve(address(router), TOKEN_1);
        router.swapExactTokensForTokens(TOKEN_1, expectedOutput[2], route, address(owner), block.timestamp);
        uint256 after_ = FRAX.balanceOf(address(owner));
        assertEq(after_ - before, expectedOutput[2]);
    }

    function distributeAndClaimFees() public {
        routerPair1Pair2GetAmountsOutAndSwapExactTokensForTokens();

        skip(8 days);
        vm.roll(block.number + 1);
        address[] memory rewards = new address[](2);
        rewards[0] = address(FRAX);
        rewards[1] = address(USDC);
        feesVotingReward.getReward(1, rewards);

        address[] memory gauges = new address[](1);
        gauges[0] = address(gauge);
        voter.distributeFees(gauges);
    }

    function minterMint() public {
        distributeAndClaimFees();

        minter.update_period();
        voter.updateFor(address(gauge));
        voter.distribute(0, voter.length());
        skip(30 minutes);
        vm.roll(block.number + 1);
    }

    function gaugeClaimRewards() public {
        minterMint();

        assertEq(address(owner), escrow.ownerOf(1));
        assertTrue(escrow.isApprovedOrOwner(address(owner), 1));
        gauge.withdraw(gauge.balanceOf(address(owner)));
        skip(1);
        pair.approve(address(gauge), PAIR_1);
        skip(1);
        gauge.deposit(PAIR_1);
        skip(1);
        uint256 before = VELO.balanceOf(address(owner));
        skip(1);
        uint256 earned = gauge.earned(address(owner));
        gauge.getReward(address(owner));
        skip(1);
        uint256 after_ = VELO.balanceOf(address(owner));
        uint256 received = after_ - before;
        assertEq(earned, received);

        gauge.withdraw(gauge.balanceOf(address(owner)));
        pair.approve(address(gauge), PAIR_1);
        gauge.deposit(PAIR_1);
        gauge.getReward(address(owner));
        gauge.withdraw(gauge.balanceOf(address(owner)));
        pair.approve(address(gauge), PAIR_1);
        gauge.deposit(PAIR_1);
        gauge.getReward(address(owner));
        gauge.withdraw(gauge.balanceOf(address(owner)));
        pair.approve(address(gauge), PAIR_1);
        gauge.deposit(PAIR_1);
        gauge.getReward(address(owner));
        gauge.withdraw(gauge.balanceOf(address(owner)));
        pair.approve(address(gauge), PAIR_1);
        gauge.deposit(PAIR_1);
        gauge.getReward(address(owner));
        gauge.withdraw(gauge.balanceOf(address(owner)));
        pair.approve(address(gauge), PAIR_1);
        gauge.deposit(PAIR_1);
        gauge.getReward(address(owner));
        gauge.withdraw(gauge.balanceOf(address(owner)));
        pair.approve(address(gauge), PAIR_1);
        gauge.deposit(PAIR_1);
        gauge.getReward(address(owner));
        skip(1 weeks);
        vm.roll(block.number + 1);
        gauge.getReward(address(owner));
        gauge.withdraw(gauge.balanceOf(address(owner)));
    }

    function gaugeClaimRewardsAfterExpiry() public {
        gaugeClaimRewards();

        pair.approve(address(gauge), PAIR_1);
        gauge.deposit(PAIR_1);
        gauge.getReward(address(owner));
        gauge.withdraw(gauge.balanceOf(address(owner)));
        pair.approve(address(gauge), PAIR_1);
        gauge.deposit(PAIR_1);
        gauge.getReward(address(owner));
        gauge.withdraw(gauge.balanceOf(address(owner)));
        pair.approve(address(gauge), PAIR_1);
        gauge.deposit(PAIR_1);
        gauge.getReward(address(owner));
        gauge.withdraw(gauge.balanceOf(address(owner)));
        pair.approve(address(gauge), PAIR_1);
        gauge.deposit(PAIR_1);
        gauge.getReward(address(owner));
        gauge.withdraw(gauge.balanceOf(address(owner)));
        pair.approve(address(gauge), PAIR_1);
        gauge.deposit(PAIR_1);
        gauge.getReward(address(owner));
        gauge.withdraw(gauge.balanceOf(address(owner)));
        pair.approve(address(gauge), PAIR_1);
        gauge.deposit(PAIR_1);
        gauge.getReward(address(owner));
        gauge.withdraw(gauge.balanceOf(address(owner)));
        pair.approve(address(gauge), PAIR_1);
        gauge.deposit(PAIR_1);
        gauge.getReward(address(owner));
        skip(1 weeks);
        vm.roll(block.number + 1);
        gauge.getReward(address(owner));
        gauge.withdraw(gauge.balanceOf(address(owner)));
    }

    function votingEscrowDecay() public {
        gaugeClaimRewardsAfterExpiry();

        address[] memory feesVotingRewards_ = new address[](1);
        feesVotingRewards_[0] = address(feesVotingReward);
        address[][] memory rewards = new address[][](1);
        address[] memory reward = new address[](1);
        reward[0] = address(DAI);
        rewards[0] = reward;
        voter.claimBribes(feesVotingRewards_, rewards, 1);
        voter.claimFees(feesVotingRewards_, rewards, 1);
        uint256 supply = escrow.totalSupply();
        assertGt(supply, 0);
        skip(MAXTIME);
        vm.roll(block.number + 1);
        assertEq(escrow.balanceOfNFT(1), 0);
        assertEq(escrow.totalSupply(), 0);
        skip(1 weeks);

        voter.reset(1);
        escrow.withdraw(1);
    }

    function routerAddLiquidityOwner3() public {
        votingEscrowDecay();

        _addLiquidityToPool(address(owner3), address(router), address(USDC), address(FRAX), true, 1e12, TOKEN_1M);
    }

    function deployPairFactoryGaugeOwner3() public {
        routerAddLiquidityOwner3();

        owner3.approve(address(pair), address(gauge), PAIR_1);
        owner3.deposit(address(gauge), PAIR_1);
    }

    function gaugeClaimRewardsOwner3() public {
        deployPairFactoryGaugeOwner3();

        owner3.withdrawGauge(address(gauge), gauge.balanceOf(address(owner3)));
        owner3.approve(address(pair), address(gauge), PAIR_1);
        owner3.deposit(address(gauge), PAIR_1);
        owner3.withdrawGauge(address(gauge), gauge.balanceOf(address(owner3)));
        owner3.approve(address(pair), address(gauge), PAIR_1);
        owner3.deposit(address(gauge), PAIR_1);

        owner3.getGaugeReward(address(gauge), address(owner3));
        owner3.withdrawGauge(address(gauge), gauge.balanceOf(address(owner3)));
        owner3.approve(address(pair), address(gauge), PAIR_1);
        owner3.deposit(address(gauge), PAIR_1);
        owner3.getGaugeReward(address(gauge), address(owner3));
        owner3.withdrawGauge(address(gauge), gauge.balanceOf(address(owner3)));
        owner3.approve(address(pair), address(gauge), PAIR_1);
        owner3.deposit(address(gauge), PAIR_1);
        owner3.getGaugeReward(address(gauge), address(owner3));
        owner3.getGaugeReward(address(gauge), address(owner3));
        owner3.getGaugeReward(address(gauge), address(owner3));
        owner3.getGaugeReward(address(gauge), address(owner3));

        owner3.withdrawGauge(address(gauge), gauge.balanceOf(address(owner)));
        owner3.approve(address(pair), address(gauge), PAIR_1);
        owner3.deposit(address(gauge), PAIR_1);
        owner3.getGaugeReward(address(gauge), address(owner3));
    }

    function minterMint2() public {
        gaugeClaimRewardsOwner3();

        skip(2 weeks);
        vm.roll(block.number + 1);
        minter.update_period();
        voter.updateFor(address(gauge));
        address[] memory gauges = new address[](1);
        gauges[0] = address(gauge);
        voter.updateFor(gauges);
        voter.distribute(0, voter.length());
        voter.claimRewards(gauges);
        assertEq(gauge.rewardRate(), 94981974648214908710);
        console2.log(gauge.rewardPerTokenStored());
    }

    function gaugeClaimRewardsOwner3NextCycle() public {
        minterMint2();

        owner3.withdrawGauge(address(gauge), gauge.balanceOf(address(owner3)));
        owner3.approve(address(pair), address(gauge), PAIR_1);
        owner3.deposit(address(gauge), PAIR_1);
        uint256 before = VELO.balanceOf(address(owner3));
        skip(1);
        owner3.getGaugeReward(address(gauge), address(owner3));
        uint256 after_ = VELO.balanceOf(address(owner3));
        uint256 received = after_ - before;
        assertGt(received, 0);

        owner3.withdrawGauge(address(gauge), gauge.balanceOf(address(owner)));
        owner3.approve(address(pair), address(gauge), PAIR_1);
        owner3.deposit(address(gauge), PAIR_1);
        owner3.getGaugeReward(address(gauge), address(owner3));
    }

    function testGaugeClaimRewards2() public {
        gaugeClaimRewardsOwner3NextCycle();

        pair.approve(address(gauge), PAIR_1);
        gauge.deposit(PAIR_1);

        _addRewardToGauge(address(voter), address(gauge), TOKEN_1);

        skip(1 weeks);
        vm.roll(block.number + 1);
        gauge.getReward(address(owner));
        gauge.withdraw(gauge.balanceOf(address(owner)));
    }

    function testSetPairName() external {
        // Note: as this contract is a custom setup, the pair contracts are not already deployed from
        // base setup, and so they need to be deployed for these tests
        deployPairCoins();

        assertEq(pair.name(), "StableV2 AMM - FRAX/USDC");
        pair.setName("Some new name");
        assertEq(pair.name(), "Some new name");
    }

    function testCannotSetPairNameIfNotEmergencyCouncil() external {
        deployPairCoins();

        vm.prank(address(owner2));
        vm.expectRevert("Pair: not emergency council");
        pair.setName("Some new name");
    }

    function testSetPairSymbol() external {
        deployPairCoins();

        assertEq(pair.symbol(), "sAMMV2-FRAX/USDC");
        pair.setSymbol("Some new symbol");
        assertEq(pair.symbol(), "Some new symbol");
    }

    function testCannotSetPairSymbolIfNotEmergencyCouncil() external {
        deployPairCoins();

        vm.prank(address(owner2));
        vm.expectRevert("Pair: not emergency council");
        pair.setSymbol("Some new symbol");
    }
}

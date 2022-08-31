pragma solidity 0.8.13;

import "./BaseTest.sol";

/// @dev Tests factory registry functionality.
contract FactoryRegistryTest is BaseTest {
    PairFactory factory2;
    GaugeFactory gaugeFactory2;
    VotingRewardsFactory votingRewardsFactory2;
    FactoryRegistry factoryRegistry2;
    Router router2;
    Pair newPair;
    Pair newPair2;

    function _setUp() public override {
        // create new factories to test against factory registry
        factory2 = new PairFactory();
        assertEq(factory2.allPairsLength(), 0);
        factory2.setFee(true, 1); // set fee back to 0.01% for old tests
        factory2.setFee(false, 1);
        router2 = new Router(address(factory2), address(voter), address(WETH));
        assertEq(address(router2.defaultFactory()), address(factory2));

        votingRewardsFactory2 = new VotingRewardsFactory();
        gaugeFactory2 = new GaugeFactory();
        factoryRegistry2 = new FactoryRegistry(
            address(factory2),
            address(votingRewardsFactory),
            address(gaugeFactory),
            address(managedRewardsFactory)
        );

        // we need to create a new pair with the old factory to create the gauge
        // as existing pairs already have gauges
        _addLiquidityToPool(address(owner), address(router), address(DAI), address(USDC), true, TOKEN_1, USDC_1);
        address create2Address = router.pairFor(address(DAI), address(USDC), true, address(0));
        newPair = Pair(factory.getPair(address(DAI), address(USDC), true));
        assertEq(create2Address, address(newPair));

        // create a new pair with new factory / router to test gauge creation against
        _addLiquidityToPool(address(owner), address(router2), address(DAI), address(USDC), true, TOKEN_1, USDC_1);
        create2Address = router2.pairFor(address(DAI), address(USDC), true, address(0));
        newPair2 = Pair(factory2.getPair(address(DAI), address(USDC), true));
        assertEq(create2Address, address(newPair2));
    }

    function testCannotUnapproveFallbackFactories() external {
        vm.expectRevert("FactoryRegistry: Cannot delete the fallback route");
        factoryRegistry.unapprove(address(factory), address(votingRewardsFactory), address(gaugeFactory));
    }

    function testCannotUnapproveNonExistentPath() external {
        vm.expectRevert("FactoryRegistry: not approved");
        factoryRegistry.unapprove(address(factory2), address(votingRewardsFactory), address(gaugeFactory));
    }

    function testCannotCreateGaugeWithUnauthorizedFactory() external {
        // expect revert if creating a gauge with an unpproved factory
        vm.startPrank(address(governor));
        vm.expectRevert("Voter: factory path not approved");
        voter.createGauge(
            address(factory2), // bad factory
            address(votingRewardsFactory),
            address(gaugeFactory),
            address(newPair)
        );
        vm.expectRevert("Voter: factory path not approved");
        voter.createGauge(
            address(factory),
            address(votingRewardsFactory2), // bad factory
            address(gaugeFactory),
            address(newPair)
        );
        vm.expectRevert("Voter: factory path not approved");
        voter.createGauge(
            address(factory),
            address(votingRewardsFactory),
            address(gaugeFactory2), // bad factory
            address(newPair)
        );
        vm.stopPrank();
    }

    function testCannotApproveSameFactoryPathTwice() external {
        vm.expectRevert("FactoryRegistry: already approved");
        factoryRegistry.approve(address(factory), address(votingRewardsFactory), address(gaugeFactory));
    }

    function testApprove() external {
        assertEq(
            factoryRegistry.isApproved(address(factory2), address(votingRewardsFactory), address(gaugeFactory)),
            false
        );
        factoryRegistry.approve(
            address(factory2), // new factory
            address(votingRewardsFactory),
            address(gaugeFactory)
        );
        assertEq(
            factoryRegistry.isApproved(address(factory2), address(votingRewardsFactory), address(gaugeFactory)),
            true
        );

        assertEq(
            factoryRegistry.isApproved(address(factory), address(votingRewardsFactory2), address(gaugeFactory)),
            false
        );
        factoryRegistry.approve(
            address(factory),
            address(votingRewardsFactory2), // new factory
            address(gaugeFactory)
        );
        assertEq(
            factoryRegistry.isApproved(address(factory), address(votingRewardsFactory2), address(gaugeFactory)),
            true
        );

        assertEq(
            factoryRegistry.isApproved(address(factory), address(votingRewardsFactory), address(gaugeFactory2)),
            false
        );
        factoryRegistry.approve(
            address(factory),
            address(votingRewardsFactory),
            address(gaugeFactory2) // new factory
        );
        assertEq(
            factoryRegistry.isApproved(address(factory), address(votingRewardsFactory), address(gaugeFactory2)),
            true
        );

        assertEq(
            factoryRegistry.isApproved(address(factory), address(votingRewardsFactory2), address(gaugeFactory2)),
            false
        );
        factoryRegistry.approve(
            address(factory),
            address(votingRewardsFactory2), // new factory
            address(gaugeFactory2) // new factory
        );
        assertEq(
            factoryRegistry.isApproved(address(factory), address(votingRewardsFactory2), address(gaugeFactory2)),
            true
        );

        assertEq(
            factoryRegistry.isApproved(address(factory2), address(votingRewardsFactory2), address(gaugeFactory)),
            false
        );
        factoryRegistry.approve(
            address(factory2), // new factory
            address(votingRewardsFactory2), // new factory
            address(gaugeFactory)
        );
        assertEq(
            factoryRegistry.isApproved(address(factory2), address(votingRewardsFactory2), address(gaugeFactory)),
            true
        );

        assertEq(
            factoryRegistry.isApproved(address(factory2), address(votingRewardsFactory), address(gaugeFactory2)),
            false
        );
        factoryRegistry.approve(
            address(factory2), // new factory
            address(votingRewardsFactory),
            address(gaugeFactory2) // new factory
        );
        assertEq(
            factoryRegistry.isApproved(address(factory2), address(votingRewardsFactory), address(gaugeFactory2)),
            true
        );

        assertEq(
            factoryRegistry.isApproved(address(factory2), address(votingRewardsFactory2), address(gaugeFactory2)),
            false
        );
        factoryRegistry.approve(
            address(factory2), // new factory
            address(votingRewardsFactory2), // new factory
            address(gaugeFactory2) // new factory
        );
        assertEq(
            factoryRegistry.isApproved(address(factory2), address(votingRewardsFactory2), address(gaugeFactory2)),
            true
        );
    }

    function testUnapprove() external {
        assertEq(
            factoryRegistry.isApproved(address(factory2), address(votingRewardsFactory), address(gaugeFactory)),
            false
        );
        factoryRegistry.approve(
            address(factory2), // new factory
            address(votingRewardsFactory),
            address(gaugeFactory)
        );
        assertEq(
            factoryRegistry.isApproved(address(factory2), address(votingRewardsFactory), address(gaugeFactory)),
            true
        );
        factoryRegistry.unapprove(
            address(factory2), // new factory
            address(votingRewardsFactory),
            address(gaugeFactory)
        );
        assertEq(
            factoryRegistry.isApproved(address(factory2), address(votingRewardsFactory), address(gaugeFactory)),
            false
        );
    }

    function testCreateGaugeWithNewPairFactory() external {
        // approve the new factory for use
        factoryRegistry.approve(
            address(factory2), // new factory
            address(votingRewardsFactory),
            address(gaugeFactory)
        );

        // use pair2 (created using factory2), or else isPair() voter.createGauge() fails
        address newGauge = voter.createGauge(
            address(factory2), // new factory
            address(votingRewardsFactory),
            address(gaugeFactory),
            address(newPair2)
        );
        address newFeesVotingReward = voter.gaugeToFees(newGauge);
        address newBribeVotingReward = voter.gaugeToBribe(newGauge);

        // ensure that the contracts created are not address(0)
        assertGt(uint256(uint160(newGauge)), 0);
        assertGt(uint256(uint160(newFeesVotingReward)), 0);
        assertGt(uint256(uint160(newBribeVotingReward)), 0);

        // voting reward validation
        address token0 = newPair2.token0();
        assertTrue(Reward(newFeesVotingReward).isReward(token0));
        assertTrue(Reward(newBribeVotingReward).isReward(token0));
        address token1 = newPair2.token1();
        assertTrue(Reward(newFeesVotingReward).isReward(token1));
        assertTrue(Reward(newBribeVotingReward).isReward(token1));

        // gauge validation
        assertEq(address(newPair2), Gauge(newGauge).stakingToken());
        assertEq(newFeesVotingReward, Gauge(newGauge).feesVotingReward());
        assertEq(address(VELO), Gauge(newGauge).rewardToken());
        assertEq(address(voter), Gauge(newGauge).voter());
        assertTrue(Gauge(newGauge).isForPair());

        // gauge checks within voter
        assertEq(newGauge, voter.gauges(address(newPair2)));
        assertEq(address(newPair2), voter.poolForGauge(newGauge));
        assertTrue(voter.isGauge(newGauge));
        assertTrue(voter.isAlive(newGauge));
    }

    function testCreateGaugeWithNewVotingRewardsFactory() external {
        // approve the new factory for use
        factoryRegistry.approve(
            address(factory),
            address(votingRewardsFactory2), // new factory
            address(gaugeFactory)
        );

        address newGauge = voter.createGauge(
            address(factory),
            address(votingRewardsFactory2), // new factory
            address(gaugeFactory),
            address(newPair)
        );
        address newFeesVotingReward = voter.gaugeToFees(newGauge);
        address newBribeVotingReward = voter.gaugeToBribe(newGauge);

        // ensure that the contracts created are not address(0)
        assertGt(uint256(uint160(newGauge)), 0);
        assertGt(uint256(uint160(newFeesVotingReward)), 0);
        assertGt(uint256(uint160(newBribeVotingReward)), 0);

        // voting validation
        address token0 = newPair.token0();
        assertTrue(Reward(newFeesVotingReward).isReward(token0));
        assertTrue(Reward(newBribeVotingReward).isReward(token0));
        address token1 = newPair.token1();
        assertTrue(Reward(newFeesVotingReward).isReward(token1));
        assertTrue(Reward(newBribeVotingReward).isReward(token1));

        // gauge validation
        assertEq(address(newPair), Gauge(newGauge).stakingToken());
        assertEq(newFeesVotingReward, Gauge(newGauge).feesVotingReward());
        assertEq(address(VELO), Gauge(newGauge).rewardToken());
        assertEq(address(voter), Gauge(newGauge).voter());
        assertTrue(Gauge(newGauge).isForPair());

        // gauge checks within voter
        assertEq(newGauge, voter.gauges(address(newPair)));
        assertEq(address(newPair), voter.poolForGauge(newGauge));
        assertTrue(voter.isGauge(newGauge));
        assertTrue(voter.isAlive(newGauge));
    }

    function testCreateGaugeWithNewGaugeFactory() external {
        // approve the new factory for use
        factoryRegistry.approve(
            address(factory),
            address(votingRewardsFactory),
            address(gaugeFactory2) // new factory
        );

        address newGauge = voter.createGauge(
            address(factory),
            address(votingRewardsFactory),
            address(gaugeFactory2), // new factory
            address(newPair)
        );
        address newFeesVotingReward = voter.gaugeToFees(newGauge);
        address newBribeVotingReward = voter.gaugeToBribe(newGauge);

        // ensure that the contracts created are not address(0)
        assertGt(uint256(uint160(newGauge)), 0);
        assertGt(uint256(uint160(newFeesVotingReward)), 0);
        assertGt(uint256(uint160(newBribeVotingReward)), 0);

        // voting validation
        address token0 = newPair.token0();
        assertTrue(Reward(newFeesVotingReward).isReward(token0));
        assertTrue(Reward(newBribeVotingReward).isReward(token0));
        address token1 = newPair.token1();
        assertTrue(Reward(newFeesVotingReward).isReward(token1));
        assertTrue(Reward(newBribeVotingReward).isReward(token1));

        // gauge validation
        assertEq(address(newPair), Gauge(newGauge).stakingToken());
        assertEq(newFeesVotingReward, Gauge(newGauge).feesVotingReward());
        assertEq(address(VELO), Gauge(newGauge).rewardToken());
        assertEq(address(voter), Gauge(newGauge).voter());
        assertTrue(Gauge(newGauge).isForPair());

        // gauge checks within voter
        assertEq(newGauge, voter.gauges(address(newPair)));
        assertEq(address(newPair), voter.poolForGauge(newGauge));
        assertTrue(voter.isGauge(newGauge));
        assertTrue(voter.isAlive(newGauge));
    }
}

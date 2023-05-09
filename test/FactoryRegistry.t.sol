pragma solidity 0.8.19;

import "./BaseTest.sol";

/// @dev Tests factory registry functionality.
contract FactoryRegistryTest is BaseTest {
    PoolFactory factory2;
    GaugeFactory gaugeFactory2;
    VotingRewardsFactory votingRewardsFactory2;
    FactoryRegistry factoryRegistry2;
    ManagedRewardsFactory managedRewardsFactory2;
    Router router2;
    Pool newPool;
    Pool newPool2;
    Pool implementation2;

    function _setUp() public override {
        implementation2 = new Pool();
        // create new factories to test against factory registry
        factory2 = new PoolFactory(address(implementation2));
        assertEq(factory2.allPoolsLength(), 0);
        factory2.setFee(true, 1); // set fee back to 0.01% for old tests
        factory2.setFee(false, 1);
        router2 = new Router(address(forwarder), address(0), address(factory2), address(voter), address(WETH));
        assertEq(address(router2.defaultFactory()), address(factory2));

        votingRewardsFactory2 = new VotingRewardsFactory();
        gaugeFactory2 = new GaugeFactory();
        factoryRegistry2 = new FactoryRegistry(
            address(factory2),
            address(votingRewardsFactory),
            address(gaugeFactory),
            address(managedRewardsFactory)
        );
        managedRewardsFactory2 = new ManagedRewardsFactory();

        // we need to create a new pool with the old factory to create the gauge
        // as existing pools already have gauges
        _addLiquidityToPool(address(owner), address(router), address(DAI), address(USDC), true, TOKEN_1, USDC_1);
        address create2Address = router.poolFor(address(DAI), address(USDC), true, address(0));
        newPool = Pool(factory.getPool(address(DAI), address(USDC), true));
        assertEq(create2Address, address(newPool));

        // create a new pool with new factory / router to test gauge creation against
        _addLiquidityToPool(address(owner), address(router2), address(DAI), address(USDC), true, TOKEN_1, USDC_1);
        create2Address = router2.poolFor(address(DAI), address(USDC), true, address(0));
        newPool2 = Pool(factory2.getPool(address(DAI), address(USDC), true));
        assertEq(create2Address, address(newPool2));
    }

    function testCannotSetManagedRewardsFactoryIfNotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(address(owner2));
        factoryRegistry.setManagedRewardsFactory(address(managedRewardsFactory2));
    }

    function testCannotSetManagedRewardsFactoryToZeroAddress() public {
        vm.expectRevert(IFactoryRegistry.ZeroAddress.selector);
        factoryRegistry.setManagedRewardsFactory(address(0));
    }

    function testCannotSetManagedRewardsFactoryToSameAddress() public {
        vm.expectRevert(IFactoryRegistry.SameAddress.selector);
        factoryRegistry.setManagedRewardsFactory(address(managedRewardsFactory));
    }

    function testSetManagedRewardsFactory() public {
        assertEq(factoryRegistry.managedRewardsFactory(), address(managedRewardsFactory));
        factoryRegistry.setManagedRewardsFactory(address(managedRewardsFactory2));
        assertEq(factoryRegistry.managedRewardsFactory(), address(managedRewardsFactory2));
    }

    function testCannotApproveAlreadyApprovedPath() external {
        factoryRegistry.approve(address(factory2), address(votingRewardsFactory), address(gaugeFactory));
        assertEq(
            factoryRegistry.isApproved(address(factory2), address(votingRewardsFactory), address(gaugeFactory)),
            true
        );

        vm.expectRevert(IFactoryRegistry.PathAlreadyApproved.selector);
        factoryRegistry.approve(address(factory2), address(votingRewardsFactory), address(gaugeFactory));
    }

    function testCannotUnapproveNonExistentPath() external {
        vm.expectRevert(IFactoryRegistry.PathNotApproved.selector);
        factoryRegistry.unapprove(address(factory2), address(votingRewardsFactory), address(gaugeFactory));
    }

    function testCannotApproveAlreadyApprovedPoolFactory() public {
        vm.expectRevert(IFactoryRegistry.PoolFactoryAlreadyApproved.selector);
        factoryRegistry.approve(address(factory), address(votingRewardsFactory2), address(gaugeFactory2));
    }

    function testCannotCreateGaugeWithUnauthorizedFactory() external {
        // expect revert if creating a gauge with an unpproved factory
        vm.startPrank(address(governor));
        vm.expectRevert(IVoter.FactoryPathNotApproved.selector);
        voter.createGauge(
            address(factory2), // bad factory
            address(votingRewardsFactory),
            address(gaugeFactory),
            address(newPool)
        );
        vm.expectRevert(IVoter.FactoryPathNotApproved.selector);
        voter.createGauge(
            address(factory),
            address(votingRewardsFactory2), // bad factory
            address(gaugeFactory),
            address(newPool)
        );
        vm.expectRevert(IVoter.FactoryPathNotApproved.selector);
        voter.createGauge(
            address(factory),
            address(votingRewardsFactory),
            address(gaugeFactory2), // bad factory
            address(newPool)
        );
        vm.stopPrank();
    }

    function testPoolFactoriesEnumerableSet() public {
        // initial state: fallbackPoolfactory is the only value
        assertEq(factoryRegistry.poolFactoriesLength(), 1);
        address[] memory poolFactories = factoryRegistry.poolFactories();
        assertEq(poolFactories[0], address(factory));

        // approving a poolFactory
        factoryRegistry.approve(address(factory2), address(votingRewardsFactory), address(gaugeFactory));
        assertEq(factoryRegistry.poolFactoriesLength(), 2);
        poolFactories = factoryRegistry.poolFactories();
        assertEq(poolFactories[0], address(factory));
        assertEq(poolFactories[1], address(factory2));

        // unapproving a poolFactory
        factoryRegistry.unapprove(address(factory2), address(votingRewardsFactory), address(gaugeFactory));
        assertEq(factoryRegistry.poolFactoriesLength(), 1);
        poolFactories = factoryRegistry.poolFactories();
        assertEq(poolFactories[0], address(factory));
    }

    function testApprove() external {
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
        factoryRegistry.unapprove(address(factory2), address(votingRewardsFactory), address(gaugeFactory));

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
        factoryRegistry.unapprove(address(factory2), address(votingRewardsFactory2), address(gaugeFactory));

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
        factoryRegistry.unapprove(address(factory2), address(votingRewardsFactory), address(gaugeFactory2));

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

    function testCreateGaugeWithNewPoolFactory() external {
        // approve the new factory for use
        factoryRegistry.approve(
            address(factory2), // new factory
            address(votingRewardsFactory),
            address(gaugeFactory)
        );

        // use pool2 (created using factory2), or else isPool() voter.createGauge() fails
        address newGauge = voter.createGauge(
            address(factory2), // new factory
            address(votingRewardsFactory),
            address(gaugeFactory),
            address(newPool2)
        );
        address newFeesVotingReward = voter.gaugeToFees(newGauge);
        address newBribeVotingReward = voter.gaugeToBribe(newGauge);

        // ensure that the contracts created are not address(0)
        assertGt(uint256(uint160(newGauge)), 0);
        assertGt(uint256(uint160(newFeesVotingReward)), 0);
        assertGt(uint256(uint160(newBribeVotingReward)), 0);

        // voting reward validation
        address token0 = newPool2.token0();
        assertTrue(Reward(newFeesVotingReward).isReward(token0));
        assertTrue(Reward(newBribeVotingReward).isReward(token0));
        address token1 = newPool2.token1();
        assertTrue(Reward(newFeesVotingReward).isReward(token1));
        assertTrue(Reward(newBribeVotingReward).isReward(token1));

        // gauge validation
        assertEq(address(newPool2), Gauge(newGauge).stakingToken());
        assertEq(newFeesVotingReward, Gauge(newGauge).feesVotingReward());
        assertEq(address(VELO), Gauge(newGauge).rewardToken());
        assertEq(address(voter), Gauge(newGauge).voter());
        assertTrue(Gauge(newGauge).isPool());

        // gauge checks within voter
        assertEq(newGauge, voter.gauges(address(newPool2)));
        assertEq(address(newPool2), voter.poolForGauge(newGauge));
        assertTrue(voter.isGauge(newGauge));
        assertTrue(voter.isAlive(newGauge));
    }

    function testCreateGaugeWithNewVotingRewardsFactory() external {
        // approve the new factory for use
        factoryRegistry.approve(
            address(factory2),
            address(votingRewardsFactory2), // new factory
            address(gaugeFactory)
        );

        address newGauge = voter.createGauge(
            address(factory2),
            address(votingRewardsFactory2), // new factory
            address(gaugeFactory),
            address(newPool2)
        );
        address newFeesVotingReward = voter.gaugeToFees(newGauge);
        address newBribeVotingReward = voter.gaugeToBribe(newGauge);

        // ensure that the contracts created are not address(0)
        assertGt(uint256(uint160(newGauge)), 0);
        assertGt(uint256(uint160(newFeesVotingReward)), 0);
        assertGt(uint256(uint160(newBribeVotingReward)), 0);

        // voting validation
        address token0 = newPool2.token0();
        assertTrue(Reward(newFeesVotingReward).isReward(token0));
        assertTrue(Reward(newBribeVotingReward).isReward(token0));
        address token1 = newPool2.token1();
        assertTrue(Reward(newFeesVotingReward).isReward(token1));
        assertTrue(Reward(newBribeVotingReward).isReward(token1));

        // gauge validation
        assertEq(address(newPool2), Gauge(newGauge).stakingToken());
        assertEq(newFeesVotingReward, Gauge(newGauge).feesVotingReward());
        assertEq(address(VELO), Gauge(newGauge).rewardToken());
        assertEq(address(voter), Gauge(newGauge).voter());
        assertTrue(Gauge(newGauge).isPool());

        // gauge checks within voter
        assertEq(newGauge, voter.gauges(address(newPool2)));
        assertEq(address(newPool2), voter.poolForGauge(newGauge));
        assertTrue(voter.isGauge(newGauge));
        assertTrue(voter.isAlive(newGauge));
    }

    function testCreateGaugeWithNewGaugeFactory() external {
        // approve the new factory for use
        factoryRegistry.approve(
            address(factory2),
            address(votingRewardsFactory),
            address(gaugeFactory2) // new factory
        );

        address newGauge = voter.createGauge(
            address(factory2),
            address(votingRewardsFactory),
            address(gaugeFactory2), // new factory
            address(newPool2)
        );
        address newFeesVotingReward = voter.gaugeToFees(newGauge);
        address newBribeVotingReward = voter.gaugeToBribe(newGauge);

        // ensure that the contracts created are not address(0)
        assertGt(uint256(uint160(newGauge)), 0);
        assertGt(uint256(uint160(newFeesVotingReward)), 0);
        assertGt(uint256(uint160(newBribeVotingReward)), 0);

        // voting validation
        address token0 = newPool2.token0();
        assertTrue(Reward(newFeesVotingReward).isReward(token0));
        assertTrue(Reward(newBribeVotingReward).isReward(token0));
        address token1 = newPool2.token1();
        assertTrue(Reward(newFeesVotingReward).isReward(token1));
        assertTrue(Reward(newBribeVotingReward).isReward(token1));

        // gauge validation
        assertEq(address(newPool2), Gauge(newGauge).stakingToken());
        assertEq(newFeesVotingReward, Gauge(newGauge).feesVotingReward());
        assertEq(address(VELO), Gauge(newGauge).rewardToken());
        assertEq(address(voter), Gauge(newGauge).voter());
        assertTrue(Gauge(newGauge).isPool());

        // gauge checks within voter
        assertEq(newGauge, voter.gauges(address(newPool2)));
        assertEq(address(newPool2), voter.poolForGauge(newGauge));
        assertTrue(voter.isGauge(newGauge));
        assertTrue(voter.isAlive(newGauge));
    }
}

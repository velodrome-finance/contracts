// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "./ExtendedBaseTest.sol";

contract EmissionSinkFlowTest is ExtendedBaseTest {
    constructor() {
        deploymentType = Deployment.CUSTOM;
    }

    function _setUp() public override {
        vm.createSelectFork(OPTIMISM_RPC_URL, 131625301);

        voter = Voter(0x41C914ee0c7E1A5edCD0295623e6dC557B5aBf3C);
        minter = Minter(voter.minter());
        VELO = Velo(address(minter.velo()));
        governor = VeloGovernor(payable(voter.governor()));
        escrow = VotingEscrow(voter.ve());
        distributor = RewardsDistributor(escrow.distributor());
        factoryRegistry = FactoryRegistry(voter.factoryRegistry());

        sinkPoolFactory = new SinkPoolFactory();
        sinkPool = SinkPool(sinkPoolFactory.pool());
        sinkGaugeFactory = new SinkGaugeFactory({_voter: address(voter)});
        votingRewardsFactory = VotingRewardsFactory(0x756E7C245C69d351FfFBfb88bA234aa395AdA8ec);

        vm.startPrank(address(governor));
        factoryRegistry.approve(address(sinkPoolFactory), address(votingRewardsFactory), address(sinkGaugeFactory));
        sinkGauge = SinkGauge(voter.createGauge(address(sinkPoolFactory), address(sinkPool)));
        vm.stopPrank();
    }

    function testEmissionSinkFlow() public {
        /// epoch 0
        minter.updatePeriod();
        assertEq(VELO.balanceOf(address(voter)), 39855055538);

        // create lock that will vote for sink gauge
        deal(address(VELO), address(this), TOKEN_100K, true);
        VELO.approve(address(escrow), TOKEN_100K);
        uint256 lockId = escrow.createLock(TOKEN_100K, MAXTIME);

        assertEq(distributor.claimable(lockId), 0);

        skip(1 hours + 1);

        // vote for sink gauge
        address[] memory pools = new address[](1);
        pools[0] = address(sinkPool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 1;
        voter.vote(lockId, pools, weights);
        skipAndRoll(1);

        /// epoch 1
        skipToNextEpoch(2 days);

        // mint expected emissions
        minter.updatePeriod();
        assertEq(VELO.balanceOf(address(voter)), 6383851850829863475836302);
        assertEq(VELO.balanceOf(address(sinkGauge)), 0);
        voter.updateFor(address(sinkGauge));
        assertEq(voter.claimable(address(sinkGauge)), 606225719113640091295);

        // distribute to sink gauge
        address[] memory gauges = new address[](1);
        gauges[0] = address(sinkGauge);
        vm.expectEmit(address(voter));
        emit IVoter.DistributeReward(address(this), address(sinkGauge), 606225719113640091295);
        voter.distribute(gauges);

        // gauge send emission directly to minter on notify (no need for getReward)
        assertEq(VELO.balanceOf(address(sinkGauge)), 0);
        assertApproxEqRel(sinkGauge.lockedRewards(), 606225719113640091295, 1e6);
        assertApproxEqRel(
            sinkGauge.tokenRewardsPerEpoch({_epochStart: VelodromeTimeLibrary.epochStart(block.timestamp)}),
            606225719113640091295,
            1e6
        );
        assertApproxEqRel(VELO.balanceOf(address(minter)), 606225719113640091295, 1e6);
        assertEq(VELO.balanceOf(address(voter)), 6383245625110749835745007);
    }
}

pragma solidity 0.8.19;

import "./BaseTest.sol";
import "contracts/AutoCompounder.sol";
import "contracts/CompoundOptimizer.sol";
import "contracts/factories/AutoCompounderFactory.sol";

contract AutoCompounderTest is BaseTest {
    uint256 tokenId;
    uint256 mTokenId;

    address manager;

    AutoCompounderFactory autoCompounderFactory;
    AutoCompounder autoCompounder;
    CompoundOptimizer optimizer;
    LockedManagedReward lockedManagedReward;
    FreeManagedReward freeManagedReward;

    address[] bribes;
    address[] fees;
    address[][] tokensToClaim;
    address[] tokensToSwap;

    constructor() {
        deploymentType = Deployment.FORK;
    }

    function _setUp() public override {
        // create managed veNFT
        vm.prank(escrow.allowedManager());
        mTokenId = escrow.createManagedLockFor(address(owner));
        lockedManagedReward = LockedManagedReward(escrow.managedToLocked(mTokenId));
        freeManagedReward = FreeManagedReward(escrow.managedToFree(mTokenId));

        vm.startPrank(address(owner));

        // Create normal veNFT and deposit into managed
        deal(address(VELO), address(owner), TOKEN_1);
        VELO.approve(address(escrow), TOKEN_1);
        tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        skipToNextEpoch(1 hours + 1);
        voter.depositManaged(tokenId, mTokenId);

        // Create auto compounder
        optimizer = new CompoundOptimizer(
            address(USDC),
            address(WETH),
            address(FRAX), // OP
            address(VELO),
            address(vFactory),
            address(factory),
            address(router)
        );
        autoCompounderFactory = new AutoCompounderFactory(
            address(forwarder),
            address(voter),
            address(router),
            address(optimizer)
        );
        escrow.approve(address(autoCompounderFactory), mTokenId);
        autoCompounder = AutoCompounder(autoCompounderFactory.createAutoCompounder(address(owner), mTokenId));

        skipToNextEpoch(1 hours + 1);

        vm.stopPrank();

        // Create a VELO pool for USDC, WETH, and FRAX (seen as OP in CompoundOptimizer)
        deal(address(VELO), address(owner), TOKEN_100K * 3);
        deal(address(WETH), address(owner), TOKEN_1 * 3);

        // @dev these pools have a higher VELO price value than v1 pools
        _addLiquidityToPool(address(owner), address(router), address(USDC), address(VELO), false, USDC_1, TOKEN_1);
        _addLiquidityToPool(address(owner), address(router), address(WETH), address(VELO), false, TOKEN_1, TOKEN_100K);
        _addLiquidityToPool(address(owner), address(router), address(FRAX), address(VELO), false, TOKEN_1, TOKEN_1);

        tokensToSwap.push(address(USDC));
        tokensToSwap.push(address(FRAX));
        tokensToSwap.push(address(DAI));
    }

    function testSwapToVELOAndCompoundWithCompoundRewardAmount() public {
        // Deal USDC, FRAX, and DAI to autocompounder to simulate earning bribes
        // NOTE: the low amount of bribe rewards leads to receiving 1% of the reward amount
        deal(address(USDC), address(autoCompounder), 1e6);
        deal(address(FRAX), address(autoCompounder), 1e6);
        deal(address(DAI), address(autoCompounder), 1e6);

        uint256 balanceNFTBefore = escrow.balanceOfNFT(mTokenId);
        uint256 balanceVELOBefore = VELO.balanceOf(address(owner4));

        // Random user calls swapToVELO()
        vm.prank(address(owner4));
        autoCompounder.claimBribesAndCompound(bribes, tokensToClaim, tokensToSwap);

        // USDC and FRAX converted even though they already have a direct pair to VELO
        // DAI converted without a direct pair to VELO
        assertEq(USDC.balanceOf(address(autoCompounder)), 0);
        assertEq(FRAX.balanceOf(address(autoCompounder)), 0);
        assertEq(DAI.balanceOf(address(autoCompounder)), 0);
        assertEq(VELO.balanceOf(address(autoCompounder)), 0);

        uint256 rewardAmountToNFT = escrow.balanceOfNFT(mTokenId) - balanceNFTBefore;
        uint256 rewardAmountToCaller = VELO.balanceOf(address(owner4)) - balanceVELOBefore;

        assertGt(rewardAmountToNFT, 0);
        assertGt(rewardAmountToCaller, 0);
        assertLt(rewardAmountToCaller, autoCompounderFactory.rewardAmount());

        // total reward is 100x what caller received - as caller received 1% the total reward
        assertEq((rewardAmountToNFT + rewardAmountToCaller) / 100, rewardAmountToCaller);
    }

    function testSwapToVELOAndCompoundWithFactoryRewardAmount() public {
        // Deal USDC, FRAX, and DAI to autocompounder to simulate earning bribe rewards
        // NOTE; the difference here is the higher reward amount
        deal(address(USDC), address(autoCompounder), 1e12);
        deal(address(FRAX), address(autoCompounder), 1e12);
        deal(address(DAI), address(autoCompounder), 1e12);

        uint256 balanceVELOCallerBefore = VELO.balanceOf(address(owner4));
        uint256 balanceNFTBefore = escrow.balanceOfNFT(mTokenId);

        // Random user calls swapToVELO()
        vm.prank(address(owner4));
        autoCompounder.claimBribesAndCompound(bribes, tokensToClaim, tokensToSwap);

        // USDC and FRAX converted even though they already have a direct pair to VELO
        // DAI converted without a direct pair to VELO
        assertEq(USDC.balanceOf(address(autoCompounder)), 0);
        assertEq(FRAX.balanceOf(address(autoCompounder)), 0);
        assertEq(DAI.balanceOf(address(autoCompounder)), 0);
        assertEq(VELO.balanceOf(address(autoCompounder)), 0);

        // Compounded into the mTokenId and caller has received a refund equal to the factory rewardAmount
        assertEq(VELO.balanceOf(address(owner4)), balanceVELOCallerBefore + autoCompounderFactory.rewardAmount());
        assertGt(escrow.balanceOfNFT(mTokenId), balanceNFTBefore);
    }

    function testSwapTokensToVELOAndCompoundClaimRebaseOnly() public {
        address[] memory pools = new address[](2);
        pools[0] = address(pool);
        pools[1] = address(pool2);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 1;
        weights[1] = 1;

        skip(1 hours);
        autoCompounder.vote(pools, weights);

        skipToNextEpoch(1 days);
        minter.updatePeriod();

        uint256 claimable = distributor.claimable(mTokenId);
        assertGt(distributor.claimable(mTokenId), 0);

        uint256 balanceNFTBefore = escrow.balanceOfNFT(mTokenId);
        autoCompounder.claimBribesAndCompound(bribes, tokensToClaim, tokensToSwap);
        assertEq(escrow.balanceOfNFT(mTokenId), balanceNFTBefore + claimable);
    }

    function testSwapTokensToVELOAndCompoundOnlyExistingVELOBalance() public {
        deal(address(VELO), address(autoCompounder), 1e18);

        uint256 balanceVELOBefore = VELO.balanceOf(address(owner3));
        uint256 balanceNFTBefore = escrow.balanceOfNFT(mTokenId);

        vm.prank(address(owner3));
        autoCompounder.claimBribesAndCompound(bribes, tokensToClaim, tokensToSwap);

        assertGt(VELO.balanceOf(address(owner3)), balanceVELOBefore);
        assertGt(escrow.balanceOfNFT(mTokenId), balanceNFTBefore);
        assertEq(VELO.balanceOf(address(autoCompounder)), 0);
    }

    function testIncreaseAmount() public {
        uint256 amount = TOKEN_1;
        deal(address(VELO), address(owner), amount);
        VELO.approve(address(autoCompounder), amount);

        uint256 balanceBefore = escrow.balanceOfNFT(mTokenId);
        uint256 supplyBefore = escrow.totalSupply();

        autoCompounder.increaseAmount(amount);

        assertEq(escrow.balanceOfNFT(mTokenId), balanceBefore + amount);
        assertEq(escrow.totalSupply(), supplyBefore + amount);
    }

    function testVote() public {
        address[] memory poolVote = new address[](1);
        uint256[] memory weights = new uint256[](1);
        poolVote[0] = address(pool2);
        weights[0] = 1;

        assertFalse(escrow.voted(mTokenId));

        autoCompounder.vote(poolVote, weights);

        assertTrue(escrow.voted(mTokenId));
        assertEq(voter.weights(address(pool2)), escrow.balanceOfNFT(mTokenId));
        assertEq(voter.votes(mTokenId, address(pool2)), escrow.balanceOfNFT(mTokenId));
        assertEq(voter.poolVote(mTokenId, 0), address(pool2));
    }

    function testSwapTokenToVELOAndCompound() public {
        uint256 amount = TOKEN_1 / 100;
        deal(address(WETH), address(autoCompounder), amount);

        uint256 balanceBefore = escrow.balanceOfNFT(mTokenId);
        uint256 veloBalanceBefore = VELO.balanceOf(address(owner));

        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route(address(WETH), address(VELO), false, address(0));
        uint256[] memory amountsOut = router.getAmountsOut(amount, routes);
        uint256 amountOut = amountsOut[amountsOut.length - 1];
        assertGt(amountOut, 0);

        autoCompounder.swapTokenToVELOAndCompound(routes);

        // no reward given to caller this time- full amount deposited into mTokenId
        assertEq(VELO.balanceOf(address(owner)), veloBalanceBefore);
        assertEq(escrow.balanceOfNFT(mTokenId), balanceBefore + amountOut);
    }

    function testClaimBribesAndCompound() public {
        // TODO- e2e
    }

    function testClaimFeesAndCompound() public {
        // TODO- e2e
    }
}

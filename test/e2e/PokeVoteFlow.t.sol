// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "./ExtendedBaseTest.sol";

contract PokeVoteFlow is ExtendedBaseTest {
    function _setUp() public override {
        VELO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAX_TIME);
        vm.startPrank(address(owner2));
        VELO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAX_TIME);
        vm.stopPrank();
        vm.startPrank(address(owner3));
        VELO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAX_TIME);
        vm.stopPrank();

        // create smaller veNFTs
        vm.startPrank(address(owner4));
        VELO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAX_TIME / 4);
        vm.stopPrank();
        skip(1);
    }

    function testPokeVoteIncentiveVotingRewardFlow() public {
        skip(1 hours + 1);

        // set up votes and rewards
        address[] memory pools = new address[](2);
        pools[0] = address(pool);
        pools[1] = address(pool2);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 5000;
        weights[1] = 5000;
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);
        address[] memory usdcRewards = new address[](1);
        usdcRewards[0] = address(USDC);

        uint256 currentIncentive = 0;
        uint256 usdcIncentive = 0;
        // @dev note that the tokenId corresponds to the owner number
        // i.e. owner owns tokenId 1
        //      owner2 owns tokenId 2...

        /// epoch zero
        // set up initial votes for multiple pools
        currentIncentive = TOKEN_1;
        usdcIncentive = USDC_1;
        _createIncentiveWithAmount(incentiveVotingReward, address(LR), currentIncentive);
        _createIncentiveWithAmount(incentiveVotingReward2, address(USDC), usdcIncentive);
        voter.vote(1, pools, weights);
        vm.prank(address(owner2));
        voter.vote(2, pools, weights);

        skipToNextEpoch(1);

        // skip claiming this epoch
        uint256 earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, currentIncentive / 2);
        earned = incentiveVotingReward2.earned(address(USDC), 1);
        assertEq(earned, usdcIncentive / 2);
        earned = incentiveVotingReward.earned(address(LR), 2);
        assertEq(earned, currentIncentive / 2);
        earned = incentiveVotingReward2.earned(address(USDC), 2);
        assertEq(earned, usdcIncentive / 2);

        skip(1);

        // test pokes before final poke have no impact
        currentIncentive = TOKEN_1 * 2;
        usdcIncentive = USDC_1 * 2;
        _createIncentiveWithAmount(incentiveVotingReward, address(LR), currentIncentive);
        _createIncentiveWithAmount(incentiveVotingReward2, address(USDC), usdcIncentive);
        skip(1 hours);

        // owner gets poked many times
        for (uint256 i = 0; i < 5; i++) {
            voter.poke(1);
            skip(1 days);
        }

        // final poke occurs at same time, expect rewards to be the same
        voter.poke(1);
        vm.prank(address(owner2));
        voter.poke(2);

        skipToNextEpoch(1);

        // check pool incentive (LR) is correct
        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        assertEq(post - pre, (TOKEN_1 * 3) / 2);

        pre = LR.balanceOf(address(owner2));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(2, rewards);
        post = LR.balanceOf(address(owner2));
        assertEq(post - pre, (TOKEN_1 * 3) / 2);

        // check pool2 incentive (usdc) is correct
        uint256 usdcPre = USDC.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward2.getReward(1, usdcRewards);
        uint256 usdcPost = USDC.balanceOf(address(owner));
        assertEq(usdcPost - usdcPre, (USDC_1 * 3) / 2);

        usdcPre = USDC.balanceOf(address(owner2));
        vm.prank(address(voter));
        incentiveVotingReward2.getReward(2, usdcRewards);
        usdcPost = USDC.balanceOf(address(owner2));
        assertEq(usdcPost - usdcPre, (USDC_1 * 3) / 2);

        // test pokes before final vote have no impact
        currentIncentive = TOKEN_1 * 3;
        usdcIncentive = USDC_1 * 3;
        _createIncentiveWithAmount(incentiveVotingReward, address(LR), currentIncentive);
        _createIncentiveWithAmount(incentiveVotingReward2, address(USDC), usdcIncentive);
        skip(1 hours);

        // owner gets poked many times
        for (uint256 i = 0; i < 5; i++) {
            voter.poke(1);
            skip(1 days);
        }
        skip(1 hours);

        // final vote occurs at same time, expect rewards to be the same
        voter.vote(1, pools, weights);
        vm.prank(address(owner2));
        voter.vote(2, pools, weights);

        skipToNextEpoch(1);

        pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(1, rewards);
        post = LR.balanceOf(address(owner));
        assertEq(post - pre, (TOKEN_1 * 3) / 2);

        pre = LR.balanceOf(address(owner2));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(2, rewards);
        post = LR.balanceOf(address(owner2));
        assertEq(post - pre, (TOKEN_1 * 3) / 2);

        usdcPre = USDC.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward2.getReward(1, usdcRewards);
        usdcPost = USDC.balanceOf(address(owner));
        assertEq(usdcPost - usdcPre, (USDC_1 * 3) / 2);

        usdcPre = USDC.balanceOf(address(owner2));
        vm.prank(address(voter));
        incentiveVotingReward2.getReward(2, usdcRewards);
        usdcPost = USDC.balanceOf(address(owner2));
        assertEq(usdcPost - usdcPre, (USDC_1 * 3) / 2);

        // test only last poke after vote is counted
        // switch to voting for pools 2 and 3
        currentIncentive = TOKEN_1 * 4;
        usdcIncentive = USDC_1 * 4;
        pools[0] = address(pool2);
        pools[1] = address(pool3);
        _createIncentiveWithAmount(incentiveVotingReward, address(LR), currentIncentive);
        _createIncentiveWithAmount(incentiveVotingReward2, address(LR), currentIncentive);
        _createIncentiveWithAmount(incentiveVotingReward3, address(USDC), usdcIncentive);
        skip(1);

        address[] memory singlePool = new address[](1);
        singlePool[0] = address(pool);
        uint256[] memory singleWeight = new uint256[](1);
        singleWeight[0] = 1;

        skip(1 hours);
        // deposit into pool to provide supply
        vm.prank(address(owner3));
        voter.vote(3, singlePool, singleWeight);
        voter.vote(1, pools, weights);
        skip(1 days);

        // owner is poked at same time as owner2 votes, so rewards should be equal
        voter.poke(1);
        vm.prank(address(owner2));
        voter.vote(2, pools, weights);

        skipToNextEpoch(1);

        // check no incentives from pool
        earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, 0);
        earned = incentiveVotingReward.earned(address(LR), 2);
        assertEq(earned, 0);

        pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward2.getReward(1, rewards);
        post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1 * 2);

        pre = LR.balanceOf(address(owner2));
        vm.prank(address(voter));
        incentiveVotingReward2.getReward(2, rewards);
        post = LR.balanceOf(address(owner2));
        assertEq(post - pre, TOKEN_1 * 2);

        usdcPre = USDC.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward3.getReward(1, usdcRewards);
        usdcPost = USDC.balanceOf(address(owner));
        assertEq(usdcPost - usdcPre, USDC_1 * 2);

        usdcPre = USDC.balanceOf(address(owner2));
        vm.prank(address(voter));
        incentiveVotingReward3.getReward(2, usdcRewards);
        usdcPost = USDC.balanceOf(address(owner2));
        assertEq(usdcPost - usdcPre, USDC_1 * 2);

        // test before and after voting accrues votes correctly
        // switch back to voting for pool 1 and 2
        currentIncentive = TOKEN_1 * 5;
        usdcIncentive = USDC_1 * 5;
        pools[0] = address(pool);
        pools[1] = address(pool2);
        _createIncentiveWithAmount(incentiveVotingReward, address(LR), currentIncentive);
        _createIncentiveWithAmount(incentiveVotingReward2, address(USDC), usdcIncentive);
        _createIncentiveWithAmount(incentiveVotingReward3, address(LR), currentIncentive);
        skip(1 hours);

        // deposit into pool3 to provide supply
        singlePool[0] = address(pool3);
        vm.prank(address(owner3));
        voter.vote(3, singlePool, singleWeight);

        // get poked prior to vote (will 'vote' for pool2, pool3)
        for (uint256 i = 0; i < 5; i++) {
            skip(1 hours);
            voter.poke(1);
        }
        skip(1 hours);

        // vote for pool, pool2
        voter.vote(1, pools, weights);

        // get poked after vote (will 'vote' for pool, pool2)
        for (uint256 i = 0; i < 5; i++) {
            skip(1 hours);
            voter.poke(1);
        }

        vm.prank(address(owner2));
        voter.vote(2, pools, weights);

        skipToNextEpoch(1);

        // check no incentives from pool
        earned = incentiveVotingReward3.earned(address(LR), 1);
        assertEq(earned, 0);
        earned = incentiveVotingReward3.earned(address(LR), 2);
        assertEq(earned, 0);

        // check other incentives are correct
        pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(1, rewards);
        post = LR.balanceOf(address(owner));
        assertEq(post - pre, (TOKEN_1 * 5) / 2);

        pre = LR.balanceOf(address(owner2));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(2, rewards);
        post = LR.balanceOf(address(owner2));
        assertEq(post - pre, (TOKEN_1 * 5) / 2);

        usdcPre = USDC.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward2.getReward(1, usdcRewards);
        usdcPost = USDC.balanceOf(address(owner));
        assertEq(usdcPost - usdcPre, (USDC_1 * 5) / 2);

        usdcPre = USDC.balanceOf(address(owner2));
        vm.prank(address(voter));
        incentiveVotingReward2.getReward(2, usdcRewards);
        usdcPost = USDC.balanceOf(address(owner2));
        assertEq(usdcPost - usdcPre, (USDC_1 * 5) / 2);
    }
}

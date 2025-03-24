// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "./BaseTest.sol";

contract IncentiveVotingRewardTest is BaseTest {
    event NotifyReward(address indexed from, address indexed reward, uint256 indexed epoch, uint256 amount);

    function _setUp() public override {
        // ve
        VELO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME);
        vm.startPrank(address(owner2));
        VELO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME);
        vm.stopPrank();
        vm.startPrank(address(owner3));
        VELO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME);
        vm.stopPrank();
        skip(1);
    }

    function testGetRewardWithZeroTotalSupply() public {
        skip(1 weeks / 2);

        // create an incentive
        LR.approve(address(incentiveVotingReward), TOKEN_1);
        incentiveVotingReward.notifyRewardAmount(address(LR), TOKEN_1);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        voter.vote(1, pools, weights);

        skipToNextEpoch(1);

        // check earned is correct
        uint256 earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1);

        // add incentive for epoch 2
        LR.approve(address(incentiveVotingReward), TOKEN_1 * 2);
        incentiveVotingReward.notifyRewardAmount(address(LR), TOKEN_1 * 2);
        skip(1 hours);

        // remove supply by voting for other pool
        pools[0] = address(pool2);
        voter.vote(1, pools, weights);

        assertEq(incentiveVotingReward.supplyAt(block.timestamp), 0);

        skipToNextEpoch(1);

        // check can still claim incentive
        earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1);
    }

    function testGetRewardWithMultipleStaggeredRewardsInOneEpoch() public {
        skip(1 weeks / 2);

        uint256 reward = TOKEN_1;
        uint256 reward2 = TOKEN_1 * 2;

        // create an incentive
        LR.approve(address(incentiveVotingReward), reward);
        incentiveVotingReward.notifyRewardAmount((address(LR)), reward);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        voter.vote(1, pools, weights);

        skip(1 days);

        // create another incentive for the same pool in the same epoch
        LR.approve(address(incentiveVotingReward), reward2);
        incentiveVotingReward.notifyRewardAmount((address(LR)), reward2);

        skipToNextEpoch(1);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));

        // expect both rewards
        uint256 totalReward = reward + reward2;
        assertEq(post - pre, totalReward);
    }

    function testCannotGetRewardMoreThanOncePerEpochWithSingleReward() public {
        skip(1 weeks / 2);

        // create an incentive
        LR.approve(address(incentiveVotingReward), TOKEN_1);
        incentiveVotingReward.notifyRewardAmount(address(LR), TOKEN_1);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        voter.vote(1, pools, weights);

        vm.prank(address(owner2));
        voter.vote(2, pools, weights);

        skipToNextEpoch(1);

        uint256 pre = LR.balanceOf(address(owner));
        uint256 earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1 / 2);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        vm.startPrank(address(voter));
        // claim first time
        incentiveVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        skip(1);
        // claim second time
        incentiveVotingReward.getReward(1, rewards);
        vm.stopPrank();

        uint256 post_post = LR.balanceOf(address(owner));
        assertEq(post_post, post);
        assertEq(post_post - pre, TOKEN_1 / 2);
    }

    function testCannotGetRewardMoreThanOncePerEpochWithMultipleRewards() public {
        skip(1 weeks / 2);

        // create an incentive
        LR.approve(address(incentiveVotingReward), TOKEN_1);
        incentiveVotingReward.notifyRewardAmount(address(LR), TOKEN_1);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        voter.vote(1, pools, weights);

        vm.prank(address(owner2));
        voter.vote(2, pools, weights);

        skipToNextEpoch(1);

        uint256 pre = LR.balanceOf(address(owner));
        uint256 earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1 / 2);

        // rewards
        address[] memory rewards = new address[](2);
        rewards[0] = address(LR);
        rewards[1] = address(LR);

        vm.startPrank(address(voter));
        // claim first time
        incentiveVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        // claim second time
        incentiveVotingReward.getReward(1, rewards);
        vm.stopPrank();

        uint256 post_post = LR.balanceOf(address(owner));
        assertEq(post_post, post);
        assertEq(post_post - pre, TOKEN_1 / 2);
    }

    function testCannotGetRewardIfNotVoterOrOwnerOrApproved() public {
        skip(1 weeks / 2);

        uint256 reward = TOKEN_1;

        // create an incentive
        LR.approve(address(incentiveVotingReward), reward);
        incentiveVotingReward.notifyRewardAmount((address(LR)), reward);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        voter.vote(1, pools, weights);

        skipToNextEpoch(1);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        vm.prank(address(owner2));
        vm.expectRevert(IReward.NotAuthorized.selector);
        incentiveVotingReward.getReward(1, rewards);
    }

    function testGetRewardWithMultipleVotes() public {
        skip(1 weeks / 2);

        uint256 reward = TOKEN_1;
        uint256 reward2 = TOKEN_1 * 2;

        // create an incentive
        LR.approve(address(incentiveVotingReward), reward);
        incentiveVotingReward.notifyRewardAmount((address(LR)), reward);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;

        voter.vote(1, pools, weights);

        skipToNextEpoch(1 hours + 1);

        // create another incentive for the same pool the following week
        LR.approve(address(incentiveVotingReward), reward2);
        incentiveVotingReward.notifyRewardAmount((address(LR)), reward2);

        voter.vote(1, pools, weights);

        skipToNextEpoch(1);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));

        uint256 totalReward = reward + reward2;
        assertEq(post - pre, totalReward);
    }

    function testGetRewardWithVotesForDifferentPoolsAcrossEpochs() public {
        skip(1 weeks / 2);

        uint256 reward = TOKEN_1;
        uint256 reward2 = TOKEN_1 * 2;

        // create an incentive for pool in epoch 0
        LR.approve(address(incentiveVotingReward), reward);
        incentiveVotingReward.notifyRewardAmount((address(LR)), reward);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;

        voter.vote(1, pools, weights);
        vm.prank(address(owner2));
        voter.vote(2, pools, weights);

        skipToNextEpoch(1 hours + 1);

        // create an incentive for pool2 in epoch 1
        LR.approve(address(incentiveVotingReward2), reward2);
        incentiveVotingReward2.notifyRewardAmount((address(LR)), reward2);
        pools[0] = address(pool2);

        voter.vote(1, pools, weights);

        skipToNextEpoch(1);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        // check rewards accrue correctly for pool
        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));

        assertEq(post - pre, reward / 2);

        // check rewards accrue correctly for pool2
        pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward2.getReward(1, rewards);
        post = LR.balanceOf(address(owner));

        assertEq(post - pre, reward2);
    }

    function testGetRewardWithPassiveVote() public {
        skip(1 weeks / 2);

        // create an incentive in epoch 0
        LR.approve(address(incentiveVotingReward), TOKEN_1);
        incentiveVotingReward.notifyRewardAmount(address(LR), TOKEN_1);
        assertEq(LR.balanceOf(address(incentiveVotingReward)), TOKEN_1);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        voter.vote(1, pools, weights);
        skip(1);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        uint256 earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, 0);

        skipToNextEpoch(1);

        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1);

        earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, 0);

        // create another incentive in epoch 1 but do not vote
        LR.approve(address(incentiveVotingReward), TOKEN_1 * 2);
        incentiveVotingReward.notifyRewardAmount(address(LR), TOKEN_1 * 2);
        assertEq(LR.balanceOf(address(incentiveVotingReward)), TOKEN_1 * 2);

        earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, 0);

        skipToNextEpoch(1);

        earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1 * 2);

        pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(1, rewards);
        post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1 * 2);
    }

    function testGetRewardWithPassiveVotes() public {
        skip(1 weeks / 2);

        // create an incentive
        LR.approve(address(incentiveVotingReward), TOKEN_1);
        incentiveVotingReward.notifyRewardAmount((address(LR)), TOKEN_1);

        // vote in epoch 0
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;

        voter.vote(1, pools, weights);
        skip(1);

        uint256 earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, 0);

        // epoch 1: five epochs pass, with an incrementing reward
        skipToNextEpoch(1);

        earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1);

        LR.approve(address(incentiveVotingReward), TOKEN_1 * 2);
        incentiveVotingReward.notifyRewardAmount((address(LR)), TOKEN_1 * 2);
        skip(1);

        earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1);

        // epoch 2
        skipToNextEpoch(1);

        earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1 * 3);

        LR.approve(address(incentiveVotingReward), TOKEN_1 * 3);
        incentiveVotingReward.notifyRewardAmount((address(LR)), TOKEN_1 * 3);
        skip(1);

        earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1 * 3);

        // epoch 3
        skipToNextEpoch(1);

        earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1 * 6);

        LR.approve(address(incentiveVotingReward), TOKEN_1 * 4);
        incentiveVotingReward.notifyRewardAmount((address(LR)), TOKEN_1 * 4);
        skip(1);

        earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1 * 6);

        // epoch 4
        skipToNextEpoch(1);

        earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1 * 10);

        LR.approve(address(incentiveVotingReward), TOKEN_1 * 5);
        incentiveVotingReward.notifyRewardAmount((address(LR)), TOKEN_1 * 5);
        skip(1);

        earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1 * 10);

        // epoch 5
        skipToNextEpoch(1);

        earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1 * 15);

        LR.approve(address(incentiveVotingReward), TOKEN_1 * 6);
        incentiveVotingReward.notifyRewardAmount((address(LR)), TOKEN_1 * 6);
        skip(1);

        earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1 * 15);

        skipToNextEpoch(1);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        // total rewards: 1 + 2 + 3 + 4 + 5 + 6
        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));

        assertEq(post - pre, TOKEN_1 * 21);
    }

    function testCannotGetRewardInSameWeekIfEpochYetToFlip() public {
        /// tests that rewards deposited that week cannot be claimed until next week
        skip(1 weeks / 2);

        // create incentive in epoch 0
        LR.approve(address(incentiveVotingReward), TOKEN_1);
        incentiveVotingReward.notifyRewardAmount((address(LR)), TOKEN_1);

        // vote in epoch 0
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;

        voter.vote(1, pools, weights);

        skipToNextEpoch(1);

        // create incentive in epoch 1
        LR.approve(address(incentiveVotingReward), TOKEN_1 * 2);
        incentiveVotingReward.notifyRewardAmount((address(LR)), TOKEN_1 * 2);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        // claim before flip but after rewards are re-deposited into incentive
        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1);

        skipToNextEpoch(1);

        // claim after flip
        pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(1, rewards);
        post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1 * 2);
    }

    function testGetRewardWithSingleVoteAndPoke() public {
        skip(1 weeks / 2);

        uint256 reward = TOKEN_1;
        uint256 reward2 = TOKEN_1 * 2;

        // create an incentive in epoch 0
        LR.approve(address(incentiveVotingReward), reward);
        incentiveVotingReward.notifyRewardAmount((address(LR)), reward);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;

        voter.vote(1, pools, weights);
        skip(1);

        uint256 earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, 0);

        skipToNextEpoch(1);

        earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1);

        // create an incentive in epoch 1
        LR.approve(address(incentiveVotingReward), reward2);
        incentiveVotingReward.notifyRewardAmount((address(LR)), reward2);
        skip(1);

        earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1);
        skip(1 hours);

        voter.poke(1);
        skip(1);

        earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1);

        skipToNextEpoch(1);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));

        uint256 total = reward + reward2;
        assertEq(post - pre, total);
    }

    function testGetRewardWithSingleCheckpoint() public {
        skip(1 weeks / 2);

        // create an incentive
        LR.approve(address(incentiveVotingReward), TOKEN_1);
        incentiveVotingReward.notifyRewardAmount(address(LR), TOKEN_1);
        assertEq(LR.balanceOf(address(incentiveVotingReward)), TOKEN_1);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;

        voter.vote(1, pools, weights);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        // cannot claim
        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        assertEq(post - pre, 0);

        // fwd half a week
        skipToNextEpoch(1);

        pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(1, rewards);
        post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1);
    }

    function testGetRewardWithSingleCheckpointWithOtherVoter() public {
        skip(1 weeks / 2);

        // create an incentive
        LR.approve(address(incentiveVotingReward), TOKEN_1);
        incentiveVotingReward.notifyRewardAmount(address(LR), TOKEN_1);
        assertEq(LR.balanceOf(address(incentiveVotingReward)), TOKEN_1);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;

        voter.vote(1, pools, weights);

        vm.prank(address(owner2));
        voter.vote(2, pools, weights);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        skipToNextEpoch(1);

        // deliver incentive
        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1 / 2);

        pre = LR.balanceOf(address(owner2));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(2, rewards);
        post = LR.balanceOf(address(owner2));
        assertEq(post - pre, TOKEN_1 / 2);
    }

    function testGetRewardWithSingleCheckpointWithOtherStaggeredVoter_() public {
        skip(1 weeks / 2);

        // create an incentive
        LR.approve(address(incentiveVotingReward), TOKEN_1);
        incentiveVotingReward.notifyRewardAmount(address(LR), TOKEN_1);
        assertEq(LR.balanceOf(address(incentiveVotingReward)), TOKEN_1);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;

        voter.vote(1, pools, weights);

        // vote delayed
        skip(1 days);
        vm.prank(address(owner2));
        voter.vote(2, pools, weights);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        // fwd
        skipToNextEpoch(1);

        // deliver incentive (should be the same amount)
        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1 / 2);
        uint256 diff = post - pre;

        pre = LR.balanceOf(address(owner2));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(2, rewards);
        post = LR.balanceOf(address(owner2));
        assertEq(post - pre, TOKEN_1 / 2);
        uint256 diff2 = post - pre;

        assertEq(diff + diff2, TOKEN_1);
    }

    function testGetRewardWithSkippedClaims() public {
        skip(1 weeks / 2);

        uint256 reward = TOKEN_1; // epoch 0 reward
        uint256 reward2 = TOKEN_1 * 2; // epoch1 reward
        uint256 reward3 = TOKEN_1 * 3; // epoch3 reward

        // create incentive with amount reward in epoch 0
        LR.approve(address(incentiveVotingReward), reward);
        incentiveVotingReward.notifyRewardAmount(address(LR), reward);
        assertEq(LR.balanceOf(address(incentiveVotingReward)), reward);

        // vote for pool
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;

        voter.vote(1, pools, weights);
        vm.prank(address(owner2));
        voter.vote(2, pools, weights);

        skipToNextEpoch(1);

        // check reward amount is correct
        uint256 expectedReward = reward / 2;
        uint256 earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, expectedReward);
        earned = incentiveVotingReward.earned(address(LR), 2);
        assertEq(earned, expectedReward);

        // create incentive with amount reward2 in epoch 1
        LR.approve(address(incentiveVotingReward), reward2);
        incentiveVotingReward.notifyRewardAmount(address(LR), reward2);
        assertEq(LR.balanceOf(address(incentiveVotingReward)), reward + reward2);

        skip(1 hours);

        // vote again for same pool
        voter.vote(1, pools, weights);
        vm.prank(address(owner2));
        voter.vote(2, pools, weights);

        skipToNextEpoch(1);

        expectedReward = (reward + reward2) / 2;
        earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, expectedReward);
        earned = incentiveVotingReward.earned(address(LR), 2);
        assertEq(earned, expectedReward);

        // create incentive with amount reward3 in epoch 2
        LR.approve(address(incentiveVotingReward), reward3);
        incentiveVotingReward.notifyRewardAmount(address(LR), reward3);
        assertEq(LR.balanceOf(address(incentiveVotingReward)), reward + reward2 + reward3);
        skip(1 hours);

        // poked into voting for same pool
        voter.poke(1);
        vm.prank(address(owner2));
        voter.poke(2);

        skipToNextEpoch(1);

        expectedReward = (reward + reward2 + reward3) / 2;
        earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, expectedReward);
        earned = incentiveVotingReward.earned(address(LR), 2);
        assertEq(earned, expectedReward);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        assertEq(post - pre, expectedReward);

        pre = LR.balanceOf(address(owner2));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(2, rewards);
        post = LR.balanceOf(address(owner2));
        assertEq(post - pre, expectedReward);
    }

    function testCannotClaimRewardForPoolIfPokedButVotedForOtherPool() public {
        skip(1 weeks / 2);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        // set up votes
        address[] memory pools = new address[](1);
        address[] memory pools2 = new address[](1);
        uint256[] memory weights = new uint256[](1);
        pools[0] = address(pool);
        pools2[0] = address(pool2);
        weights[0] = 10000;

        // create an incentive in epoch 0
        LR.approve(address(incentiveVotingReward), TOKEN_1);
        incentiveVotingReward.notifyRewardAmount(address(LR), TOKEN_1);

        // vote for pool in epoch 0
        voter.vote(1, pools, weights);
        vm.prank(address(owner2));
        voter.vote(2, pools, weights);

        skipToNextEpoch(1);

        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1 / 2);

        pre = LR.balanceOf(address(owner2));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(2, rewards);
        post = LR.balanceOf(address(owner2));
        assertEq(post - pre, TOKEN_1 / 2);

        skip(1);

        // create an incentive for pool in epoch 1
        LR.approve(address(incentiveVotingReward), TOKEN_1);
        incentiveVotingReward.notifyRewardAmount(address(LR), TOKEN_1);
        // create an incentive for pool2 in epoch 1
        LR.approve(address(incentiveVotingReward2), TOKEN_1 * 2);
        incentiveVotingReward2.notifyRewardAmount(address(LR), TOKEN_1 * 2);
        skip(1 hours);

        // poke causes id 1 to "vote" for pool
        voter.poke(1);
        skip(1 hours);

        // vote for pool2 in epoch 1
        voter.vote(1, pools2, weights);

        // go to next epoch
        skipToNextEpoch(1);

        // earned for pool should be 0
        uint256 earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, 0);

        // earned for pool for nft 2 should be full incentive amount
        earned = incentiveVotingReward.earned(address(LR), 2);
        assertEq(earned, TOKEN_1);

        // earned for pool2 should be TOKEN_1
        earned = incentiveVotingReward2.earned(address(LR), 1);
        assertEq(earned, TOKEN_1 * 2);

        pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward2.getReward(1, rewards);
        post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1 * 2);
    }

    function testGetRewardWithAlternatingVotes() public {
        skip(1 weeks / 2);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        // set up votes
        address[] memory pools = new address[](1);
        address[] memory pools2 = new address[](1);
        uint256[] memory weights = new uint256[](1);
        pools[0] = address(pool);
        pools2[0] = address(pool2);
        weights[0] = 10000;

        // create an incentive in epoch 0
        LR.approve(address(incentiveVotingReward), TOKEN_1);
        incentiveVotingReward.notifyRewardAmount(address(LR), TOKEN_1);

        // vote for pool in epoch 0
        voter.vote(1, pools, weights);
        vm.prank(address(owner2));
        voter.vote(2, pools, weights);
        skip(1);

        // fwd half a week
        skipToNextEpoch(1);

        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1 / 2);

        uint256 earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, 0);
        skip(1);

        // create an incentive for pool in epoch 1
        LR.approve(address(incentiveVotingReward), TOKEN_1);
        incentiveVotingReward.notifyRewardAmount(address(LR), TOKEN_1);
        // create an incentive for pool2 in epoch 1
        LR.approve(address(incentiveVotingReward2), TOKEN_1 * 2);
        incentiveVotingReward2.notifyRewardAmount(address(LR), TOKEN_1 * 2);
        skip(1 hours);

        voter.vote(1, pools2, weights);
        vm.prank(address(owner3));
        voter.vote(3, pools2, weights);

        // go to next week
        skipToNextEpoch(1 hours + 1);

        earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, 0);

        voter.vote(1, pools, weights);

        earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, 0);
        earned = incentiveVotingReward2.earned(address(LR), 1);
        assertEq(earned, TOKEN_1);

        pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward2.getReward(1, rewards);
        post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1);
    }

    // same test as above but with some initial checkpoints in place
    function testGetRewardWithAlternatingVotesWithInitialCheckpoints() public {
        skip(1 weeks / 2);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        // set up votes
        address[] memory pools = new address[](1);
        address[] memory pools2 = new address[](1);
        uint256[] memory weights = new uint256[](1);
        pools[0] = address(pool);
        pools2[0] = address(pool2);
        weights[0] = 10000;

        // add initial checkpoints
        for (uint256 i = 0; i < 5; i++) {
            // vote for pool in epoch 0
            voter.vote(1, pools, weights);
            vm.prank(address(owner2));
            voter.vote(2, pools, weights);

            // fwd half a week
            skipToNextEpoch(1 hours + 1);
        }

        // create an incentive in epoch 0
        LR.approve(address(incentiveVotingReward), TOKEN_1);
        incentiveVotingReward.notifyRewardAmount(address(LR), TOKEN_1);

        // vote for pool in epoch 0
        voter.vote(1, pools, weights);
        vm.prank(address(owner2));
        voter.vote(2, pools, weights);
        skip(1);

        // fwd half a week
        skipToNextEpoch(1);

        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1 / 2);

        uint256 earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, 0);
        skip(1);

        // create an incentive for pool in epoch 1
        LR.approve(address(incentiveVotingReward), TOKEN_1);
        incentiveVotingReward.notifyRewardAmount(address(LR), TOKEN_1);
        // create an incentive for pool2 in epoch 1
        LR.approve(address(incentiveVotingReward2), TOKEN_1 * 2);
        incentiveVotingReward2.notifyRewardAmount(address(LR), TOKEN_1 * 2);
        skip(1 hours);

        voter.vote(1, pools2, weights);
        vm.prank(address(owner3));
        voter.vote(3, pools2, weights);

        // go to next week
        skipToNextEpoch(1 hours + 1);

        earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, 0);

        voter.vote(1, pools, weights);

        earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, 0);
        earned = incentiveVotingReward2.earned(address(LR), 1);
        assertEq(earned, TOKEN_1);

        pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward2.getReward(1, rewards);
        post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1);
    }

    function testCannotClaimRewardForPoolIfPokedButReset() public {
        skip(1 weeks / 2);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        // set up votes
        address[] memory pools = new address[](1);
        uint256[] memory weights = new uint256[](1);
        pools[0] = address(pool);
        weights[0] = 10000;

        // create an incentive in epoch 0
        LR.approve(address(incentiveVotingReward), TOKEN_1);
        incentiveVotingReward.notifyRewardAmount(address(LR), TOKEN_1);

        // vote for pool in epoch 0
        voter.vote(1, pools, weights);
        vm.prank(address(owner2));
        voter.vote(2, pools, weights);

        skipToNextEpoch(1);

        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1 / 2);
        skip(1);

        // create an incentive for pool in epoch 1
        LR.approve(address(incentiveVotingReward), TOKEN_1);
        incentiveVotingReward.notifyRewardAmount(address(LR), TOKEN_1);
        skip(1 hours);

        // poke causes id 1 to "vote" for pool
        voter.poke(1);
        skip(1);

        // abstain in epoch 1
        voter.reset(1);

        // go to next epoch
        skipToNextEpoch(1);

        // earned for pool should be 0
        uint256 earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, 0);
    }

    function testGetRewardWithVoteThenPoke() public {
        /// tests poking makes no difference to voting outcome
        skip(1 weeks / 2);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        // set up votes
        address[] memory pools = new address[](1);
        uint256[] memory weights = new uint256[](1);
        pools[0] = address(pool);
        weights[0] = 10000;

        // create an incentive in epoch 0
        LR.approve(address(incentiveVotingReward), TOKEN_1);
        incentiveVotingReward.notifyRewardAmount(address(LR), TOKEN_1);

        // vote for pool in epoch 0
        voter.vote(1, pools, weights);
        vm.prank(address(owner2));
        voter.vote(2, pools, weights);

        skipToNextEpoch(1);

        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1 / 2);
        skip(1);

        // create an incentive for pool in epoch 1
        LR.approve(address(incentiveVotingReward), TOKEN_1);
        incentiveVotingReward.notifyRewardAmount(address(LR), TOKEN_1);
        skip(1 hours);

        voter.vote(1, pools, weights);
        skip(1 hours);

        // get poked an hour later
        voter.poke(1);
        vm.prank(address(owner2));
        voter.vote(2, pools, weights);

        // go to next epoch
        skipToNextEpoch(1);

        // earned for pool should be 0
        uint256 earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1 / 2);
    }

    function testGetRewardWithVotesForMultiplePools() public {
        skip(1 weeks / 2);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        // set up votes
        address[] memory pools = new address[](2);
        uint256[] memory weights = new uint256[](2);
        pools[0] = address(pool);
        pools[1] = address(pool2);
        weights[0] = 2;
        weights[1] = 8;

        // create an incentive in epoch 0 for pool
        LR.approve(address(incentiveVotingReward), TOKEN_1);
        incentiveVotingReward.notifyRewardAmount(address(LR), TOKEN_1);
        // create a usdc incentive in epoch 1 for pool2
        USDC.approve(address(incentiveVotingReward2), USDC_1);
        incentiveVotingReward2.notifyRewardAmount(address(USDC), USDC_1);

        // vote for pool in epoch 0
        voter.vote(1, pools, weights); // 20% to pool, 80% to pool2

        // flip weights around
        weights[0] = 8;
        weights[1] = 2;
        vm.prank(address(owner2));
        voter.vote(2, pools, weights); // 80% to pool, 20% to pool2

        skipToNextEpoch(1);

        // check pool incentives are correct
        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1 / 5);

        pre = LR.balanceOf(address(owner2));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(2, rewards);
        post = LR.balanceOf(address(owner2));
        assertEq(post - pre, (TOKEN_1 * 4) / 5);

        // check pool2 incentives are correct
        rewards[0] = address(USDC);
        pre = USDC.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward2.getReward(1, rewards);
        post = USDC.balanceOf(address(owner));
        assertEq(post - pre, (USDC_1 * 4) / 5);

        pre = USDC.balanceOf(address(owner2));
        vm.prank(address(voter));
        incentiveVotingReward2.getReward(2, rewards);
        post = USDC.balanceOf(address(owner2));
        assertEq(post - pre, USDC_1 / 5);
    }

    function testCannotGetRewardForNewPoolVotedAfterEpochFlip() public {
        skip(1 weeks / 2);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        // set up votes
        address[] memory pools = new address[](1);
        uint256[] memory weights = new uint256[](1);
        pools[0] = address(pool);
        weights[0] = 10000;

        // create an incentive for pool and pool2 in epoch 0
        LR.approve(address(incentiveVotingReward), TOKEN_1);
        incentiveVotingReward.notifyRewardAmount(address(LR), TOKEN_1);
        USDC.approve(address(incentiveVotingReward2), USDC_1);
        incentiveVotingReward2.notifyRewardAmount(address(USDC), USDC_1);

        // vote for pool in epoch 0
        voter.vote(1, pools, weights);
        vm.prank(address(owner2));
        voter.vote(2, pools, weights);

        // owner3 votes for pool2
        pools[0] = address(pool2);
        vm.prank(address(owner3));
        voter.vote(3, pools, weights);

        // go to next epoch but do not distribute
        skipToNextEpoch(1 hours + 1);

        // vote for pool2 shortly after epoch flips
        voter.vote(1, pools, weights);
        skip(1);

        // attempt to claim from initial pool currently voted for fails
        uint256 pre = USDC.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward2.getReward(1, rewards);
        uint256 post = USDC.balanceOf(address(owner));
        assertEq(post - pre, 0);

        // claim last week's rewards
        pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(1, rewards);
        post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1 / 2);
    }

    function testCannotGetRewardInSameEpochAsVote() public {
        skip(1 weeks / 2);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        // set up votes
        address[] memory pools = new address[](1);
        uint256[] memory weights = new uint256[](1);
        pools[0] = address(pool);
        weights[0] = 10000;

        // create an incentive for pool in epoch 0
        LR.approve(address(incentiveVotingReward), TOKEN_1);
        incentiveVotingReward.notifyRewardAmount(address(LR), TOKEN_1);
        skip(1);

        // vote for pool in epoch 0
        voter.vote(1, pools, weights);
        vm.prank(address(owner2));
        voter.vote(2, pools, weights);
        skip(1);

        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        assertEq(post - pre, 0);

        skipToNextEpoch(1);

        // create an incentive for pool in epoch 1
        LR.approve(address(incentiveVotingReward), TOKEN_1 * 2);
        incentiveVotingReward.notifyRewardAmount(address(LR), TOKEN_1 * 2);
        skip(1 hours);

        // vote for pool in epoch 1
        voter.vote(1, pools, weights);
        vm.prank(address(owner2));
        voter.vote(2, pools, weights);
        skip(1);

        // attempt claim again after vote, only get rewards from epoch 0
        pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(1, rewards);
        post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1 / 2);

        skipToNextEpoch(1);

        pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(1, rewards);
        post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1);
    }

    function testCannotGetRewardInSameEpochAsVoteWithFuzz(uint256 ts) public {
        skipToNextEpoch(1 hours + 1);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        // set up votes
        address[] memory pools = new address[](1);
        uint256[] memory weights = new uint256[](1);
        pools[0] = address(pool);
        weights[0] = 10000;

        // create an incentive for pool in epoch 0
        LR.approve(address(incentiveVotingReward), TOKEN_1);
        incentiveVotingReward.notifyRewardAmount(address(LR), TOKEN_1);

        // vote for pool in epoch 0
        voter.vote(1, pools, weights);
        vm.prank(address(owner2));

        ts = bound(ts, 0, 1 weeks - (1 hours) - 2);
        skipAndRoll(ts);

        assertEq(incentiveVotingReward.earned(address(LR), 1), 0);
    }

    function testGetRewardWithVoteAndNotifyRewardInDifferentOrders() public {
        skip(1 weeks / 2);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        // set up votes
        address[] memory pools = new address[](1);
        uint256[] memory weights = new uint256[](1);
        pools[0] = address(pool);
        weights[0] = 10000;

        // create an incentive for pool in epoch 0
        LR.approve(address(incentiveVotingReward), TOKEN_1);
        incentiveVotingReward.notifyRewardAmount(address(LR), TOKEN_1);
        skip(1 hours);

        // vote for pool in epoch 0
        voter.vote(1, pools, weights);
        vm.prank(address(owner2));
        voter.vote(2, pools, weights);
        skip(1);

        uint256 earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, 0);

        skipToNextEpoch(1);

        earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1 / 2);
        skip(1 hours);

        // vote first, then create incentive
        voter.vote(1, pools, weights);
        vm.prank(address(owner2));
        voter.vote(2, pools, weights);
        skip(1);

        earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1 / 2);

        LR.approve(address(incentiveVotingReward), TOKEN_1 * 2);
        incentiveVotingReward.notifyRewardAmount(address(LR), TOKEN_1 * 2);
        skip(1);

        earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1 / 2);

        skipToNextEpoch(1);

        earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, (TOKEN_1 * 3) / 2);

        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        assertEq(post - pre, (TOKEN_1 * 3) / 2);
    }

    function testDepositAndWithdrawCreatesCheckpoints() public {
        skip(1 weeks / 2);

        uint256 epoch = incentiveVotingReward.epoch();
        assertEq(epoch, 0); // no existing checkpoints

        IVotingEscrow.GlobalPoint memory grp = incentiveVotingReward.globalRewardPointHistory(1); // starts from 1
        assertEq(grp.bias, 0);
        assertEq(grp.slope, 0);
        assertEq(grp.ts, 0);
        assertEq(grp.permanentLockBalance, 0);

        uint256 userEpoch = incentiveVotingReward.userRewardEpoch(1);
        assertEq(userEpoch, 0);

        // deposit by voting
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        voter.vote(1, pools, weights);

        uint256 expectedTs = block.timestamp;
        uint256 expectedBal = escrow.balanceOfNFT(1);
        IVotingEscrow.LockedBalance memory locked = escrow.locked(1);

        // check single user and supply checkpoint created
        epoch = incentiveVotingReward.epoch();
        assertEq(epoch, 1);

        uint256 slope = expectedBal / (locked.end - expectedTs); // this should not change in this test

        grp = incentiveVotingReward.globalRewardPointHistory(1);
        assertEq(grp.ts, expectedTs);
        assertEq(convert(grp.bias), expectedBal);
        assertEq(convert(grp.slope), slope);
        assertEq(grp.permanentLockBalance, 0);

        userEpoch = incentiveVotingReward.userRewardEpoch(1);
        assertEq(userEpoch, 1);
        IVotingEscrow.UserPoint memory urp = incentiveVotingReward.userRewardPointHistory(1, 1);
        assertEq(convert(urp.bias), expectedBal);
        assertEq(convert(urp.slope), slope);
        assertEq(urp.permanent, 0);
        assertEq(incentiveVotingReward.lockExpiry(1), locked.end);
        assertEq(urp.ts, expectedTs);

        assertEq(incentiveVotingReward.slopeChanges(locked.end), -toInt128(slope));
        assertEq(incentiveVotingReward.biasCorrections(locked.end), 0);

        skipToNextEpoch(1 hours + 1);

        // withdraw by voting for other pool
        pools[0] = address(pool2);
        voter.vote(1, pools, weights);

        uint256 expectedTs2 = block.timestamp;
        int128 prevBias = grp.bias;

        epoch = incentiveVotingReward.epoch();
        assertEq(epoch, 2);

        // check new checkpoint created
        // should withdraw the full weight
        grp = incentiveVotingReward.globalRewardPointHistory(2); // checkpoint at current timestamp
        assertEq(grp.ts, expectedTs2);
        assertEq(convert(grp.bias), 0);
        assertEq(convert(grp.slope), 0);
        assertEq(grp.permanentLockBalance, 0);

        // next user checkpoint should be zero weight
        userEpoch = incentiveVotingReward.userRewardEpoch(1);
        assertEq(userEpoch, 2);
        urp = incentiveVotingReward.userRewardPointHistory(1, 2);
        assertEq(convert(urp.bias), 0);
        assertEq(convert(urp.slope), 0);
        assertEq(urp.permanent, 0);
        assertEq(urp.ts, expectedTs2);
        assertEq(incentiveVotingReward.lockExpiry(1), 0);

        assertEq(incentiveVotingReward.slopeChanges(locked.end), 0);
        assertEq(incentiveVotingReward.biasCorrections(locked.end), 0);

        // validate the other pool where we voted too
        epoch = incentiveVotingReward2.epoch();
        assertEq(epoch, 1);
        expectedBal = escrow.balanceOfNFT(1);

        grp = incentiveVotingReward2.globalRewardPointHistory(1);
        assertEq(grp.ts, expectedTs2);
        assertEq(convert(grp.bias), expectedBal);
        assertEq(convert(grp.slope), slope);
        assertEq(grp.permanentLockBalance, 0);

        userEpoch = incentiveVotingReward2.userRewardEpoch(1);
        assertEq(userEpoch, 1);
        urp = incentiveVotingReward2.userRewardPointHistory(1, 1);
        assertEq(convert(urp.bias), expectedBal);
        assertEq(convert(urp.slope), slope);
        assertEq(urp.permanent, 0);
        assertEq(urp.ts, expectedTs2);
        assertEq(incentiveVotingReward2.lockExpiry(1), locked.end);

        assertEq(incentiveVotingReward2.slopeChanges(locked.end), -toInt128(slope));
        assertEq(incentiveVotingReward.biasCorrections(locked.end), 0);
    }

    function testDepositAndWithdrawWithinSameEpochOverwritesCheckpoints() public {
        skip(1 weeks / 2);

        // test vote and poke overwrites checkpoints
        // deposit by voting
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;

        voter.vote(1, pools, weights);

        uint256 expectedTs = block.timestamp;
        uint256 expectedBal = escrow.balanceOfNFT(1);
        IVotingEscrow.LockedBalance memory locked = escrow.locked(1);

        uint256 slope = expectedBal / (locked.end - expectedTs); // this should not change in this test

        uint256 epoch = incentiveVotingReward.epoch();
        assertEq(epoch, 1);

        IVotingEscrow.GlobalPoint memory grp = incentiveVotingReward.globalRewardPointHistory(1); // starts from 1
        assertEq(grp.ts, expectedTs);
        assertEq(convert(grp.bias), expectedBal);
        assertEq(convert(grp.slope), slope);
        assertEq(grp.permanentLockBalance, 0);

        uint256 userEpoch = incentiveVotingReward.userRewardEpoch(1);
        assertEq(userEpoch, 1);

        IVotingEscrow.UserPoint memory urp = incentiveVotingReward.userRewardPointHistory(1, 1);

        assertEq(convert(urp.bias), expectedBal);
        assertEq(convert(urp.slope), slope);
        assertEq(urp.permanent, 0);
        assertEq(incentiveVotingReward.lockExpiry(1), locked.end);
        assertEq(urp.ts, expectedTs);

        assertEq(incentiveVotingReward.slopeChanges(locked.end), -toInt128(slope));
        assertEq(incentiveVotingReward.biasCorrections(locked.end), 0);

        // poked after one day. any checkpoints created should overwrite prior checkpoints.
        skip(1 days);
        voter.poke(1);

        expectedTs = block.timestamp;
        expectedBal = escrow.balanceOfNFT(1);

        epoch = incentiveVotingReward.epoch();
        assertEq(epoch, 1);

        grp = incentiveVotingReward.globalRewardPointHistory(1);
        assertEq(grp.ts, expectedTs);
        assertEq(convert(grp.bias), expectedBal);
        assertEq(convert(grp.slope), slope);
        assertEq(grp.permanentLockBalance, 0);

        userEpoch = incentiveVotingReward.userRewardEpoch(1);
        assertEq(userEpoch, 1);

        urp = incentiveVotingReward.userRewardPointHistory(1, 1);
        assertEq(convert(urp.bias), expectedBal);
        assertEq(convert(urp.slope), slope);
        assertEq(urp.permanent, 0);
        assertEq(incentiveVotingReward.lockExpiry(1), locked.end);
        assertEq(urp.ts, expectedTs);

        assertEq(incentiveVotingReward.slopeChanges(locked.end), -toInt128(slope));
        assertEq(incentiveVotingReward.biasCorrections(locked.end), 0);

        // check poke and reset/withdraw overwrites checkpoints
        skipToNextEpoch(1 hours + 1);

        // poke to create a checkpoint in new epoch
        voter.poke(1);

        // check old checkpoints are not overridden
        grp = incentiveVotingReward.globalRewardPointHistory(1);
        assertEq(grp.ts, expectedTs);
        assertEq(convert(grp.bias), expectedBal);
        assertEq(convert(grp.slope), slope);
        assertEq(grp.permanentLockBalance, 0);

        urp = incentiveVotingReward.userRewardPointHistory(1, 1);
        assertEq(convert(urp.bias), expectedBal);
        assertEq(convert(urp.slope), slope);
        assertEq(urp.permanent, 0);
        assertEq(incentiveVotingReward.lockExpiry(1), locked.end);
        assertEq(urp.ts, expectedTs);

        uint256 expectedTs2 = block.timestamp;
        int128 prevBias = grp.bias;
        expectedBal = escrow.balanceOfNFT(1);

        // check new checkpoints
        epoch = incentiveVotingReward.epoch();
        assertEq(epoch, 2);

        grp = incentiveVotingReward.globalRewardPointHistory(2);
        assertEq(grp.ts, expectedTs2);
        assertEq(convert(grp.bias), expectedBal);
        assertEq(convert(grp.slope), slope);
        assertEq(grp.permanentLockBalance, 0);

        userEpoch = incentiveVotingReward.userRewardEpoch(1);
        assertEq(userEpoch, 2);

        urp = incentiveVotingReward.userRewardPointHistory(1, 2);
        assertEq(convert(urp.bias), expectedBal);
        assertEq(convert(urp.slope), slope);
        assertEq(urp.permanent, 0);
        assertEq(incentiveVotingReward.lockExpiry(1), locked.end);
        assertEq(urp.ts, expectedTs2);

        assertEq(incentiveVotingReward.slopeChanges(locked.end), -toInt128(slope));
        assertEq(incentiveVotingReward.biasCorrections(locked.end), 0);

        // withdraw via reset after one day, expect supply to be zero
        skip(1 days);
        voter.reset(1);

        expectedTs = block.timestamp;

        // overwrite checkpoint should be zero weight
        epoch = incentiveVotingReward.epoch();
        assertEq(epoch, 2);
        grp = incentiveVotingReward.globalRewardPointHistory(2);
        assertEq(grp.ts, expectedTs);
        assertEq(convert(grp.bias), 0);
        assertEq(convert(grp.slope), 0);
        assertEq(grp.permanentLockBalance, 0);

        // overwrite checkpoint should be zero weight
        userEpoch = incentiveVotingReward.userRewardEpoch(1);
        assertEq(userEpoch, 2);
        urp = incentiveVotingReward.userRewardPointHistory(1, 2);
        assertEq(convert(urp.bias), 0);
        assertEq(convert(urp.slope), 0);
        assertEq(urp.permanent, 0);
        assertEq(urp.ts, expectedTs);
        assertEq(incentiveVotingReward.lockExpiry(1), 0);

        assertEq(incentiveVotingReward.slopeChanges(locked.end), 0);
        assertEq(incentiveVotingReward.biasCorrections(locked.end), 0);
    }

    function testDepositFromManyUsersInSameTimestampOverwritesSupplyCheckpoint() public {
        skip(1 weeks / 2);

        // deposit by voting
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;

        // test two (supply) checkpoints at same ts
        voter.vote(1, pools, weights);

        uint256 ownerBal = escrow.balanceOfNFT(1);
        uint256 owner2Bal = escrow.balanceOfNFT(2);
        uint256 expectedTs = block.timestamp;

        // same end for both nft
        IVotingEscrow.LockedBalance memory locked = escrow.locked(1);

        uint256 slope = ownerBal / (locked.end - expectedTs);

        // check single user and supply checkpoint created
        uint256 epoch = incentiveVotingReward.epoch();
        assertEq(epoch, 1);

        IVotingEscrow.GlobalPoint memory grp = incentiveVotingReward.globalRewardPointHistory(1); // starts from 1
        assertEq(grp.ts, expectedTs);
        assertEq(convert(grp.bias), ownerBal);
        assertEq(convert(grp.slope), slope);
        assertEq(grp.permanentLockBalance, 0);

        uint256 userEpoch = incentiveVotingReward.userRewardEpoch(1);
        assertEq(userEpoch, 1);

        IVotingEscrow.UserPoint memory urp = incentiveVotingReward.userRewardPointHistory(1, 1);

        assertEq(convert(urp.bias), ownerBal);
        assertEq(convert(urp.slope), slope);
        assertEq(urp.permanent, 0);
        assertEq(incentiveVotingReward.lockExpiry(1), locked.end);
        assertEq(urp.ts, expectedTs);

        assertEq(incentiveVotingReward.slopeChanges(locked.end), -toInt128(slope));
        assertEq(incentiveVotingReward.biasCorrections(locked.end), 0);

        vm.prank(address(owner2));
        voter.vote(2, pools, weights);

        // check owner2 vote overwrites checkpoint correctly
        epoch = incentiveVotingReward.epoch();
        assertEq(epoch, 1);

        grp = incentiveVotingReward.globalRewardPointHistory(1); // starts from 1
        assertEq(grp.ts, expectedTs);
        assertEq(convert(grp.bias), ownerBal + owner2Bal);
        assertEq(convert(grp.slope), slope * 2);
        assertEq(grp.permanentLockBalance, 0);

        // creates user rewardpoint for owner 2
        userEpoch = incentiveVotingReward.userRewardEpoch(1);
        assertEq(userEpoch, 1);

        urp = incentiveVotingReward.userRewardPointHistory(2, 1);

        assertEq(convert(urp.bias), ownerBal);
        assertEq(convert(urp.slope), slope);
        assertEq(urp.permanent, 0);
        assertEq(incentiveVotingReward.lockExpiry(2), locked.end);
        assertEq(urp.ts, expectedTs);

        assertEq(incentiveVotingReward.slopeChanges(locked.end), -toInt128(slope * 2));
        assertEq(incentiveVotingReward.biasCorrections(locked.end), 0);
    }

    function testGetRewardWithSeparateRewardClaims() public {
        skip(1 weeks / 2);

        // create a LR incentive
        LR.approve(address(incentiveVotingReward), TOKEN_1);
        incentiveVotingReward.notifyRewardAmount(address(LR), TOKEN_1);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        voter.vote(1, pools, weights);

        vm.prank(address(owner2));
        voter.vote(2, pools, weights);

        skipToNextEpoch(1);

        // create usdc incentive, vote passively this epoch
        USDC.approve(address(incentiveVotingReward), USDC_1);
        incentiveVotingReward.notifyRewardAmount(address(USDC), USDC_1);

        uint256 earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1 / 2);

        earned = incentiveVotingReward.earned(address(USDC), 1);
        assertEq(earned, 0);

        skipToNextEpoch(1);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        // claim LR reward first
        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1 / 2);

        skipToNextEpoch(1);

        // claim USDC the week after
        rewards[0] = address(USDC);
        pre = USDC.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(1, rewards);
        post = USDC.balanceOf(address(owner));
        assertEq(post - pre, USDC_1 / 2);
    }

    function testCannotNotifyRewardWithZeroAmount() public {
        vm.expectRevert(IReward.ZeroAmount.selector);
        incentiveVotingReward.notifyRewardAmount(address(LR), 0);
    }

    function testCannotNotifyRewardWithUnwhitelistedToken() public {
        address token = address(new MockERC20("TEST", "TEST", 18));

        assertEq(voter.isWhitelistedToken(token), false);

        vm.expectRevert(IReward.NotWhitelisted.selector);
        incentiveVotingReward.notifyRewardAmount(token, TOKEN_1);
    }

    function testNotifyRewardAmountWithWhiteListedToken() public {
        LR.approve(address(incentiveVotingReward), TOKEN_1);
        uint256 pre = LR.balanceOf(address(owner));
        vm.expectEmit(true, true, true, true, address(incentiveVotingReward));
        emit NotifyReward(address(owner), address(LR), 604800, TOKEN_1);
        incentiveVotingReward.notifyRewardAmount(address(LR), TOKEN_1);
        uint256 post = LR.balanceOf(address(owner));

        assertEq(incentiveVotingReward.isReward(address(LR)), true);
        assertEq(incentiveVotingReward.tokenRewardsPerEpoch(address(LR), 604800), TOKEN_1);
        assertEq(pre - post, TOKEN_1);
        assertEq(LR.balanceOf(address(incentiveVotingReward)), TOKEN_1);

        skip(1 hours);

        LR.approve(address(incentiveVotingReward), TOKEN_1 * 2);
        pre = LR.balanceOf(address(owner));
        vm.expectEmit(true, true, true, true, address(incentiveVotingReward));
        emit NotifyReward(address(owner), address(LR), 604800, TOKEN_1 * 2);
        incentiveVotingReward.notifyRewardAmount(address(LR), TOKEN_1 * 2);
        post = LR.balanceOf(address(owner));

        assertEq(incentiveVotingReward.tokenRewardsPerEpoch(address(LR), 604800), TOKEN_1 * 3);
        assertEq(pre - post, TOKEN_1 * 2);
        assertEq(LR.balanceOf(address(incentiveVotingReward)), TOKEN_1 * 3);
    }

    function testGetRewardAfterExpiration() public {
        vm.startPrank(address(owner4));
        VELO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, 1 weeks);
        vm.stopPrank();

        skip(1 weeks / 2);

        // create a LR reward
        LR.approve(address(incentiveVotingReward), TOKEN_1);
        incentiveVotingReward.notifyRewardAmount(address(LR), TOKEN_1);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        vm.prank(address(owner4));
        voter.vote(tokenId, pools, weights);

        skipToNextEpoch(1);

        // validate nft expired
        IVotingEscrow.LockedBalance memory locked = escrow.locked(tokenId);
        assertTrue(locked.end < block.timestamp);

        uint256 earned = incentiveVotingReward.earned(address(LR), tokenId);
        assertEq(earned, TOKEN_1);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        // claim LR reward
        uint256 pre = LR.balanceOf(address(owner4));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(tokenId, rewards);
        uint256 post = LR.balanceOf(address(owner4));
        assertEq(post - pre, TOKEN_1);

        skipToNextEpoch(1);

        earned = incentiveVotingReward.earned(address(LR), tokenId);
        assertEq(earned, 0);
    }

    function testLockExpiryAndBiasCorrectionIsCorrectOnWithdrawAndDeposit() public {
        skip(1 weeks / 2);

        // vote
        address[] memory pools = new address[](2);
        uint256[] memory weights = new uint256[](2);
        pools[0] = address(pool);
        pools[1] = address(pool2);
        weights[0] = 7000;
        weights[1] = 3000;

        voter.vote(1, pools, weights);

        skipToNextEpoch(0);
        rewind(1); // we are at epochflip - 1

        IVotingEscrow.LockedBalance memory locked = escrow.locked(1);
        IReward.LockExpiryAndBiasCorrection memory lebc = incentiveVotingReward.lockExpiryAndBiasCorrection(1);
        IReward.LockExpiryAndBiasCorrection memory lebc2 = incentiveVotingReward2.lockExpiryAndBiasCorrection(1);

        uint256 rewardBias = incentiveVotingReward.balanceOfNFTAt(1, block.timestamp);
        uint256 rewardBias2 = incentiveVotingReward2.balanceOfNFTAt(1, block.timestamp);

        uint256 totalBias = escrow.balanceOfNFT(1);

        assertEq(lebc.lockExpiry, locked.end);
        assertEq(convert(lebc.biasCorrection), totalBias - rewardBias);

        assertEq(lebc2.lockExpiry, locked.end);
        assertEq(convert(lebc2.biasCorrection), totalBias / 3 - rewardBias2);

        skipToNextEpoch(1 hours + 1);

        voter.reset(1);

        lebc = incentiveVotingReward.lockExpiryAndBiasCorrection(1);
        lebc2 = incentiveVotingReward2.lockExpiryAndBiasCorrection(1);

        assertEq(lebc.lockExpiry, 0);
        assertEq(convert(lebc.biasCorrection), 0);

        assertEq(lebc2.lockExpiry, 0);
        assertEq(convert(lebc2.biasCorrection), 0);
    }

    function testGas_GetReward() public {
        skip(1 weeks / 2);

        uint256 reward = TOKEN_1;
        uint256 reward2 = TOKEN_1 * 2;

        // create an incentive
        LR.approve(address(incentiveVotingReward), reward);
        incentiveVotingReward.notifyRewardAmount((address(LR)), reward);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        voter.vote(1, pools, weights);

        skipToNextEpoch(1);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        vm.prank(address(voter));
        incentiveVotingReward.getReward(1, rewards);

        vm.snapshotGasLastCall("IncentiveVotingReward_getReward");
    }
}

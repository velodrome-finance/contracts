// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "./ExtendedBaseTest.sol";

contract SimpleIncentiveVotingRewardFlow is ExtendedBaseTest {
    function _setUp() public override {
        skip(1 hours);
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

    function testMultiEpochIncentiveVotingRewardFlow() public {
        // set up votes and rewards
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        address[] memory rewards = new address[](2);
        rewards[0] = address(LR);
        rewards[1] = address(USDC);

        // @dev note that the tokenId corresponds to the owner number
        // i.e. owner owns tokenId 1
        //      owner2 owns tokenId 2...
        // test with both LR & USDC throughout to account for different decimals

        /// epoch zero
        // test two voters with differing balances
        // owner + owner 4 votes
        // owner has max lock time
        // owner4 has quarter of max lock time
        uint256 currentIncentive = TOKEN_1;
        uint256 usdcIncentive = USDC_1;
        _createIncentiveWithAmount(incentiveVotingReward, address(LR), currentIncentive);
        _createIncentiveWithAmount(incentiveVotingReward, address(USDC), usdcIncentive);
        voter.vote(1, pools, weights); // balance: 997231719186530010
        vm.prank(address(owner4));
        voter.vote(4, pools, weights); // balance: 249286513795874010
        skipToNextEpoch(1);
        /// epoch one
        // expect distributions to be:
        // ~4 parts to owner
        // ~1 part to owner
        uint256 pre = LR.balanceOf(address(owner));
        uint256 usdcPre = USDC.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        uint256 usdcPost = USDC.balanceOf(address(owner));

        uint256 tokenId1CurrentBalance;
        {
            // tokenId4CurrentBalance only used in this scope
            uint256 tokenId4CurrentBalance;
            uint256 lockEnd = incentiveVotingReward.lockExpiry(1);

            IVotingEscrow.UserPoint memory urp1 = incentiveVotingReward.userRewardPointHistory(1, 1);
            tokenId1CurrentBalance = convert(urp1.slope) * (lockEnd - block.timestamp + 2);

            lockEnd = incentiveVotingReward.lockExpiry(4);

            IVotingEscrow.UserPoint memory urp4 = incentiveVotingReward.userRewardPointHistory(4, 1);
            tokenId4CurrentBalance = convert(urp4.slope) * (lockEnd - block.timestamp + 2);

            assertEq(
                post - pre,
                (currentIncentive * tokenId1CurrentBalance) / (tokenId1CurrentBalance + tokenId4CurrentBalance)
            );
            assertEq(
                usdcPost - usdcPre,
                (usdcIncentive * tokenId1CurrentBalance) / (tokenId1CurrentBalance + tokenId4CurrentBalance)
            );

            pre = LR.balanceOf(address(owner4));
            usdcPre = USDC.balanceOf(address(owner4));
            vm.prank(address(voter));
            incentiveVotingReward.getReward(4, rewards);
            post = LR.balanceOf(address(owner4));
            usdcPost = USDC.balanceOf(address(owner4));

            assertEq(
                post - pre,
                (currentIncentive * tokenId4CurrentBalance) / (tokenId1CurrentBalance + tokenId4CurrentBalance)
            );
            assertEq(
                usdcPost - usdcPre,
                (usdcIncentive * tokenId4CurrentBalance) / (tokenId1CurrentBalance + tokenId4CurrentBalance)
            );
        }
        // test incentive delivered late in the week
        skip(1 weeks / 2);
        currentIncentive = TOKEN_1 * 2;
        usdcIncentive = USDC_1 * 2;
        _createIncentiveWithAmount(incentiveVotingReward, address(LR), currentIncentive);
        _createIncentiveWithAmount(incentiveVotingReward, address(USDC), usdcIncentive);
        skip(1);

        voter.vote(1, pools, weights);
        vm.prank(address(owner2));
        voter.vote(2, pools, weights);
        vm.prank(address(owner4));
        voter.reset(4);

        /// epoch two
        skipToNextEpoch(1);

        pre = LR.balanceOf(address(owner));
        usdcPre = USDC.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(1, rewards);
        post = LR.balanceOf(address(owner));
        usdcPost = USDC.balanceOf(address(owner));
        assertEq(post - pre, currentIncentive / 2);
        assertEq(usdcPost - usdcPre, usdcIncentive / 2);

        pre = LR.balanceOf(address(owner2));
        usdcPre = USDC.balanceOf(address(owner2));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(2, rewards);
        post = LR.balanceOf(address(owner2));
        usdcPost = USDC.balanceOf(address(owner2));
        assertEq(post - pre, currentIncentive / 2);
        assertEq(usdcPost - usdcPre, usdcIncentive / 2);

        // test deferred claiming of incentives
        uint256 deferredIncentive = TOKEN_1 * 3;
        uint256 deferredUsdcIncentive = USDC_1 * 3;
        _createIncentiveWithAmount(incentiveVotingReward, address(LR), deferredIncentive);
        _createIncentiveWithAmount(incentiveVotingReward, address(USDC), deferredUsdcIncentive);
        skip(1 hours);

        voter.vote(1, pools, weights);
        vm.prank(address(owner2));
        voter.vote(2, pools, weights);

        /// epoch three
        skipToNextEpoch(1);

        // test multiple reward tokens for pool2
        currentIncentive = TOKEN_1 * 4;
        usdcIncentive = USDC_1 * 4;
        _createIncentiveWithAmount(incentiveVotingReward2, address(LR), currentIncentive);
        _createIncentiveWithAmount(incentiveVotingReward2, address(USDC), usdcIncentive);
        skip(1);

        {
            // skip claiming this epoch, but check earned
            uint256 earned_ = incentiveVotingReward.earned(address(LR), 1);
            assertEq(earned_, deferredIncentive / 2);
            earned_ = incentiveVotingReward.earned(address(USDC), 1);
            assertEq(earned_, deferredUsdcIncentive / 2);
            earned_ = incentiveVotingReward.earned(address(LR), 2);
            assertEq(earned_, deferredIncentive / 2);
            earned_ = incentiveVotingReward.earned(address(USDC), 2);
            assertEq(earned_, deferredUsdcIncentive / 2);
            skip(1 hours);
        }

        // vote for pool2 instead with owner3
        pools[0] = address(pool2);
        voter.vote(1, pools, weights);
        vm.prank(address(owner3));
        voter.vote(3, pools, weights);

        /// epoch four
        skipToNextEpoch(1);

        // claim for first voter
        pre = LR.balanceOf(address(owner));
        usdcPre = USDC.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward2.getReward(1, rewards);
        post = LR.balanceOf(address(owner));
        usdcPost = USDC.balanceOf(address(owner));
        assertEq(post - pre, currentIncentive / 2);
        assertEq(usdcPost - usdcPre, usdcIncentive / 2);

        // claim for second voter
        pre = LR.balanceOf(address(owner3));
        usdcPre = USDC.balanceOf(address(owner3));
        vm.prank(address(voter));
        incentiveVotingReward2.getReward(3, rewards);
        post = LR.balanceOf(address(owner3));
        usdcPost = USDC.balanceOf(address(owner3));
        assertEq(post - pre, currentIncentive / 2);
        assertEq(usdcPost - usdcPre, usdcIncentive / 2);

        // claim deferred incentive
        pre = LR.balanceOf(address(owner));
        usdcPre = USDC.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(1, rewards);
        post = LR.balanceOf(address(owner));
        usdcPost = USDC.balanceOf(address(owner));
        assertEq(post - pre, deferredIncentive / 2);
        assertEq(usdcPost - usdcPre, deferredUsdcIncentive / 2);

        pre = LR.balanceOf(address(owner2));
        usdcPre = USDC.balanceOf(address(owner2));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(2, rewards);
        post = LR.balanceOf(address(owner2));
        usdcPost = USDC.balanceOf(address(owner2));
        assertEq(post - pre, deferredIncentive / 2);
        assertEq(usdcPost - usdcPre, deferredUsdcIncentive / 2);

        // test staggered votes
        currentIncentive = TOKEN_1 * 5;
        usdcIncentive = USDC_1 * 5;
        _createIncentiveWithAmount(incentiveVotingReward, address(LR), currentIncentive);
        _createIncentiveWithAmount(incentiveVotingReward, address(USDC), usdcIncentive);
        skip(1 hours);

        // owner re-locks to max time, is currently 4 weeks ahead
        escrow.increaseUnlockTime(1, MAX_TIME);

        pools[0] = address(pool);
        vm.prank(address(owner2));
        voter.vote(2, pools, weights); // balance: 978053644924474005
        skip(1 days);
        voter.vote(1, pools, weights); // balance: 996546795607210005

        /// epoch five
        skipToNextEpoch(1);

        // owner share: 992465745379384005/(973287663189880005+992465745379384005) ~= .505 note: decay included
        pre = LR.balanceOf(address(owner));
        usdcPre = USDC.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(1, rewards);
        post = LR.balanceOf(address(owner));
        usdcPost = USDC.balanceOf(address(owner));

        uint256 tokenId2CurrentBalance;
        {
            uint256 lockEnd = incentiveVotingReward.lockExpiry(1);

            IVotingEscrow.UserPoint memory urp1 =
                incentiveVotingReward.userRewardPointHistory(1, incentiveVotingReward.userRewardEpoch(1));
            tokenId1CurrentBalance = convert(urp1.slope) * (lockEnd - block.timestamp + 2);

            lockEnd = incentiveVotingReward.lockExpiry(2);

            IVotingEscrow.UserPoint memory urp2 =
                incentiveVotingReward.userRewardPointHistory(2, incentiveVotingReward.userRewardEpoch(2));
            tokenId2CurrentBalance = convert(urp2.slope) * (lockEnd - block.timestamp + 2);
        }

        assertEq(
            post - pre, (currentIncentive * tokenId1CurrentBalance) / (tokenId1CurrentBalance + tokenId2CurrentBalance)
        );

        assertEq(
            usdcPost - usdcPre,
            (usdcIncentive * tokenId1CurrentBalance) / (tokenId1CurrentBalance + tokenId2CurrentBalance)
        );

        // owner2 share: 973287663189880005/(992465745379384005+973287663189880005) ~= .495 note: decay included
        pre = LR.balanceOf(address(owner2));
        usdcPre = USDC.balanceOf(address(owner2));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(2, rewards);
        post = LR.balanceOf(address(owner2));
        usdcPost = USDC.balanceOf(address(owner2));
        assertEq(
            post - pre, (currentIncentive * tokenId2CurrentBalance) / (tokenId1CurrentBalance + tokenId2CurrentBalance)
        );

        assertEq(
            usdcPost - usdcPre,
            (usdcIncentive * tokenId2CurrentBalance) / (tokenId1CurrentBalance + tokenId2CurrentBalance)
        );

        currentIncentive = TOKEN_1 * 6;
        usdcIncentive = USDC_1 * 6;
        _createIncentiveWithAmount(incentiveVotingReward, address(LR), currentIncentive);
        _createIncentiveWithAmount(incentiveVotingReward, address(USDC), usdcIncentive);

        // test votes with different vote size
        // owner2 increases amount
        vm.startPrank(address(owner2));
        VELO.approve(address(escrow), TOKEN_1);
        escrow.increaseAmount(2, TOKEN_1);
        vm.stopPrank();

        skip(1 hours);

        voter.vote(1, pools, weights); // balance: 992437206566602005
        vm.prank(address(owner2));
        voter.vote(2, pools, weights); // balance: 1946518248876966809

        /// epoch six
        skipToNextEpoch(1);

        // owner share: 992437206566602005/(992437206566602005+1946518248876966809) ~= .338
        pre = LR.balanceOf(address(owner));
        usdcPre = USDC.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(1, rewards);
        post = LR.balanceOf(address(owner));
        usdcPost = USDC.balanceOf(address(owner));
        assertApproxEqRel(post - pre, (currentIncentive * 338) / 1000, 1e15); // 3 decimal places
        assertApproxEqRel(usdcPost - usdcPre, (usdcIncentive * 338) / 1000, 1e15);

        // owner2 share: 1946518248876966809/(992437206566602005+1946518248876966809) ~= .662
        pre = LR.balanceOf(address(owner2));
        usdcPre = USDC.balanceOf(address(owner2));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(2, rewards);
        post = LR.balanceOf(address(owner2));
        usdcPost = USDC.balanceOf(address(owner2));
        assertApproxEqRel(post - pre, (currentIncentive * 662) / 1000, 1e15);
        assertApproxEqRel(usdcPost - usdcPre, (usdcIncentive * 662) / 1000, 1e15);

        skip(1 hours);
        // stop voting with owner2
        vm.prank(address(owner2));
        voter.reset(2);

        // test multiple pools. only incentive pool1 with LR, pool2 with USDC
        // create normal incentives for pool
        currentIncentive = TOKEN_1 * 7;
        _createIncentiveWithAmount(incentiveVotingReward, address(LR), currentIncentive);
        // create usdc incentive for pool2
        usdcIncentive = USDC_1 * 7;
        _createIncentiveWithAmount(incentiveVotingReward2, address(USDC), usdcIncentive);
        skip(1);

        // re-lock owner + owner3
        escrow.increaseUnlockTime(1, MAX_TIME);
        vm.prank(address(owner3));
        escrow.increaseUnlockTime(3, MAX_TIME);
        skip(1 hours);

        pools = new address[](2);
        weights = new uint256[](2);
        pools[0] = address(pool);
        pools[1] = address(pool2);
        weights[0] = 2000;
        weights[1] = 8000;

        voter.vote(1, pools, weights); // 1 votes 20% pool 80 pool2
        weights[0] = 8000;
        weights[1] = 2000;
        vm.prank(address(owner3));
        voter.vote(3, pools, weights); // 3 votes 80% pool 20%% pool2

        skipToNextEpoch(1);

        // owner should receive 1/5, owner3 should receive 4/5 of pool incentives
        pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(1, rewards);
        post = LR.balanceOf(address(owner));
        assertEq(post - pre, currentIncentive / 5);

        pre = LR.balanceOf(address(owner3));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(3, rewards);
        post = LR.balanceOf(address(owner3));
        assertEq(post - pre, (currentIncentive * 4) / 5);

        // owner should receive 4/5, owner3 should receive 1/5 of pool2 incentives
        rewards[0] = address(USDC);
        delete rewards[1];
        usdcPre = USDC.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward2.getReward(1, rewards);
        usdcPost = USDC.balanceOf(address(owner));
        assertEq(usdcPost - usdcPre, (usdcIncentive * 4) / 5);

        usdcPre = USDC.balanceOf(address(owner3));
        vm.prank(address(voter));
        incentiveVotingReward2.getReward(3, rewards);
        usdcPost = USDC.balanceOf(address(owner3));
        assertEq(usdcPost - usdcPre, usdcIncentive / 5);

        skipToNextEpoch(1);

        // test passive voting
        currentIncentive = TOKEN_1 * 8;
        usdcIncentive = USDC_1 * 8;
        _createIncentiveWithAmount(incentiveVotingReward, address(LR), currentIncentive);
        _createIncentiveWithAmount(incentiveVotingReward, address(USDC), usdcIncentive);
        skip(1 hours);

        pools = new address[](1);
        weights = new uint256[](1);
        pools[0] = address(pool);
        weights[0] = 500;
        rewards[0] = address(LR);
        rewards[1] = address(USDC);
        voter.vote(1, pools, weights);
        vm.prank(address(owner3));
        voter.vote(3, pools, weights);

        skipToNextEpoch(1);

        // check earned
        uint256 earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, currentIncentive / 2);
        earned = incentiveVotingReward.earned(address(USDC), 1);
        assertEq(earned, usdcIncentive / 2);
        earned = incentiveVotingReward.earned(address(LR), 3);
        assertEq(earned, currentIncentive / 2);
        earned = incentiveVotingReward.earned(address(USDC), 3);
        assertEq(earned, usdcIncentive / 2);

        currentIncentive = TOKEN_1 * 9;
        usdcIncentive = USDC_1 * 9;
        _createIncentiveWithAmount(incentiveVotingReward, address(LR), currentIncentive);
        _createIncentiveWithAmount(incentiveVotingReward, address(USDC), usdcIncentive);

        uint256 expected = (TOKEN_1 * 8) / 2;
        // check earned remains the same even if incentive gets re-deposited
        earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, expected);
        earned = incentiveVotingReward.earned(address(LR), 3);
        assertEq(earned, expected);
        expected = (USDC_1 * 8) / 2;
        earned = incentiveVotingReward.earned(address(USDC), 1);
        assertEq(earned, expected);
        earned = incentiveVotingReward.earned(address(USDC), 3);
        assertEq(earned, expected);

        skipToNextEpoch(1);

        currentIncentive = TOKEN_1 * 10;
        usdcIncentive = USDC_1 * 10;
        _createIncentiveWithAmount(incentiveVotingReward, address(LR), currentIncentive);
        _createIncentiveWithAmount(incentiveVotingReward, address(USDC), usdcIncentive);

        expected = (TOKEN_1 * 8 + TOKEN_1 * 9) / 2;
        earned = incentiveVotingReward.earned(address(LR), 1);
        assertEq(earned, expected);
        earned = incentiveVotingReward.earned(address(LR), 3);
        assertEq(earned, expected);
        expected = (USDC_1 * 8 + USDC_1 * 9) / 2;
        earned = incentiveVotingReward.earned(address(USDC), 1);
        assertEq(earned, expected);
        earned = incentiveVotingReward.earned(address(USDC), 3);
        assertEq(earned, expected);

        skipToNextEpoch(1);

        currentIncentive = TOKEN_1 * 11;
        _createIncentiveWithAmount(incentiveVotingReward, address(LR), currentIncentive);

        pre = LR.balanceOf(address(owner));
        usdcPre = USDC.balanceOf(address(owner));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(1, rewards);
        post = LR.balanceOf(address(owner));
        usdcPost = USDC.balanceOf(address(owner));
        expected = (TOKEN_1 * 8 + TOKEN_1 * 9 + TOKEN_1 * 10) / 2;
        assertEq(post - pre, expected);
        expected = (USDC_1 * 8 + USDC_1 * 9 + USDC_1 * 10) / 2;
        assertEq(usdcPost - usdcPre, expected);

        pre = LR.balanceOf(address(owner3));
        usdcPre = USDC.balanceOf(address(owner3));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(3, rewards);
        post = LR.balanceOf(address(owner3));
        usdcPost = USDC.balanceOf(address(owner3));
        expected = (TOKEN_1 * 8 + TOKEN_1 * 9 + TOKEN_1 * 10) / 2;
        assertEq(post - pre, expected);
        expected = (USDC_1 * 8 + USDC_1 * 9 + USDC_1 * 10) / 2;
        assertEq(usdcPost - usdcPre, expected);
    }

    function testCanClaimRewardAfterTransferWhileVoted() public {
        // set up votes and rewards
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        address[] memory rewards = new address[](2);
        rewards[0] = address(LR);
        rewards[1] = address(USDC);

        uint256 currentIncentive = TOKEN_1;
        uint256 usdcIncentive = USDC_1;
        _createIncentiveWithAmount(incentiveVotingReward, address(LR), currentIncentive);
        _createIncentiveWithAmount(incentiveVotingReward, address(USDC), usdcIncentive);
        voter.vote(1, pools, weights);
        vm.prank(address(owner4));
        voter.vote(4, pools, weights);

        skip(1 days);

        // simulate sale of nft to other owner3
        escrow.transferFrom(address(owner), address(owner3), 1);
        assertFalse(escrow.isApprovedOrOwner(address(owner), 1));

        skipToNextEpoch(1);

        /// epoch one
        // expect distributions to be:
        // ~4 parts to owner3 (new owner of nft)
        // ~1 part to owner4
        uint256 pre = LR.balanceOf(address(owner3));
        uint256 usdcPre = USDC.balanceOf(address(owner3));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner3));
        uint256 usdcPost = USDC.balanceOf(address(owner3));

        uint256 tokenId1LRBalance = post - pre;
        uint256 tokenId1USDCBalance = usdcPost - usdcPre;

        uint256 tokenId1CurrentBalance;
        uint256 tokenId4CurrentBalance;
        {
            uint256 lockEnd = incentiveVotingReward.lockExpiry(1);

            IVotingEscrow.UserPoint memory urp1 = incentiveVotingReward.userRewardPointHistory(1, 1);
            tokenId1CurrentBalance = convert(urp1.slope) * (lockEnd - block.timestamp + 2);

            lockEnd = incentiveVotingReward.lockExpiry(4);

            IVotingEscrow.UserPoint memory urp2 = incentiveVotingReward.userRewardPointHistory(4, 1);
            tokenId4CurrentBalance = convert(urp2.slope) * (lockEnd - block.timestamp + 2);
        }

        assertEq(
            tokenId1LRBalance,
            (currentIncentive * tokenId1CurrentBalance) / (tokenId1CurrentBalance + tokenId4CurrentBalance)
        );
        assertEq(
            tokenId1USDCBalance,
            (usdcIncentive * tokenId1CurrentBalance) / (tokenId1CurrentBalance + tokenId4CurrentBalance)
        );

        // check tokenId4
        pre = LR.balanceOf(address(owner4));
        usdcPre = USDC.balanceOf(address(owner4));
        vm.prank(address(voter));
        incentiveVotingReward.getReward(4, rewards);
        post = LR.balanceOf(address(owner4));
        usdcPost = USDC.balanceOf(address(owner4));

        uint256 tokenId4LRBalance = post - pre;
        uint256 tokenId4USDCBalance = usdcPost - usdcPre;

        assertEq(
            tokenId4LRBalance,
            (currentIncentive * tokenId4CurrentBalance) / (tokenId1CurrentBalance + tokenId4CurrentBalance)
        );
        assertEq(
            tokenId4USDCBalance,
            (usdcIncentive * tokenId4CurrentBalance) / (tokenId1CurrentBalance + tokenId4CurrentBalance)
        );

        assertApproxEqAbs(tokenId1LRBalance + tokenId4LRBalance, TOKEN_1, 1);
        assertApproxEqAbs(tokenId1USDCBalance + tokenId4USDCBalance, USDC_1, 1);
    }
}

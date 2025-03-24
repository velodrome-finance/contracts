// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "./ExtendedBaseTest.sol";

contract VotingReward is ExtendedBaseTest {
    uint256 tokenId;
    uint256 tokenId2;

    address[] pools;
    uint256[] weights;
    address[] rewards;

    uint256 currentIncentive;
    uint256 usdcIncentive;
    uint256 expectedTs;
    uint256 tokenIdExpectedBal;
    uint256 tokenId2ExpectedBal;
    uint256 tokenIdExpectedSlope;
    uint256 tokenId2ExpectedSlope;

    uint256 pool2_tokenIdExpectedBal;
    uint256 pool2_tokenId2ExpectedBal;
    uint256 pool2_tokenIdExpectedSlope;
    uint256 pool2_tokenId2ExpectedSlope;

    function _setUp() public override {
        VELO.approve(address(escrow), TOKEN_1);
        tokenId = escrow.createLock(TOKEN_1, MAX_TIME);

        // create smaller veNFTs
        vm.startPrank(address(owner2));
        VELO.approve(address(escrow), TOKEN_1);
        tokenId2 = escrow.createLock(TOKEN_1, MAX_TIME / 2);
        vm.stopPrank();

        skip(1);

        // set up votes and rewards
        pools = new address[](2);
        pools[0] = address(pool);
        pools[1] = address(pool2);
        weights = new uint256[](2);
        weights[0] = 5000;
        weights[1] = 5000;
        rewards = new address[](2);
        rewards[0] = address(LR);
        rewards[1] = address(USDC);

        currentIncentive = TOKEN_1;
        usdcIncentive = USDC_1;
    }

    function testVotingGetRewardFlow() public {
        // owner owns nft with id: tokenId with amount: TOKEN_1
        // owner2 owns nft with id: tokenId2 with amount: TOKEN_1 (locked for 2 year, but later it extended to MAXTIME)
        // incentives are always TOKEN_1 and USDC_1
        // votes are 50-50 between pool and pool2, but only add rewards to pool during this test

        skip(1 hours + 1);

        // check initial state
        // no cp
        _assertGlobalRewardPoint({
            expectedEpoch: 0,
            rewardContract: address(incentiveVotingReward),
            bias: 0,
            slope: 0,
            ts: 0,
            permanentLockBalance: 0
        });
        _assertUserRewardPoint({
            _tokenId: tokenId,
            expectedUserEpoch: 0,
            rewardContract: address(incentiveVotingReward),
            bias: 0,
            slope: 0,
            ts: 0,
            permanent: 0,
            expectedEnd: 0,
            additionalSlope: 0
        });

        // EPOCH 1
        // should write 1 new global cp
        // 1 new user reward cp for each
        // epoch:               1
        // tokenId userEpoch:   1
        // tokenId2 userEpoch:  1

        // set up initial votes for multiple pools
        _createIncentiveWithAmount(incentiveVotingReward, address(LR), currentIncentive);
        _createIncentiveWithAmount(incentiveVotingReward, address(USDC), usdcIncentive);
        voter.vote(tokenId, pools, weights);
        vm.prank(address(owner2));
        voter.vote(tokenId2, pools, weights);

        expectedTs = block.timestamp;
        tokenIdExpectedBal = escrow.balanceOfNFT(tokenId) / 2; // votes are 50-50
        tokenId2ExpectedBal = escrow.balanceOfNFT(tokenId2) / 2;

        IVotingEscrow.LockedBalance memory tokenIdLocked = escrow.locked(tokenId);
        tokenIdExpectedSlope = tokenIdExpectedBal / (tokenIdLocked.end - expectedTs);

        IVotingEscrow.LockedBalance memory tokenId2Locked = escrow.locked(tokenId2);
        tokenId2ExpectedSlope = tokenId2ExpectedBal / (tokenId2Locked.end - expectedTs);

        // votes are 50-50 between two pools
        // check owner
        _assertUserRewardPoint({
            _tokenId: tokenId,
            expectedUserEpoch: 1,
            rewardContract: address(incentiveVotingReward),
            bias: tokenIdExpectedBal,
            slope: tokenIdExpectedSlope,
            ts: expectedTs,
            permanent: 0,
            expectedEnd: tokenIdLocked.end,
            additionalSlope: 0
        });
        // check owner2
        _assertUserRewardPoint({
            _tokenId: tokenId2,
            expectedUserEpoch: 1,
            rewardContract: address(incentiveVotingReward),
            bias: tokenId2ExpectedBal,
            slope: tokenId2ExpectedSlope,
            ts: expectedTs,
            permanent: 0,
            expectedEnd: tokenId2Locked.end,
            additionalSlope: 0
        });

        // check global reward point
        _assertGlobalRewardPoint({
            expectedEpoch: 1,
            rewardContract: address(incentiveVotingReward),
            bias: tokenIdExpectedBal + tokenId2ExpectedBal,
            slope: tokenIdExpectedSlope + tokenId2ExpectedSlope,
            ts: expectedTs,
            permanentLockBalance: 0
        });

        // check biasCorrections for both owner
        assertEq(incentiveVotingReward.biasCorrections(tokenIdLocked.end), -300598);
        assertEq(incentiveVotingReward.biasCorrections(tokenId2Locked.end), -300598);

        skipToNextEpoch(1);
        // EPOCH 2
        // should write 1 new global cp
        // 1 new user reward cp for each
        // epoch:               2
        // tokenId userEpoch:   2
        // tokenId2 userEpoch:  2

        uint256 firstEpochTokenIdEarned;
        uint256 firstEpochTokenIdUsdcEarned;

        {
            uint256 decreasedTokenIdBalance =
                tokenIdExpectedBal - tokenIdExpectedSlope * (block.timestamp - expectedTs - 2); // substract 2 because we skipped one in this epoch and we do -1 in earned

            // sanity check
            assertApproxEqAbs(decreasedTokenIdBalance, escrow.balanceOfNFTAt(tokenId, block.timestamp - 2) / 2, 300598); // delta should be the bias correction

            uint256 decreasedTokenId2Balance =
                tokenId2ExpectedBal - tokenId2ExpectedSlope * (block.timestamp - expectedTs - 2);

            // sanity check
            assertApproxEqAbs(
                decreasedTokenId2Balance, escrow.balanceOfNFTAt(tokenId2, block.timestamp - 2) / 2, 300598
            ); // delta should be the bias correction

            // check owner's earned and cache it
            (firstEpochTokenIdEarned, firstEpochTokenIdUsdcEarned) = _checkEarnedNoClaim({
                _tokenId: tokenId,
                rewardContract: address(incentiveVotingReward),
                _currentIncentive: currentIncentive,
                _usdcIncentive: usdcIncentive,
                rewards: rewards,
                balance: decreasedTokenIdBalance,
                totalBalance: decreasedTokenIdBalance + decreasedTokenId2Balance
            });

            // check owner2's earned
            _checkEarnedNoClaim({
                _tokenId: tokenId2,
                rewardContract: address(incentiveVotingReward),
                _currentIncentive: currentIncentive,
                _usdcIncentive: usdcIncentive,
                rewards: rewards,
                balance: decreasedTokenId2Balance,
                totalBalance: decreasedTokenIdBalance + decreasedTokenId2Balance
            });
        }

        skip(1 hours);

        // owner increase amount
        VELO.approve(address(escrow), TOKEN_1);
        escrow.increaseAmount(tokenId, TOKEN_1);

        vm.prank(address(owner2));
        // increase lock duration for owner2 to end at the same time as owner's
        escrow.increaseUnlockTime(tokenId2, tokenIdLocked.end - block.timestamp);
        uint256 oldTokenId2End = tokenId2Locked.end;
        tokenId2Locked = escrow.locked(tokenId2);
        assertEq(tokenIdLocked.end, tokenId2Locked.end);

        // validate that the owners reward point and global point is not yet updated (needs to poke or vote)
        // owner
        _assertUserRewardPoint({
            _tokenId: tokenId,
            expectedUserEpoch: 1,
            rewardContract: address(incentiveVotingReward),
            bias: tokenIdExpectedBal,
            slope: tokenIdExpectedSlope,
            ts: expectedTs,
            permanent: 0,
            expectedEnd: tokenIdLocked.end,
            additionalSlope: 0
        });
        // owner2
        _assertUserRewardPoint({
            _tokenId: tokenId2,
            expectedUserEpoch: 1,
            rewardContract: address(incentiveVotingReward),
            bias: tokenId2ExpectedBal,
            slope: tokenId2ExpectedSlope,
            ts: expectedTs,
            permanent: 0,
            expectedEnd: oldTokenId2End,
            additionalSlope: 0
        });

        // check global reward point
        _assertGlobalRewardPoint({
            expectedEpoch: 1,
            rewardContract: address(incentiveVotingReward),
            bias: tokenIdExpectedBal + tokenId2ExpectedBal,
            slope: tokenIdExpectedSlope + tokenId2ExpectedSlope,
            ts: expectedTs,
            permanentLockBalance: 0
        });

        // update checkpoints in reward contracts according to the new nft states
        voter.poke(tokenId);
        vm.prank(address(owner2));
        voter.poke(tokenId2);

        expectedTs = block.timestamp;

        // recalculate slope and bias for both owners
        tokenIdExpectedBal = escrow.balanceOfNFT(tokenId) / 2; // @note: votes still 50-50
        tokenId2ExpectedBal = escrow.balanceOfNFT(tokenId2) / 2;

        tokenIdExpectedSlope = tokenIdExpectedBal / (tokenIdLocked.end - expectedTs);
        tokenId2ExpectedSlope = tokenId2ExpectedBal / (tokenId2Locked.end - expectedTs);

        // votes are still 50-50 between two pools
        // check owner
        _assertUserRewardPoint({
            _tokenId: tokenId,
            expectedUserEpoch: 2,
            rewardContract: address(incentiveVotingReward),
            bias: tokenIdExpectedBal,
            slope: tokenIdExpectedSlope,
            ts: expectedTs,
            permanent: 0,
            expectedEnd: tokenIdLocked.end,
            additionalSlope: tokenId2ExpectedSlope
        });
        // check owner2
        _assertUserRewardPoint({
            _tokenId: tokenId2,
            expectedUserEpoch: 2,
            rewardContract: address(incentiveVotingReward),
            bias: tokenId2ExpectedBal,
            slope: tokenId2ExpectedSlope,
            ts: expectedTs,
            permanent: 0,
            expectedEnd: tokenId2Locked.end,
            additionalSlope: tokenIdExpectedSlope
        });

        // explicitly check old slope change for owner2 is canceled
        assertEq(incentiveVotingReward.slopeChanges(oldTokenId2End), 0);
        // explicitly check old bias correction for owner2 is cancelled
        assertEq(incentiveVotingReward.biasCorrections(oldTokenId2End), 0);

        // biasCorrections for both owner is at the same time (-300599 * 2)
        assertEq(incentiveVotingReward.biasCorrections(tokenIdLocked.end), -601198);

        // check global reward point
        _assertGlobalRewardPoint({
            expectedEpoch: 2,
            rewardContract: address(incentiveVotingReward),
            bias: tokenIdExpectedBal + tokenId2ExpectedBal,
            slope: tokenIdExpectedSlope + tokenId2ExpectedSlope,
            ts: expectedTs,
            permanentLockBalance: 0
        });

        skip(1 weeks / 2);
        // lock owner's nft permanently
        escrow.lockPermanent(tokenId);
        voter.poke(tokenId);

        // should overwrite previous cp since we are in the same epoch
        _assertUserRewardPoint({
            _tokenId: tokenId,
            expectedUserEpoch: 2,
            rewardContract: address(incentiveVotingReward),
            bias: 0,
            slope: 0,
            ts: block.timestamp, // @note we can't update expectedTs here because we need it later for the decreased balance calculation
            permanent: TOKEN_1, // @note only 1 because votes are 50-50
            expectedEnd: 0,
            additionalSlope: 0 // @note: tokenId2 slopechange still active
        });

        // explicitly check old slope change and bias correction for owner is canceled since we create permanent lock
        assertEq(incentiveVotingReward.slopeChanges(tokenIdLocked.end), -toInt128(tokenId2ExpectedSlope));
        assertEq(incentiveVotingReward.biasCorrections(tokenIdLocked.end), -300599);

        // only tokenId2 balance should be counted in the global bias
        uint256 decreasedTokenId2Balance = tokenId2ExpectedBal - tokenId2ExpectedSlope * (block.timestamp - expectedTs);

        // should overwrite previous global point
        _assertGlobalRewardPoint({
            expectedEpoch: 2,
            rewardContract: address(incentiveVotingReward),
            bias: decreasedTokenId2Balance,
            slope: tokenId2ExpectedSlope,
            ts: block.timestamp,
            permanentLockBalance: TOKEN_1
        });

        // add some more reward
        _createIncentiveWithAmount(incentiveVotingReward, address(LR), currentIncentive);
        _createIncentiveWithAmount(incentiveVotingReward, address(USDC), usdcIncentive);

        skipToNextEpoch(1);
        // EPOCH 3
        // same state as previous epoch since we don't deposit/withdraw
        // no new user reward cp for each
        // epoch:               2
        // tokenId userEpoch:   2
        // tokenId2 userEpoch:  2

        // recaulate owner2's balance at the time of the reward claiming
        decreasedTokenId2Balance = tokenId2ExpectedBal - tokenId2ExpectedSlope * (block.timestamp - expectedTs - 2);

        // claim rewards
        {
            // check owner
            uint256 pre = LR.balanceOf(address(owner));
            uint256 usdcPre = USDC.balanceOf(address(owner));
            incentiveVotingReward.getReward(tokenId, rewards);
            uint256 post = LR.balanceOf(address(owner));
            uint256 usdcPost = USDC.balanceOf(address(owner));

            // TOKEN_1 because we just calculate the rewards for this epoch
            // epoch 0 rewards + epoch 1 rewards
            assertEq(
                (post - pre),
                (currentIncentive * TOKEN_1 / (TOKEN_1 + decreasedTokenId2Balance)) + firstEpochTokenIdEarned
            );
            assertEq(
                (usdcPost - usdcPre),
                (usdcIncentive * TOKEN_1 / (TOKEN_1 + decreasedTokenId2Balance)) + firstEpochTokenIdUsdcEarned
            );

            // check owner2
            pre = LR.balanceOf(address(owner2));
            usdcPre = USDC.balanceOf(address(owner2));
            vm.prank(address(owner2));
            incentiveVotingReward.getReward(tokenId2, rewards);
            post = LR.balanceOf(address(owner2));
            usdcPost = USDC.balanceOf(address(owner2));

            assertApproxEqAbs(
                (post - pre),
                (currentIncentive * decreasedTokenId2Balance / (TOKEN_1 + decreasedTokenId2Balance))
                    + (TOKEN_1 - firstEpochTokenIdEarned),
                1
            );
            assertApproxEqAbs(
                (usdcPost - usdcPre),
                (usdcIncentive * decreasedTokenId2Balance / (TOKEN_1 + decreasedTokenId2Balance))
                    + (USDC_1 - firstEpochTokenIdUsdcEarned),
                1
            );

            // validate earned should be 0 for both tokens after claiming
            _checkEarnedNoClaim({
                _tokenId: tokenId,
                rewardContract: address(incentiveVotingReward),
                _currentIncentive: 0,
                _usdcIncentive: 0,
                rewards: rewards,
                balance: 0,
                totalBalance: 1
            });
            _checkEarnedNoClaim({
                _tokenId: tokenId2,
                rewardContract: address(incentiveVotingReward),
                _currentIncentive: 0,
                _usdcIncentive: 0,
                rewards: rewards,
                balance: 0,
                totalBalance: 1
            });
        }

        uint256 epoch3StartTs = VelodromeTimeLibrary.epochStart(block.timestamp);

        // pass 2 epochs
        skipToNextEpoch(1);
        // EPOCH 4
        uint256 epoch4StartTs = VelodromeTimeLibrary.epochStart(block.timestamp);
        skipToNextEpoch(1 hours + 1);
        // EPOCH 5
        // should write 3 new global cp
        // 1 new user reward cp for each
        // epoch:               5
        // tokenId userEpoch:   3
        // tokenId2 userEpoch:  3

        voter.poke(tokenId);
        vm.prank(address(owner2));
        voter.poke(tokenId2);

        // check missing global cps first
        {
            // epoch 3
            IVotingEscrow.GlobalPoint memory grp = incentiveVotingReward.globalRewardPointHistory(3);
            // @note: tokenId2ExpectedBal and expectedTs is still from the previous user cp from epoch 2
            assertEq(convert(grp.bias), tokenId2ExpectedBal - tokenId2ExpectedSlope * (epoch3StartTs - expectedTs));
            assertEq(convert(grp.slope), tokenId2ExpectedSlope);
            assertEq(grp.ts, epoch3StartTs); // epochStart is the ts for the missing global cps
            assertEq(grp.permanentLockBalance, TOKEN_1);

            // epoch 4
            grp = incentiveVotingReward.globalRewardPointHistory(4);
            assertEq(convert(grp.bias), tokenId2ExpectedBal - tokenId2ExpectedSlope * (epoch4StartTs - expectedTs));
            assertEq(convert(grp.slope), tokenId2ExpectedSlope);
            assertEq(grp.ts, epoch4StartTs);
            assertEq(grp.permanentLockBalance, TOKEN_1);
        }

        expectedTs = block.timestamp;
        tokenId2ExpectedBal = escrow.balanceOfNFT(tokenId2) / 2;

        // check current global cp
        _assertGlobalRewardPoint({
            expectedEpoch: 5,
            rewardContract: address(incentiveVotingReward),
            bias: tokenId2ExpectedBal,
            slope: tokenId2ExpectedSlope,
            ts: expectedTs,
            permanentLockBalance: TOKEN_1
        });

        // validate slopeChange and bias correction is unchanged
        assertEq(incentiveVotingReward.slopeChanges(tokenId2Locked.end), -toInt128(tokenId2ExpectedSlope));
        assertEq(incentiveVotingReward.biasCorrections(tokenId2Locked.end), -300599);

        // check user cps
        // should write new user checkpoint
        _assertUserRewardPoint({
            _tokenId: tokenId,
            expectedUserEpoch: 3,
            rewardContract: address(incentiveVotingReward),
            bias: 0,
            slope: 0,
            ts: expectedTs,
            permanent: TOKEN_1,
            expectedEnd: 0,
            additionalSlope: 0
        });
        // owner2
        _assertUserRewardPoint({
            _tokenId: tokenId2,
            expectedUserEpoch: 3,
            rewardContract: address(incentiveVotingReward),
            bias: tokenId2ExpectedBal,
            slope: tokenId2ExpectedSlope,
            ts: expectedTs,
            permanent: 0,
            expectedEnd: tokenId2Locked.end,
            additionalSlope: 0
        });

        // walk forward in time so owner2 nft expires
        uint256 skipTime = (tokenId2Locked.end - expectedTs) / 1 weeks;
        {
            uint256 epoch106Start;
            for (uint256 i = 0; i < skipTime; i++) {
                if (i == 101) {
                    epoch106Start = block.timestamp;
                }
                skipToNextEpoch(0);
            }

            skip(1 hours + 1);

            vm.prank(address(owner2));
            voter.poke(tokenId2);

            // check one random global cp
            {
                // EPOCH 106
                IVotingEscrow.GlobalPoint memory grp = incentiveVotingReward.globalRewardPointHistory(106);
                // @note: tokenId2ExpectedBal and expectedTs is still from the previous (latest) user cp from epoch 5
                assertEq(convert(grp.bias), tokenId2ExpectedBal - tokenId2ExpectedSlope * (epoch106Start - expectedTs));
                assertEq(convert(grp.slope), tokenId2ExpectedSlope);
                assertEq(grp.ts, epoch106Start);
                assertEq(grp.permanentLockBalance, TOKEN_1);
            }
        }

        // EPOCH 208
        // should write 203 new global cp
        // 1 new user reward cp
        // epoch:             208
        // tokenId userEpoch:   3
        // tokenId2 userEpoch:  4
        // check one random missing global cp first

        tokenId2ExpectedBal = escrow.balanceOfNFT(tokenId2) / 2;
        expectedTs = block.timestamp;

        // check global and user cps
        _assertGlobalRewardPoint({
            expectedEpoch: 5 + skipTime,
            rewardContract: address(incentiveVotingReward),
            bias: tokenId2ExpectedBal,
            slope: tokenId2ExpectedSlope,
            ts: expectedTs,
            permanentLockBalance: TOKEN_1
        });

        // owner2
        _assertUserRewardPoint({
            _tokenId: tokenId2,
            expectedUserEpoch: 4,
            rewardContract: address(incentiveVotingReward),
            bias: tokenId2ExpectedBal,
            slope: tokenId2ExpectedSlope,
            ts: expectedTs,
            permanent: 0,
            expectedEnd: tokenId2Locked.end,
            additionalSlope: 0
        });

        // last epoch where tokenId2 slope is active
        assertEq(
            incentiveVotingReward.slopeChanges(VelodromeTimeLibrary.epochNext(block.timestamp)),
            -toInt128(tokenId2ExpectedSlope)
        );

        assertEq(incentiveVotingReward.biasCorrections(VelodromeTimeLibrary.epochNext(block.timestamp)), -300599);

        skipToNextEpoch(1 hours + 1);

        // EPOCH 209
        // should write 1 new global cp
        // 1 new user reward cp
        // epoch:             209
        // tokenId userEpoch:   4
        // tokenId2 userEpoch:  4

        assertEq(incentiveVotingReward.slopeChanges(VelodromeTimeLibrary.epochNext(block.timestamp)), 0);
        assertEq(incentiveVotingReward.biasCorrections(VelodromeTimeLibrary.epochNext(block.timestamp)), 0);

        // nft power should be 0 by this time
        tokenId2ExpectedBal = escrow.balanceOfNFT(tokenId2);
        assertEq(tokenId2ExpectedBal, 0);

        vm.prank(address(owner2));
        vm.expectRevert(IVoter.ZeroBalance.selector);
        voter.poke(tokenId2);

        // poke for owner
        voter.poke(tokenId);
        expectedTs = block.timestamp;

        _assertGlobalRewardPoint({
            expectedEpoch: 209,
            rewardContract: address(incentiveVotingReward),
            bias: 0,
            slope: 0,
            ts: expectedTs,
            permanentLockBalance: TOKEN_1
        });

        _assertUserRewardPoint({
            _tokenId: tokenId,
            expectedUserEpoch: 4,
            rewardContract: address(incentiveVotingReward),
            bias: 0,
            slope: 0,
            ts: expectedTs,
            permanent: TOKEN_1,
            expectedEnd: 0,
            additionalSlope: 0
        });

        _createIncentiveWithAmount(incentiveVotingReward, address(LR), currentIncentive);
        _createIncentiveWithAmount(incentiveVotingReward, address(USDC), usdcIncentive);

        skipToNextEpoch(1 hours + 1);

        // EPOCH 210
        // should write 1 new global cp
        // 1 new user reward cp
        // epoch:             210
        // tokenId userEpoch:   4
        // tokenId2 userEpoch:  5

        vm.prank(address(owner2));
        voter.reset(tokenId2);

        {
            // check owner - should receive all rewards
            uint256 pre = LR.balanceOf(address(owner));
            uint256 usdcPre = USDC.balanceOf(address(owner));
            incentiveVotingReward.getReward(tokenId, rewards);
            uint256 post = LR.balanceOf(address(owner));
            uint256 usdcPost = USDC.balanceOf(address(owner));

            assertEq((post - pre), TOKEN_1);
            assertEq((usdcPost - usdcPre), USDC_1);

            // check owner 2 - should be 0
            pre = LR.balanceOf(address(owner2));
            usdcPre = USDC.balanceOf(address(owner2));
            vm.prank(address(owner2));
            incentiveVotingReward.getReward(tokenId2, rewards);
            post = LR.balanceOf(address(owner2));
            usdcPost = USDC.balanceOf(address(owner2));

            assertEq((post - pre), 0);
            assertEq((usdcPost - usdcPre), 0);
        }

        expectedTs = block.timestamp;

        _assertGlobalRewardPoint({
            expectedEpoch: 210,
            rewardContract: address(incentiveVotingReward),
            bias: 0,
            slope: 0,
            ts: expectedTs,
            permanentLockBalance: TOKEN_1
        });

        // owner2 user reward cp should be zeroed out
        _assertUserRewardPoint({
            _tokenId: tokenId2,
            expectedUserEpoch: 5,
            rewardContract: address(incentiveVotingReward),
            bias: 0,
            slope: 0,
            ts: expectedTs,
            permanent: 0,
            expectedEnd: 0,
            additionalSlope: 0
        });
    }

    struct FirstEpochEarnedByPool {
        uint256 firstEpochTokenIdEarned;
        uint256 firstEpochTokenIdUsdcEarned;
        uint256 pool2_firstEpochTokenIdEarned;
        uint256 pool2_firstEpochTokenIdUsdcEarned;
    }

    /// @dev same test as above but the voting weight is 70-30 instead of 50-50
    ///      both pools got the same amount of rewards
    function testVotingGetRewardFlowUnevenVotingWeight() public {
        // owner owns nft with id: tokenId with amount: TOKEN_1
        // owner2 owns nft with id: tokenId2 with amount: TOKEN_1 (locked for 2 year, but later it extended to MAXTIME)
        // incentives are always TOKEN_1 and USDC_1
        // votes are 70-30 between pool and pool2 both pools got the same amount of rewards

        weights[0] = 7000;
        weights[1] = 3000;

        skip(1 hours + 1);

        // check initial state
        // no cp
        _assertGlobalRewardPoint({
            expectedEpoch: 0,
            rewardContract: address(incentiveVotingReward),
            bias: 0,
            slope: 0,
            ts: 0,
            permanentLockBalance: 0
        });
        _assertUserRewardPoint({
            _tokenId: tokenId,
            expectedUserEpoch: 0,
            rewardContract: address(incentiveVotingReward),
            bias: 0,
            slope: 0,
            ts: 0,
            permanent: 0,
            expectedEnd: 0,
            additionalSlope: 0
        });

        // EPOCH 1
        // should write 1 new global cp
        // 1 new user reward cp for each
        // epoch:               1
        // tokenId userEpoch:   1
        // tokenId2 userEpoch:  1

        // set up initial votes for multiple pools
        _createIncentiveWithAmount(incentiveVotingReward, address(LR), currentIncentive);
        _createIncentiveWithAmount(incentiveVotingReward, address(USDC), usdcIncentive);
        _createIncentiveWithAmount(incentiveVotingReward2, address(LR), currentIncentive);
        _createIncentiveWithAmount(incentiveVotingReward2, address(USDC), usdcIncentive);

        voter.vote(tokenId, pools, weights);
        vm.prank(address(owner2));
        voter.vote(tokenId2, pools, weights);

        IVotingEscrow.LockedBalance memory tokenIdLocked = escrow.locked(tokenId);
        IVotingEscrow.LockedBalance memory tokenId2Locked = escrow.locked(tokenId2);

        expectedTs = block.timestamp;
        //-----// pool //-----//
        tokenIdExpectedBal = escrow.balanceOfNFT(tokenId) / 10 * 7; // votes are 70-30
        tokenId2ExpectedBal = escrow.balanceOfNFT(tokenId2) / 10 * 7;
        tokenIdExpectedSlope = tokenIdExpectedBal / (tokenIdLocked.end - expectedTs);
        tokenId2ExpectedSlope = tokenId2ExpectedBal / (tokenId2Locked.end - expectedTs);

        //-----// pool2 //-----//
        pool2_tokenIdExpectedBal = escrow.balanceOfNFT(tokenId) / 10 * 3;
        pool2_tokenId2ExpectedBal = escrow.balanceOfNFT(tokenId2) / 10 * 3;
        pool2_tokenIdExpectedSlope = pool2_tokenIdExpectedBal / (tokenIdLocked.end - expectedTs);
        pool2_tokenId2ExpectedSlope = pool2_tokenId2ExpectedBal / (tokenId2Locked.end - expectedTs);

        // votes are 70-30 between two pools
        ///-----// pool //-----///
        // check owner
        _assertUserRewardPoint({
            _tokenId: tokenId,
            expectedUserEpoch: 1,
            rewardContract: address(incentiveVotingReward),
            bias: tokenIdExpectedBal,
            slope: tokenIdExpectedSlope,
            ts: expectedTs,
            permanent: 0,
            expectedEnd: tokenIdLocked.end,
            additionalSlope: 0
        });
        // check owner2
        _assertUserRewardPoint({
            _tokenId: tokenId2,
            expectedUserEpoch: 1,
            rewardContract: address(incentiveVotingReward),
            bias: tokenId2ExpectedBal,
            slope: tokenId2ExpectedSlope,
            ts: expectedTs,
            permanent: 0,
            expectedEnd: tokenId2Locked.end,
            additionalSlope: 0
        });
        // check global reward point
        _assertGlobalRewardPoint({
            expectedEpoch: 1,
            rewardContract: address(incentiveVotingReward),
            bias: tokenIdExpectedBal + tokenId2ExpectedBal,
            slope: tokenIdExpectedSlope + tokenId2ExpectedSlope,
            ts: expectedTs,
            permanentLockBalance: 0
        });

        ///-----// pool2 //-----///
        // check owner
        _assertUserRewardPoint({
            _tokenId: tokenId,
            expectedUserEpoch: 1,
            rewardContract: address(incentiveVotingReward2),
            bias: pool2_tokenIdExpectedBal,
            slope: pool2_tokenIdExpectedSlope,
            ts: expectedTs,
            permanent: 0,
            expectedEnd: tokenIdLocked.end,
            additionalSlope: 0
        });
        // check owner2
        _assertUserRewardPoint({
            _tokenId: tokenId2,
            expectedUserEpoch: 1,
            rewardContract: address(incentiveVotingReward2),
            bias: pool2_tokenId2ExpectedBal,
            slope: pool2_tokenId2ExpectedSlope,
            ts: expectedTs,
            permanent: 0,
            expectedEnd: tokenId2Locked.end,
            additionalSlope: 0
        });

        _assertGlobalRewardPoint({
            expectedEpoch: 1,
            rewardContract: address(incentiveVotingReward2),
            bias: pool2_tokenIdExpectedBal + pool2_tokenId2ExpectedBal,
            slope: pool2_tokenIdExpectedSlope + pool2_tokenId2ExpectedSlope,
            ts: expectedTs,
            permanentLockBalance: 0
        });

        // check biasCorrections for both owner
        //-----// pool //-----//
        assertEq(incentiveVotingReward.biasCorrections(tokenIdLocked.end), -297739728369983401);
        assertEq(incentiveVotingReward.biasCorrections(tokenId2Locked.end), -148150687291852201);

        //-----// pool2 //-----//
        assertEq(incentiveVotingReward2.biasCorrections(tokenIdLocked.end), -33082192040842069);
        assertEq(incentiveVotingReward2.biasCorrections(tokenId2Locked.end), -16461187476605269);

        skipToNextEpoch(1);
        // EPOCH 2
        // should write 1 new global cp
        // 1 new user reward cp for each
        // epoch:               2
        // tokenId userEpoch:   2
        // tokenId2 userEpoch:  2

        FirstEpochEarnedByPool memory e = FirstEpochEarnedByPool({
            firstEpochTokenIdEarned: 0,
            firstEpochTokenIdUsdcEarned: 0,
            pool2_firstEpochTokenIdEarned: 0,
            pool2_firstEpochTokenIdUsdcEarned: 0
        });

        //-----// pool //-----//

        {
            uint256 firstEpochTokenIdEarned;
            uint256 firstEpochTokenIdUsdcEarned;
            uint256 decreasedTokenIdBalance =
                tokenIdExpectedBal - tokenIdExpectedSlope * (block.timestamp - expectedTs - 2); // substract 2 because we skipped one in this epoch and we do -1 in earned

            // sanity check
            assertApproxEqAbs(
                decreasedTokenIdBalance, escrow.balanceOfNFTAt(tokenId, block.timestamp - 2) / 2, 297739728369983401
            ); // delta should be the bias correction

            uint256 decreasedTokenId2Balance =
                tokenId2ExpectedBal - tokenId2ExpectedSlope * (block.timestamp - expectedTs - 2);

            // sanity check
            assertApproxEqAbs(
                decreasedTokenId2Balance, escrow.balanceOfNFTAt(tokenId2, block.timestamp - 2) / 2, 148150687291852201
            ); // delta should be the bias correction

            // check owner's earned and cache it
            (firstEpochTokenIdEarned, firstEpochTokenIdUsdcEarned) = _checkEarnedNoClaim({
                _tokenId: tokenId,
                rewardContract: address(incentiveVotingReward),
                _currentIncentive: currentIncentive,
                _usdcIncentive: usdcIncentive,
                rewards: rewards,
                balance: decreasedTokenIdBalance,
                totalBalance: decreasedTokenIdBalance + decreasedTokenId2Balance
            });
            e.firstEpochTokenIdEarned = firstEpochTokenIdEarned;
            e.firstEpochTokenIdUsdcEarned = firstEpochTokenIdUsdcEarned;

            // check owner2's earned
            _checkEarnedNoClaim({
                _tokenId: tokenId2,
                rewardContract: address(incentiveVotingReward),
                _currentIncentive: currentIncentive,
                _usdcIncentive: usdcIncentive,
                rewards: rewards,
                balance: decreasedTokenId2Balance,
                totalBalance: decreasedTokenIdBalance + decreasedTokenId2Balance
            });
        }

        //-----// pool2 //-----//

        {
            uint256 firstEpochTokenIdEarned;
            uint256 firstEpochTokenIdUsdcEarned;

            uint256 decreasedTokenIdBalance =
                pool2_tokenIdExpectedBal - pool2_tokenIdExpectedSlope * (block.timestamp - expectedTs - 2); // substract 2 because we skipped one in this epoch and we do -1 in earned

            // sanity check
            assertApproxEqAbs(
                decreasedTokenIdBalance, escrow.balanceOfNFTAt(tokenId, block.timestamp - 2) / 2, 297739728369983401
            ); // delta should be the bias correction

            uint256 decreasedTokenId2Balance =
                pool2_tokenId2ExpectedBal - pool2_tokenId2ExpectedSlope * (block.timestamp - expectedTs - 2);

            // sanity check
            assertApproxEqAbs(
                decreasedTokenId2Balance, escrow.balanceOfNFTAt(tokenId2, block.timestamp - 2) / 2, 148150687291852201
            ); // delta should be the bias correction

            // check owner's earned and cache it
            (firstEpochTokenIdEarned, firstEpochTokenIdUsdcEarned) = _checkEarnedNoClaim({
                _tokenId: tokenId,
                rewardContract: address(incentiveVotingReward2),
                _currentIncentive: currentIncentive,
                _usdcIncentive: usdcIncentive,
                rewards: rewards,
                balance: decreasedTokenIdBalance,
                totalBalance: decreasedTokenIdBalance + decreasedTokenId2Balance
            });

            e.pool2_firstEpochTokenIdEarned = firstEpochTokenIdEarned;
            e.pool2_firstEpochTokenIdUsdcEarned = firstEpochTokenIdUsdcEarned;

            // check owner2's earned
            _checkEarnedNoClaim({
                _tokenId: tokenId2,
                rewardContract: address(incentiveVotingReward2),
                _currentIncentive: currentIncentive,
                _usdcIncentive: usdcIncentive,
                rewards: rewards,
                balance: decreasedTokenId2Balance,
                totalBalance: decreasedTokenIdBalance + decreasedTokenId2Balance
            });
        }

        skip(1 hours);

        // owner increase amount
        VELO.approve(address(escrow), TOKEN_1);
        escrow.increaseAmount(tokenId, TOKEN_1);

        vm.prank(address(owner2));
        // increase lock duration for owner2 to end at the same time as owner's
        escrow.increaseUnlockTime(tokenId2, tokenIdLocked.end - block.timestamp);
        uint256 oldTokenId2End = tokenId2Locked.end;
        tokenId2Locked = escrow.locked(tokenId2);
        assertEq(tokenIdLocked.end, tokenId2Locked.end);

        // validate that the owners reward point and global point is not yet updated (needs to poke or vote)
        // owner
        // @note skip this validation for pool2
        _assertUserRewardPoint({
            _tokenId: tokenId,
            expectedUserEpoch: 1,
            rewardContract: address(incentiveVotingReward),
            bias: tokenIdExpectedBal,
            slope: tokenIdExpectedSlope,
            ts: expectedTs,
            permanent: 0,
            expectedEnd: tokenIdLocked.end,
            additionalSlope: 0
        });
        // owner2
        _assertUserRewardPoint({
            _tokenId: tokenId2,
            expectedUserEpoch: 1,
            rewardContract: address(incentiveVotingReward),
            bias: tokenId2ExpectedBal,
            slope: tokenId2ExpectedSlope,
            ts: expectedTs,
            permanent: 0,
            expectedEnd: oldTokenId2End,
            additionalSlope: 0
        });

        // check global reward point
        _assertGlobalRewardPoint({
            expectedEpoch: 1,
            rewardContract: address(incentiveVotingReward),
            bias: tokenIdExpectedBal + tokenId2ExpectedBal,
            slope: tokenIdExpectedSlope + tokenId2ExpectedSlope,
            ts: expectedTs,
            permanentLockBalance: 0
        });

        /// < pool2 validation skipped >

        // update checkpoints in reward contracts according to the new nft states
        voter.poke(tokenId);
        vm.prank(address(owner2));
        voter.poke(tokenId2);

        expectedTs = block.timestamp;

        // recalculate slope and bias for both owners
        //-----// pool //-----//
        tokenIdExpectedBal = escrow.balanceOfNFT(tokenId) / 10 * 7; // @note: votes still 70-30
        tokenId2ExpectedBal = escrow.balanceOfNFT(tokenId2) / 10 * 7;
        tokenIdExpectedSlope = tokenIdExpectedBal / (tokenIdLocked.end - expectedTs);
        tokenId2ExpectedSlope = tokenId2ExpectedBal / (tokenId2Locked.end - expectedTs);

        //-----// pool2 //-----//
        pool2_tokenIdExpectedBal = escrow.balanceOfNFT(tokenId) / 10 * 3;
        pool2_tokenId2ExpectedBal = escrow.balanceOfNFT(tokenId2) / 10 * 3;
        pool2_tokenIdExpectedSlope = pool2_tokenIdExpectedBal / (tokenIdLocked.end - expectedTs);
        pool2_tokenId2ExpectedSlope = pool2_tokenId2ExpectedBal / (tokenId2Locked.end - expectedTs);

        // votes are still 70-30 between two pools
        // check owner
        //-----// pool //-----//
        _assertUserRewardPoint({
            _tokenId: tokenId,
            expectedUserEpoch: 2,
            rewardContract: address(incentiveVotingReward),
            bias: tokenIdExpectedBal,
            slope: tokenIdExpectedSlope,
            ts: expectedTs,
            permanent: 0,
            expectedEnd: tokenIdLocked.end,
            additionalSlope: tokenId2ExpectedSlope
        });
        // check owner2
        _assertUserRewardPoint({
            _tokenId: tokenId2,
            expectedUserEpoch: 2,
            rewardContract: address(incentiveVotingReward),
            bias: tokenId2ExpectedBal,
            slope: tokenId2ExpectedSlope,
            ts: expectedTs,
            permanent: 0,
            expectedEnd: tokenId2Locked.end,
            additionalSlope: tokenIdExpectedSlope
        });

        //-----// pool2 //-----//
        _assertUserRewardPoint({
            _tokenId: tokenId,
            expectedUserEpoch: 2,
            rewardContract: address(incentiveVotingReward2),
            bias: pool2_tokenIdExpectedBal,
            slope: pool2_tokenIdExpectedSlope,
            ts: expectedTs,
            permanent: 0,
            expectedEnd: tokenIdLocked.end,
            additionalSlope: pool2_tokenId2ExpectedSlope
        });
        // check owner2
        _assertUserRewardPoint({
            _tokenId: tokenId2,
            expectedUserEpoch: 2,
            rewardContract: address(incentiveVotingReward2),
            bias: pool2_tokenId2ExpectedBal,
            slope: pool2_tokenId2ExpectedSlope,
            ts: expectedTs,
            permanent: 0,
            expectedEnd: tokenId2Locked.end,
            additionalSlope: pool2_tokenIdExpectedSlope
        });

        //-----// pool //-----//
        // explicitly check old slope change for owner2 is canceled
        assertEq(incentiveVotingReward.slopeChanges(oldTokenId2End), 0);
        // explicitly check old bias correction for owner2 is cancelled
        assertEq(incentiveVotingReward.biasCorrections(oldTokenId2End), 0);

        // biasCorrections for both owner is at the same time
        assertEq(
            incentiveVotingReward.biasCorrections(tokenIdLocked.end),
            -(incentiveVotingReward.biasCorrection(tokenId) + incentiveVotingReward.biasCorrection(tokenId2))
        );

        //-----// pool2 //-----//
        // explicitly check old slope change for owner2 is canceled
        assertEq(incentiveVotingReward2.slopeChanges(oldTokenId2End), 0);
        // explicitly check old bias correction for owner2 is cancelled
        assertEq(incentiveVotingReward2.biasCorrections(oldTokenId2End), 0);

        // biasCorrections for both owner is at the same time
        assertEq(
            incentiveVotingReward2.biasCorrections(tokenIdLocked.end),
            -(incentiveVotingReward2.biasCorrection(tokenId) + incentiveVotingReward2.biasCorrection(tokenId2))
        );

        //-----// pool //-----//
        // check global reward point
        _assertGlobalRewardPoint({
            expectedEpoch: 2,
            rewardContract: address(incentiveVotingReward),
            bias: tokenIdExpectedBal + tokenId2ExpectedBal,
            slope: tokenIdExpectedSlope + tokenId2ExpectedSlope,
            ts: expectedTs,
            permanentLockBalance: 0
        });

        //-----// pool2 //-----//
        _assertGlobalRewardPoint({
            expectedEpoch: 2,
            rewardContract: address(incentiveVotingReward2),
            bias: pool2_tokenIdExpectedBal + pool2_tokenId2ExpectedBal,
            slope: pool2_tokenIdExpectedSlope + pool2_tokenId2ExpectedSlope,
            ts: expectedTs,
            permanentLockBalance: 0
        });

        skip(1 weeks / 2);
        // lock owner's nft permanently
        escrow.lockPermanent(tokenId);
        voter.poke(tokenId);

        // should overwrite previous cp since we are in the same epoch
        //-----// pool //-----//
        _assertUserRewardPoint({
            _tokenId: tokenId,
            expectedUserEpoch: 2,
            rewardContract: address(incentiveVotingReward),
            bias: 0,
            slope: 0,
            ts: block.timestamp, // @note we can't update expectedTs here because we need it later for the decreased balance calculation
            permanent: TOKEN_1 / 10 * 7 * 2, // @note only 1.4 because votes are 70-30
            expectedEnd: 0,
            additionalSlope: 0 // @note: tokenId2 slopechange still active
        });

        //-----// pool2 //-----//
        _assertUserRewardPoint({
            _tokenId: tokenId,
            expectedUserEpoch: 2,
            rewardContract: address(incentiveVotingReward2),
            bias: 0,
            slope: 0,
            ts: block.timestamp, // @note we can't update expectedTs here because we need it later for the decreased balance calculation
            permanent: TOKEN_1 / 10 * 3 * 2 - 1, // @note only 0.6 because votes are 70-30
            expectedEnd: 0,
            additionalSlope: 0 // @note: tokenId2 slopechange still active
        });

        //-----// pool //-----//
        // explicitly check old slope change and bias correction for owner is canceled since we create permanent lock
        assertEq(incentiveVotingReward.slopeChanges(tokenIdLocked.end), -toInt128(tokenId2ExpectedSlope));
        assertEq(incentiveVotingReward.biasCorrections(tokenIdLocked.end), -296301372205770600);

        //-----// pool2 //-----//
        assertEq(incentiveVotingReward2.slopeChanges(tokenIdLocked.end), -toInt128(pool2_tokenId2ExpectedSlope));
        assertEq(incentiveVotingReward2.biasCorrections(tokenIdLocked.end), -32922374689262868);

        //-----// pool //-----//
        // only tokenId2 balance should be counted in the global bias
        uint256 decreasedTokenId2Balance = tokenId2ExpectedBal - tokenId2ExpectedSlope * (block.timestamp - expectedTs);

        // should overwrite previous global point
        _assertGlobalRewardPoint({
            expectedEpoch: 2,
            rewardContract: address(incentiveVotingReward),
            bias: decreasedTokenId2Balance,
            slope: tokenId2ExpectedSlope,
            ts: block.timestamp,
            permanentLockBalance: TOKEN_1 / 10 * 7 * 2
        });

        //-----// pool2 //-----//
        uint256 pool2_decreasedTokenId2Balance =
            pool2_tokenId2ExpectedBal - pool2_tokenId2ExpectedSlope * (block.timestamp - expectedTs);

        // should overwrite previous global point
        _assertGlobalRewardPoint({
            expectedEpoch: 2,
            rewardContract: address(incentiveVotingReward2),
            bias: pool2_decreasedTokenId2Balance,
            slope: pool2_tokenId2ExpectedSlope,
            ts: block.timestamp,
            permanentLockBalance: TOKEN_1 / 10 * 3 * 2 - 1
        });

        // add some more reward
        _createIncentiveWithAmount(incentiveVotingReward, address(LR), currentIncentive);
        _createIncentiveWithAmount(incentiveVotingReward, address(USDC), usdcIncentive);
        _createIncentiveWithAmount(incentiveVotingReward2, address(LR), currentIncentive);
        _createIncentiveWithAmount(incentiveVotingReward2, address(USDC), usdcIncentive);

        skipToNextEpoch(1);
        // EPOCH 3
        // same state as previous epoch since we don't deposit/withdraw
        // no new user reward cp for each
        // epoch:               2
        // tokenId userEpoch:   2
        // tokenId2 userEpoch:  2

        //-----// pool //-----//
        // recaulate owner2's balance at the time of the reward claiming
        decreasedTokenId2Balance = tokenId2ExpectedBal - tokenId2ExpectedSlope * (block.timestamp - expectedTs - 2);

        // claim rewards
        {
            // check owner
            uint256 pre = LR.balanceOf(address(owner));
            uint256 usdcPre = USDC.balanceOf(address(owner));
            incentiveVotingReward.getReward(tokenId, rewards);
            uint256 post = LR.balanceOf(address(owner));
            uint256 usdcPost = USDC.balanceOf(address(owner));

            // TOKEN_1 because we just calculate the rewards for this epoch
            // epoch 0 rewards + epoch 1 rewards

            assertApproxEqAbs(
                (post - pre),
                (currentIncentive * 14e17 / (14e17 + decreasedTokenId2Balance)) + e.firstEpochTokenIdEarned,
                1
            );

            assertApproxEqAbs(
                (usdcPost - usdcPre),
                (usdcIncentive * 14e17 / (14e17 + decreasedTokenId2Balance)) + e.firstEpochTokenIdUsdcEarned,
                1
            );

            // check owner2
            pre = LR.balanceOf(address(owner2));
            usdcPre = USDC.balanceOf(address(owner2));
            vm.prank(address(owner2));
            incentiveVotingReward.getReward(tokenId2, rewards);
            post = LR.balanceOf(address(owner2));
            usdcPost = USDC.balanceOf(address(owner2));

            assertApproxEqAbs(
                (post - pre),
                (currentIncentive * decreasedTokenId2Balance / (14e17 + decreasedTokenId2Balance))
                    + (TOKEN_1 - e.firstEpochTokenIdEarned),
                1
            );
            assertApproxEqAbs(
                (usdcPost - usdcPre),
                (usdcIncentive * decreasedTokenId2Balance / (14e17 + decreasedTokenId2Balance))
                    + (USDC_1 - e.firstEpochTokenIdUsdcEarned),
                1
            );

            // validate earned should be 0 for both tokens after claiming
            _checkEarnedNoClaim({
                _tokenId: tokenId,
                rewardContract: address(incentiveVotingReward),
                _currentIncentive: 0,
                _usdcIncentive: 0,
                rewards: rewards,
                balance: 0,
                totalBalance: 1
            });
            _checkEarnedNoClaim({
                _tokenId: tokenId2,
                rewardContract: address(incentiveVotingReward),
                _currentIncentive: 0,
                _usdcIncentive: 0,
                rewards: rewards,
                balance: 0,
                totalBalance: 1
            });
        }

        //-----// pool2 //-----//
        // recaulate owner2's balance at the time of the reward claiming
        pool2_decreasedTokenId2Balance =
            pool2_tokenId2ExpectedBal - pool2_tokenId2ExpectedSlope * (block.timestamp - expectedTs - 2);

        // claim rewards
        {
            // check owner
            uint256 pre = LR.balanceOf(address(owner));
            uint256 usdcPre = USDC.balanceOf(address(owner));
            incentiveVotingReward2.getReward(tokenId, rewards);
            uint256 post = LR.balanceOf(address(owner));
            uint256 usdcPost = USDC.balanceOf(address(owner));

            // TOKEN_1 because we just calculate the rewards for this epoch
            // epoch 0 rewards + epoch 1 rewards

            assertApproxEqAbs(
                (post - pre),
                (currentIncentive * 6e17 / (6e17 + pool2_decreasedTokenId2Balance)) + e.pool2_firstEpochTokenIdEarned,
                1
            );

            assertApproxEqAbs(
                (usdcPost - usdcPre),
                (usdcIncentive * 6e17 / (6e17 + pool2_decreasedTokenId2Balance)) + e.pool2_firstEpochTokenIdUsdcEarned,
                1
            );

            // check owner2
            pre = LR.balanceOf(address(owner2));
            usdcPre = USDC.balanceOf(address(owner2));
            vm.prank(address(owner2));
            incentiveVotingReward2.getReward(tokenId2, rewards);
            post = LR.balanceOf(address(owner2));
            usdcPost = USDC.balanceOf(address(owner2));

            assertApproxEqAbs(
                (post - pre),
                (currentIncentive * pool2_decreasedTokenId2Balance / (6e17 + pool2_decreasedTokenId2Balance))
                    + (TOKEN_1 - e.pool2_firstEpochTokenIdEarned),
                1
            );
            assertApproxEqAbs(
                (usdcPost - usdcPre),
                (usdcIncentive * pool2_decreasedTokenId2Balance / (6e17 + pool2_decreasedTokenId2Balance))
                    + (USDC_1 - e.pool2_firstEpochTokenIdUsdcEarned),
                1
            );

            // validate earned should be 0 for both tokens after claiming
            _checkEarnedNoClaim({
                _tokenId: tokenId,
                rewardContract: address(incentiveVotingReward2),
                _currentIncentive: 0,
                _usdcIncentive: 0,
                rewards: rewards,
                balance: 0,
                totalBalance: 1
            });
            _checkEarnedNoClaim({
                _tokenId: tokenId2,
                rewardContract: address(incentiveVotingReward2),
                _currentIncentive: 0,
                _usdcIncentive: 0,
                rewards: rewards,
                balance: 0,
                totalBalance: 1
            });
        }

        uint256 epoch3StartTs = VelodromeTimeLibrary.epochStart(block.timestamp);

        // pass 2 epochs
        skipToNextEpoch(1);
        // EPOCH 4
        uint256 epoch4StartTs = VelodromeTimeLibrary.epochStart(block.timestamp);
        skipToNextEpoch(1 hours + 1);
        // EPOCH 5
        // should write 3 new global cp
        // 1 new user reward cp for each
        // epoch:               5
        // tokenId userEpoch:   3
        // tokenId2 userEpoch:  3

        voter.poke(tokenId);
        vm.prank(address(owner2));
        voter.poke(tokenId2);

        // check missing global cps first
        //-----// pool //-----///
        {
            // epoch 3
            IVotingEscrow.GlobalPoint memory grp = incentiveVotingReward.globalRewardPointHistory(3);
            // @note: tokenId2ExpectedBal and expectedTs is still from the previous user cp from epoch 2
            assertApproxEqAbs(
                convert(grp.bias), tokenId2ExpectedBal - tokenId2ExpectedSlope * (epoch3StartTs - expectedTs), 3
            );
            assertEq(convert(grp.slope), tokenId2ExpectedSlope);
            assertEq(grp.ts, epoch3StartTs); // epochStart is the ts for the missing global cps
            assertEq(grp.permanentLockBalance, 14e17);

            // epoch 4
            grp = incentiveVotingReward.globalRewardPointHistory(4);
            assertApproxEqAbs(
                convert(grp.bias), tokenId2ExpectedBal - tokenId2ExpectedSlope * (epoch4StartTs - expectedTs), 3
            );
            assertEq(convert(grp.slope), tokenId2ExpectedSlope);
            assertEq(grp.ts, epoch4StartTs);
            assertEq(grp.permanentLockBalance, 14e17);
        }

        //-----// pool2 //-----//
        {
            // epoch 3
            IVotingEscrow.GlobalPoint memory grp = incentiveVotingReward2.globalRewardPointHistory(3);
            // @note: pool2_tokenId2ExpectedBal and expectedTs is still from the previous user cp from epoch 2
            assertApproxEqAbs(
                convert(grp.bias),
                pool2_tokenId2ExpectedBal - pool2_tokenId2ExpectedSlope * (epoch3StartTs - expectedTs),
                3
            );
            assertEq(convert(grp.slope), pool2_tokenId2ExpectedSlope);
            assertEq(grp.ts, epoch3StartTs); // epochStart is the ts for the missing global cps
            assertEq(grp.permanentLockBalance, 6e17 - 1);

            // epoch 4
            grp = incentiveVotingReward2.globalRewardPointHistory(4);
            assertApproxEqAbs(
                convert(grp.bias),
                pool2_tokenId2ExpectedBal - pool2_tokenId2ExpectedSlope * (epoch4StartTs - expectedTs),
                3
            );
            assertEq(convert(grp.slope), pool2_tokenId2ExpectedSlope);
            assertEq(grp.ts, epoch4StartTs);
            assertEq(grp.permanentLockBalance, 6e17 - 1);
        }

        expectedTs = block.timestamp;
        tokenId2ExpectedBal = escrow.balanceOfNFT(tokenId2) / 10 * 7;

        pool2_tokenId2ExpectedBal = escrow.balanceOfNFT(tokenId2) / 10 * 3;

        // check current global cp
        //-----// pool //-----//
        _assertGlobalRewardPoint({
            expectedEpoch: 5,
            rewardContract: address(incentiveVotingReward),
            bias: tokenId2ExpectedBal,
            slope: tokenId2ExpectedSlope,
            ts: expectedTs,
            permanentLockBalance: 14e17
        });

        //-----// pool2 //-----//
        _assertGlobalRewardPoint({
            expectedEpoch: 5,
            rewardContract: address(incentiveVotingReward2),
            bias: pool2_tokenId2ExpectedBal,
            slope: pool2_tokenId2ExpectedSlope,
            ts: expectedTs,
            permanentLockBalance: 6e17 - 1
        });

        // validate slopeChange and bias correction is unchanged
        //-----// pool //-----//
        assertEq(incentiveVotingReward.slopeChanges(tokenId2Locked.end), -toInt128(tokenId2ExpectedSlope));
        assertEq(incentiveVotingReward.biasCorrections(tokenId2Locked.end), -291986303713132200);

        //-----// pool2 //-----//
        assertEq(incentiveVotingReward2.slopeChanges(tokenId2Locked.end), -toInt128(pool2_tokenId2ExpectedSlope));
        assertEq(incentiveVotingReward2.biasCorrections(tokenId2Locked.end), -32442922634525268);

        // check user cps
        // should write new user checkpoint
        //-----// pool //-----//
        _assertUserRewardPoint({
            _tokenId: tokenId,
            expectedUserEpoch: 3,
            rewardContract: address(incentiveVotingReward),
            bias: 0,
            slope: 0,
            ts: expectedTs,
            permanent: 14e17,
            expectedEnd: 0,
            additionalSlope: 0
        });
        // owner2
        _assertUserRewardPoint({
            _tokenId: tokenId2,
            expectedUserEpoch: 3,
            rewardContract: address(incentiveVotingReward),
            bias: tokenId2ExpectedBal,
            slope: tokenId2ExpectedSlope,
            ts: expectedTs,
            permanent: 0,
            expectedEnd: tokenId2Locked.end,
            additionalSlope: 0
        });

        //-----// pool2 //-----//
        _assertUserRewardPoint({
            _tokenId: tokenId,
            expectedUserEpoch: 3,
            rewardContract: address(incentiveVotingReward2),
            bias: 0,
            slope: 0,
            ts: expectedTs,
            permanent: 6e17 - 1,
            expectedEnd: 0,
            additionalSlope: 0
        });
        // owner2
        _assertUserRewardPoint({
            _tokenId: tokenId2,
            expectedUserEpoch: 3,
            rewardContract: address(incentiveVotingReward2),
            bias: pool2_tokenId2ExpectedBal,
            slope: pool2_tokenId2ExpectedSlope,
            ts: expectedTs,
            permanent: 0,
            expectedEnd: tokenId2Locked.end,
            additionalSlope: 0
        });

        // walk forward in time so owner2 nft expires
        uint256 skipTime = (tokenId2Locked.end - expectedTs) / 1 weeks;
        {
            uint256 epoch106Start;
            for (uint256 i = 0; i < skipTime; i++) {
                if (i == 101) {
                    epoch106Start = block.timestamp;
                }
                skipToNextEpoch(0);
            }

            skip(1 hours + 1);

            vm.prank(address(owner2));
            voter.poke(tokenId2);

            // check one random global cp
            {
                // EPOCH 106
                //-----// pool //-----//
                IVotingEscrow.GlobalPoint memory grp = incentiveVotingReward.globalRewardPointHistory(106);
                // @note: tokenId2ExpectedBal and expectedTs is still from the previous (latest) user cp from epoch 5
                assertApproxEqAbs(
                    convert(grp.bias), tokenId2ExpectedBal - tokenId2ExpectedSlope * (epoch106Start - expectedTs), 3
                );
                assertEq(convert(grp.slope), tokenId2ExpectedSlope);
                assertEq(grp.ts, epoch106Start);
                assertEq(grp.permanentLockBalance, 14e17);

                assertEq(incentiveVotingReward.biasCorrections(tokenId2Locked.end), -2377933800);

                //-----// pool2 //-----//
                grp = incentiveVotingReward2.globalRewardPointHistory(106);
                // @note: pool2_tokenId2ExpectedBal and expectedTs is still from the previous (latest) user cp from epoch 5
                assertApproxEqAbs(
                    convert(grp.bias),
                    pool2_tokenId2ExpectedBal - pool2_tokenId2ExpectedSlope * (epoch106Start - expectedTs),
                    3
                );
                assertEq(convert(grp.slope), pool2_tokenId2ExpectedSlope);
                assertEq(grp.ts, epoch106Start);
                assertEq(grp.permanentLockBalance, 6e17 - 1);

                assertEq(incentiveVotingReward2.biasCorrections(tokenId2Locked.end), -263947668);
            }
        }

        // EPOCH 208
        // should write 203 new global cp
        // 1 new user reward cp
        // epoch:             208
        // tokenId userEpoch:   3
        // tokenId2 userEpoch:  4
        // check one random missing global cp first

        tokenId2ExpectedBal = escrow.balanceOfNFT(tokenId2) / 10 * 7;
        pool2_tokenId2ExpectedBal = escrow.balanceOfNFT(tokenId2) / 10 * 3;

        expectedTs = block.timestamp;

        // check global and user cps
        //-----// pool //-----//
        _assertGlobalRewardPoint({
            expectedEpoch: 5 + skipTime,
            rewardContract: address(incentiveVotingReward),
            bias: tokenId2ExpectedBal,
            slope: tokenId2ExpectedSlope,
            ts: expectedTs,
            permanentLockBalance: 14e17
        });

        // owner2
        _assertUserRewardPoint({
            _tokenId: tokenId2,
            expectedUserEpoch: 4,
            rewardContract: address(incentiveVotingReward),
            bias: tokenId2ExpectedBal,
            slope: tokenId2ExpectedSlope,
            ts: expectedTs,
            permanent: 0,
            expectedEnd: tokenId2Locked.end,
            additionalSlope: 0
        });

        //-----// pool2 //-----//
        _assertGlobalRewardPoint({
            expectedEpoch: 5 + skipTime,
            rewardContract: address(incentiveVotingReward2),
            bias: pool2_tokenId2ExpectedBal,
            slope: pool2_tokenId2ExpectedSlope,
            ts: expectedTs,
            permanentLockBalance: 6e17 - 1
        });

        // owner2
        _assertUserRewardPoint({
            _tokenId: tokenId2,
            expectedUserEpoch: 4,
            rewardContract: address(incentiveVotingReward2),
            bias: pool2_tokenId2ExpectedBal,
            slope: pool2_tokenId2ExpectedSlope,
            ts: expectedTs,
            permanent: 0,
            expectedEnd: tokenId2Locked.end,
            additionalSlope: 0
        });

        // last epoch where tokenId2 slope is active
        //-----// pool //-----//
        assertEq(
            incentiveVotingReward.slopeChanges(VelodromeTimeLibrary.epochNext(block.timestamp)),
            -toInt128(tokenId2ExpectedSlope)
        );
        assertEq(incentiveVotingReward.biasCorrections(VelodromeTimeLibrary.epochNext(block.timestamp)), -2377933800);

        /// pool 2 ///
        assertEq(
            incentiveVotingReward2.slopeChanges(VelodromeTimeLibrary.epochNext(block.timestamp)),
            -toInt128(pool2_tokenId2ExpectedSlope)
        );
        assertEq(incentiveVotingReward2.biasCorrections(VelodromeTimeLibrary.epochNext(block.timestamp)), -263947668);

        skipToNextEpoch(1 hours + 1);

        // EPOCH 209
        // should write 1 new global cp
        // 1 new user reward cp
        // epoch:             209
        // tokenId userEpoch:   4
        // tokenId2 userEpoch:  4

        //-----// pool //-----//
        assertEq(incentiveVotingReward.slopeChanges(VelodromeTimeLibrary.epochNext(block.timestamp)), 0);
        assertEq(incentiveVotingReward.biasCorrections(VelodromeTimeLibrary.epochNext(block.timestamp)), 0);

        //-----// pool2 //-----//
        assertEq(incentiveVotingReward2.slopeChanges(VelodromeTimeLibrary.epochNext(block.timestamp)), 0);
        assertEq(incentiveVotingReward2.biasCorrections(VelodromeTimeLibrary.epochNext(block.timestamp)), 0);

        // nft power should be 0 by this time
        /// same for both pools ////
        tokenId2ExpectedBal = escrow.balanceOfNFT(tokenId2);
        assertEq(tokenId2ExpectedBal, 0);

        vm.prank(address(owner2));
        vm.expectRevert(IVoter.ZeroBalance.selector);
        voter.poke(tokenId2);

        // poke for owner
        voter.poke(tokenId);
        expectedTs = block.timestamp;

        //-----// pool //-----//
        _assertGlobalRewardPoint({
            expectedEpoch: 209,
            rewardContract: address(incentiveVotingReward),
            bias: 0, // should be 0
            slope: 0,
            ts: expectedTs,
            permanentLockBalance: 14e17
        });

        _assertUserRewardPoint({
            _tokenId: tokenId,
            expectedUserEpoch: 4,
            rewardContract: address(incentiveVotingReward),
            bias: 0,
            slope: 0,
            ts: expectedTs,
            permanent: 14e17,
            expectedEnd: 0,
            additionalSlope: 0
        });

        //-----// pool2 //-----//
        _assertGlobalRewardPoint({
            expectedEpoch: 209,
            rewardContract: address(incentiveVotingReward2),
            bias: 0, // should be 0
            slope: 0,
            ts: expectedTs,
            permanentLockBalance: 6e17 - 1
        });

        _assertUserRewardPoint({
            _tokenId: tokenId,
            expectedUserEpoch: 4,
            rewardContract: address(incentiveVotingReward2),
            bias: 0,
            slope: 0,
            ts: expectedTs,
            permanent: 6e17 - 1,
            expectedEnd: 0,
            additionalSlope: 0
        });

        _createIncentiveWithAmount(incentiveVotingReward, address(LR), currentIncentive);
        _createIncentiveWithAmount(incentiveVotingReward, address(USDC), usdcIncentive);
        _createIncentiveWithAmount(incentiveVotingReward2, address(LR), currentIncentive);
        _createIncentiveWithAmount(incentiveVotingReward2, address(USDC), usdcIncentive);

        skipToNextEpoch(1 hours + 1);

        // EPOCH 210
        // should write 1 new global cp
        // 1 new user reward cp
        // epoch:             210
        // tokenId userEpoch:   4
        // tokenId2 userEpoch:  5

        vm.prank(address(owner2));
        voter.reset(tokenId2);

        //-----// pool //-----//
        {
            // check owner - should receive all rewards
            uint256 pre = LR.balanceOf(address(owner));
            uint256 usdcPre = USDC.balanceOf(address(owner));
            incentiveVotingReward.getReward(tokenId, rewards);
            uint256 post = LR.balanceOf(address(owner));
            uint256 usdcPost = USDC.balanceOf(address(owner));

            assertEq((post - pre), TOKEN_1);
            assertEq((usdcPost - usdcPre), USDC_1);

            // check owner 2 - should be 0
            pre = LR.balanceOf(address(owner2));
            usdcPre = USDC.balanceOf(address(owner2));
            vm.prank(address(owner2));
            incentiveVotingReward.getReward(tokenId2, rewards);
            post = LR.balanceOf(address(owner2));
            usdcPost = USDC.balanceOf(address(owner2));

            assertEq((post - pre), 0);
            assertEq((usdcPost - usdcPre), 0);
        }

        //-----// pool2 //-----//
        {
            // check owner - should receive all rewards
            uint256 pre = LR.balanceOf(address(owner));
            uint256 usdcPre = USDC.balanceOf(address(owner));
            incentiveVotingReward2.getReward(tokenId, rewards);
            uint256 post = LR.balanceOf(address(owner));
            uint256 usdcPost = USDC.balanceOf(address(owner));

            assertEq((post - pre), TOKEN_1);
            assertEq((usdcPost - usdcPre), USDC_1);

            // check owner 2 - should be 0
            pre = LR.balanceOf(address(owner2));
            usdcPre = USDC.balanceOf(address(owner2));
            vm.prank(address(owner2));
            incentiveVotingReward2.getReward(tokenId2, rewards);
            post = LR.balanceOf(address(owner2));
            usdcPost = USDC.balanceOf(address(owner2));

            assertEq((post - pre), 0);
            assertEq((usdcPost - usdcPre), 0);
        }

        expectedTs = block.timestamp;

        //-----// pool //-----//
        _assertGlobalRewardPoint({
            expectedEpoch: 210,
            rewardContract: address(incentiveVotingReward),
            bias: 0,
            slope: 0,
            ts: expectedTs,
            permanentLockBalance: 14e17
        });

        // owner2 user reward cp should be zeroed out
        _assertUserRewardPoint({
            _tokenId: tokenId2,
            expectedUserEpoch: 5,
            rewardContract: address(incentiveVotingReward),
            bias: 0,
            slope: 0,
            ts: expectedTs,
            permanent: 0,
            expectedEnd: 0,
            additionalSlope: 0
        });

        //-----// pool2 //-----//
        _assertGlobalRewardPoint({
            expectedEpoch: 210,
            rewardContract: address(incentiveVotingReward2),
            bias: 0,
            slope: 0,
            ts: expectedTs,
            permanentLockBalance: 6e17 - 1
        });

        // owner2 user reward cp should be zeroed out
        _assertUserRewardPoint({
            _tokenId: tokenId2,
            expectedUserEpoch: 5,
            rewardContract: address(incentiveVotingReward2),
            bias: 0,
            slope: 0,
            ts: expectedTs,
            permanent: 0,
            expectedEnd: 0,
            additionalSlope: 0
        });
    }

    function testWhiteListedNftVoteAtEpochFlipWritesCorrectGlobalRewardCheckpoint() public {
        vm.prank(address(governor));
        voter.whitelistNFT(tokenId, true);

        skip(1 hours);

        _createIncentiveWithAmount(incentiveVotingReward, address(LR), currentIncentive);
        _createIncentiveWithAmount(incentiveVotingReward, address(USDC), usdcIncentive);
        voter.vote(tokenId, pools, weights);

        expectedTs = block.timestamp;
        tokenIdExpectedBal = escrow.balanceOfNFT(tokenId) / 2; // votes are 50-50

        IVotingEscrow.LockedBalance memory tokenIdLocked = escrow.locked(tokenId);
        tokenIdExpectedSlope = tokenIdExpectedBal / (tokenIdLocked.end - expectedTs);

        // epoch should be 1
        // check global reward point
        _assertGlobalRewardPoint({
            expectedEpoch: 1,
            rewardContract: address(incentiveVotingReward),
            bias: tokenIdExpectedBal,
            slope: tokenIdExpectedSlope,
            ts: expectedTs,
            permanentLockBalance: 0
        });

        _assertUserRewardPoint({
            _tokenId: tokenId,
            expectedUserEpoch: 1,
            rewardContract: address(incentiveVotingReward),
            bias: tokenIdExpectedBal,
            slope: tokenIdExpectedSlope,
            ts: expectedTs,
            permanent: 0,
            expectedEnd: tokenIdLocked.end,
            additionalSlope: 0
        });

        skipToNextEpoch(0);
        rewind(1);

        voter.poke(tokenId);

        expectedTs = block.timestamp;
        tokenIdExpectedBal = escrow.balanceOfNFT(tokenId) / 2;

        // check global reward point
        _assertGlobalRewardPoint({
            expectedEpoch: 1,
            rewardContract: address(incentiveVotingReward),
            bias: tokenIdExpectedBal,
            slope: tokenIdExpectedSlope,
            ts: expectedTs,
            permanentLockBalance: 0
        });

        skip(1); // we are at epochflip
        vm.expectRevert(IVoter.DistributeWindow.selector);
        voter.poke(tokenId);

        skip(1); // epochflip + 1
        vm.expectRevert(IVoter.DistributeWindow.selector);
        voter.poke(tokenId);

        skip(1 hours - 1);
        vm.expectRevert(IVoter.DistributeWindow.selector);
        voter.poke(tokenId);

        skip(1); // voting allowed
        voter.poke(tokenId);

        expectedTs = block.timestamp;
        tokenIdExpectedBal = escrow.balanceOfNFT(tokenId) / 2;

        // epoch should be 2
        _assertGlobalRewardPoint({
            expectedEpoch: 2,
            rewardContract: address(incentiveVotingReward),
            bias: tokenIdExpectedBal,
            slope: tokenIdExpectedSlope,
            ts: expectedTs,
            permanentLockBalance: 0
        });

        _assertUserRewardPoint({
            _tokenId: tokenId,
            expectedUserEpoch: 2,
            rewardContract: address(incentiveVotingReward),
            bias: tokenIdExpectedBal,
            slope: tokenIdExpectedSlope,
            ts: expectedTs,
            permanent: 0,
            expectedEnd: tokenIdLocked.end,
            additionalSlope: 0
        });
    }

    /// HELPERS

    function _assertGlobalRewardPoint(
        uint256 expectedEpoch,
        address rewardContract,
        uint256 bias,
        uint256 slope,
        uint256 ts,
        uint256 permanentLockBalance
    ) internal view {
        uint256 epoch = IReward(rewardContract).epoch();
        assertEq(epoch, expectedEpoch);

        IVotingEscrow.GlobalPoint memory grp = IReward(rewardContract).globalRewardPointHistory(expectedEpoch);

        if (convert(grp.bias) == bias) {
            assertEq(convert(grp.bias), bias);
        } else {
            assertApproxEqAbs(convert(grp.bias), bias, 9);
        }

        assertEq(convert(grp.slope), slope);
        assertEq(grp.ts, ts);
        assertEq(grp.permanentLockBalance, permanentLockBalance);
    }

    function _assertUserRewardPoint(
        uint256 _tokenId,
        uint256 expectedUserEpoch,
        address rewardContract,
        uint256 bias,
        uint256 slope,
        uint256 ts,
        uint256 permanent,
        uint256 expectedEnd,
        uint256 additionalSlope
    ) internal view {
        uint256 userEpoch = IReward(rewardContract).userRewardEpoch(_tokenId);
        assertEq(userEpoch, expectedUserEpoch);

        IVotingEscrow.UserPoint memory urp = IReward(rewardContract).userRewardPointHistory(_tokenId, expectedUserEpoch);

        if (convert(urp.bias) == bias) {
            assertEq(convert(urp.bias), bias);
        } else {
            assertApproxEqAbs(convert(urp.bias), bias, 9);
        }
        assertEq(convert(urp.slope), slope);
        assertEq(urp.permanent, permanent);
        assertEq(IReward(rewardContract).lockExpiry(_tokenId), expectedEnd);
        assertEq(urp.ts, ts);

        assertEq(IReward(rewardContract).slopeChanges(expectedEnd), -toInt128(slope + additionalSlope));
    }

    function _checkEarnedNoClaim(
        uint256 _tokenId,
        address rewardContract,
        uint256 _currentIncentive,
        uint256 _usdcIncentive,
        address[] memory rewards,
        uint256 balance,
        uint256 totalBalance
    ) internal view returns (uint256 earned, uint256 usdcEarned) {
        earned = IReward(rewardContract).earned(rewards[0], _tokenId);
        assertApproxEqAbs(earned, _currentIncentive * balance / totalBalance, 1);

        usdcEarned = IReward(rewardContract).earned(rewards[1], _tokenId);
        assertApproxEqAbs(usdcEarned, _usdcIncentive * balance / totalBalance, 1);
    }
}

pragma solidity 0.8.13;

import "./BaseTest.sol";

contract RewardsDistributorTest is BaseTest {
    function _setUp() public override {
        // timestamp: 604801
        VELO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        skip(1);

        address[] memory pools = new address[](2);
        pools[0] = address(pair);
        pools[1] = address(pair2);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 1;
        weights[1] = 1;

        skip(1 hours);
        voter.vote(tokenId, pools, weights);
    }

    function testInitialize() public {
        assertEq(distributor.startTime(), 604800);
        assertEq(distributor.lastTokenTime(), 604800);
        assertEq(distributor.timeCursor(), 604800);
        assertEq(distributor.token(), address(VELO));
        assertEq(distributor.ve(), address(escrow));
    }

    function testClaim() public {
        skipToNextEpoch(1 days); // epoch 0, ts: 1296000, blk: 2

        VELO.approve(address(escrow), TOKEN_1M);
        uint256 tokenId = escrow.createLock(TOKEN_1M, MAXTIME);

        IVotingEscrow.LockedBalance memory locked = escrow.locked(tokenId);
        assertEq(convert(locked.amount), TOKEN_1M);
        assertEq(locked.end, 127008000);
        assertEq(locked.isPermanent, false);

        assertEq(escrow.userPointEpoch(tokenId), 1);
        IVotingEscrow.UserPoint memory userPoint = escrow.userPointHistory(tokenId, 1);
        assertEq(convert(userPoint.slope), TOKEN_1M / MAXTIME); // TOKEN_1M / MAXTIME
        assertEq(convert(userPoint.bias), 996575342465753345952000); // (TOKEN_1M / MAXTIME) * (127008000 - 1296000)
        assertEq(userPoint.ts, 1296000);
        assertEq(userPoint.blk, 2);

        vm.startPrank(address(owner2));
        VELO.approve(address(escrow), TOKEN_1M);
        uint256 tokenId2 = escrow.createLock(TOKEN_1M, MAXTIME);
        vm.stopPrank();

        locked = escrow.locked(tokenId2);
        assertEq(convert(locked.amount), TOKEN_1M);
        assertEq(locked.end, 127008000);
        assertEq(locked.isPermanent, false);

        assertEq(escrow.userPointEpoch(tokenId2), 1);
        userPoint = escrow.userPointHistory(tokenId2, 1);
        assertEq(convert(userPoint.slope), TOKEN_1M / MAXTIME); // TOKEN_1M / MAXTIME
        assertEq(convert(userPoint.bias), 996575342465753345952000); // (TOKEN_1M / MAXTIME) * (127008000 - 1296000)
        assertEq(userPoint.ts, 1296000);
        assertEq(userPoint.blk, 2);

        skipToNextEpoch(0); // distribute epoch 1's rebases
        minter.update_period();
        assertEq(distributor.claimable(tokenId), 0);
        assertEq(distributor.claimable(tokenId2), 0);

        skipToNextEpoch(0); // epoch 1's rebases available
        minter.update_period();
        assertEq(distributor.claimable(tokenId), 104194458010096665703);
        assertEq(distributor.claimable(tokenId2), 104194458010096665703);

        skipToNextEpoch(0); // epoch 1+2's rebases available
        minter.update_period();
        assertEq(distributor.claimable(tokenId), 159028895672296095334);
        assertEq(distributor.claimable(tokenId2), 159028895672296095334);

        skipToNextEpoch(0);
        minter.update_period();
        assertEq(distributor.claimable(tokenId), 191249761614125424271);
        assertEq(distributor.claimable(tokenId2), 191249761614125424271);

        IVotingEscrow.LockedBalance memory preLocked = escrow.locked(tokenId);
        distributor.claim(tokenId);
        IVotingEscrow.LockedBalance memory postLocked = escrow.locked(tokenId);
        assertEq(postLocked.amount - preLocked.amount, 191249761614125424271);
        assertEq(postLocked.end, 127008000);
        assertEq(postLocked.isPermanent, false);
    }

    function testClaimWithPermanentLocks() public {
        skipToNextEpoch(1 days); // epoch 0, ts: 1296000, blk: 2

        VELO.approve(address(escrow), TOKEN_1M);
        uint256 tokenId = escrow.createLock(TOKEN_1M, MAXTIME);
        escrow.lockPermanent(tokenId);

        IVotingEscrow.LockedBalance memory locked = escrow.locked(tokenId);
        assertEq(convert(locked.amount), TOKEN_1M);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, true);

        assertEq(escrow.userPointEpoch(tokenId), 1);
        IVotingEscrow.UserPoint memory userPoint = escrow.userPointHistory(tokenId, 1);
        assertEq(convert(userPoint.slope), 0);
        assertEq(convert(userPoint.bias), 0);
        assertEq(userPoint.ts, 1296000);
        assertEq(userPoint.blk, 2);
        assertEq(userPoint.permanent, TOKEN_1M);

        vm.startPrank(address(owner2));
        VELO.approve(address(escrow), TOKEN_1M);
        uint256 tokenId2 = escrow.createLock(TOKEN_1M, MAXTIME);
        escrow.lockPermanent(tokenId2);
        vm.stopPrank();

        locked = escrow.locked(tokenId2);
        assertEq(convert(locked.amount), TOKEN_1M);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, true);

        assertEq(escrow.userPointEpoch(tokenId2), 1);
        userPoint = escrow.userPointHistory(tokenId2, 1);
        assertEq(convert(userPoint.slope), 0);
        assertEq(convert(userPoint.bias), 0);
        assertEq(userPoint.ts, 1296000);
        assertEq(userPoint.blk, 2);
        assertEq(userPoint.permanent, TOKEN_1M);

        skipToNextEpoch(0); // distribute epoch 1's rebases
        minter.update_period();
        assertEq(distributor.claimable(tokenId), 0);
        assertEq(distributor.claimable(tokenId2), 0);

        skipToNextEpoch(0); // epoch 1's rebases available
        minter.update_period();
        assertEq(distributor.claimable(tokenId), 108145184011338358550);
        assertEq(distributor.claimable(tokenId2), 108145184011338358550);

        skipToNextEpoch(0); // epoch 1+2's rebases available
        minter.update_period();
        assertEq(distributor.claimable(tokenId), 165895710137244019608);
        assertEq(distributor.claimable(tokenId2), 165895710137244019608);

        skipToNextEpoch(0);
        minter.update_period();
        assertEq(distributor.claimable(tokenId), 200331559938841949783);
        assertEq(distributor.claimable(tokenId2), 200331559938841949783);

        IVotingEscrow.LockedBalance memory preLocked = escrow.locked(tokenId);
        distributor.claim(tokenId);
        IVotingEscrow.LockedBalance memory postLocked = escrow.locked(tokenId);
        assertEq(postLocked.amount - preLocked.amount, 200331559938841949783);
        assertEq(postLocked.end, 0);
        assertEq(postLocked.isPermanent, true);
    }

    function testClaimWithBothLocks() public {
        skipToNextEpoch(1 days); // epoch 0, ts: 1296000, blk: 2

        VELO.approve(address(escrow), TOKEN_1M);
        uint256 tokenId = escrow.createLock(TOKEN_1M, MAXTIME);
        escrow.lockPermanent(tokenId);

        vm.startPrank(address(owner2));
        VELO.approve(address(escrow), TOKEN_1M);
        uint256 tokenId2 = escrow.createLock(TOKEN_1M, MAXTIME);
        vm.stopPrank();

        // expect permanent lock to earn more rebases
        skipToNextEpoch(0); // distribute epoch 1's rebases
        minter.update_period();
        assertEq(distributor.claimable(tokenId), 0);
        assertEq(distributor.claimable(tokenId2), 0);

        skipToNextEpoch(0); // epoch 1's rebases available
        minter.update_period();
        assertEq(distributor.claimable(tokenId), 106558990028146297350);
        assertEq(distributor.claimable(tokenId2), 105756148322454775798);

        skipToNextEpoch(0); // epoch 1+2's rebases available
        minter.update_period();
        assertEq(distributor.claimable(tokenId), 163187964338003809527);
        assertEq(distributor.claimable(tokenId2), 161686957195615410120);

        skipToNextEpoch(0);
        minter.update_period();
        assertEq(distributor.claimable(tokenId), 196791755388778962521);
        assertEq(distributor.claimable(tokenId2), 194715340865384136653);
    }

    function testCheckpointTotalSupplyWithPermanentLock() public {
        // timestamp: 608402
        // note nft was created at 604801, within current epoch
        assertEq(distributor.timeCursor(), 604800);
        assertEq(distributor.veSupply(604800), 0);

        skip(1 days);
        escrow.lockPermanent(1);
        VELO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME);
        skip(1 hours);
        distributor.checkpointTotalSupply();

        assertEq(distributor.timeCursor(), 1209600);
        assertEq(distributor.veSupply(604800), 0);

        skipToNextEpoch(0);
        distributor.checkpointTotalSupply();

        assertEq(distributor.timeCursor(), 1814400);
        assertEq(escrow.balanceOfNFTAt(1, 1209600), TOKEN_1);
        assertEq(distributor.veForAt(1, 1209600), TOKEN_1);
        assertEq(escrow.balanceOfNFTAt(2, 1209600), 992465753306832000);
        assertEq(distributor.veForAt(2, 1209600), 992465753306832000);
        assertEq(distributor.veSupply(1209600), 992465753306832000 + TOKEN_1);
        assertEq(distributor.veSupply(1209600), escrow.getPastTotalSupply(1209600));

        skipToNextEpoch(0);
        distributor.checkpointTotalSupply();

        assertEq(distributor.timeCursor(), 2419200);
        assertEq(escrow.balanceOfNFTAt(1, 1814400), TOKEN_1);
        assertEq(distributor.veForAt(1, 1814400), TOKEN_1);
        assertEq(escrow.balanceOfNFTAt(2, 1814400), 987671232759456000);
        assertEq(distributor.veForAt(2, 1814400), 987671232759456000);
        assertEq(distributor.veSupply(1814400), 987671232759456000 + TOKEN_1);
        assertEq(distributor.veSupply(1814400), escrow.getPastTotalSupply(1814400));
    }

    function testClaimWithExpiredNFT() public {
        // test reward claims to expired NFTs are distributed as unlocked VELO
        VELO.approve(address(escrow), TOKEN_1M);
        uint256 tokenId = escrow.createLock(TOKEN_1M, WEEK * 4);

        skipToNextEpoch(1);
        minter.update_period();
        assertEq(distributor.claimable(tokenId), 0);

        for (uint256 i = 0; i < 4; i++) {
            minter.update_period();
            skipToNextEpoch(1);
        }

        assertGt(distributor.claimable(tokenId), 0); // accrued rebases

        IVotingEscrow.LockedBalance memory locked = escrow.locked(tokenId);
        assertGt(block.timestamp, locked.end); // lock expired

        uint256 rebase = distributor.claimable(tokenId);
        uint256 pre = VELO.balanceOf(address(owner));
        distributor.claim(tokenId);
        uint256 post = VELO.balanceOf(address(owner));

        locked = escrow.locked(tokenId); // update locked value post claim

        assertEq(post - pre, rebase); // expired rebase distributed as unlocked VELO
        assertEq(uint256(uint128(locked.amount)), TOKEN_1M); // expired nft locked balance unchanged
    }

    function testClaimManyWithExpiredNFT() public {
        // test claim many with one expired nft and one normal nft
        VELO.approve(address(escrow), TOKEN_1M);
        uint256 tokenId = escrow.createLock(TOKEN_1M, WEEK * 4);
        VELO.approve(address(escrow), TOKEN_1M);
        uint256 tokenId2 = escrow.createLock(TOKEN_1M, MAXTIME);

        skipToNextEpoch(1);
        minter.update_period();
        assertEq(distributor.claimable(tokenId), 0);
        assertEq(distributor.claimable(tokenId2), 0);

        for (uint256 i = 0; i < 4; i++) {
            minter.update_period();
            skipToNextEpoch(1);
        }

        assertGt(distributor.claimable(tokenId), 0); // accrued rebases
        assertGt(distributor.claimable(tokenId2), 0);

        IVotingEscrow.LockedBalance memory locked = escrow.locked(tokenId);
        assertGt(block.timestamp, locked.end); // lock expired

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = tokenId;
        tokenIds[1] = tokenId2;

        uint256 rebase = distributor.claimable(tokenId);
        uint256 rebase2 = distributor.claimable(tokenId2);

        uint256 pre = VELO.balanceOf(address(owner));
        assertTrue(distributor.claimMany(tokenIds));
        uint256 post = VELO.balanceOf(address(owner));

        locked = escrow.locked(tokenId); // update locked value post claim
        IVotingEscrow.LockedBalance memory postLocked2 = escrow.locked(tokenId2);

        assertEq(post - pre, rebase); // expired rebase distributed as unlocked VELO
        assertEq(uint256(uint128(locked.amount)), TOKEN_1M); // expired nft locked balance unchanged
        assertEq(uint256(uint128(postLocked2.amount)) - uint256(uint128(locked.amount)), rebase2); // rebase accrued to normal nft
    }
}

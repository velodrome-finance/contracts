pragma solidity 0.8.13;

import "./BaseTest.sol";

contract RewardsDistributorTest is BaseTest {
    function _setUp() public override {
        VELO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        skip(1);

        address[] memory pools = new address[](2);
        pools[0] = address(pair);
        pools[1] = address(pair2);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 1;
        weights[1] = 1;
        voter.vote(tokenId, pools, weights);
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
        IVotingEscrow.LockedBalance memory locked2 = escrow.locked(tokenId2);

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

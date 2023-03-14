// 1:1 with Hardhat test
pragma solidity 0.8.13;

import "./BaseTest.sol";

contract VoterTest is BaseTest {
    event WhitelistToken(address indexed whitelister, address indexed token, bool _bool);
    event WhitelistNFT(address indexed whitelister, uint256 indexed tokenId, bool _bool);
    event Voted(address indexed voter, uint256 tokenId, uint256 weight);
    event NotifyReward(address indexed sender, address indexed reward, uint256 amount);

    // Note: _vote are not included in one-vote-per-epoch
    // Only vote() should be constrained as they must be called by the owner
    // Reset is not constrained as epochs are accrue and are distributed once per epoch
    // poke() can be called by anyone anytime to "refresh" an outdated vote state
    function testCannotChangeVoteInSameEpoch() public {
        VELO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME);

        // vote
        skipToNextEpoch(1 hours + 1);
        address[] memory pools = new address[](1);
        pools[0] = address(pair);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 5000;
        voter.vote(1, pools, weights);

        // fwd half epoch
        skip(1 weeks / 2);

        // try voting again and fail
        pools[0] = address(pair2);
        vm.expectRevert("Voter: already voted or deposited this epoch");
        voter.vote(1, pools, weights);
    }

    function testCannotResetInSameEpoch() public {
        VELO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME);

        // vote
        skipToNextEpoch(1 hours + 1);
        address[] memory pools = new address[](1);
        pools[0] = address(pair);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 5000;
        voter.vote(1, pools, weights);

        // fwd half epoch
        skip(1 weeks / 2);

        // try resetting and fail
        vm.expectRevert("Voter: already voted or deposited this epoch");
        voter.reset(1);
    }

    function testVoteAfterResetInSameEpoch() public {
        skip(1 weeks / 2);

        VELO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME);

        // create a bribe
        LR.approve(address(bribeVotingReward), TOKEN_1);
        bribeVotingReward.notifyRewardAmount(address(LR), TOKEN_1);
        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pair);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 1;
        voter.vote(1, pools, weights);

        skipToNextEpoch(1);

        assertEq(bribeVotingReward.earned(address(LR), 1), TOKEN_1);

        voter.reset(1);

        skip(1 days);

        LR.approve(address(bribeVotingReward2), TOKEN_1);
        bribeVotingReward2.notifyRewardAmount(address(LR), TOKEN_1);
        pools[0] = address(pair2);
        voter.vote(1, pools, weights);

        skipToNextEpoch(1);

        // rewards only occur for pair2, not pair
        assertEq(bribeVotingReward.earned(address(LR), 1), TOKEN_1);
        assertEq(bribeVotingReward2.earned(address(LR), 1), TOKEN_1);
    }

    function testVote() public {
        skip(1 hours + 1);
        VELO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        // vote
        address[] memory pools = new address[](2);
        pools[0] = address(pair);
        pools[1] = address(pair2);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 1;
        weights[1] = 2;

        /// balance: 997231719186530010
        vm.expectEmit(true, false, false, true, address(voter));
        emit Voted(address(owner), 1, 332410573062176670);
        vm.expectEmit(true, false, false, true, address(voter));
        emit Voted(address(owner), 1, 664821146124353340);
        voter.vote(tokenId, pools, weights);

        assertTrue(escrow.voted(tokenId));
        assertEq(voter.lastVoted(tokenId), block.timestamp);
        assertEq(voter.totalWeight(), 997231719186530010);
        assertEq(voter.usedWeights(tokenId), 997231719186530010);
        assertEq(voter.weights(address(pair)), 332410573062176670);
        assertEq(voter.weights(address(pair2)), 664821146124353340);
        assertEq(voter.votes(tokenId, address(pair)), 332410573062176670);
        assertEq(voter.votes(tokenId, address(pair2)), 664821146124353340);
        assertEq(voter.poolVote(tokenId, 0), address(pair));
        assertEq(voter.poolVote(tokenId, 1), address(pair2));

        vm.startPrank(address(owner2));
        VELO.approve(address(escrow), TOKEN_1);
        uint256 tokenId2 = escrow.createLock(TOKEN_1, MAXTIME);
        voter.vote(tokenId2, pools, weights);
        vm.stopPrank();

        assertTrue(escrow.voted(tokenId));
        assertEq(voter.lastVoted(tokenId), block.timestamp);
        assertEq(voter.totalWeight(), 1994463438373060020);
        assertEq(voter.usedWeights(tokenId), 997231719186530010);
        assertEq(voter.weights(address(pair)), 664821146124353340);
        assertEq(voter.weights(address(pair2)), 1329642292248706680);
        assertEq(voter.votes(tokenId, address(pair)), 332410573062176670);
        assertEq(voter.votes(tokenId, address(pair2)), 664821146124353340);
        assertEq(voter.poolVote(tokenId, 0), address(pair));
        assertEq(voter.poolVote(tokenId, 1), address(pair2));
    }

    function testReset() public {
        VELO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        voter.reset(tokenId);

        assertFalse(escrow.voted(tokenId));
        assertEq(voter.totalWeight(), 0);
        assertEq(voter.usedWeights(tokenId), 0);
        vm.expectRevert();
        voter.poolVote(tokenId, 0);
    }

    function testResetAfterVote() public {
        skip(1 hours + 1);
        VELO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        vm.startPrank(address(owner2));
        VELO.approve(address(escrow), TOKEN_1);
        uint256 tokenId2 = escrow.createLock(TOKEN_1, MAXTIME);
        vm.stopPrank();

        // vote
        address[] memory pools = new address[](2);
        pools[0] = address(pair);
        pools[1] = address(pair2);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 1;
        weights[1] = 2;

        voter.vote(tokenId, pools, weights);
        vm.prank(address(owner2));
        voter.vote(tokenId2, pools, weights);

        assertEq(voter.totalWeight(), 1994463438373060020);
        assertEq(voter.usedWeights(tokenId), 997231719186530010);
        assertEq(voter.weights(address(pair)), 664821146124353340);
        assertEq(voter.weights(address(pair2)), 1329642292248706680);
        assertEq(voter.votes(tokenId, address(pair)), 332410573062176670);
        assertEq(voter.votes(tokenId, address(pair2)), 664821146124353340);
        assertEq(voter.poolVote(tokenId, 0), address(pair));
        assertEq(voter.poolVote(tokenId, 1), address(pair2));

        uint256 lastVoted = voter.lastVoted(tokenId);
        skipToNextEpoch(1);

        voter.reset(tokenId);

        assertFalse(escrow.voted(tokenId));
        assertEq(voter.lastVoted(tokenId), lastVoted);
        assertEq(voter.totalWeight(), 997231719186530010);
        assertEq(voter.usedWeights(tokenId), 0);
        assertEq(voter.weights(address(pair)), 332410573062176670);
        assertEq(voter.weights(address(pair2)), 664821146124353340);
        assertEq(voter.votes(tokenId, address(pair)), 0);
        assertEq(voter.votes(tokenId, address(pair2)), 0);
        vm.expectRevert();
        voter.poolVote(tokenId, 0);
    }

    function testCannotVoteWithInactiveManagedNFT() public {
        uint256 mTokenId = escrow.createManagedLockFor(address(owner));

        skipAndRoll(1);

        escrow.setManagedState(mTokenId, true);
        assertTrue(escrow.deactivated(mTokenId));

        address[] memory pools = new address[](1);
        pools[0] = address(pair);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 1;

        vm.expectRevert("Voter: inactive managed nft");
        voter.vote(mTokenId, pools, weights);
    }

    function testCannotVoteAnHourAfterEpochFlips() public {
        VELO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pair);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 5000;

        skipToNextEpoch(0);
        vm.expectRevert("Voter: distribute window");
        voter.vote(1, pools, weights);

        skip(30 minutes);
        vm.expectRevert("Voter: distribute window");
        voter.vote(1, pools, weights);

        skip(30 minutes);
        vm.expectRevert("Voter: distribute window");
        voter.vote(1, pools, weights);

        skip(1);
        voter.vote(1, pools, weights);
    }

    function testCannotVoteAnHourBeforeEpochFlips() public {
        skipToNextEpoch(0);

        VELO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pair);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 5000;

        skip(7 days - 1 hours);
        uint256 sid = vm.snapshot();
        voter.vote(1, pools, weights);

        vm.revertTo(sid);
        skip(1);
        vm.expectRevert("Voter: nft not whitelisted");
        voter.vote(1, pools, weights);

        skip(1 hours - 2); /// one second prior to epoch flip
        vm.expectRevert("Voter: nft not whitelisted");
        voter.vote(1, pools, weights);

        vm.prank(address(governor));
        voter.whitelistNFT(1, true);
        voter.vote(1, pools, weights);

        skipToNextEpoch(1 hours + 1); /// new epoch
        voter.vote(1, pools, weights);
    }

    function testCannotSetMaxVotingNumIfNotGovernor() public {
        vm.prank(address(owner2));
        vm.expectRevert("Voter: not governor");
        voter.setMaxVotingNum(42);
    }

    function testCannotSetMaxVotingNumToSameNum() public {
        uint256 maxVotingNum = voter.maxVotingNum();
        vm.prank(address(governor));
        vm.expectRevert("Voter: same value");
        voter.setMaxVotingNum(maxVotingNum);
    }

    function testCannotSetMaxVotingNumBelow10() public {
        vm.startPrank(address(governor));
        vm.expectRevert("Voter: too low");
        voter.setMaxVotingNum(9);
    }

    function testSetMaxVotingNum() public {
        assertEq(voter.maxVotingNum(), 30);
        vm.prank(address(governor));
        voter.setMaxVotingNum(10);
        assertEq(voter.maxVotingNum(), 10);
    }

    function testCannotSetGovernorIfNotGovernor() public {
        vm.prank(address(owner2));
        vm.expectRevert("Voter: not governor");
        voter.setGovernor(address(owner2));
    }

    function testSetGovernor() public {
        vm.prank(address(governor));
        voter.setGovernor(address(owner2));

        assertEq(voter.governor(), address(owner2));
    }

    function testCannotSetEpochGovernorIfNotGovernor() public {
        vm.prank(address(owner2));
        vm.expectRevert("Voter: not governor");
        voter.setGovernor(address(owner2));
    }

    function testSetEpochGovernor() public {
        vm.prank(address(governor));
        voter.setEpochGovernor(address(owner2));

        assertEq(voter.epochGovernor(), address(owner2));
    }

    function testCannotSetEmergencyCouncilIfNotEmergencyCouncil() public {
        vm.prank(address(owner2));
        vm.expectRevert("Voter: not emergency council");
        voter.setEmergencyCouncil(address(owner2));
    }

    function testSetEmergencyCouncil() public {
        voter.setEmergencyCouncil(address(owner2));

        assertEq(voter.emergencyCouncil(), address(owner2));
    }

    function testCannotWhitelistIfNotGovernor() public {
        vm.prank(address(owner2));
        vm.expectRevert("Voter: not governor");
        voter.whitelistToken(address(WETH), true);
    }

    function testWhitelistTokenWithTrueExpectWhitelisted() public {
        address token = address(new MockERC20("TEST", "TEST", 18));

        assertFalse(voter.isWhitelistedToken(token));

        vm.prank(address(governor));
        vm.expectEmit(true, true, false, true, address(voter));
        emit WhitelistToken(address(governor), address(token), true);
        voter.whitelistToken(token, true);

        assertTrue(voter.isWhitelistedToken(token));
    }

    function testWhitelistTokenWithFalseExpectUnwhitelisted() public {
        address token = address(new MockERC20("TEST", "TEST", 18));

        assertFalse(voter.isWhitelistedToken(token));

        vm.prank(address(governor));
        voter.whitelistToken(token, true);

        assertTrue(voter.isWhitelistedToken(token));

        vm.prank(address(governor));
        vm.expectEmit(true, true, false, true, address(voter));
        emit WhitelistToken(address(governor), address(token), false);
        voter.whitelistToken(token, false);

        assertFalse(voter.isWhitelistedToken(token));
    }

    function testCannotwhitelistNFTIfNotGovernor() public {
        vm.prank(address(owner2));
        vm.expectRevert("Voter: not governor");
        voter.whitelistNFT(1, true);
    }

    function testwhitelistNFTWithTrueExpectWhitelisted() public {
        assertFalse(voter.isWhitelistedNFT(1));

        vm.prank(address(governor));
        vm.expectEmit(true, true, false, true, address(voter));
        emit WhitelistNFT(address(governor), 1, true);
        voter.whitelistNFT(1, true);

        assertTrue(voter.isWhitelistedNFT(1));
    }

    function testwhitelistNFTWithFalseExpectUnwhitelisted() public {
        assertFalse(voter.isWhitelistedNFT(1));

        vm.prank(address(governor));
        voter.whitelistNFT(1, true);

        assertTrue(voter.isWhitelistedNFT(1));

        vm.prank(address(governor));
        vm.expectEmit(true, true, false, true, address(voter));
        emit WhitelistNFT(address(governor), 1, false);
        voter.whitelistNFT(1, false);

        assertFalse(voter.isWhitelistedNFT(1));
    }

    function testKillGauge() public {
        voter.killGauge(address(gauge));
        assertFalse(voter.isAlive(address(gauge)));
    }

    function testCannotKillGaugeIfAlreadyKilled() public {
        voter.killGauge(address(gauge));
        assertFalse(voter.isAlive(address(gauge)));

        vm.expectRevert("Voter: gauge already dead");
        voter.killGauge(address(gauge));
    }

    function testReviveGauge() public {
        voter.killGauge(address(gauge));
        assertFalse(voter.isAlive(address(gauge)));

        voter.reviveGauge(address(gauge));
        assertTrue(voter.isAlive(address(gauge)));
    }

    function testCannotReviveGaugeIfAlreadyAlive() public {
        assertTrue(voter.isAlive(address(gauge)));

        vm.expectRevert("Voter: gauge already alive");
        voter.reviveGauge(address(gauge));
    }

    function testCannotKillNonExistentGauge() public {
        vm.expectRevert("Voter: gauge already dead");
        voter.killGauge(address(0xDEAD));
    }

    function testCannotKillGaugeIfNotEmergencyCouncil() public {
        vm.expectRevert("Voter: not emergency council");
        vm.prank(address(owner2));
        voter.killGauge(address(gauge));
    }

    function testKilledGaugeCanWithdraw() public {
        _addLiquidityToPool(address(owner), address(router), address(FRAX), address(USDC), true, TOKEN_100K, USDC_100K);

        uint256 supply = pair.balanceOf(address(owner));
        pair.approve(address(gauge), supply);
        gauge.deposit(supply);

        voter.killGauge(address(gauge));

        uint256 pre = pair.balanceOf(address(gauge));
        gauge.withdraw(supply);
        uint256 post = pair.balanceOf(address(gauge));

        assertEq(pre - post, supply);
    }

    function testKilledGaugeCanUpdateButSetToZero() public {
        _seedVoterWithVotingSupply();

        skipToNextEpoch(1);
        minter.update_period();
        voter.updateFor(address(gauge));

        // expect distribution
        assertGt(voter.claimable(address(gauge)), 0);

        voter.killGauge(address(gauge));

        voter.updateFor(address(gauge));

        assertEq(voter.claimable(address(gauge)), 0);
    }

    function testKilledGaugeCanDistributeButSetToZero() public {
        _seedVoterWithVotingSupply();

        skipToNextEpoch(1);
        minter.update_period();

        voter.updateFor(address(gauge));

        // expect distribution
        assertGt(voter.claimable(address(gauge)), 0);

        voter.killGauge(address(gauge));

        // distribute should update claimable to zero
        voter.distribute(0, voter.length());

        assertEq(voter.claimable(address(gauge)), 0);
    }

    function testCanStillDistributeAllWithKilledGauge() public {
        _seedVoterWithVotingSupply();

        skipToNextEpoch(1);
        minter.update_period();

        // both gauges have equal voting weight
        voter.updateFor(address(gauge));
        voter.updateFor(address(gauge2));

        // check existence of claims against gauges
        assertEq(voter.claimable(address(gauge)), 7499999999999999999999999);
        assertEq(voter.claimable(address(gauge2)), 7499999999999999999999999);

        address[] memory gauges = new address[](2);
        gauges[0] = address(gauge);
        gauges[1] = address(gauge2);
        voter.updateFor(gauges);

        voter.killGauge(address(gauge));

        voter.distribute(0, voter.length());

        // killed gauge receives no contributions
        assertEq(VELO.balanceOf(address(gauge)), 0);
        // gauge2 receives distributions
        assertEq(VELO.balanceOf(address(gauge2)), 7499999999999999999999999);
    }

    function testCannotNotifyRewardAmountIfNotMinter() public {
        vm.expectRevert("Voter: only minter can deposit reward");
        voter.notifyRewardAmount(TOKEN_1);
    }

    function testNotifyRewardAmount() public {
        _seedVoterWithVotingSupply();

        deal(address(VELO), address(minter), TOKEN_1);
        vm.prank(address(minter));
        VELO.approve(address(voter), TOKEN_1);

        uint256 minterPre = VELO.balanceOf(address(minter));
        uint256 voterPre = VELO.balanceOf(address(voter));

        vm.prank(address(minter));
        vm.expectEmit(true, false, false, true, address(voter));
        emit NotifyReward(address(minter), address(VELO), TOKEN_1);
        voter.notifyRewardAmount(TOKEN_1);

        uint256 minterPost = VELO.balanceOf(address(minter));
        uint256 voterPost = VELO.balanceOf(address(voter));

        assertEq(voterPost - voterPre, TOKEN_1);
        assertEq(minterPre - minterPost, TOKEN_1);
    }

    function testCannotDepositManagedIfNotOwnerOrApproved() public {
        uint256 mTokenId = escrow.createManagedLockFor(address(owner2));
        escrow.createManagedLockFor(address(owner));
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        vm.prank(address(owner2));
        vm.expectRevert("Voter: not owner or approved");
        voter.depositManaged(tokenId, mTokenId);
    }

    function testCannotDepositManagedWithInactiveManagedNft() public {
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        uint256 mTokenId = escrow.createManagedLockFor(address(owner));

        skipAndRoll(1);
        escrow.setManagedState(mTokenId, true);

        vm.expectRevert("Voter: inactive managed nft");
        voter.depositManaged(tokenId, mTokenId);
    }

    function testCannotDepositManagedAnHourBeforeEpochFlips() public {
        skipToNextEpoch(0);

        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        uint256 mTokenId = escrow.createManagedLockFor(address(owner));

        skip(7 days - 1 hours);
        uint256 sid = vm.snapshot();
        voter.depositManaged(tokenId, mTokenId);

        vm.revertTo(sid);
        skip(1);
        vm.expectRevert("Voter: cannot deposit in window");
        voter.depositManaged(tokenId, mTokenId);

        skip(1 hours - 2); /// one second prior to epoch flip
        vm.expectRevert("Voter: cannot deposit in window");
        voter.depositManaged(tokenId, mTokenId);

        skip(1); /// new epoch
        voter.depositManaged(tokenId, mTokenId);
    }

    function testCannotWithdrawManagedIfDepositManagedInSameEpoch() public {
        uint256 mTokenId = escrow.createManagedLockFor(address(owner2));
        escrow.createManagedLockFor(address(owner));
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        voter.depositManaged(tokenId, mTokenId);

        skip(1 weeks / 2);

        vm.expectRevert("Voter: already voted or deposited this epoch");
        voter.withdrawManaged(tokenId);
    }

    function testCannotWithdrawManagedIfNotOwnerOrApproved() public {
        uint256 mTokenId = escrow.createManagedLockFor(address(owner2));
        escrow.createManagedLockFor(address(owner));
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        voter.depositManaged(tokenId, mTokenId);

        skipToNextEpoch(1);

        vm.prank(address(owner3));
        vm.expectRevert("Voter: not owner or approved");
        voter.withdrawManaged(tokenId);
    }

    function testDepositManagedPokeWithoutExistingVote() public {
        uint256 mTokenId = escrow.createManagedLockFor(address(owner2));
        escrow.createManagedLockFor(address(owner));
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        skipToNextEpoch(1 hours + 1);

        voter.depositManaged(tokenId, mTokenId);

        assertFalse(escrow.voted(mTokenId));
        assertEq(voter.totalWeight(), 0);
        assertEq(voter.usedWeights(mTokenId), 0);
    }

    function testDepositManagedPokeWithExistingVote() public {
        uint256 mTokenId = escrow.createManagedLockFor(address(owner2));

        escrow.createManagedLockFor(address(owner));
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        uint256 tokenId2 = escrow.createLock(TOKEN_1, MAXTIME);

        skipToNextEpoch(1 hours + 1);

        voter.depositManaged(tokenId, mTokenId);

        address[] memory pools = new address[](1);
        pools[0] = address(pair);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        vm.prank(address(owner2));
        voter.vote(mTokenId, pools, weights);

        uint256 usedWeightsBefore = voter.usedWeights(mTokenId);
        uint256 totalWeightBefore = voter.totalWeight();

        voter.depositManaged(tokenId2, mTokenId);

        assertGt(voter.usedWeights(mTokenId), usedWeightsBefore);
        assertGt(voter.totalWeight(), totalWeightBefore);
    }

    function testWithdrawManagedToReset() public {
        uint256 mTokenId = escrow.createManagedLockFor(address(owner2));
        escrow.createManagedLockFor(address(owner));
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        skipToNextEpoch(1 hours + 1);

        voter.depositManaged(tokenId, mTokenId);

        address[] memory pools = new address[](1);
        pools[0] = address(pair);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        vm.prank(address(owner2));
        voter.vote(mTokenId, pools, weights);

        skipToNextEpoch(1 hours + 1);

        voter.withdrawManaged(tokenId);
        assertFalse(escrow.voted(mTokenId));
        assertEq(voter.totalWeight(), 0);
        assertEq(voter.usedWeights(mTokenId), 0);

        vm.expectRevert();
        voter.poolVote(mTokenId, 0);
    }

    function testWithdrawManagedToPoke() public {
        uint256 mTokenId = escrow.createManagedLockFor(address(owner2));
        escrow.createManagedLockFor(address(owner));
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        uint256 tokenId2 = escrow.createLock(TOKEN_1, MAXTIME);

        skipToNextEpoch(1 hours + 1);

        voter.depositManaged(tokenId, mTokenId);
        voter.depositManaged(tokenId2, mTokenId);

        address[] memory pools = new address[](1);
        pools[0] = address(pair);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        vm.prank(address(owner2));
        voter.vote(mTokenId, pools, weights);
        assertEq(escrow.balanceOfNFT(mTokenId), voter.totalWeight());
        assertEq(voter.usedWeights(mTokenId), voter.totalWeight());

        skipToNextEpoch(1 hours + 1);

        voter.withdrawManaged(tokenId);
        assertTrue(escrow.voted(mTokenId));
        // ensure voting weight of managed veNFT is now equal to the the regular tokenId
        assertEq(voter.totalWeight(), escrow.balanceOfNFT(tokenId));
        assertEq(voter.usedWeights(mTokenId), escrow.balanceOfNFT(tokenId));

        address poolVote = voter.poolVote(mTokenId, 0);
        assertEq(poolVote, address(pair));
    }

    function _seedVoterWithVotingSupply() internal {
        skip(1 hours + 1);
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
}

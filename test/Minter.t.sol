// 1:1 with Hardhat test
pragma solidity 0.8.13;

import "./BaseTest.sol";

contract MinterTest is BaseTest {
    using stdStorage for StdStorage;
    uint256 tokenId;

    event Nudge(uint256 _period, uint256 _oldRate, uint256 _newRate);

    function _setUp() public override {
        VELO.approve(address(escrow), TOKEN_1);
        tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        skip(1);

        address[] memory pools = new address[](2);
        pools[0] = address(pair);
        pools[1] = address(pair2);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 1;
        weights[1] = 1;
        voter.vote(tokenId, pools, weights);
    }

    function testMinterDeploy() public {
        assertEq(minter.MAXIMUM_TAIL_RATE(), 100); // 1%
        assertEq(minter.MINIMUM_TAIL_RATE(), 1); // .01%
        assertEq(minter.EMISSION(), 9_900);
        assertEq(minter.TAIL_START(), 5_000_000 * 1e18);
        assertEq(minter.weekly(), 15_000_000 * 1e18);
        assertEq(minter.tailEmissionRate(), 30); // .3%
        assertEq(minter.active_period(), 604800);
    }

    function testTailEmissionFlipsWhenWeeklyEmissionDecaysBelowTailStart() public {
        skipToNextEpoch(1);

        assertEq(VELO.balanceOf(address(voter)), 0);

        // 5_015_652 * 1e18 ~= approximate weekly value after 109 epochs
        // (last epoch prior to tail emissions kicking in)
        stdstore.target(address(minter)).sig("weekly()").checked_write(5_015_652 * 1e18);

        skipToNextEpoch(1);
        minter.update_period();
        assertApproxEqRel(VELO.balanceOf(address(voter)), 5_015_652 * 1e18, 1e12);
        voter.distribute(0, voter.length());

        skipToNextEpoch(1);
        // totalSupply ~= 55_015_652 * 1e18
        // expected mint = totalSupply * .3% ~= 105_047
        minter.update_period();
        assertApproxEqRel(VELO.balanceOf(address(voter)), 165_047 * 1e18, 1e12);
        assertLt(minter.weekly(), 5_000_000 * 1e18);
    }

    function testCannotNudgeIfNotEpochGovernor() public {
        /// put in tail emission schedule
        stdstore.target(address(minter)).sig("tail()").checked_write(true);

        vm.prank(address(owner2));
        vm.expectRevert("Minter: not epoch governor");
        minter.nudge();
    }

    function testCannotNudgeIfAlreadyNudged() public {
        /// put in tail emission schedule
        stdstore.target(address(minter)).sig("tail()").checked_write(true);
        assertFalse(minter.proposals(604800));

        vm.prank(address(epochGovernor));
        minter.nudge();
        assertTrue(minter.proposals(604800));
        skip(1);

        vm.expectRevert("Minter: tail rate already nudged this epoch");
        vm.prank(address(epochGovernor));
        minter.nudge();
    }

    function testCannotNudgeAboveMaximumRate() public {
        /// put in tail emission schedule
        stdstore.target(address(minter)).sig("tail()").checked_write(true);
        stdstore.target(address(minter)).sig("tailEmissionRate()").checked_write(100);
        assertEq(minter.tailEmissionRate(), 100);

        vm.expectRevert("Minter: cannot nudge above maximum rate");
        vm.prank(address(epochGovernor));
        minter.nudge();
    }

    function testCannotNudgeBelowMinimumRate() public {
        /// put in tail emission schedule
        stdstore.target(address(minter)).sig("tail()").checked_write(true);
        stdstore.target(address(minter)).sig("tailEmissionRate()").checked_write(1);
        assertEq(minter.tailEmissionRate(), 1);

        vm.expectRevert("Minter: cannot nudge below minimum rate");
        vm.prank(address(epochGovernor));
        minter.nudge();
    }

    function testNudge() public {
        stdstore.target(address(minter)).sig("tail()").checked_write(true);
        /// note: see IGovernor.ProposalState for enum numbering
        stdstore.target(address(epochGovernor)).sig("result()").checked_write(4);
        assertEq(minter.tailEmissionRate(), 30);

        vm.expectEmit(true, false, false, true, address(minter));
        emit Nudge(604800, 30, 31);
        vm.prank(address(epochGovernor));
        minter.nudge();

        assertEq(minter.tailEmissionRate(), 31);
        assertTrue(minter.proposals(604800));

        skipToNextEpoch(1);
        minter.update_period();

        stdstore.target(address(epochGovernor)).sig("result()").checked_write(3);

        vm.expectEmit(true, false, false, true, address(minter));
        emit Nudge(1209600, 31, 30);
        vm.prank(address(epochGovernor));
        minter.nudge();

        assertEq(minter.tailEmissionRate(), 30);
        assertTrue(minter.proposals(1209600));

        skipToNextEpoch(1);
        minter.update_period();

        stdstore.target(address(epochGovernor)).sig("result()").checked_write(6);

        vm.expectEmit(true, false, false, true, address(minter));
        emit Nudge(1814400, 30, 30);
        vm.prank(address(epochGovernor));
        minter.nudge();

        assertEq(minter.tailEmissionRate(), 30);
        assertTrue(minter.proposals(1814400));
    }

    function testMinterWeeklyDistribute() public {
        minter.update_period();
        assertEq(minter.weekly(), 15 * TOKEN_1M); // 15M

        uint256 pre = VELO.balanceOf(address(voter));
        skipToNextEpoch(1);
        minter.update_period();
        assertEq(distributor.claimable(tokenId), 0);
        // emissions decay by 1% after one epoch
        uint256 post = VELO.balanceOf(address(voter));
        assertEq(post - pre, (15 * TOKEN_1M));
        assertEq(minter.weekly(), ((15 * TOKEN_1M) * 99) / 100);

        pre = post;
        skipToNextEpoch(1);
        vm.roll(block.number + 1);
        minter.update_period();
        post = VELO.balanceOf(address(voter));

        // check rebase accumulated
        assertGt(distributor.claimable(1), 0);
        distributor.claim(1);
        assertEq(distributor.claimable(1), 0);

        assertEq(post - pre, (15 * TOKEN_1M * 99) / 100);
        assertEq(minter.weekly(), (((15 * TOKEN_1M * 99) / 100) * 99) / 100);

        skip(1 weeks);
        vm.roll(block.number + 1);
        minter.update_period();

        distributor.claim(1);

        skip(1 weeks);
        vm.roll(block.number + 1);
        minter.update_period();

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        distributor.claimMany(tokenIds);

        skip(1 weeks);
        vm.roll(block.number + 1);
        minter.update_period();
        distributor.claim(1);

        skip(1 weeks);
        vm.roll(block.number + 1);
        minter.update_period();
        distributor.claimMany(tokenIds);

        skip(1 weeks);
        vm.roll(block.number + 1);
        minter.update_period();
        distributor.claim(1);
    }
}

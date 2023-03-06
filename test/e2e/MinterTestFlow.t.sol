pragma solidity 0.8.13;

import "./ExtendedBaseTest.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract MinterTestFlow is ExtendedBaseTest {
    event Mint(address indexed _sender, uint256 _weekly, uint256 _circulating_supply, bool _tail);

    function testMinterRebaseFlow() public {
        /// epoch 0
        minter.update_period();
        assertEq(VELO.balanceOf(address(voter)), 0);

        VELO.approve(address(escrow), TOKEN_100K);
        uint256 tokenId = escrow.createLock(TOKEN_100K, MAXTIME);

        vm.startPrank(address(owner2));
        VELO.approve(address(escrow), TOKEN_100K);
        uint256 tokenId2 = escrow.createLock(TOKEN_100K, MAXTIME);
        vm.stopPrank();

        assertEq(distributor.claimable(tokenId), 0);
        assertEq(distributor.claimable(tokenId), 0);

        skip(1 hours + 1);

        // equal votes for both pools
        address[] memory pools = new address[](2);
        pools[0] = address(pair);
        pools[1] = address(pair2);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 1;
        weights[1] = 1;
        voter.vote(tokenId, pools, weights);
        vm.prank(address(owner2));
        voter.vote(tokenId2, pools, weights);
        skipAndRoll(1);

        pair.approve(address(gauge), PAIR_1);
        gauge.deposit(PAIR_1);

        /// epoch 1
        skipToNextEpoch(2 days); // gauge distributions spread out over 5 days

        /// 15000000000000000000000000
        uint256 expectedMint = _expectedMintAfter(1);
        vm.expectEmit(true, true, false, false, address(minter));
        emit Mint(address(owner), expectedMint, 0, false);
        minter.update_period();
        assertEq(VELO.balanceOf(address(voter)), expectedMint);

        uint256 epochStart = _getEpochStart(block.timestamp);
        voter.distribute(address(gauge));
        assertApproxEqRel(VELO.balanceOf(address(gauge)), expectedMint / 2, 1e6);
        assertApproxEqRel(VELO.balanceOf(address(voter)), expectedMint / 2, 1e6);
        assertApproxEqRel(gauge.rewardRate(), expectedMint / 2 / (5 days), 1e6);
        assertApproxEqRel(gauge.rewardRateByEpoch(epochStart), expectedMint / 2 / (5 days), 1e6);
        skipAndRoll(1);

        minter.update_period();
        assertApproxEqRel(VELO.balanceOf(address(voter)), expectedMint / 2, 1e6);
        skipAndRoll(1);

        voter.distribute(address(gauge2));
        assertApproxEqRel(VELO.balanceOf(address(gauge2)), expectedMint / 2, 1e6);
        assertLt(VELO.balanceOf(address(voter)), 1e6); // dust
        skipAndRoll(1);

        skip(1 hours);
        voter.distribute(address(gauge)); // second distribute should make no difference to gauge
        assertApproxEqRel(VELO.balanceOf(address(gauge)), expectedMint / 2, 1e6);
        assertLt(VELO.balanceOf(address(voter)), 1e6); // dust
        assertApproxEqRel(gauge.rewardRate(), expectedMint / 2 / (5 days), 1e6);
        assertApproxEqRel(gauge.rewardRateByEpoch(epochStart), expectedMint / 2 / (5 days), 1e6);

        /// epoch 2
        skipToNextEpoch(1);
        uint256 balance = VELO.balanceOf(address(gauge));
        /// 14850000000000000000000000
        expectedMint = _expectedMintAfter(2);
        balance += expectedMint / 2;

        vm.expectEmit(true, true, false, false, address(minter));
        emit Mint(address(voter), expectedMint, 0, false);
        voter.distribute(0, voter.length());
        assertLt(VELO.balanceOf(address(voter)), 1e6);
        assertApproxEqRel(VELO.balanceOf(address(gauge)), balance, 1e6);
        assertApproxEqRel(VELO.balanceOf(address(gauge)), balance, 1e6);

        /// after 110 epochs, tail emissions turn on
        for (uint256 i = 0; i < 108; i++) {
            skipToNextEpoch(1);
            minter.update_period();
        }
        voter.distribute(0, voter.length());
        assertTrue(minter.tail());

        // skip to first tail distribution
        skipToNextEpoch(1);

        minter.update_period();
        /// total velo supply ~1053450368, tail emissions .3% of total supply
        assertApproxEqAbs(VELO.balanceOf(address(voter)), 3160351 * TOKEN_1, TOKEN_1);
        voter.distribute(0, voter.length());

        assertEq(minter.tailEmissionRate(), 30);

        escrow.increaseUnlockTime(tokenId, MAXTIME);

        address[] memory targets = new address[](1);
        targets[0] = address(minter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(minter.nudge.selector);
        string memory description = Strings.toString(block.timestamp);

        uint256 pid = epochGovernor.propose(targets, values, calldatas, description);

        skipAndRoll(15 minutes); // epoch + 15 minutes + 1
        vm.expectRevert("GovernorSimple: vote not currently active");
        epochGovernor.castVote(pid, 1);
        skipAndRoll(1); // epoch + 15 minutes + 2

        /// expect 1 (for vote) to pass
        epochGovernor.castVote(pid, 1);
        vm.prank(address(owner2));
        epochGovernor.castVote(pid, 0);

        skipAndRoll(1 weeks); // epoch + 15 minutes + 2
        epochGovernor.execute(targets, values, calldatas, keccak256(bytes(description)));
        assertEq(minter.tailEmissionRate(), 31);

        minter.update_period();
        /// total velo supply ~1056610719, tail emissions .31% of total supply
        assertApproxEqAbs(VELO.balanceOf(address(voter)), 3275493 * TOKEN_1, TOKEN_1);
        voter.distribute(0, voter.length());

        description = Strings.toString(block.timestamp);
        pid = epochGovernor.propose(targets, values, calldatas, description);
        skipAndRoll(15 minutes + 1); // epoch + 30 minutes + 3

        /// expect 2 (no change vote) to pass
        epochGovernor.castVote(pid, 2);
        vm.prank(address(owner2));
        epochGovernor.castVote(pid, 1);

        skipToNextEpoch(0);
        // create new proposal immediately on epoch flip (i.e. two concurrent proposals)
        string memory description2 = Strings.toString(block.timestamp);
        uint256 pid2 = epochGovernor.propose(targets, values, calldatas, description2);

        skipAndRoll(30 minutes + 3); // epoch + 30 minutes + 3
        epochGovernor.execute(targets, values, calldatas, keccak256(bytes(description)));
        assertEq(minter.tailEmissionRate(), 31);

        minter.update_period();
        /// total velo supply ~1059886384, tail emissions .31% of total supply
        assertApproxEqAbs(VELO.balanceOf(address(voter)), 3285647 * TOKEN_1, TOKEN_1);
        voter.distribute(0, voter.length());

        /// expect 0 (against vote) to pass
        epochGovernor.castVote(pid2, 0);
        vm.prank(address(owner2));
        epochGovernor.castVote(pid2, 2);

        skipAndRoll(1 weeks);
        epochGovernor.execute(targets, values, calldatas, keccak256(bytes(description2)));
        assertEq(minter.tailEmissionRate(), 30);

        minter.update_period();
        /// total velo supply ~1063172199, tail emissions .31% of total supply
        assertApproxEqAbs(VELO.balanceOf(address(voter)), 3189516 * TOKEN_1, TOKEN_1);
        voter.distribute(0, voter.length());
    }

    /// @dev Helper to calculate expected tokens minted.
    function _expectedMintAfter(uint256 _weeks) internal pure returns (uint256) {
        uint256 amount = 15_000_000 * 1e18;
        for (uint256 i = 0; i < _weeks - 1; i++) {
            amount = (amount * 9_900) / 10_000;
        }
        return amount;
    }
}

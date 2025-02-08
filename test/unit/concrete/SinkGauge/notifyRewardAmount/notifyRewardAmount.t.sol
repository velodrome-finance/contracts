// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../SinkGauge.t.sol";

contract NotifyRewardAmountTest is SinkGaugeTest {
    function test_WhenCallerIsNotVoter() external {
        // It should revert with {NotVoter}
        uint256 _amount;

        vm.expectRevert(ISinkGauge.NotVoter.selector);
        sinkGauge.notifyRewardAmount({_amount: _amount});
    }

    modifier whenCallerIsVoter() {
        vm.startPrank(address(voter));
        _;
    }

    function test_WhenAmountIsZero() external whenCallerIsVoter {
        // It should revert with {ZeroAmount}
        uint256 _amount = 0;

        vm.expectRevert(ISinkGauge.ZeroAmount.selector);
        sinkGauge.notifyRewardAmount({_amount: _amount});
    }

    function test_WhenAmountIsGreaterThanZero() external whenCallerIsVoter {
        // It should transfer rewards from voter to minter
        // It should update locked rewards
        // It should update token rewards per epoch
        // It should emit a {NotifyReward} event
        // It should emit a {ClaimRewards} event

        uint256 _amount = TOKEN_100K;
        deal(address(VELO), address(voter), _amount, true);
        VELO.approve({spender: address(sinkGauge), value: _amount});

        vm.expectEmit(address(sinkGauge));
        emit ISinkGauge.NotifyReward({_from: address(voter), _amount: _amount});
        vm.expectEmit(address(sinkGauge));
        emit ISinkGauge.ClaimRewards({_from: address(minter), _amount: _amount});
        sinkGauge.notifyRewardAmount({_amount: _amount});

        assertEq(VELO.balanceOf(address(voter)), 0);
        assertEq(VELO.balanceOf(address(sinkGauge)), 0);
        assertEq(VELO.balanceOf(address(minter)), _amount);
        assertEq(sinkGauge.lockedRewards(), _amount);

        uint256 epochStart = VelodromeTimeLibrary.epochStart({timestamp: block.timestamp});
        assertEq(sinkGauge.tokenRewardsPerEpoch({_epochStart: epochStart}), _amount);
    }
}

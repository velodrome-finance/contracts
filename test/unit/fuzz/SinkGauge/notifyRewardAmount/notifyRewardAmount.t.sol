// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../SinkGauge.t.sol";

contract NotifyRewardAmountFuzzTest is SinkGaugeTest {
    function testFuzz_WhenCallerIsNotVoter(address _caller) external {
        // It should revert with {NotVoter}
        vm.assume(_caller != address(voter));
        uint256 _amount;

        vm.expectRevert(ISinkGauge.NotVoter.selector);
        sinkGauge.notifyRewardAmount({_amount: _amount});
    }

    modifier whenCallerIsVoter() {
        vm.startPrank(address(voter));
        _;
    }

    function testFuzz_WhenAmountIsZero() external {}

    function testFuzz_WhenAmountIsGreaterThanZero(uint256 _amount) external whenCallerIsVoter {
        // It should transfer rewards from voter to minter
        // It should update locked rewards
        // It should update token rewards per epoch
        // It should emit a {NotifyReward} event
        // It should emit a {ClaimRewards} event
        _amount = bound(_amount, 1, TOKEN_10B);

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

// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../SimpleEpochGovernor.t.sol";

contract ExecuteNudgeTest is SimpleEpochGovernorTest {
    function test_WhenCallerIsNotGovernor() external {
        // It should revert with {NotGovernor}
        vm.prank(address(owner));
        vm.expectRevert(ISimpleEpochGovernor.NotGovernor.selector);
        simpleGovernor.executeNudge();
    }

    modifier whenCallerIsGovernor() {
        vm.startPrank(address(governor));
        _;
    }

    function test_WhenResultIsSucceeded() external whenCallerIsGovernor {
        // It should execute nudge in minter
        // It should increase tail emission rate by 1 bps
        // It should emit a {NudgeExecuted} event
        assertEq(minter.tailEmissionRate(), 30);

        // set new result
        simpleGovernor.setResult({_state: IEpochGovernor.ProposalState.Succeeded});

        // execute
        vm.expectEmit(address(minter));
        emit IMinter.Nudge({
            _period: minter.activePeriod(),
            _oldRate: minter.tailEmissionRate(),
            _newRate: minter.tailEmissionRate() + 1
        });
        vm.expectEmit(address(simpleGovernor));
        emit ISimpleEpochGovernor.NudgeExecuted({result: IEpochGovernor.ProposalState.Succeeded});
        simpleGovernor.executeNudge();

        assertEq(minter.tailEmissionRate(), 31);
    }

    function test_WhenResultIsDefeated() external whenCallerIsGovernor {
        // It should execute nudge in minter
        // It should decrease tail emission rate by 1 bps
        // It should emit a {NudgeExecuted} event
        assertEq(minter.tailEmissionRate(), 30);

        // set new result
        simpleGovernor.setResult({_state: IEpochGovernor.ProposalState.Defeated});

        // execute
        vm.expectEmit(address(minter));
        emit IMinter.Nudge({
            _period: minter.activePeriod(),
            _oldRate: minter.tailEmissionRate(),
            _newRate: minter.tailEmissionRate() - 1
        });
        vm.expectEmit(address(simpleGovernor));
        emit ISimpleEpochGovernor.NudgeExecuted({result: IEpochGovernor.ProposalState.Defeated});
        simpleGovernor.executeNudge();

        assertEq(minter.tailEmissionRate(), 29);
    }

    function test_WhenResultIsExpired() external whenCallerIsGovernor {
        // It should execute nudge in minter
        // It should not update tail emission
        // It should emit a {NudgeExecuted} event
        assertEq(minter.tailEmissionRate(), 30);

        // set new result
        simpleGovernor.setResult({_state: IEpochGovernor.ProposalState.Expired});

        // execute
        vm.expectEmit(address(minter));
        emit IMinter.Nudge({
            _period: minter.activePeriod(),
            _oldRate: minter.tailEmissionRate(),
            _newRate: minter.tailEmissionRate()
        });
        vm.expectEmit(address(simpleGovernor));
        emit ISimpleEpochGovernor.NudgeExecuted({result: IEpochGovernor.ProposalState.Expired});
        simpleGovernor.executeNudge();

        assertEq(minter.tailEmissionRate(), 30);
    }
}

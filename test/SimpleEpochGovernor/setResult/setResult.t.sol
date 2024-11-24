// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../SimpleEpochGovernor.t.sol";

contract SetResultTest is SimpleEpochGovernorTest {
    function test_WhenCallerIsNotGovernor() external {
        // It should revert with {NotGovernor}
        vm.prank(address(owner));
        vm.expectRevert(ISimpleEpochGovernor.NotGovernor.selector);
        simpleGovernor.setResult({_state: IEpochGovernor.ProposalState.Succeeded});
    }

    modifier whenCallerIsGovernor() {
        vm.startPrank(address(governor));
        _;
    }

    function test_WhenNewStateIsNotValid() external whenCallerIsGovernor {
        // It should revert with {InvalidState}
        vm.expectRevert(ISimpleEpochGovernor.InvalidState.selector);
        simpleGovernor.setResult({_state: IEpochGovernor.ProposalState.Pending});

        vm.expectRevert(ISimpleEpochGovernor.InvalidState.selector);
        simpleGovernor.setResult({_state: IEpochGovernor.ProposalState.Active});

        vm.expectRevert(ISimpleEpochGovernor.InvalidState.selector);
        simpleGovernor.setResult({_state: IEpochGovernor.ProposalState.Canceled});

        vm.expectRevert(ISimpleEpochGovernor.InvalidState.selector);
        simpleGovernor.setResult({_state: IEpochGovernor.ProposalState.Queued});

        vm.expectRevert(ISimpleEpochGovernor.InvalidState.selector);
        simpleGovernor.setResult({_state: IEpochGovernor.ProposalState.Executed});
    }

    function test_WhenNewStateIsSucceeded() external whenCallerIsGovernor {
        // It should set the succeeded result
        // It should emit a {ResultSet} event
        vm.expectEmit(address(simpleGovernor));
        emit ISimpleEpochGovernor.ResultSet({state: IEpochGovernor.ProposalState.Succeeded});
        simpleGovernor.setResult({_state: IEpochGovernor.ProposalState.Succeeded});

        assert(simpleGovernor.result() == IEpochGovernor.ProposalState.Succeeded);
    }

    function test_WhenNewStateIsDefeated() external whenCallerIsGovernor {
        // It should set the defeated result
        // It should emit a {ResultSet} event
        vm.expectEmit(address(simpleGovernor));
        emit ISimpleEpochGovernor.ResultSet({state: IEpochGovernor.ProposalState.Defeated});
        simpleGovernor.setResult({_state: IEpochGovernor.ProposalState.Defeated});

        assert(simpleGovernor.result() == IEpochGovernor.ProposalState.Defeated);
    }

    function test_WhenNewStateIsExpired() external whenCallerIsGovernor {
        // It should set the expired result
        // It should emit a {ResultSet} event
        vm.expectEmit(address(simpleGovernor));
        emit ISimpleEpochGovernor.ResultSet({state: IEpochGovernor.ProposalState.Expired});
        simpleGovernor.setResult({_state: IEpochGovernor.ProposalState.Expired});

        assert(simpleGovernor.result() == IEpochGovernor.ProposalState.Expired);
    }
}

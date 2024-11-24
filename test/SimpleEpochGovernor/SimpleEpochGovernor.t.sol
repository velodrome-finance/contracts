// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../BaseTest.sol";
import {IEpochGovernor} from "contracts/interfaces/IEpochGovernor.sol";
import {ISimpleEpochGovernor} from "contracts/interfaces/ISimpleEpochGovernor.sol";

contract SimpleEpochGovernorTest is BaseTest {
    using stdStorage for StdStorage;

    SimpleEpochGovernor public simpleGovernor;

    function _setUp() public override {
        simpleGovernor = new SimpleEpochGovernor(address(minter), address(voter));
        vm.prank(address(governor));
        voter.setEpochGovernor(address(simpleGovernor));

        stdstore.target(address(minter)).sig("weekly()").checked_write(4_999_999 * 1e18);
    }

    function testInitialState() public view {
        assertEq(address(simpleGovernor.voter()), address(voter));
        assert(simpleGovernor.result() == IEpochGovernor.ProposalState.Defeated);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IVotes} from "./governance/IVotes.sol";

import {IGovernor} from "./governance/IGovernor.sol";
import {GovernorSimple} from "./governance/GovernorSimple.sol";
import {GovernorCountingMajority} from "./governance/GovernorCountingMajority.sol";
import {GovernorSimpleVotes} from "./governance/GovernorSimpleVotes.sol";

/**
 * @dev Epoch based governance system that allows for a three option majority (against, for, abstain).
 *      Note that hash proposals are unique per epoch, but calls to a function with different values
 *      may be allowed any number of times. It is best to use EpochGovernor with a function that accepts
 *      no values.
 */
contract EpochGovernor is GovernorSimple, GovernorCountingMajority, GovernorSimpleVotes {
    constructor(
        address _forwarder,
        IVotes _ve,
        address _minter
    ) GovernorSimple(_forwarder, "Epoch Governor", _minter) GovernorSimpleVotes(_ve) {}

    function votingDelay() public pure override(IGovernor) returns (uint256) {
        return (15 minutes);
    }

    function votingPeriod() public pure override(IGovernor) returns (uint256) {
        return (1 weeks);
    }
}

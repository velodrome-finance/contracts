// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

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
    constructor(IVotes _ve, address _minter) GovernorSimple("Epoch Governor", _minter) GovernorSimpleVotes(_ve) {}

    function votingDelay() public pure override(IGovernor) returns (uint256) {
        return 100;
    }

    function votingPeriod() public pure override(IGovernor) returns (uint256) {
        return (1 weeks) / 2; // assumes block every two seconds
    }
}

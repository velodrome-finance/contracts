// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IEpochGovernor} from "./IEpochGovernor.sol";
import {IMinter} from "./IMinter.sol";
import {IVoter} from "./IVoter.sol";

interface ISimpleEpochGovernor is IEpochGovernor {
    error NotGovernor();
    error InvalidState();

    event ResultSet(ProposalState indexed state);
    event NudgeExecuted(ProposalState indexed result);

    /// @notice Address of Velodrome Minter contract
    function minter() external view returns (IMinter);

    /// @notice Address of Velodrome v2 Voter
    function voter() external view returns (IVoter);

    /// @notice Execute `Minter.nudge()` with current `result`
    /// @dev Only callable by governor
    function executeNudge() external;

    /// @notice Set proposal result
    /// @dev Only callable by governor
    /// @param _state New state for proposal's result
    function setResult(ProposalState _state) external;
}

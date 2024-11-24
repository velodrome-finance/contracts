// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import {ISimpleEpochGovernor, IEpochGovernor} from "./interfaces/ISimpleEpochGovernor.sol";
import {IMinter} from "./interfaces/IMinter.sol";
import {IVoter} from "./interfaces/IVoter.sol";

contract SimpleEpochGovernor is ISimpleEpochGovernor {
    /// @inheritdoc ISimpleEpochGovernor
    IMinter public immutable minter;
    /// @inheritdoc ISimpleEpochGovernor
    IVoter public immutable voter;
    /// @inheritdoc IEpochGovernor
    ProposalState public result;

    constructor(address _minter, address _voter) {
        minter = IMinter(_minter);
        voter = IVoter(_voter);
        result = ProposalState.Defeated;
    }

    /// @inheritdoc ISimpleEpochGovernor
    function executeNudge() external {
        if (msg.sender != voter.governor()) {
            revert NotGovernor();
        }
        minter.nudge();
        emit NudgeExecuted({result: result});
    }

    /// @inheritdoc ISimpleEpochGovernor
    function setResult(ProposalState _state) external {
        if (msg.sender != voter.governor()) {
            revert NotGovernor();
        }
        if (_state != ProposalState.Expired && _state != ProposalState.Succeeded && _state != ProposalState.Defeated) {
            revert InvalidState();
        }
        result = _state;
        emit ResultSet({state: _state});
    }
}

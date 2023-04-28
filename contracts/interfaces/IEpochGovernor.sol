// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IEpochGovernor {
    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed
    }

    function result() external returns (ProposalState);
}

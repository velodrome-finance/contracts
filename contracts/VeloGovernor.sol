// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

import {IVetoGovernor} from "./governance/IVetoGovernor.sol";
import {VetoGovernor} from "./governance/VetoGovernor.sol";
import {VetoGovernorCountingSimple} from "./governance/VetoGovernorCountingSimple.sol";
import {VetoGovernorVotes} from "./governance/VetoGovernorVotes.sol";
import {VetoGovernorVotesQuorumFraction} from "./governance/VetoGovernorVotesQuorumFraction.sol";

contract VeloGovernor is VetoGovernor, VetoGovernorCountingSimple, VetoGovernorVotes, VetoGovernorVotesQuorumFraction {
    address public team;
    address public vetoer;
    address public pendingVetoer;
    uint256 public constant MAX_PROPOSAL_NUMERATOR = 500; // max 5%
    uint256 public constant PROPOSAL_DENOMINATOR = 10_000;
    uint256 public proposalNumerator = 2; // start at 0.02%

    constructor(IVotes _ve)
        VetoGovernor("Velodrome Governor")
        VetoGovernorVotes(_ve)
        VetoGovernorVotesQuorumFraction(4) // 4%
    {
        team = msg.sender;
        vetoer = msg.sender;
    }

    function votingDelay() public pure override(IVetoGovernor) returns (uint256) {
        return (15 minutes);
    }

    function votingPeriod() public pure override(IVetoGovernor) returns (uint256) {
        return (1 weeks);
    }

    function setTeam(address newTeam) external {
        require(msg.sender == team, "VeloGovernor: not team");
        team = newTeam;
    }

    function setProposalNumerator(uint256 numerator) external {
        require(msg.sender == team, "VeloGovernor: not team");
        require(numerator <= MAX_PROPOSAL_NUMERATOR, "VeloGovernor: numerator too high");
        proposalNumerator = numerator;
    }

    function proposalThreshold() public view override(VetoGovernor) returns (uint256) {
        return (token.getPastTotalSupply(block.timestamp - 1) * proposalNumerator) / PROPOSAL_DENOMINATOR;
    }

    /// @dev Vetoer can be removed once the risk of a 51% attack becomes unfeasible.
    ///      This can be done by transferring ownership of vetoer to a contract that is "bricked"
    ///      i.e. a non-zero address contract that is immutable with no ability to call this function.
    function setVetoer(address _vetoer) external {
        require(_vetoer != address(0), "VeloGovernor: zero address");
        require(msg.sender == vetoer, "VeloGovernor: not vetoer");
        pendingVetoer = _vetoer;
    }

    function acceptVetoer() external {
        require(msg.sender == pendingVetoer, "VeloGovernor: not pending vetoer");
        vetoer = pendingVetoer;
        delete pendingVetoer;
    }

    /// @notice Support for vetoer to protect against 51% attacks
    function veto(uint256 _proposalId) external {
        require(msg.sender == vetoer, "VeloGovernor: not vetoer");
        _veto(_proposalId);
    }

    function renounceVetoer() external {
        require(msg.sender == vetoer, "VeloGovernor: not vetoer");
        delete vetoer;
    }
}

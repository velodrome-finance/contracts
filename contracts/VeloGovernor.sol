// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {GovernorVotesQuorumFraction} from "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";

contract VeloGovernor is Governor, GovernorCountingSimple, GovernorVotes, GovernorVotesQuorumFraction {
    address public team;
    uint256 public constant MAX_PROPOSAL_NUMERATOR = 50; // max 5%
    uint256 public constant PROPOSAL_DENOMINATOR = 10_000;
    uint256 public proposalNumerator = 20; // start at 0.02%

    constructor(IVotes _ve)
        Governor("Velodrome Governor")
        GovernorVotes(_ve)
        GovernorVotesQuorumFraction(4) // 4%
    {
        team = msg.sender;
    }

    function votingDelay() public pure override(IGovernor) returns (uint256) {
        return 100;
    }

    function votingPeriod() public pure override(IGovernor) returns (uint256) {
        return (1 weeks) / 2; // assumes block every two seconds
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

    function proposalThreshold() public view override(Governor) returns (uint256) {
        return (token.getPastTotalSupply(block.number) * proposalNumerator) / PROPOSAL_DENOMINATOR;
    }
}

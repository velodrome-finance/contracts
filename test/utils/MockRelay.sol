// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IGovernor} from "../../contracts/governance/IGovernor.sol";
import {IVotingEscrow} from "../../contracts/interfaces/IVotingEscrow.sol";
import {IVoter} from "../../contracts/interfaces/IVoter.sol";

contract MockRelay is IERC721Receiver {
    // The managed lock token ID that this relay holds
    uint256 public managedLockId;

    // Mapping to store fractional votes for each proposal
    // governor => proposalId => (total_against, total_for, total_abstain)
    mapping(address => mapping(uint256 => uint256[3])) public totalVotes;

    // Mapping to track if a tokenId has voted on a proposal
    // governor => proposalId => tokenId => hasVoted
    mapping(address _governor => mapping(uint256 _proposalId => mapping(uint256 _tokenId => bool))) public hasVoted;

    // The escrow contract that manages the locks
    address public immutable escrow;

    constructor(address _escrow) {
        escrow = _escrow;
    }

    // Function to register fractional votes for a proposal
    function registerVote(
        address _governor,
        uint256 proposalId,
        uint256 tokenId,
        uint256 againstWeight,
        uint256 forWeight,
        uint256 abstainWeight
    ) external {
        require(managedLockId != 0, "No managed lock");
        require(IVotingEscrow(escrow).ownerOf(tokenId) == msg.sender, "Not owner of tokenId");
        require(IVotingEscrow(escrow).idToManaged(tokenId) == managedLockId, "Token not deposited with managed NFT");
        require(!hasVoted[_governor][proposalId][tokenId], "Already voted with this tokenId");

        // Get the voter address from escrow
        address voter = IVotingEscrow(escrow).voter();

        uint256 depositTime = IVoter(voter).lastVoted(tokenId);
        uint256 proposalStartTime = IGovernor(_governor).proposalSnapshot(proposalId);

        // Ensure the token was deposited before the proposal started
        require(depositTime < proposalStartTime, "Token deposited after proposal start");

        // Update the total votes for this proposal
        totalVotes[_governor][proposalId][0] += againstWeight;
        totalVotes[_governor][proposalId][1] += forWeight;
        totalVotes[_governor][proposalId][2] += abstainWeight;

        // Mark that this tokenId has voted
        hasVoted[_governor][proposalId][tokenId] = true;
    }

    // Function to execute the actual vote on the governor
    function executeVote(address _governor, uint256 proposalId) external {
        require(managedLockId != 0, "No managed lock");

        // Get the total votes for this proposal
        uint256[3] memory votes = totalVotes[_governor][proposalId];

        // Ensure there are votes to cast
        uint256 totalWeight = votes[0] + votes[1] + votes[2];
        require(totalWeight > 0, "No votes registered");

        // Encode the fractional votes as packed uint128 values
        bytes memory params = abi.encodePacked(uint128(votes[0]), uint128(votes[1]), uint128(votes[2]));

        // Cast the fractional vote
        IGovernor(_governor).castVoteWithReasonAndParams({
            _proposalId: proposalId,
            _tokenId: managedLockId,
            _support: 255,
            _reason: "",
            _params: params
        });

        // Clear the votes after execution
        delete totalVotes[_governor][proposalId];
    }

    // IERC721Receiver implementation
    function onERC721Received(address, address, uint256 id, bytes calldata) external override returns (bytes4) {
        require(msg.sender == escrow, "Only escrow");
        require(managedLockId == 0, "Already has a lock");
        managedLockId = id;
        return this.onERC721Received.selector;
    }
}

// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {GovernorSimple} from "./GovernorSimple.sol";

/**
 * @dev Extension of {Governor} for fractional voting.
 * @dev note slightly modified to support tokenId based voting
 *
 * Similar to {GovernorCountingSimple}, this contract is a votes counting module for {Governor} that supports 3 options:
 * Against, For, Abstain. Additionally, it includes a fourth option: Fractional, which allows voters to split their voting
 * power amongst the other 3 options.
 *
 * Votes cast with the Fractional support must be accompanied by a `params` argument that is three packed `uint128` values
 * representing the weight the delegate assigns to Against, For, and Abstain respectively. For those votes cast for the other
 * 3 options, the `params` argument must be empty.
 *
 * This is mostly useful when the delegate is a contract that implements its own rules for voting. These delegate-contracts
 * can cast fractional votes according to the preferences of multiple entities delegating their voting power.
 *
 * Some example use cases include:
 *
 * * Voting from tokens that are held by a DeFi pool
 * * Voting from an L2 with tokens held by a bridge
 * * Voting privately from a shielded pool using zero knowledge proofs.
 *
 * Based on ScopeLift's GovernorCountingFractional[https://github.com/ScopeLift/flexible-voting/blob/e5de2efd1368387b840931f19f3c184c85842761/src/GovernorCountingFractional.sol]
 *
 * _Available since v5.1._
 */
abstract contract EpochGovernorCountingFractional is GovernorSimple {
    using Math for *;

    uint8 internal constant VOTE_TYPE_FRACTIONAL = 255;

    struct ProposalVote {
        uint256 againstVotes;
        uint256 forVotes;
        uint256 abstainVotes;
        mapping(uint256 tokenId => uint256) usedVotes;
    }

    /**
     * @dev Mapping from proposal ID to vote tallies for that proposal.
     */
    mapping(uint256 proposalId => ProposalVote) private _proposalVotes;

    /**
     * @dev A fractional vote params uses more votes than are available for that user.
     */
    error GovernorExceedRemainingWeight(uint256 _tokenId, uint256 _usedVotes, uint256 _remainingWeight);

    /**
     * @dev See {IGovernor-COUNTING_MODE}.
     */
    // solhint-disable-next-line func-name-mixedcase
    function COUNTING_MODE() public pure virtual override returns (string memory) {
        return "support=bravo,fractional&quorum=for,abstain&params=fractional";
    }

    /**
     * @dev See {IGovernor-hasVoted}.
     */
    function hasVoted(uint256 _proposalId, uint256 _tokenId) public view virtual override returns (bool) {
        return usedVotes({_proposalId: _proposalId, _tokenId: _tokenId}) > 0;
    }

    /**
     * @dev Get the number of votes already cast by `tokenId` for a proposal with `proposalId`. Useful for
     * integrations that allow delegates to cast rolling, partial votes.
     */
    function usedVotes(uint256 _proposalId, uint256 _tokenId) public view virtual returns (uint256) {
        return _proposalVotes[_proposalId].usedVotes[_tokenId];
    }

    /**
     * @dev Get current distribution of votes for a given proposal.
     */
    function proposalVotes(uint256 _proposalId)
        public
        view
        virtual
        returns (uint256 _againstVotes, uint256 _forVotes, uint256 _abstainVotes)
    {
        ProposalVote storage proposalVote = _proposalVotes[_proposalId];
        return (proposalVote.againstVotes, proposalVote.forVotes, proposalVote.abstainVotes);
    }

    /**
     * @dev Select winner of majority vote.
     */
    function _selectWinner(uint256 _proposalId) internal view returns (ProposalState) {
        ProposalVote storage proposalVote = _proposalVotes[_proposalId];
        uint256 againstVotes = proposalVote.againstVotes;
        uint256 forVotes = proposalVote.forVotes;
        uint256 abstainVotes = proposalVote.abstainVotes;

        if (againstVotes > forVotes && againstVotes > abstainVotes) return ProposalState.Defeated; // Decrease
        if (forVotes > againstVotes && forVotes > abstainVotes) return ProposalState.Succeeded; // Increase
        return ProposalState.Expired; // No change
    }

    /**
     * @dev See {Governor-_countVote}. Function that records the delegate's votes.
     *
     * Executing this function consumes (part of) the delegate's weight on the proposal. This weight can be
     * distributed amongst the 3 options (Against, For, Abstain) by specifying a fractional `support`.
     *
     * This counting module supports two vote casting modes: nominal and fractional.
     *
     * - Nominal: A nominal vote is cast by setting `support` to one of the 3 bravo options (Against, For, Abstain).
     * - Fractional: A fractional vote is cast by setting `support` to `type(uint8).max` (255).
     *
     * Casting a nominal vote requires `params` to be empty and consumes the delegate's full remaining weight on the
     * proposal for the specified `support` option. This is similar to the {GovernorCountingSimple} module and follows
     * the `VoteType` enum from Governor Bravo. As a consequence, no vote weight remains unspent so no further voting
     * is possible (for this `proposalId` and this `account`).
     *
     * Casting a fractional vote consumes a fraction of the delegate's remaining weight on the proposal according to the
     * weights the delegate assigns to each support option (Against, For, Abstain respectively). The sum total of the
     * three decoded vote weights _must_ be less than or equal to the delegate's remaining weight on the proposal (i.e.
     * their checkpointed total weight minus votes already cast on the proposal). This format can be produced using:
     *
     * `abi.encodePacked(uint128(againstVotes), uint128(forVotes), uint128(abstainVotes))`
     *
     * NOTE: Consider that fractional voting restricts the number of casted vote (in each category) to 128 bits.
     * Depending on how many decimals the underlying token has, a single voter may require to split their vote into
     * multiple vote operations. For precision higher than ~30 decimals, large token holders may require an
     * potentially large number of calls to cast all their votes. The voter has the possibility to cast all the
     * remaining votes in a single operation using the traditional "bravo" vote.
     */
    // slither-disable-next-line cyclomatic-complexity
    function _countVote(
        uint256 _proposalId,
        uint256 _tokenId,
        uint8 _support,
        uint256 _totalWeight,
        bytes memory _params
    ) internal virtual override returns (uint256) {
        // Compute number of remaining votes. Returns 0 on overflow.
        (, uint256 remainingWeight) =
            _totalWeight.trySub({b: usedVotes({_proposalId: _proposalId, _tokenId: _tokenId})});
        if (remainingWeight == 0) {
            revert GovernorAlreadyCastVote({_tokenId: _tokenId});
        }

        uint256 againstVotes = 0;
        uint256 forVotes = 0;
        uint256 abstainVotes = 0;
        uint256 usedWeight = 0;

        // For clarity of event indexing, fractional voting must be clearly advertised in the "support" field.
        //
        // Supported `support` value must be:
        // - "Full" voting: `support = 0` (Against), `1` (For) or `2` (Abstain), with empty params.
        // - "Fractional" voting: `support = 255`, with 48 bytes params.
        if (_support == uint8(GovernorCountingSimple.VoteType.Against)) {
            if (_params.length != 0) revert GovernorInvalidVoteParams();
            usedWeight = againstVotes = remainingWeight;
        } else if (_support == uint8(GovernorCountingSimple.VoteType.For)) {
            if (_params.length != 0) revert GovernorInvalidVoteParams();
            usedWeight = forVotes = remainingWeight;
        } else if (_support == uint8(GovernorCountingSimple.VoteType.Abstain)) {
            if (_params.length != 0) revert GovernorInvalidVoteParams();
            usedWeight = abstainVotes = remainingWeight;
        } else if (_support == VOTE_TYPE_FRACTIONAL) {
            // The `params` argument is expected to be three packed `uint128`:
            // `abi.encodePacked(uint128(againstVotes), uint128(forVotes), uint128(abstainVotes))`
            if (_params.length != 0x30) revert GovernorInvalidVoteParams();

            assembly ("memory-safe") {
                againstVotes := shr(128, mload(add(_params, 0x20)))
                forVotes := shr(128, mload(add(_params, 0x30)))
                abstainVotes := shr(128, mload(add(_params, 0x40)))
                usedWeight := add(add(againstVotes, forVotes), abstainVotes) // inputs are uint128: cannot overflow
            }

            // check parsed arguments are valid
            if (usedWeight > remainingWeight) {
                revert GovernorExceedRemainingWeight({
                    _tokenId: _tokenId,
                    _usedVotes: usedWeight,
                    _remainingWeight: remainingWeight
                });
            }
        } else {
            revert GovernorInvalidVoteType();
        }

        // update votes tracking
        ProposalVote storage details = _proposalVotes[_proposalId];
        if (againstVotes > 0) details.againstVotes += againstVotes;
        if (forVotes > 0) details.forVotes += forVotes;
        if (abstainVotes > 0) details.abstainVotes += abstainVotes;
        details.usedVotes[_tokenId] += usedWeight;

        return usedWeight;
    }
}

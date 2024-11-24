// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Modified IVotes interface for tokenId based voting
interface IVotes {
    /**
     * @dev Emitted when an account changes their delegate.
     */
    event DelegateChanged(address indexed _delegator, uint256 indexed _fromDelegate, uint256 indexed _toDelegate);

    /**
     * @dev Emitted when a token transfer or delegate change results in changes to a delegate's number of votes.
     */
    event DelegateVotesChanged(address indexed _delegate, uint256 _previousBalance, uint256 _newBalance);

    /**
     * @dev Returns the amount of votes that `tokenId` had at a specific moment in the past.
     *      If the account passed in is not the owner, returns 0.
     */
    function getPastVotes(address _account, uint256 _tokenId, uint256 _timepoint) external view returns (uint256);

    /**
     * @dev Returns the total supply of votes available at a specific moment in the past. If the `clock()` is
     * configured to use block numbers, this will return the value the end of the corresponding block.
     *
     * NOTE: This value is the sum of all available votes, which is not necessarily the sum of all delegated votes.
     * Votes that have not been delegated are still part of total supply, even though they would not participate in a
     * vote.
     */
    function getPastTotalSupply(uint256 _timepoint) external view returns (uint256);

    /**
     * @dev Returns the delegate that `tokenId` has chosen. Can never be equal to the delegator's `tokenId`.
     *      Returns 0 if not delegated.
     */
    function delegates(uint256 _tokenId) external view returns (uint256);

    /**
     * @dev Delegates votes from the sender to `delegatee`.
     */
    function delegate(uint256 _delegator, uint256 _delegatee) external;

    /**
     * @dev Delegates votes from `delegator` to `delegatee`. Signer must own `delegator`.
     */
    function delegateBySig(
        uint256 _delegator,
        uint256 _delegatee,
        uint256 _nonce,
        uint256 _expiry,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external;
}

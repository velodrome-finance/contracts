// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IVotingEscrow} from "../IVotingEscrow.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface ISplitter {
    error NotTeam();
    error NotAllowed();
    error NotApprovedOrOwner();

    /// @notice Address of the VotingEscrow contract.
    function escrow() external view returns (IVotingEscrow);

    /// @notice Address of the factory registry contract.
    function factoryRegistry() external view returns (Ownable);

    /// @notice account -> can split
    function canSplit(address _account) external view returns (bool);

    /// @notice Toggle split for a specific address.
    /// @dev Toggle split for address(0) to enable or disable for all.
    /// @dev Reverts if not called by owner of factory registry.
    /// @param _account Address to toggle split permissions
    /// @param _bool True to allow, false to disallow
    function toggleSplit(address _account, bool _bool) external;

    /// @notice Splits veNFT into two new veNFTS - one with oldLocked.amount - `_amount`, and the second with `_amount`
    /// @dev    Requires approval to transfer to Splitter contract to work
    ///         As Splitter requires approval, only owner or approved for all can call this, unlike split
    ///         This burns the tokenId of the target veNFT
    ///         Callable by approved or owner
    ///         If this is called by approved, approved will not have permissions to manipulate the newly created veNFTs
    ///         Returns the two new split veNFTs to owner
    ///         If `from` is permanent, will automatically dedelegate.
    ///         This will burn the veNFT. Any rebases or rewards that are unclaimed
    ///         will no longer be claimable. Claim all rebases and rewards prior to calling this.
    /// @param _from VeNFT to split.
    /// @param _amount Amount to split from veNFT.
    /// @return _tokenId1 Return tokenId of veNFT with oldLocked.amount - `_amount`.
    /// @return _tokenId2 Return tokenId of veNFT with `_amount`.
    function split(uint256 _from, uint256 _amount) external returns (uint256 _tokenId1, uint256 _tokenId2);
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {ISplitter} from "../interfaces/v2/ISplitter.sol";
import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import {SafeCastLibrary} from "../libraries/SafeCastLibrary.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

/// @title Splitter
/// @author velodrome.finance
/// @notice Protected split contract for VotingEscrow
contract Splitter is ISplitter, ERC2771Context, ReentrancyGuard, ERC721Holder {
    using SafeCastLibrary for uint256;

    /// @inheritdoc ISplitter
    IVotingEscrow public immutable escrow;
    /// @inheritdoc ISplitter
    Ownable public immutable factoryRegistry;

    /// @inheritdoc ISplitter
    mapping(address => bool) public canSplit;

    /// @param _escrow The VotingEscrow contract
    constructor(address _escrow) ERC2771Context(IVotingEscrow(_escrow).forwarder()) {
        escrow = IVotingEscrow(_escrow);
        factoryRegistry = Ownable(escrow.factoryRegistry());
    }

    /// @inheritdoc ISplitter
    function toggleSplit(address _account, bool _bool) external {
        if (_msgSender() != factoryRegistry.owner()) revert NotTeam();
        canSplit[_account] = _bool;
    }

    /// @inheritdoc ISplitter
    function split(
        uint256 _from,
        uint256 _amount
    ) external nonReentrant returns (uint256 _tokenId1, uint256 _tokenId2) {
        address _owner = escrow.ownerOf(_from);
        if (!canSplit[_owner] && !canSplit[address(0)]) revert NotAllowed();
        if (!escrow.isApprovedOrOwner(_msgSender(), _from)) revert NotApprovedOrOwner();
        _amount.toInt128();
        escrow.safeTransferFrom(_owner, address(this), _from);
        (_tokenId1, _tokenId2) = escrow.split(_from, _amount);
        escrow.safeTransferFrom(address(this), _owner, _tokenId1);
        escrow.safeTransferFrom(address(this), _owner, _tokenId2);
    }
}

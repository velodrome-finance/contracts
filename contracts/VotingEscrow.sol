// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IVeArtProxy} from "./interfaces/IVeArtProxy.sol";
import {IVotingEscrow} from "./interfaces/IVotingEscrow.sol";
import {IVoter} from "./interfaces/IVoter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IReward} from "./interfaces/IReward.sol";
import {IFactoryRegistry} from "./interfaces/IFactoryRegistry.sol";
import {IManagedRewardsFactory} from "./interfaces/IManagedRewardsFactory.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @title Voting Escrow V2
/// @notice veNFT implementation that escrows ERC-20 tokens in the form of an ERC-721 NFT
/// @notice Votes have a weight depending on time, so that users are committed to the future of (whatever they are voting for)
/// @author Modified from Solidly (https://github.com/solidlyexchange/solidly/blob/master/contracts/ve.sol)
/// @author Modified from Curve (https://github.com/curvefi/curve-dao-contracts/blob/master/contracts/VotingEscrow.vy)
/// @author Modified from Nouns DAO (https://github.com/withtally/my-nft-dao-project/blob/main/contracts/ERC721Checkpointable.sol)
/// @dev Vote weight decays linearly over time. Lock time cannot be more than `MAXTIME` (4 years).
contract VotingEscrow is IVotingEscrow, Context, ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    address public immutable factoryRegistry;
    address public immutable token;
    address public voter;
    address public team;
    address public artProxy;
    /// @dev address which can create managed NFTs
    address public allowedManager;

    mapping(uint256 => Point) internal _pointHistory; // epoch -> unsigned point

    /// @dev Mapping of interface id to bool about whether or not it's supported
    mapping(bytes4 => bool) internal supportedInterfaces;

    /// @dev ERC165 interface ID of ERC165
    bytes4 internal constant ERC165_INTERFACE_ID = 0x01ffc9a7;

    /// @dev ERC165 interface ID of ERC721
    bytes4 internal constant ERC721_INTERFACE_ID = 0x80ac58cd;

    /// @dev ERC165 interface ID of ERC721Metadata
    bytes4 internal constant ERC721_METADATA_INTERFACE_ID = 0x5b5e139f;

    /// @dev Current count of token
    uint256 public tokenId;

    /// @param _token `VELO` token address
    /// @param _artProxy Art Proxy address
    /// @param _factoryRegistry Factory Registry address
    /// @param _team Team multisig
    constructor(
        address _token,
        address _artProxy,
        address _factoryRegistry,
        address _team
    ) {
        voter = msg.sender;
        team = _team;
        token = _token;
        artProxy = _artProxy;
        factoryRegistry = _factoryRegistry;

        _pointHistory[0].blk = block.number;
        _pointHistory[0].ts = block.timestamp;

        supportedInterfaces[ERC165_INTERFACE_ID] = true;
        supportedInterfaces[ERC721_INTERFACE_ID] = true;
        supportedInterfaces[ERC721_METADATA_INTERFACE_ID] = true;

        // mint-ish
        emit Transfer(address(0), address(this), tokenId);
        // burn-ish
        emit Transfer(address(this), address(0), tokenId);
    }

    /*///////////////////////////////////////////////////////////////
                            MANAGED NFT STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVotingEscrow
    mapping(uint256 => EscrowType) public escrowType;

    /// @inheritdoc IVotingEscrow
    mapping(uint256 => uint256) public idToManaged;
    /// @inheritdoc IVotingEscrow
    mapping(uint256 => mapping(uint256 => uint256)) public weights;
    /// @inheritdoc IVotingEscrow
    mapping(uint256 => bool) public deactivated;

    /// @inheritdoc IVotingEscrow
    mapping(uint256 => address) public managedToLocked;
    /// @inheritdoc IVotingEscrow
    mapping(uint256 => address) public managedToFree;

    /*///////////////////////////////////////////////////////////////
                            MANAGED NFT LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVotingEscrow
    function createManagedLockFor(address _to) external nonReentrant returns (uint256 _mTokenId) {
        address sender = _msgSender();
        require(sender == allowedManager || sender == IVoter(voter).governor(), "VotingEscrow: not allowed");

        uint256 _unlockTime = ((block.timestamp + MAXTIME) / WEEK) * WEEK;

        ++tokenId;
        _mTokenId = tokenId;
        _mint(_to, _mTokenId);
        _depositFor(_mTokenId, 0, _unlockTime, _locked[_mTokenId], DepositType.CREATE_LOCK_TYPE);

        escrowType[_mTokenId] = EscrowType.MANAGED;

        (address _lockedManagedReward, address _freeManagedReward) = IManagedRewardsFactory(
            IFactoryRegistry(factoryRegistry).managedRewardsFactory()
        ).createRewards(voter);
        IERC20(token).approve(_lockedManagedReward, type(uint256).max);
        managedToLocked[_mTokenId] = _lockedManagedReward;
        managedToFree[_mTokenId] = _freeManagedReward;

        emit CreateManaged(_to, _mTokenId, sender, _lockedManagedReward, _freeManagedReward);
    }

    /// @inheritdoc IVotingEscrow
    function depositManaged(uint256 _tokenId, uint256 _mTokenId) external nonReentrant {
        require(escrowType[_mTokenId] == EscrowType.MANAGED, "VotingEscrow: can only deposit into managed nft");
        require(!deactivated[_mTokenId], "VotingEscrow: inactive managed nft");
        require(escrowType[_tokenId] == EscrowType.NORMAL, "VotingEscrow: can only deposit normal nft");
        require(!voted[_tokenId], "VotingEscrow: nft voted");
        require(ownershipChange[_tokenId] != block.number, "VotingEscrow: flash nft protection");
        require(_balanceOfNFT(_tokenId, block.timestamp) > 0, "VotingEscrow: no balance to deposit");

        // adjust user nft
        int128 _amount = _locked[_tokenId].amount;
        _checkpoint(_tokenId, _locked[_tokenId], LockedBalance(0, 0));
        _locked[_tokenId] = LockedBalance(0, 0);

        // adjust managed nft
        uint256 _weight = uint256(uint128(_amount));
        uint256 _unlockTime = ((block.timestamp + MAXTIME) / WEEK) * WEEK;
        LockedBalance memory newLocked = _locked[_mTokenId];
        newLocked.amount += _amount;
        newLocked.end = _unlockTime;
        _checkpoint(_mTokenId, _locked[_mTokenId], newLocked);
        _locked[_mTokenId] = newLocked;

        weights[_tokenId][_mTokenId] = _weight;
        idToManaged[_tokenId] = _mTokenId;
        escrowType[_tokenId] = EscrowType.LOCKED;

        address _lockedManagedReward = managedToLocked[_mTokenId];
        IReward(_lockedManagedReward)._deposit(uint256(uint128(_amount)), _tokenId);
        address _freeManagedReward = managedToFree[_mTokenId];
        IReward(_freeManagedReward)._deposit(uint256(uint128(_amount)), _tokenId);

        emit DepositManaged(idToOwner[_tokenId], _tokenId, _mTokenId, _weight, block.timestamp);
    }

    /// @inheritdoc IVotingEscrow
    function withdrawManaged(uint256 _tokenId) external nonReentrant {
        uint256 _mTokenId = idToManaged[_tokenId];
        address sender = _msgSender();
        require(escrowType[_tokenId] == EscrowType.LOCKED, "VotingEscrow: nft not locked");
        require(_isApprovedOrOwner(sender, _tokenId), "VotingEscrow: not owner or approved");

        // update accrued rewards
        address _lockedManagedReward = managedToLocked[_mTokenId];
        address _freeManagedReward = managedToFree[_mTokenId];
        uint256 _weight = weights[_tokenId][_mTokenId];
        uint256 _reward = IReward(_lockedManagedReward).earned(address(token), _tokenId);
        uint256 _total = _weight + _reward;
        uint256 _unlockTime = ((block.timestamp + MAXTIME) / WEEK) * WEEK;

        // claim locked rewards (rebases + compounded reward)
        address[] memory rewards = new address[](1);
        rewards[0] = address(token);
        IReward(_lockedManagedReward).getReward(_tokenId, rewards);

        // adjust user nft
        LockedBalance memory newLockedNormal = LockedBalance(int128(int256(_total)), _unlockTime);
        _checkpoint(_tokenId, _locked[_tokenId], newLockedNormal);
        _locked[_tokenId] = newLockedNormal;

        // adjust managed nft
        LockedBalance memory newLockedManaged = _locked[_mTokenId];
        newLockedManaged.amount -= int128(int256(_total));
        newLockedManaged.end = _unlockTime;
        _checkpoint(_mTokenId, _locked[_mTokenId], newLockedManaged);
        _locked[_mTokenId] = newLockedManaged;

        IReward(_lockedManagedReward)._withdraw(uint256(uint128(_weight)), _tokenId);
        IReward(_freeManagedReward)._withdraw(uint256(uint128(_weight)), _tokenId);

        delete idToManaged[_tokenId];
        delete weights[_tokenId][_mTokenId];
        delete escrowType[_tokenId];

        // TODO: make this withdraw with updated weight (incl rebase)
        emit WithdrawManaged(sender, _tokenId, _mTokenId, _weight, block.timestamp);
    }

    /// @inheritdoc IVotingEscrow
    function setAllowedManager(address _allowedManager) external {
        require(msg.sender == IVoter(voter).governor(), "VotingEscrow: not governor");
        require(_allowedManager != allowedManager, "VotingEscrow: same address");
        require(_allowedManager != address(0), "VotingEscrow: zero address");
        allowedManager = _allowedManager;
        emit SetAllowedManager(_allowedManager);
    }

    /// @inheritdoc IVotingEscrow
    function setManagedState(uint256 _mTokenId, bool _state) external {
        require(msg.sender == IVoter(voter).emergencyCouncil(), "VotingEscrow: not emergency council");
        require(escrowType[_mTokenId] == EscrowType.MANAGED, "VotingEscrow: can only modify managed nft state");
        require(deactivated[_mTokenId] != _state, "VotingEscrow: same state");
        deactivated[_mTokenId] = _state;
    }

    /*///////////////////////////////////////////////////////////////
                             METADATA STORAGE
    //////////////////////////////////////////////////////////////*/

    string public constant name = "veNFT";
    string public constant symbol = "veNFT";
    string public constant version = "2.0.0";
    uint8 public constant decimals = 18;

    function setTeam(address _team) external {
        require(msg.sender == team);
        team = _team;
    }

    function setArtProxy(address _proxy) external {
        require(msg.sender == team);
        artProxy = _proxy;
    }

    /// @inheritdoc IVotingEscrow
    function tokenURI(uint256 _tokenId) external view returns (string memory) {
        require(idToOwner[_tokenId] != address(0), "VotingEscrow: query for nonexistent token");
        LockedBalance memory oldLocked = _locked[_tokenId];
        return
            IVeArtProxy(artProxy)._tokenURI(
                _tokenId,
                _balanceOfNFT(_tokenId, block.timestamp),
                oldLocked.end,
                uint256(int256(oldLocked.amount))
            );
    }

    /*//////////////////////////////////////////////////////////////
                      ERC721 BALANCE/OWNER STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Mapping from NFT ID to the address that owns it.
    mapping(uint256 => address) internal idToOwner;

    /// @dev Mapping from owner address to count of his tokens.
    mapping(address => uint256) internal ownerToNFTokenCount;

    /// @inheritdoc IVotingEscrow
    function ownerOf(uint256 _tokenId) public view returns (address) {
        return idToOwner[_tokenId];
    }

    /// @dev Returns the number of NFTs owned by `_owner`.
    ///      Throws if `_owner` is the zero address. NFTs assigned to the zero address are considered invalid.
    /// @param _owner Address for whom to query the balance.
    function _balance(address _owner) internal view returns (uint256) {
        return ownerToNFTokenCount[_owner];
    }

    /// @inheritdoc IVotingEscrow
    function balanceOf(address _owner) external view returns (uint256) {
        return _balance(_owner);
    }

    /*//////////////////////////////////////////////////////////////
                         ERC721 APPROVAL STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Mapping from NFT ID to approved address.
    mapping(uint256 => address) internal idToApprovals;

    /// @dev Mapping from owner address to mapping of operator addresses.
    mapping(address => mapping(address => bool)) internal ownerToOperators;

    mapping(uint256 => uint256) internal ownershipChange;

    /// @inheritdoc IVotingEscrow
    function getApproved(uint256 _tokenId) external view returns (address) {
        return idToApprovals[_tokenId];
    }

    /// @inheritdoc IVotingEscrow
    function isApprovedForAll(address _owner, address _operator) external view returns (bool) {
        return (ownerToOperators[_owner])[_operator];
    }

    /// @inheritdoc IVotingEscrow
    function isApprovedOrOwner(address _spender, uint256 _tokenId) external view returns (bool) {
        return _isApprovedOrOwner(_spender, _tokenId);
    }

    function _isApprovedOrOwner(address _spender, uint256 _tokenId) internal view returns (bool) {
        address owner = idToOwner[_tokenId];
        bool spenderIsOwner = owner == _spender;
        bool spenderIsApproved = _spender == idToApprovals[_tokenId];
        bool spenderIsApprovedForAll = (ownerToOperators[owner])[_spender];
        return spenderIsOwner || spenderIsApproved || spenderIsApprovedForAll;
    }

    /*//////////////////////////////////////////////////////////////
                              ERC721 LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVotingEscrow
    function approve(address _approved, uint256 _tokenId) public {
        address sender = _msgSender();
        address owner = idToOwner[_tokenId];
        // Throws if `_tokenId` is not a valid NFT
        require(owner != address(0));
        // Throws if `_approved` is the current owner
        require(_approved != owner);
        // Check requirements
        bool senderIsOwner = (idToOwner[_tokenId] == sender);
        bool senderIsApprovedForAll = (ownerToOperators[owner])[sender];
        require(senderIsOwner || senderIsApprovedForAll);
        // Set the approval
        idToApprovals[_tokenId] = _approved;
        emit Approval(owner, _approved, _tokenId);
    }

    /// @inheritdoc IVotingEscrow
    function setApprovalForAll(address _operator, bool _approved) external {
        address sender = _msgSender();
        // Throws if `_operator` is the `msg.sender`
        assert(_operator != sender);
        ownerToOperators[sender][_operator] = _approved;
        emit ApprovalForAll(sender, _operator, _approved);
    }

    /* TRANSFER FUNCTIONS */

    function _clearApproval(address _owner, uint256 _tokenId) internal {
        // Throws if `_owner` is not the current owner
        assert(idToOwner[_tokenId] == _owner);
        if (idToApprovals[_tokenId] != address(0)) {
            // Reset approvals
            idToApprovals[_tokenId] = address(0);
        }
    }

    function _transferFrom(
        address _from,
        address _to,
        uint256 _tokenId,
        address _sender
    ) internal {
        require(escrowType[_tokenId] != EscrowType.LOCKED, "VotingEscrow: nft locked");
        // Check requirements
        require(_isApprovedOrOwner(_sender, _tokenId));
        // Clear approval. Throws if `_from` is not the current owner
        _clearApproval(_from, _tokenId);
        // Remove NFT. Throws if `_tokenId` is not a valid NFT
        _removeTokenFrom(_from, _tokenId);
        // auto re-delegate
        _moveTokenDelegates(delegates(_from), delegates(_to), _tokenId);
        // Add NFT
        _addTokenTo(_to, _tokenId);
        // Set the block of ownership transfer (for Flash NFT protection)
        ownershipChange[_tokenId] = block.number;
        // Log the transfer
        emit Transfer(_from, _to, _tokenId);
    }

    /// @inheritdoc IVotingEscrow
    function transferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) external {
        _transferFrom(_from, _to, _tokenId, _msgSender());
    }

    /// @inheritdoc IVotingEscrow
    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) external {
        safeTransferFrom(_from, _to, _tokenId, "");
    }

    function _isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    /// @inheritdoc IVotingEscrow
    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId,
        bytes memory _data
    ) public {
        address sender = _msgSender();
        _transferFrom(_from, _to, _tokenId, sender);

        if (_isContract(_to)) {
            // Throws if transfer destination is a contract which does not implement 'onERC721Received'
            try IERC721Receiver(_to).onERC721Received(sender, _from, _tokenId, _data) returns (bytes4 response) {
                if (response != IERC721Receiver(_to).onERC721Received.selector) {
                    revert("ERC721: ERC721Receiver rejected tokens");
                }
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert("ERC721: transfer to non ERC721Receiver implementer");
                } else {
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                              ERC165 LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVotingEscrow
    function supportsInterface(bytes4 _interfaceID) external view returns (bool) {
        return supportedInterfaces[_interfaceID];
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @dev Mapping from owner address to mapping of index to tokenIds
    mapping(address => mapping(uint256 => uint256)) internal ownerToNFTokenIdList;

    /// @dev Mapping from NFT ID to index of owner
    mapping(uint256 => uint256) internal tokenToOwnerIndex;

    /// @inheritdoc IVotingEscrow
    function tokenOfOwnerByIndex(address _owner, uint256 _tokenIndex) external view returns (uint256) {
        return ownerToNFTokenIdList[_owner][_tokenIndex];
    }

    /// @dev Add a NFT to an index mapping to a given address
    /// @param _to address of the receiver
    /// @param _tokenId uint ID Of the token to be added
    function _addTokenToOwnerList(address _to, uint256 _tokenId) internal {
        uint256 currentCount = _balance(_to);

        ownerToNFTokenIdList[_to][currentCount] = _tokenId;
        tokenToOwnerIndex[_tokenId] = currentCount;
    }

    /// @dev Add a NFT to a given address
    ///      Throws if `_tokenId` is owned by someone.
    function _addTokenTo(address _to, uint256 _tokenId) internal {
        // Throws if `_tokenId` is owned by someone
        assert(idToOwner[_tokenId] == address(0));
        // Change the owner
        idToOwner[_tokenId] = _to;
        // Update owner token index tracking
        _addTokenToOwnerList(_to, _tokenId);
        // Change count tracking
        ownerToNFTokenCount[_to] += 1;
    }

    /// @dev Function to mint tokens
    ///      Throws if `_to` is zero address.
    ///      Throws if `_tokenId` is owned by someone.
    /// @param _to The address that will receive the minted tokens.
    /// @param _tokenId The token id to mint.
    /// @return A boolean that indicates if the operation was successful.
    function _mint(address _to, uint256 _tokenId) internal returns (bool) {
        // Throws if `_to` is zero address
        assert(_to != address(0));
        // checkpoint for gov
        _moveTokenDelegates(address(0), delegates(_to), _tokenId);
        // Add NFT. Throws if `_tokenId` is owned by someone
        _addTokenTo(_to, _tokenId);
        emit Transfer(address(0), _to, _tokenId);
        return true;
    }

    /// @dev Remove a NFT from an index mapping to a given address
    /// @param _from address of the sender
    /// @param _tokenId uint ID Of the token to be removed
    function _removeTokenFromOwnerList(address _from, uint256 _tokenId) internal {
        // Delete
        uint256 currentCount = _balance(_from) - 1;
        uint256 currentIndex = tokenToOwnerIndex[_tokenId];

        if (currentCount == currentIndex) {
            // update ownerToNFTokenIdList
            ownerToNFTokenIdList[_from][currentCount] = 0;
            // update tokenToOwnerIndex
            tokenToOwnerIndex[_tokenId] = 0;
        } else {
            uint256 lastTokenId = ownerToNFTokenIdList[_from][currentCount];

            // Add
            // update ownerToNFTokenIdList
            ownerToNFTokenIdList[_from][currentIndex] = lastTokenId;
            // update tokenToOwnerIndex
            tokenToOwnerIndex[lastTokenId] = currentIndex;

            // Delete
            // update ownerToNFTokenIdList
            ownerToNFTokenIdList[_from][currentCount] = 0;
            // update tokenToOwnerIndex
            tokenToOwnerIndex[_tokenId] = 0;
        }
    }

    /// @dev Remove a NFT from a given address
    ///      Throws if `_from` is not the current owner.
    function _removeTokenFrom(address _from, uint256 _tokenId) internal {
        // Throws if `_from` is not the current owner
        assert(idToOwner[_tokenId] == _from);
        // Change the owner
        idToOwner[_tokenId] = address(0);
        // Update owner token index tracking
        _removeTokenFromOwnerList(_from, _tokenId);
        // Change count tracking
        ownerToNFTokenCount[_from] -= 1;
    }

    function _burn(uint256 _tokenId) internal {
        require(_isApprovedOrOwner(msg.sender, _tokenId), "VotingEscrow: caller is not owner nor approved");

        address owner = ownerOf(_tokenId);

        // Clear approval
        approve(address(0), _tokenId);
        // checkpoint for gov
        _moveTokenDelegates(delegates(owner), address(0), _tokenId);
        // Remove token
        _removeTokenFrom(msg.sender, _tokenId);
        emit Transfer(owner, address(0), _tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                             ESCROW STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant WEEK = 1 weeks;
    uint256 internal constant MAXTIME = 4 * 365 * 86400;
    int128 internal constant iMAXTIME = 4 * 365 * 86400;
    uint256 internal constant MULTIPLIER = 1 ether;

    uint256 public epoch;
    uint256 public supply;

    mapping(uint256 => LockedBalance) internal _locked;
    mapping(uint256 => Point[1000000000]) internal _userPointHistory;
    mapping(uint256 => uint256) public userPointEpoch;
    /// @inheritdoc IVotingEscrow
    mapping(uint256 => int128) public slopeChanges;

    /// @inheritdoc IVotingEscrow
    function pointHistory(uint256 _loc) external view returns (Point memory) {
        return _pointHistory[_loc];
    }

    /// @inheritdoc IVotingEscrow
    function locked(uint256 _tokenId) external view returns (LockedBalance memory) {
        return _locked[_tokenId];
    }

    /// @inheritdoc IVotingEscrow
    function lockedEnd(uint256 _tokenId) external view returns (uint256) {
        return _locked[_tokenId].end;
    }

    /// @inheritdoc IVotingEscrow
    function lockedAmount(uint256 _tokenId) external view returns (uint256) {
        return uint256(uint128(_locked[_tokenId].amount));
    }

    /// @inheritdoc IVotingEscrow
    function userPointHistory(uint256 _tokenId, uint256 _loc) external view returns (Point memory) {
        return _userPointHistory[_tokenId][_loc];
    }

    /// @inheritdoc IVotingEscrow
    function getLastUserSlope(uint256 _tokenId) external view returns (int128) {
        uint256 uepoch = userPointEpoch[_tokenId];
        return _userPointHistory[_tokenId][uepoch].slope;
    }

    /// @inheritdoc IVotingEscrow
    function userPointHistoryTs(uint256 _tokenId, uint256 _idx) external view returns (uint256) {
        return _userPointHistory[_tokenId][_idx].ts;
    }

    /*//////////////////////////////////////////////////////////////
                              ESCROW LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Record global and per-user data to checkpoint
    /// @param _tokenId NFT token ID. No user checkpoint if 0
    /// @param _oldLocked Pevious locked amount / end lock time for the user
    /// @param _newLocked New locked amount / end lock time for the user
    function _checkpoint(
        uint256 _tokenId,
        LockedBalance memory _oldLocked,
        LockedBalance memory _newLocked
    ) internal {
        Point memory uOld;
        Point memory uNew;
        int128 oldDslope = 0;
        int128 newDslope = 0;
        uint256 _epoch = epoch;

        if (_tokenId != 0) {
            // Calculate slopes and biases
            // Kept at zero when they have to
            if (_oldLocked.end > block.timestamp && _oldLocked.amount > 0) {
                uOld.slope = _oldLocked.amount / iMAXTIME;
                uOld.bias = uOld.slope * int128(int256(_oldLocked.end - block.timestamp));
            }
            if (_newLocked.end > block.timestamp && _newLocked.amount > 0) {
                uNew.slope = _newLocked.amount / iMAXTIME;
                uNew.bias = uNew.slope * int128(int256(_newLocked.end - block.timestamp));
            }

            // Read values of scheduled changes in the slope
            // _oldLocked.end can be in the past and in the future
            // _newLocked.end can ONLY by in the FUTURE unless everything expired: than zeros
            oldDslope = slopeChanges[_oldLocked.end];
            if (_newLocked.end != 0) {
                if (_newLocked.end == _oldLocked.end) {
                    newDslope = oldDslope;
                } else {
                    newDslope = slopeChanges[_newLocked.end];
                }
            }
        }

        Point memory lastPoint = Point({bias: 0, slope: 0, ts: block.timestamp, blk: block.number});
        if (_epoch > 0) {
            lastPoint = _pointHistory[_epoch];
        }
        uint256 lastCheckpoint = lastPoint.ts;
        // initialLastPoint is used for extrapolation to calculate block number
        // (approximately, for *At methods) and save them
        // as we cannot figure that out exactly from inside the contract
        Point memory initialLastPoint = lastPoint;
        uint256 blockSlope = 0; // dblock/dt
        if (block.timestamp > lastPoint.ts) {
            blockSlope = (MULTIPLIER * (block.number - lastPoint.blk)) / (block.timestamp - lastPoint.ts);
        }
        // If last point is already recorded in this block, slope=0
        // But that's ok b/c we know the block in such case

        // Go over weeks to fill history and calculate what the current point is
        {
            uint256 t_i = (lastCheckpoint / WEEK) * WEEK;
            for (uint256 i = 0; i < 255; ++i) {
                // Hopefully it won't happen that this won't get used in 5 years!
                // If it does, users will be able to withdraw but vote weight will be broken
                t_i += WEEK;
                int128 d_slope = 0;
                if (t_i > block.timestamp) {
                    t_i = block.timestamp;
                } else {
                    d_slope = slopeChanges[t_i];
                }
                lastPoint.bias -= lastPoint.slope * int128(int256(t_i - lastCheckpoint));
                lastPoint.slope += d_slope;
                if (lastPoint.bias < 0) {
                    // This can happen
                    lastPoint.bias = 0;
                }
                if (lastPoint.slope < 0) {
                    // This cannot happen - just in case
                    lastPoint.slope = 0;
                }
                lastCheckpoint = t_i;
                lastPoint.ts = t_i;
                lastPoint.blk = initialLastPoint.blk + (blockSlope * (t_i - initialLastPoint.ts)) / MULTIPLIER;
                _epoch += 1;
                if (t_i == block.timestamp) {
                    lastPoint.blk = block.number;
                    break;
                } else {
                    _pointHistory[_epoch] = lastPoint;
                }
            }
        }

        epoch = _epoch;
        // Now _pointHistory is filled until t=now

        if (_tokenId != 0) {
            // If last point was in this block, the slope change has been applied already
            // But in such case we have 0 slope(s)
            lastPoint.slope += (uNew.slope - uOld.slope);
            lastPoint.bias += (uNew.bias - uOld.bias);
            if (lastPoint.slope < 0) {
                lastPoint.slope = 0;
            }
            if (lastPoint.bias < 0) {
                lastPoint.bias = 0;
            }
        }

        // Record the changed point into history
        _pointHistory[_epoch] = lastPoint;

        if (_tokenId != 0) {
            // Schedule the slope changes (slope is going down)
            // We subtract new_user_slope from [_newLocked.end]
            // and add old_user_slope to [_oldLocked.end]
            if (_oldLocked.end > block.timestamp) {
                // oldDslope was <something> - uOld.slope, so we cancel that
                oldDslope += uOld.slope;
                if (_newLocked.end == _oldLocked.end) {
                    oldDslope -= uNew.slope; // It was a new deposit, not extension
                }
                slopeChanges[_oldLocked.end] = oldDslope;
            }

            if (_newLocked.end > block.timestamp) {
                if (_newLocked.end > _oldLocked.end) {
                    newDslope -= uNew.slope; // old slope disappeared at this point
                    slopeChanges[_newLocked.end] = newDslope;
                }
                // else: we recorded it already in oldDslope
            }
            // Now handle user history
            uint256 userEpoch = userPointEpoch[_tokenId] + 1;

            userPointEpoch[_tokenId] = userEpoch;
            uNew.ts = block.timestamp;
            uNew.blk = block.number;
            _userPointHistory[_tokenId][userEpoch] = uNew;
        }
    }

    /// @notice Deposit and lock tokens for a user
    /// @param _tokenId NFT that holds lock
    /// @param _value Amount to deposit
    /// @param _unlockTime New time when to unlock the tokens, or 0 if unchanged
    /// @param _oldLocked Previous locked amount / timestamp
    /// @param _depositType The type of deposit
    function _depositFor(
        uint256 _tokenId,
        uint256 _value,
        uint256 _unlockTime,
        LockedBalance memory _oldLocked,
        DepositType _depositType
    ) internal {
        uint256 supplyBefore = supply;
        supply = supplyBefore + _value;

        // Set newLocked to _oldLocked without mangling memory
        LockedBalance memory newLocked;
        (newLocked.amount, newLocked.end) = (_oldLocked.amount, _oldLocked.end);

        // Adding to existing lock, or if a lock is expired - creating a new one
        newLocked.amount += int128(int256(_value));
        if (_unlockTime != 0) {
            newLocked.end = _unlockTime;
        }
        _locked[_tokenId] = newLocked;

        // Possibilities:
        // Both _oldLocked.end could be current or expired (>/< block.timestamp)
        // value == 0 (extend lock) or value > 0 (add to lock or extend lock)
        // newLocked.end > block.timestamp (always)
        _checkpoint(_tokenId, _oldLocked, newLocked);

        address from = _msgSender();
        if (_value != 0) {
            assert(IERC20(token).transferFrom(from, address(this), _value));
        }

        emit Deposit(from, _tokenId, _value, newLocked.end, _depositType, block.timestamp);
        emit Supply(supplyBefore, supplyBefore + _value);
    }

    /// @inheritdoc IVotingEscrow
    function checkpoint() external {
        _checkpoint(0, LockedBalance(0, 0), LockedBalance(0, 0));
    }

    /// @inheritdoc IVotingEscrow
    function depositFor(uint256 _tokenId, uint256 _value) external nonReentrant {
        LockedBalance memory oldLocked = _locked[_tokenId];

        require(_value > 0, "VotingEscrow: zero amount");
        require(oldLocked.amount > 0, "VotingEscrow: no existing lock found");
        require(oldLocked.end > block.timestamp, "VotingEscrow: cannot add to expired lock, withdraw");
        _depositFor(_tokenId, _value, 0, oldLocked, DepositType.DEPOSIT_FOR_TYPE);
    }

    /// @dev Deposit `_value` tokens for `_to` and lock for `_lockDuration`
    /// @param _value Amount to deposit
    /// @param _lockDuration Number of seconds to lock tokens for (rounded down to nearest week)
    /// @param _to Address to deposit
    function _createLock(
        uint256 _value,
        uint256 _lockDuration,
        address _to
    ) internal returns (uint256) {
        uint256 unlockTime = ((block.timestamp + _lockDuration) / WEEK) * WEEK; // Locktime is rounded down to weeks

        require(_value > 0, "VotingEscrow: zero amount");
        require(unlockTime > block.timestamp, "VotingEscrow: lock duration not in future");
        require(unlockTime <= block.timestamp + MAXTIME, "VotingEscrow: lock duration greater than 4 years");

        ++tokenId;
        uint256 _tokenId = tokenId;
        _mint(_to, _tokenId);

        _depositFor(_tokenId, _value, unlockTime, _locked[_tokenId], DepositType.CREATE_LOCK_TYPE);
        return _tokenId;
    }

    /// @inheritdoc IVotingEscrow
    function createLock(uint256 _value, uint256 _lockDuration) external nonReentrant returns (uint256) {
        return _createLock(_value, _lockDuration, _msgSender());
    }

    /// @inheritdoc IVotingEscrow
    function createLockFor(
        uint256 _value,
        uint256 _lockDuration,
        address _to
    ) external nonReentrant returns (uint256) {
        return _createLock(_value, _lockDuration, _to);
    }

    /// @inheritdoc IVotingEscrow
    function increaseAmount(uint256 _tokenId, uint256 _value) external nonReentrant {
        assert(_isApprovedOrOwner(_msgSender(), _tokenId));
        EscrowType _escrowType = escrowType[_tokenId];
        require(_escrowType != EscrowType.LOCKED, "VotingEscrow: nft locked");

        LockedBalance memory oldLocked = _locked[_tokenId];

        assert(_value > 0); // dev: need non-zero value
        require(oldLocked.amount > 0, "VotingEscrow: no existing lock found");
        require(oldLocked.end > block.timestamp, "VotingEscrow: cannot add to expired lock. Withdraw");

        _depositFor(_tokenId, _value, 0, oldLocked, DepositType.INCREASE_LOCK_AMOUNT);

        if (_escrowType == EscrowType.MANAGED) {
            // increaseAmount called on managed tokens are treated as locked rewards
            address _lockedManagedReward = managedToLocked[_tokenId];
            IReward(_lockedManagedReward).notifyRewardAmount(address(token), _value);
        }
    }

    /// @inheritdoc IVotingEscrow
    function increaseUnlockTime(uint256 _tokenId, uint256 _lockDuration) external nonReentrant {
        assert(_isApprovedOrOwner(_msgSender(), _tokenId));
        require(escrowType[_tokenId] != EscrowType.LOCKED, "VotingEscrow: nft locked");

        LockedBalance memory oldLocked = _locked[_tokenId];
        uint256 unlockTime = ((block.timestamp + _lockDuration) / WEEK) * WEEK; // Locktime is rounded down to weeks

        require(oldLocked.end > block.timestamp, "VotingEscrow: lock expired");
        require(oldLocked.amount > 0, "VotingEscrow: nothing is locked");
        require(unlockTime > oldLocked.end, "VotingEscrow: can only increase lock duration");
        require(unlockTime <= block.timestamp + MAXTIME, "VotingEscrow: voting lock can be 4 years max");

        _depositFor(_tokenId, 0, unlockTime, oldLocked, DepositType.INCREASE_UNLOCK_TIME);
    }

    /// @inheritdoc IVotingEscrow
    function withdraw(uint256 _tokenId) external nonReentrant {
        address sender = _msgSender();
        assert(_isApprovedOrOwner(sender, _tokenId));
        require(!voted[_tokenId], "VotingEscrow: voted");
        require(escrowType[_tokenId] == EscrowType.NORMAL, "VotingEscrow: can only withdraw from normal nft");

        LockedBalance memory oldLocked = _locked[_tokenId];
        require(block.timestamp >= oldLocked.end, "VotingEscrow: lock not expired");
        uint256 value = uint256(int256(oldLocked.amount));

        _locked[_tokenId] = LockedBalance(0, 0);
        uint256 supplyBefore = supply;
        supply = supplyBefore - value;

        // oldLocked can have either expired <= timestamp or zero end
        // oldLocked has only 0 end
        // Both can have >= 0 amount
        _checkpoint(_tokenId, oldLocked, LockedBalance(0, 0));

        assert(IERC20(token).transfer(sender, value));

        // Burn the NFT
        _burn(_tokenId);

        emit Withdraw(sender, _tokenId, value, block.timestamp);
        emit Supply(supplyBefore, supplyBefore - value);
    }

    /*///////////////////////////////////////////////////////////////
                           GAUGE VOTING STORAGE
    //////////////////////////////////////////////////////////////*/

    // The following ERC20/minime-compatible methods are not real balanceOf and supply!
    // They measure the weights for the purpose of voting, so they don't represent
    // real coins.

    /// @notice Binary search to estimate timestamp for block number
    /// @param _block Block to find
    /// @param _maxEpoch Don't go beyond this epoch
    /// @return Approximate timestamp for block
    function _findBlockEpoch(uint256 _block, uint256 _maxEpoch) internal view returns (uint256) {
        // Binary search
        uint256 _min = 0;
        uint256 _max = _maxEpoch;
        for (uint256 i = 0; i < 128; ++i) {
            // Will be always enough for 128-bit numbers
            if (_min >= _max) {
                break;
            }
            uint256 _mid = (_min + _max + 1) / 2;
            if (_pointHistory[_mid].blk <= _block) {
                _min = _mid;
            } else {
                _max = _mid - 1;
            }
        }
        return _min;
    }

    /// @notice Get the current voting power for `_tokenId`
    /// @dev Adheres to the ERC20 `balanceOf` interface for Aragon compatibility
    /// @param _tokenId NFT for lock
    /// @param _t Epoch time to return voting power at
    /// @return User voting power
    function _balanceOfNFT(uint256 _tokenId, uint256 _t) internal view returns (uint256) {
        uint256 _epoch = userPointEpoch[_tokenId];
        if (_epoch == 0) {
            return 0;
        } else {
            Point memory lastPoint = _userPointHistory[_tokenId][_epoch];
            lastPoint.bias -= lastPoint.slope * int128(int256(_t) - int256(lastPoint.ts));
            if (lastPoint.bias < 0) {
                lastPoint.bias = 0;
            }
            return uint256(int256(lastPoint.bias));
        }
    }

    /// @inheritdoc IVotingEscrow
    function balanceOfNFT(uint256 _tokenId) external view returns (uint256) {
        if (ownershipChange[_tokenId] == block.number) return 0;
        return _balanceOfNFT(_tokenId, block.timestamp);
    }

    /// @inheritdoc IVotingEscrow
    function balanceOfNFTAt(uint256 _tokenId, uint256 _t) external view returns (uint256) {
        return _balanceOfNFT(_tokenId, _t);
    }

    /// @notice Measure voting power of `_tokenId` at block height `_block`
    /// @dev Adheres to MiniMe `balanceOfAt` interface: https://github.com/Giveth/minime
    /// @param _tokenId User's wallet NFT
    /// @param _block Block to calculate the voting power at
    /// @return Voting power
    function _balanceOfAtNFT(uint256 _tokenId, uint256 _block) internal view returns (uint256) {
        // Copying and pasting totalSupply code because Vyper cannot pass by
        // reference yet
        assert(_block <= block.number);

        // Binary search
        uint256 _min = 0;
        uint256 _max = userPointEpoch[_tokenId];
        for (uint256 i = 0; i < 128; ++i) {
            // Will be always enough for 128-bit numbers
            if (_min >= _max) {
                break;
            }
            uint256 _mid = (_min + _max + 1) / 2;
            if (_userPointHistory[_tokenId][_mid].blk <= _block) {
                _min = _mid;
            } else {
                _max = _mid - 1;
            }
        }

        Point memory userPoint = _userPointHistory[_tokenId][_min];

        uint256 maxEpoch = epoch;
        uint256 _epoch = _findBlockEpoch(_block, maxEpoch);
        Point memory point0 = _pointHistory[_epoch];
        uint256 dBlock = 0;
        uint256 dT = 0;
        if (_epoch < maxEpoch) {
            Point memory point1 = _pointHistory[_epoch + 1];
            dBlock = point1.blk - point0.blk;
            dT = point1.ts - point0.ts;
        } else {
            dBlock = block.number - point0.blk;
            dT = block.timestamp - point0.ts;
        }
        uint256 blockTime = point0.ts;
        if (dBlock != 0) {
            blockTime += (dT * (_block - point0.blk)) / dBlock;
        }

        userPoint.bias -= userPoint.slope * int128(int256(blockTime - userPoint.ts));
        if (userPoint.bias >= 0) {
            return uint256(uint128(userPoint.bias));
        } else {
            return 0;
        }
    }

    /// @inheritdoc IVotingEscrow
    function balanceOfAtNFT(uint256 _tokenId, uint256 _block) external view returns (uint256) {
        return _balanceOfAtNFT(_tokenId, _block);
    }

    /// @inheritdoc IVotingEscrow
    function totalSupplyAt(uint256 _block) public view returns (uint256) {
        assert(_block <= block.number);
        uint256 _epoch = epoch;
        uint256 targetEpoch = _findBlockEpoch(_block, _epoch);

        Point memory point = _pointHistory[targetEpoch];
        uint256 dt = 0;
        if (targetEpoch < _epoch) {
            Point memory nextPoint = _pointHistory[targetEpoch + 1];
            if (point.blk != nextPoint.blk) {
                dt = ((_block - point.blk) * (nextPoint.ts - point.ts)) / (nextPoint.blk - point.blk);
            }
        } else {
            if (point.blk != block.number) {
                dt = ((_block - point.blk) * (block.timestamp - point.ts)) / (block.number - point.blk);
            }
        }
        // Now dt contains info on how far are we beyond point
        return _supplyAt(point, point.ts + dt);
    }

    /// @notice Calculate total voting power at some point in the past
    /// @param _point The point (bias/slope) to start search from
    /// @param _t Time to calculate the total voting power at
    /// @return Total voting power at that time
    function _supplyAt(Point memory _point, uint256 _t) internal view returns (uint256) {
        Point memory lastPoint = _point;
        uint256 t_i = (lastPoint.ts / WEEK) * WEEK;
        for (uint256 i = 0; i < 255; ++i) {
            t_i += WEEK;
            int128 dSlope = 0;
            if (t_i > _t) {
                t_i = _t;
            } else {
                dSlope = slopeChanges[t_i];
            }
            lastPoint.bias -= lastPoint.slope * int128(int256(t_i - lastPoint.ts));
            if (t_i == _t) {
                break;
            }
            lastPoint.slope += dSlope;
            lastPoint.ts = t_i;
        }

        if (lastPoint.bias < 0) {
            lastPoint.bias = 0;
        }
        return uint256(uint128(lastPoint.bias));
    }

    /// @inheritdoc IVotingEscrow
    function totalSupply() external view returns (uint256) {
        return totalSupplyAtT(block.timestamp);
    }

    /// @inheritdoc IVotingEscrow
    function totalSupplyAtT(uint256 _t) public view returns (uint256) {
        uint256 _epoch = epoch;
        Point memory lastPoint = _pointHistory[_epoch];
        return _supplyAt(lastPoint, _t);
    }

    /*///////////////////////////////////////////////////////////////
                            GAUGE VOTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVotingEscrow
    mapping(uint256 => bool) public voted;
    mapping(uint256 => bool) public canSplit;
    bool public anyoneCanSplit;

    /// @inheritdoc IVotingEscrow
    function setVoter(address _voter) external {
        require(_msgSender() == voter);
        voter = _voter;
    }

    /// @inheritdoc IVotingEscrow
    function voting(uint256 _tokenId) external {
        require(_msgSender() == voter);
        voted[_tokenId] = true;
    }

    /// @inheritdoc IVotingEscrow
    function abstain(uint256 _tokenId) external {
        require(_msgSender() == voter);
        voted[_tokenId] = false;
    }

    /// @inheritdoc IVotingEscrow
    function merge(uint256 _from, uint256 _to) external nonReentrant {
        address sender = _msgSender();
        require(!voted[_from], "VotingEscrow: voted");
        require(escrowType[_from] == EscrowType.NORMAL, "VotingEscrow: can only merge normal from nft");
        require(escrowType[_to] == EscrowType.NORMAL, "VotingEscrow: can only merge normal to nft");
        require(_from != _to, "VotingEscrow: same nft");
        require(_isApprovedOrOwner(sender, _from), "VotingEscrow: invalid permissions (from)");
        require(_isApprovedOrOwner(sender, _to), "VotingEscrow: invalid permissions (to)");
        LockedBalance memory oldLockedTo = _locked[_to];
        require(oldLockedTo.end > block.timestamp, "VotingEscrow: to nft lock expired");

        LockedBalance memory oldLockedFrom = _locked[_from];
        uint256 end = oldLockedFrom.end >= oldLockedTo.end ? oldLockedFrom.end : oldLockedTo.end;

        _locked[_from] = LockedBalance(0, 0);
        _checkpoint(_from, oldLockedFrom, LockedBalance(0, 0));
        _burn(_from);

        LockedBalance memory newLockedTo;
        newLockedTo.amount = oldLockedTo.amount + oldLockedFrom.amount;
        newLockedTo.end = end;
        _checkpoint(_to, oldLockedTo, newLockedTo);
        _locked[_to] = newLockedTo;
    }

    /// @inheritdoc IVotingEscrow
    function split(uint256 _from, uint256 _amount) external nonReentrant returns (uint256 _tokenId) {
        address sender = _msgSender();
        require(canSplit[_from] || anyoneCanSplit, "VotingEscrow: split not public yet");
        require(escrowType[_from] == EscrowType.NORMAL, "VotingEscrow: split requires normal nft");
        require(!voted[_from], "VotingEscrow: voted");
        require(_isApprovedOrOwner(sender, _from), "VotingEscrow: from: invalid permissions");
        LockedBalance memory oldLocked = _locked[_from];
        require(oldLocked.end > block.timestamp, "VotingEscrow: nft lock expired");
        int128 _splitAmount = int128(int256(_amount));
        require(_splitAmount > 0, "VotingEscrow: zero amount");
        require(oldLocked.amount > _splitAmount, "VotingEscrow: amount too big");

        // Remove balance from old veNFT
        LockedBalance memory newLocked = _locked[_from];
        newLocked.amount -= _splitAmount;
        _checkpoint(_from, oldLocked, newLocked);
        _locked[_from] = newLocked;

        // Create new veNFT
        ++tokenId;
        _tokenId = tokenId;
        _mint(sender, _tokenId);

        // Checkpoint adding balance to new veNFT
        newLocked.amount = _splitAmount;
        _checkpoint(_tokenId, oldLocked, newLocked);
        _locked[_tokenId] = newLocked;
    }

    /// @notice Toggle split for public access.
    function enableSplitForAll() external {
        require(_msgSender() == team, "VotingEscrow: not team");
        anyoneCanSplit = true;
    }

    /// @notice Allow a specific veNFT to be split.
    /// @param _tokenId .
    function allowSplit(uint256 _tokenId) external {
        require(_msgSender() == team, "VotingEscrow: not team");
        canSplit[_tokenId] = true;
    }

    /*///////////////////////////////////////////////////////////////
                            DAO VOTING STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// @notice The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant DELEGATION_TYPEHASH =
        keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    /// @notice A record of each accounts delegate
    mapping(address => address) private _delegates;
    uint256 public constant MAX_DELEGATES = 1024; // avoid too much gas

    /// @notice A record of delegated token checkpoints for each account, by index
    mapping(address => mapping(uint32 => Checkpoint)) private _checkpoints;

    /// @inheritdoc IVotingEscrow
    mapping(address => uint32) public numCheckpoints;

    /// @inheritdoc IVotingEscrow
    mapping(address => uint256) public nonces;

    /// @inheritdoc IVotingEscrow
    function delegates(address delegator) public view returns (address) {
        address current = _delegates[delegator];
        return current == address(0) ? delegator : current;
    }

    /// @inheritdoc IVotingEscrow
    function checkpoints(address account, uint32 index) external view returns (Checkpoint memory) {
        return _checkpoints[account][index];
    }

    /// @inheritdoc IVotingEscrow
    function getVotes(address account) external view returns (uint256) {
        uint32 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) {
            return 0;
        }
        uint256[] storage _tokenIds = _checkpoints[account][nCheckpoints - 1].tokenIds;
        uint256 votes = 0;
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 tId = _tokenIds[i];
            votes = votes + _balanceOfNFT(tId, block.timestamp);
        }
        return votes;
    }

    /// @inheritdoc IVotingEscrow
    function getTokenIdsAt(address account, uint256 blockNumber) public view returns (uint256[] memory _tokenIds) {
        uint32 _checkIndex = getPastVotesIndex(account, blockNumber);
        _tokenIds = _checkpoints[account][_checkIndex].tokenIds;
    }

    /// @inheritdoc IVotingEscrow
    function getPastVotesIndex(address account, uint256 blockNumber) public view returns (uint32) {
        uint32 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) {
            return 0;
        }
        // First check most recent balance
        if (_checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
            return (nCheckpoints - 1);
        }

        // Next check implicit zero balance
        if (_checkpoints[account][0].fromBlock > blockNumber) {
            return 0;
        }

        uint32 lower = 0;
        uint32 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint32 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            Checkpoint storage cp = _checkpoints[account][center];
            if (cp.fromBlock == blockNumber) {
                return center;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return lower;
    }

    /// @inheritdoc IVotingEscrow
    function getPastVotes(address account, uint256 blockNumber) public view returns (uint256) {
        uint32 _checkIndex = getPastVotesIndex(account, blockNumber);
        // Sum votes
        uint256[] storage _tokenIds = _checkpoints[account][_checkIndex].tokenIds;
        uint256 votes = 0;
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 tId = _tokenIds[i];
            votes = votes + _balanceOfAtNFT(tId, blockNumber);
        }
        return votes;
    }

    /// @inheritdoc IVotingEscrow
    function getPastTotalSupply(uint256 blockNumber) external view returns (uint256) {
        return totalSupplyAt(blockNumber);
    }

    /*///////////////////////////////////////////////////////////////
                             DAO VOTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function _moveTokenDelegates(
        address srcRep,
        address dstRep,
        uint256 _tokenId
    ) internal {
        if (srcRep != dstRep && _tokenId > 0) {
            if (srcRep != address(0)) {
                uint32 srcRepNum = numCheckpoints[srcRep];
                uint256[] storage srcRepOld = srcRepNum > 0
                    ? _checkpoints[srcRep][srcRepNum - 1].tokenIds
                    : _checkpoints[srcRep][0].tokenIds;
                uint32 nextSrcRepNum = _findWhatCheckpointToWrite(srcRep);
                uint256[] storage srcRepNew = _checkpoints[srcRep][nextSrcRepNum].tokenIds;
                // All the same except _tokenId
                for (uint256 i = 0; i < srcRepOld.length; i++) {
                    uint256 tId = srcRepOld[i];
                    if (tId != _tokenId) {
                        srcRepNew.push(tId);
                    }
                }

                numCheckpoints[srcRep] = srcRepNum + 1;
            }

            if (dstRep != address(0)) {
                uint32 dstRepNum = numCheckpoints[dstRep];
                uint256[] storage dstRepOld = dstRepNum > 0
                    ? _checkpoints[dstRep][dstRepNum - 1].tokenIds
                    : _checkpoints[dstRep][0].tokenIds;
                uint32 nextDstRepNum = _findWhatCheckpointToWrite(dstRep);
                uint256[] storage dstRepNew = _checkpoints[dstRep][nextDstRepNum].tokenIds;
                // All the same plus _tokenId
                require(dstRepOld.length + 1 <= MAX_DELEGATES, "VotingEscrow: dstRep would have too many tokenIds");
                for (uint256 i = 0; i < dstRepOld.length; i++) {
                    uint256 tId = dstRepOld[i];
                    dstRepNew.push(tId);
                }
                dstRepNew.push(_tokenId);

                numCheckpoints[dstRep] = dstRepNum + 1;
            }
        }
    }

    function _findWhatCheckpointToWrite(address account) internal view returns (uint32) {
        uint256 _blockNumber = block.number;
        uint32 _nCheckPoints = numCheckpoints[account];

        if (_nCheckPoints > 0 && _checkpoints[account][_nCheckPoints - 1].fromBlock == _blockNumber) {
            return _nCheckPoints - 1;
        } else {
            return _nCheckPoints;
        }
    }

    function _moveAllDelegates(
        address owner,
        address srcRep,
        address dstRep
    ) internal {
        // You can only redelegate what you own
        if (srcRep != dstRep) {
            if (srcRep != address(0)) {
                uint32 srcRepNum = numCheckpoints[srcRep];
                uint256[] storage srcRepOld = srcRepNum > 0
                    ? _checkpoints[srcRep][srcRepNum - 1].tokenIds
                    : _checkpoints[srcRep][0].tokenIds;
                uint32 nextSrcRepNum = _findWhatCheckpointToWrite(srcRep);
                uint256[] storage srcRepNew = _checkpoints[srcRep][nextSrcRepNum].tokenIds;
                // All the same except what owner owns
                for (uint256 i = 0; i < srcRepOld.length; i++) {
                    uint256 tId = srcRepOld[i];
                    if (idToOwner[tId] != owner) {
                        srcRepNew.push(tId);
                    }
                }

                numCheckpoints[srcRep] = srcRepNum + 1;
            }

            if (dstRep != address(0)) {
                uint32 dstRepNum = numCheckpoints[dstRep];
                uint256[] storage dstRepOld = dstRepNum > 0
                    ? _checkpoints[dstRep][dstRepNum - 1].tokenIds
                    : _checkpoints[dstRep][0].tokenIds;
                uint32 nextDstRepNum = _findWhatCheckpointToWrite(dstRep);
                uint256[] storage dstRepNew = _checkpoints[dstRep][nextDstRepNum].tokenIds;
                uint256 ownerTokenCount = ownerToNFTokenCount[owner];
                require(
                    dstRepOld.length + ownerTokenCount <= MAX_DELEGATES,
                    "VotingEscrow: dstRep would have too many tokenIds"
                );
                // All the same
                for (uint256 i = 0; i < dstRepOld.length; i++) {
                    uint256 tId = dstRepOld[i];
                    dstRepNew.push(tId);
                }
                // Plus all that's owned
                for (uint256 i = 0; i < ownerTokenCount; i++) {
                    uint256 tId = ownerToNFTokenIdList[owner][i];
                    dstRepNew.push(tId);
                }

                numCheckpoints[dstRep] = dstRepNum + 1;
            }
        }
    }

    function _delegate(address delegator, address delegatee) internal {
        /// @notice differs from `_delegate()` in `Comp.sol` to use `delegates` override method to simulate auto-delegation
        address currentDelegate = delegates(delegator);

        _delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);
        _moveAllDelegates(delegator, currentDelegate, delegatee);
    }

    /// @inheritdoc IVotingEscrow
    function delegate(address delegatee) public {
        address sender = _msgSender();
        if (delegatee == address(0)) delegatee = sender;
        return _delegate(sender, delegatee);
    }

    /// @inheritdoc IVotingEscrow
    function delegateBySig(
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        bytes32 domainSeparator = keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name)), keccak256(bytes(version)), block.chainid, address(this))
        );
        bytes32 structHash = keccak256(abi.encode(DELEGATION_TYPEHASH, delegatee, nonce, expiry));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "VotingEscrow: invalid signature");
        require(nonce == nonces[signatory]++, "VotingEscrow: invalid nonce");
        require(block.timestamp <= expiry, "VotingEscrow: signature expired");
        return _delegate(signatory, delegatee);
    }
}

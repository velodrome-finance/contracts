pragma solidity 0.8.13;

import {IERC721, IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

interface IVotingEscrow is IVotes, IERC721, IERC721Metadata {
    struct LockedBalance {
        int128 amount;
        uint256 end;
    }

    struct Point {
        int128 bias;
        int128 slope; // # -dweight / dt
        uint256 ts;
        uint256 blk; // block
    }

    /// @notice A checkpoint for marking delegated tokenIds from a given timestamp
    struct Checkpoint {
        uint256 fromTimestamp;
        uint256[] tokenIds;
    }

    enum DepositType {
        DEPOSIT_FOR_TYPE,
        CREATE_LOCK_TYPE,
        INCREASE_LOCK_AMOUNT,
        INCREASE_UNLOCK_TIME
    }

    /// @dev Different types of veNFTs:
    /// NORMAL  - typical veNFT
    /// LOCKED  - veNFT which is locked into a MANAGED veNFT
    /// MANAGED - veNFT which can accept the deposit of NORMAL veNFTs
    enum EscrowType {
        NORMAL,
        LOCKED,
        MANAGED
    }

    event Deposit(
        address indexed provider,
        uint256 tokenId,
        uint256 value,
        uint256 indexed locktime,
        DepositType depositType,
        uint256 ts
    );
    event Withdraw(address indexed provider, uint256 tokenId, uint256 value, uint256 ts);
    event Supply(uint256 prevSupply, uint256 supply);
    event CreateManaged(
        address indexed _to,
        uint256 indexed _mTokenId,
        address _from,
        address _lockedManagedReward,
        address _freeManagedReward
    );

    event DepositManaged(
        address indexed _owner,
        uint256 indexed _tokenId,
        uint256 indexed _mTokenId,
        uint256 _weight,
        uint256 _ts
    );
    event WithdrawManaged(
        address indexed _owner,
        uint256 indexed _tokenId,
        uint256 indexed _mTokenId,
        uint256 _weight,
        uint256 _ts
    );
    event SetAllowedManager(address _allowedManager);

    // State variables
    function factoryRegistry() external view returns (address);

    function token() external view returns (address);

    function voter() external view returns (address);

    function team() external view returns (address);

    function artProxy() external view returns (address);

    function allowedManager() external view returns (address);

    function tokenId() external view returns (uint256);

    /*///////////////////////////////////////////////////////////////
                            MANAGED NFT STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Mapping of token id to escrow type
    ///      Takes advantage of the fact default value is EscrowType.NORMAL
    function escrowType(uint256 tokenId) external view returns (EscrowType);

    /// @dev Mapping of token id to managed id
    function idToManaged(uint256 tokenId) external view returns (uint256 managedTokenId);

    /// @dev Mapping of user token id to managed token id to weight of token id
    function weights(uint256 tokenId, uint256 managedTokenId) external view returns (uint256 weight);

    /// @dev Mapping of managed id to deactivated state
    function deactivated(uint256 tokenId) external view returns (bool inactive);

    /// @dev Mapping from managed nft id to locked managed rewards
    ///      `token` denominated rewards (rebases/rewards) stored in locked managed rewards contract
    ///      to prevent co-mingling of assets
    function managedToLocked(uint256 tokenId) external view returns (address);

    /// @dev Mapping from managed nft id to free managed rewards contract
    ///      these rewards can be freely withdrawn by users
    function managedToFree(uint256 tokenId) external view returns (address);

    /*///////////////////////////////////////////////////////////////
                            MANAGED NFT LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Create managed NFT for use within ecosystem.
    /// @dev Throws if address already owns a managed NFT.
    /// @return _mTokenId managed token id.
    function createManagedLockFor(address _to) external returns (uint256 _mTokenId);

    /// @notice Delegates balance to managed nft
    /// @dev Managed nft will remain max-locked as long as there is at least one deposit or withdrawal per week.
    ///      Throws if NFT was transferred in same block (flash NFT protection).
    ///      Throws if deposit nft is managed.
    ///      Throws if recipient nft is not managed.
    ///      Throws if deposit nft is already locked.
    ///      Throws if deposit nft already voted.
    /// @param _tokenId tokenId of NFT being deposited
    /// @param _mTokenId tokenId of managed NFT that will receive the deposit
    function depositManaged(uint256 _tokenId, uint256 _mTokenId) external;

    /// @notice Retrieves locked rewards and withdraws balance from managed nft.
    /// @dev Throws if NFT not locked.
    ///      Throws if msg.sender not approved or owner.
    /// @param _tokenId tokenId of NFT being deposited.
    function withdrawManaged(uint256 _tokenId) external;

    /// @notice Permit one address to call createManagedLockFor() that is not Voter.governor()
    function setAllowedManager(address _allowedManager) external;

    /// @notice Set Managed NFT state. Inactive NFTs cannot be deposited into.
    /// @param _mTokenId managed nft state to set
    /// @param _state true => inactive, false => active
    function setManagedState(uint256 _mTokenId, bool _state) external;

    /*///////////////////////////////////////////////////////////////
                             METADATA STORAGE
    //////////////////////////////////////////////////////////////*/

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function version() external view returns (string memory);

    function decimals() external view returns (uint8);

    function setTeam(address _team) external;

    function setArtProxy(address _proxy) external;

    /// @inheritdoc IERC721Metadata
    function tokenURI(uint256 tokenId) external view returns (string memory);

    /*//////////////////////////////////////////////////////////////
                      ERC721 BALANCE/OWNER STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC721
    function ownerOf(uint256 tokenId) external view returns (address owner);

    /// @inheritdoc IERC721
    function balanceOf(address owner) external view returns (uint256 balance);

    /*//////////////////////////////////////////////////////////////
                         ERC721 APPROVAL STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC721
    function getApproved(uint256 _tokenId) external view returns (address operator);

    /// @inheritdoc IERC721
    function isApprovedForAll(address owner, address operator) external view returns (bool);

    /// @notice Check whether spender is owner or an approved user for a given veNFT
    /// @param _spender .
    /// @param _tokenId .
    function isApprovedOrOwner(address _spender, uint256 _tokenId) external returns (bool);

    /*//////////////////////////////////////////////////////////////
                              ERC721 LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC721
    function approve(address to, uint256 tokenId) external;

    /// @inheritdoc IERC721
    function setApprovalForAll(address operator, bool approved) external;

    /// @inheritdoc IERC721
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    /// @inheritdoc IERC721
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    /// @inheritdoc IERC721
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes calldata data
    ) external;

    /*//////////////////////////////////////////////////////////////
                              ERC165 LOGIC
    //////////////////////////////////////////////////////////////*/

    function supportsInterface(bytes4 _interfaceID) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Get token by index
    /// @param _owner Address of token owner
    /// @param _tokenIndex Index of token to query
    /// @return tokenId at the given index
    function tokenOfOwnerByIndex(address _owner, uint256 _tokenIndex) external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                             ESCROW STORAGE
    //////////////////////////////////////////////////////////////*/

    function epoch() external view returns (uint256);

    function supply() external view returns (uint256);

    function userPointEpoch(uint256 _tokenId) external view returns (uint256 _epoch);

    /// @notice time -> signed slope change
    function slopeChanges(uint256 _timestamp) external view returns (int128);

    /// @notice Global point history at a given index
    function pointHistory(uint256 _loc) external view returns (Point memory);

    /// @notice Get the LockedBalance (amount, end) of a _tokenId
    /// @param _tokenId .
    /// @return LockedBalance of _tokenId
    function locked(uint256 _tokenId) external view returns (LockedBalance memory);

    /// @notice Get timestamp when `_tokenId`'s lock finishes
    /// @param _tokenId .
    /// @return Epoch time of the lock end
    function lockedEnd(uint256 _tokenId) external view returns (uint256);

    /// @notice Get amount locked in `_tokenId`
    /// @param _tokenId User NFT
    /// @return _amount Amount of token locked
    function lockedAmount(uint256 _tokenId) external view returns (uint256);

    /// @notice User -> Point[userEpoch]
    function userPointHistory(uint256 _tokenId, uint256 _loc) external view returns (Point memory);

    /// @notice Get the most recently recorded rate of voting power decrease for `_tokenId`
    /// @param _tokenId .
    /// @return Value of the slope
    function getLastUserSlope(uint256 _tokenId) external view returns (int128);

    /// @notice Get the timestamp for checkpoint `_idx` for `_tokenId`
    /// @param _tokenId token of the NFT
    /// @param _idx User epoch number
    /// @return Epoch time of the checkpoint
    function userPointHistoryTs(uint256 _tokenId, uint256 _idx) external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                              ESCROW LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Record global data to checkpoint
    function checkpoint() external;

    /// @notice Deposit `_value` tokens for `_tokenId` and add to the lock
    /// @dev Anyone (even a smart contract) can deposit for someone else, but
    ///      cannot extend their locktime and deposit for a brand new user
    /// @param _tokenId lock NFT
    /// @param _value Amount to add to user's lock
    function depositFor(uint256 _tokenId, uint256 _value) external;

    /// @notice Deposit `_value` tokens for `msg.sender` and lock for `_lockDuration`
    /// @param _value Amount to deposit
    /// @param _lockDuration Number of seconds to lock tokens for (rounded down to nearest week)
    /// @return TokenId of created veNFT
    function createLock(uint256 _value, uint256 _lockDuration) external returns (uint256);

    /// @notice Deposit `_value` tokens for `_to` and lock for `_lockDuration`
    /// @param _value Amount to deposit
    /// @param _lockDuration Number of seconds to lock tokens for (rounded down to nearest week)
    /// @param _to Address to deposit
    /// @return TokenId of created veNFT
    function createLockFor(
        uint256 _value,
        uint256 _lockDuration,
        address _to
    ) external returns (uint256);

    /// @notice Deposit `_value` additional tokens for `_tokenId` without modifying the unlock time
    /// @param _value Amount of tokens to deposit and add to the lock
    function increaseAmount(uint256 _tokenId, uint256 _value) external;

    /// @notice Extend the unlock time for `_tokenId`
    /// @param _lockDuration New number of seconds until tokens unlock
    function increaseUnlockTime(uint256 _tokenId, uint256 _lockDuration) external;

    /// @notice Withdraw all tokens for `_tokenId`
    /// @dev Only possible if the lock has expired
    function withdraw(uint256 _tokenId) external;

    /*///////////////////////////////////////////////////////////////
                           GAUGE VOTING STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Get the voting power for _tokenId at the current block
    /// @param _tokenId .
    /// @return Voting power
    function balanceOfNFT(uint256 _tokenId) external view returns (uint256);

    /// @notice Get the voting power for _tokenId at a given timestamp
    /// @param _tokenId .
    /// @param _t Timestamp to query voting power
    /// @return Voting power
    function balanceOfNFTAt(uint256 _tokenId, uint256 _t) external view returns (uint256);

    /// @notice Get the voting power for _tokenId at a given block
    /// @param _tokenId .
    /// @param _block Block number to query voting power
    /// @return Voting power
    function balanceOfAtNFT(uint256 _tokenId, uint256 _block) external view returns (uint256);

    /// @notice Calculate total voting power at some point in the past
    /// @param _block Block to calculate the total voting power at
    /// @return Total voting power at `_block`
    function totalSupplyAt(uint256 _block) external view returns (uint256);

    /// @notice Calculate total voting power at current timestamp
    /// @return Total voting power
    function totalSupply() external view returns (uint256);

    /// @notice Calculate total voting power
    /// @dev Adheres to the ERC20 `totalSupply` interface for Aragon compatibility
    /// @return Total voting power
    function totalSupplyAtT(uint256 t) external view returns (uint256);

    /*///////////////////////////////////////////////////////////////
                            GAUGE VOTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice See if a queried _tokenId has actively voted
    /// @param _tokenId .
    /// @return True if voted, else false
    function voted(uint256 _tokenId) external view returns (bool);

    /// @notice Set the global state voter and distributor
    /// @dev This is only called once, at setup
    function setVoterAndDistributor(address _voter, address _distributor) external;

    /// @notice Set `voted` for _tokenId to true
    /// @dev only callable by voter
    function voting(uint256 _tokenId) external;

    /// @notice Set `voted` for _tokenId to false
    /// @dev only callable by voter
    function abstain(uint256 _tokenId) external;

    /// @notice Merges `_from` into `_to`.
    /// @param _from VeNFT to merge from.
    /// @param _to VeNFT to merge into.
    function merge(uint256 _from, uint256 _to) external;

    /// @notice Splits `_amount` into a separate veNFT.
    /// @param _from VeNFT to split.
    /// @param _amount Amount to split from veNFT.
    /// @return _tokenId Return tokenId of newly split veNFT.
    function split(uint256 _from, uint256 _amount) external returns (uint256 _tokenId);

    /*///////////////////////////////////////////////////////////////
                            DAO VOTING STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The number of checkpoints for each account
    function numCheckpoints(address account) external view returns (uint32);

    /// @notice A record of states for signing / validating signatures
    function nonces(address account) external view returns (uint256);

    /// @inheritdoc IVotes
    function delegates(address delegator) external view returns (address);

    /// @notice A record of delegated token checkpoints for each account, by index
    /// @param account .
    /// @param index .
    /// @return Checkpoint
    function checkpoints(address account, uint32 index) external view returns (Checkpoint memory);

    /// @inheritdoc IVotes
    function getVotes(address account) external view returns (uint256);

    /// @notice Get the token ids delegated to an `account` at a certain block number
    /// @param account .
    /// @param blockNumber .
    /// @return _tokenIds Array of tokenIds held by `account`
    function getTokenIdsAt(address account, uint256 blockNumber) external view returns (uint256[] memory _tokenIds);

    /// @notice Binary tree serach to get the checkpoint index for an account at a specific block number
    /// @param account .
    /// @param blockNumber .
    /// @return Index of checkpoint
    function getPastVotesIndex(address account, uint256 blockNumber) external view returns (uint32);

    /// @inheritdoc IVotes
    function getPastVotes(address account, uint256 blockNumber) external view returns (uint256);

    /// @inheritdoc IVotes
    function getPastTotalSupply(uint256 blockNumber) external view returns (uint256);

    /*///////////////////////////////////////////////////////////////
                             DAO VOTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVotes
    function delegate(address delegatee) external;

    /// @inheritdoc IVotes
    function delegateBySig(
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

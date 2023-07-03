// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {SinkManagerFacilitator} from "./SinkManagerFacilitator.sol";
import {ISinkManager} from "../../interfaces/ISinkManager.sol";
import {IMinter} from "../../interfaces/IMinter.sol";
import {IVotingEscrow} from "../../interfaces/IVotingEscrow.sol";
import {IVelo} from "../../interfaces/IVelo.sol";
import {IGaugeV1} from "../../interfaces/v1/IGaugeV1.sol";
import {IVoterV1} from "../../interfaces/v1/IVoterV1.sol";
import {IVotingEscrowV1} from "../../interfaces/v1/IVotingEscrowV1.sol";
import {IRewardsDistributorV1} from "../../interfaces/v1/IRewardsDistributorV1.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {VelodromeTimeLibrary} from "../../libraries/VelodromeTimeLibrary.sol";
import {SafeCastLibrary} from "../../libraries/SafeCastLibrary.sol";

/// @title Velodrome Sink Manager
/// @notice Absorb v1 Velo and converting v1 veNFTs and VELO into v2
/// @author velodrome.finance, @pegahcarter
contract SinkManager is ISinkManager, ERC2771Context, Ownable, ERC721Holder, ReentrancyGuard {
    using SafeCastLibrary for int128;
    uint256 internal constant MAXTIME = 4 * 365 days;
    uint256 internal constant WEEK = 1 weeks;
    // @dev Additional salt for contract creation
    uint256 private counter;

    /// @dev tokenId => tokenIdV2
    mapping(uint256 => uint256) public conversions;
    /// @dev tokenId => facilitator address
    mapping(uint256 => address) public facilitators;

    /// @dev token id of veNFT owned by this contract to capture v1 VELO emissions
    uint256 public ownedTokenId;

    /// @dev Address of fake pool used to capture emissions
    address private sinkDrain;

    // @dev Address of deployed facilitator contract to clone
    address public facilitatorImplementation;

    /// @dev V1 Voting contract
    IVoterV1 public immutable voter;
    /// @dev V1 Velo contract
    IVelo public immutable velo;
    /// @dev V2 Velo contract
    IVelo public immutable veloV2;
    /// @dev V2 Minter contract
    IMinter public immutable minterV2;
    /// @dev V1 Voting Escrow contract
    IVotingEscrowV1 public immutable ve;
    /// @dev V2 Voting Escrow contract
    IVotingEscrow public immutable veV2;
    /// @dev V1 Rewards Distributor contract
    IRewardsDistributorV1 public immutable rewardsDistributor;
    /// @dev V1 sinkDrain gauge
    IGaugeV1 public gauge;
    /// @dev epoch start => velo captured
    mapping(uint256 => uint256) internal _captured;

    constructor(
        address _forwarder,
        address _sinkDrain,
        address _facilitatorImplementation,
        address _voter,
        address _velo,
        address _veloV2,
        address _ve,
        address _veV2,
        address _rewardsDistributor
    ) ERC2771Context(_forwarder) {
        sinkDrain = _sinkDrain;
        facilitatorImplementation = _facilitatorImplementation;
        voter = IVoterV1(_voter);
        velo = IVelo(_velo);
        veloV2 = IVelo(_veloV2);
        minterV2 = IMinter(IVelo(_veloV2).minter());
        ve = IVotingEscrowV1(_ve);
        veV2 = IVotingEscrow(_veV2);
        rewardsDistributor = IRewardsDistributorV1(_rewardsDistributor);

        velo.approve(_ve, type(uint256).max);
        veloV2.approve(_veV2, type(uint256).max);
    }

    // --------------------------------------------------------------------
    // Conversion methods
    // --------------------------------------------------------------------

    /// @inheritdoc ISinkManager
    function convertVELO(uint256 amount) external {
        uint256 _ownedTokenId = ownedTokenId;
        if (_ownedTokenId == 0) revert TokenIdNotSet();
        address sender = _msgSender();

        // Mint emissions prior to conversion
        minterV2.updatePeriod();

        // Deposit old VELO
        velo.transferFrom(sender, address(this), amount);

        // Add VELO to owned escrow
        ve.increase_amount(_ownedTokenId, amount);

        // return new VELO
        veloV2.mint(sender, amount);
        _captured[VelodromeTimeLibrary.epochStart(block.timestamp)] += amount;

        emit ConvertVELO(sender, amount, block.timestamp);
    }

    /// @inheritdoc ISinkManager
    function convertVe(uint256 tokenId) external nonReentrant returns (uint256 tokenIdV2) {
        uint256 _ownedTokenId = ownedTokenId;
        if (_ownedTokenId == 0) revert TokenIdNotSet();

        // Ensure the veNFT was not converted
        if (conversions[tokenId] != 0) revert NFTAlreadyConverted();

        // Ensure this contract has been approved to transfer the veNFT
        if (!ve.isApprovedOrOwner(address(this), tokenId)) revert NFTNotApproved();

        // Ensure the veNFT has not expired
        if (ve.locked__end(tokenId) <= block.timestamp) revert NFTExpired();

        address sender = _msgSender();

        // Mint emissions prior to conversion
        minterV2.updatePeriod();

        // Create contract to facilitate the merge
        SinkManagerFacilitator facilitator = SinkManagerFacilitator(
            Clones.cloneDeterministic(
                facilitatorImplementation,
                keccak256(abi.encodePacked(++counter, blockhash(block.number - 1)))
            )
        );

        // Transfer the veNFT to the facilitator
        ve.safeTransferFrom(sender, address(facilitator), tokenId);

        /* Create new veNFT with same lock parameters */

        // Fetch lock information of v1 veNFT
        (int128 _lockAmount, uint256 lockEnd) = ve.locked(tokenId); // amount of v1 VELO locked, unlock timestamp
        uint256 lockAmount = _lockAmount.toUint256();
        // determine lockDuration based on current epoch start - see unlockTime in ve._createLock()
        uint256 lockDuration = lockEnd - (block.timestamp / WEEK) * WEEK;

        // mint v2 VELO to deposit into lock
        veloV2.mint(address(this), lockAmount);

        // Create v2 veNFT
        tokenIdV2 = veV2.createLockFor(lockAmount, lockDuration, sender);

        // Merge into the sinkManager veNFT
        ve.approve(address(facilitator), ownedTokenId);
        facilitator.merge(ve, tokenId, ownedTokenId);
        ve.approve(address(0), ownedTokenId);

        // poke vote to update voting balance to gauge
        voter.poke(_ownedTokenId);

        // event emission and storage of conversion
        conversions[tokenId] = tokenIdV2;
        facilitators[tokenId] = address(facilitator);
        _captured[VelodromeTimeLibrary.epochStart(block.timestamp)] += lockAmount;
        emit ConvertVe(sender, tokenId, tokenIdV2, lockAmount, lockEnd, block.timestamp);
    }

    // --------------------------------------------------------------------
    // Maintenance
    // --------------------------------------------------------------------
    /// @inheritdoc ISinkManager
    function claimRebaseAndGaugeRewards() external {
        if (address(gauge) == address(0)) revert GaugeNotSet();
        uint256 _ownedTokenId = ownedTokenId;

        // Claim gauge rewards and deposit into owned veNFT
        uint256 amountResidual = velo.balanceOf(address(this));
        address[] memory rewards = new address[](1);
        rewards[0] = address(velo);
        gauge.getReward(address(this), rewards);
        uint256 amountAfterReward = velo.balanceOf(address(this));
        uint256 amountRewarded = amountAfterReward - amountResidual;
        if (amountAfterReward > 0) {
            ve.increase_amount(_ownedTokenId, amountAfterReward);
        }

        // Claim rebases
        uint256 amountRebased = rewardsDistributor.claimable(_ownedTokenId);
        if (amountRebased > 0) {
            rewardsDistributor.claim(_ownedTokenId);
        }

        // increase locktime to max if possible
        uint256 unlockTime = ((block.timestamp + MAXTIME) / WEEK) * WEEK;
        (, uint256 end) = ve.locked(_ownedTokenId);
        if (unlockTime > end) {
            ve.increase_unlock_time(_ownedTokenId, MAXTIME);
        }

        // poke vote to update voting balance to gauge
        voter.poke(_ownedTokenId);

        emit ClaimRebaseAndGaugeRewards(_msgSender(), amountResidual, amountRewarded, amountRebased, block.timestamp);
    }

    // --------------------------------------------------------------------
    // Admin
    // --------------------------------------------------------------------
    /// @notice Initial setup of the ownedTokenId, the v1 veNFT which votes for the SinkDrain
    function setOwnedTokenId(uint256 tokenId) external onlyOwner {
        if (ownedTokenId != 0) revert TokenIdAlreadySet();
        if (ve.ownerOf(tokenId) != address(this)) revert ContractNotOwnerOfToken();
        ownedTokenId = tokenId;
    }

    /// @notice Deposit all of SinkDrain token to gauge to earn 100% of rewards
    /// And vote for the gauge to allocate rewards
    function setupSinkDrain(address _gauge) external onlyOwner {
        uint256 _ownedTokenId = ownedTokenId;
        if (_ownedTokenId == 0) revert TokenIdNotSet();
        if (address(gauge) != address(0)) revert GaugeAlreadySet();

        // Set gauge for future claims
        gauge = IGaugeV1(_gauge);

        // Approve gauge to transfer token
        IERC20 token = IERC20(gauge.stake());
        uint256 balance = token.balanceOf(address(this));
        token.approve(_gauge, balance);

        // Deposit SinkDrain to gauge
        gauge.deposit(balance, 0);

        // Initial vote
        address[] memory poolVote = new address[](1);
        uint256[] memory weights = new uint256[](1);
        poolVote[0] = gauge.stake();
        weights[0] = 1;
        voter.vote(_ownedTokenId, poolVote, weights);
    }

    /// @inheritdoc ISinkManager
    function captured(uint256 _timestamp) external view returns (uint256 _amount) {
        _amount = _captured[VelodromeTimeLibrary.epochStart(_timestamp)];
    }

    function _msgData() internal view override(ERC2771Context, Context) returns (bytes calldata) {
        return ERC2771Context._msgData();
    }

    function _msgSender() internal view override(ERC2771Context, Context) returns (address) {
        return ERC2771Context._msgSender();
    }
}

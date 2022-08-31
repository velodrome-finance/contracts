// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {ISinkManager} from "../../interfaces/ISinkManager.sol";
import {IVotingEscrow} from "../../interfaces/IVotingEscrow.sol";
import {IVelo} from "../../interfaces/IVelo.sol";
import {IGaugeV1} from "../../interfaces/v1/IGaugeV1.sol";
import {IVoterV1} from "../../interfaces/v1/IVoterV1.sol";
import {IVotingEscrowV1} from "../../interfaces/v1/IVotingEscrowV1.sol";
import {IRewardsDistributorV1} from "../../interfaces/v1/IRewardsDistributorV1.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {VelodromeTimeLibrary} from "../../libraries/VelodromeTimeLibrary.sol";

/// @title Velodrome Sink Manager
/// @notice Absorb v1 Velo and converting v1 veNFTs and VELO into v2
/// @author Carter Carlson (@pegahcarter)
contract SinkManager is ISinkManager, Context, Ownable, ERC721Holder, ReentrancyGuard {
    uint256 internal constant MAXTIME = 4 * 365 days;
    uint256 internal constant WEEK = 1 weeks;

    /// @dev tokenId => tokenIdV2
    mapping(uint256 => uint256) public conversions;

    /// @dev token id of veNFT owned by this contract to capture v1 VELO emissions
    uint256 public ownedTokenId;

    /// @dev V1 Voting contract
    IVoterV1 public voter;
    /// @dev V1 Velo contract
    IVelo public velo;
    /// @dev V2 Velo contract
    IVelo public veloV2;
    /// @dev V1 Voting Escrow contract
    IVotingEscrowV1 public ve;
    /// @dev V2 Voting Escrow contract
    IVotingEscrow public veV2;
    /// @dev V1 Rewards Distributor contract
    IRewardsDistributorV1 public rewardsDistributor;
    /// @dev V1 black hole gauge
    IGaugeV1 public gauge;
    /// @dev epoch start => velo captured
    mapping(uint256 => uint256) internal _captured;

    constructor(
        address _voter,
        address _velo,
        address _veloV2,
        address _ve,
        address _veV2,
        address _rewardsDistributor
    ) {
        voter = IVoterV1(_voter);
        velo = IVelo(_velo);
        veloV2 = IVelo(_veloV2);
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
        require(ownedTokenId != 0, "SinkManager: tokenId not set");
        address sender = _msgSender();

        // Deposit old VELO
        velo.transferFrom(sender, address(this), amount);

        // Add VELO to owned ve
        ve.increase_amount(ownedTokenId, amount);

        // return new VELO
        veloV2.mint(sender, amount);
        _captured[VelodromeTimeLibrary.epochStart(block.timestamp)] += amount;

        emit ConvertVELO(sender, amount, block.timestamp);
    }

    /// @inheritdoc ISinkManager
    function convertVe(uint256 tokenId) external nonReentrant returns (uint256 tokenIdV2) {
        require(ownedTokenId != 0, "SinkManager: tokenId not set");

        // Ensure the ve was not converted
        require(conversions[tokenId] == 0, "SinkManager: nft already converted");

        // Ensure the ve has not expired
        require(ve.locked__end(tokenId) > block.timestamp, "SinkManager: nft expired");

        address sender = _msgSender();

        // Transfer v1 ve to this contract - note this would fail if ve has not reset through Voter
        ve.safeTransferFrom(sender, address(this), tokenId);

        /* Create new ve with same lock parameters */

        // Fetch lock information of v1 ve
        (int128 _lockAmount, uint256 lockEnd) = ve.locked(tokenId); // amount of v1 VELO locked, unlock timestamp
        uint256 lockAmount = uint256(int256(_lockAmount));
        // determine lockDuration based on current epoch start - see unlockTime in ve._createLock()
        uint256 lockDuration = lockEnd - (block.timestamp / WEEK) * WEEK;

        // mint v2 VELO to deposit into lock
        veloV2.mint(address(this), lockAmount);

        // Create v2 ve
        tokenIdV2 = veV2.createLockFor(lockAmount, lockDuration, sender);

        // Merge into the sinkManager ve
        ve.merge(tokenId, ownedTokenId);

        // poke vote to update voting balance to gauge
        voter.poke(ownedTokenId);

        // event emission and storage of conversion
        conversions[tokenId] = tokenIdV2;
        _captured[VelodromeTimeLibrary.epochStart(block.timestamp)] += lockAmount;
        emit ConvertVe(sender, lockAmount, lockEnd, tokenId, tokenIdV2, block.timestamp);
    }

    // --------------------------------------------------------------------
    // Maintenance
    // --------------------------------------------------------------------
    /// @inheritdoc ISinkManager
    function claimRebaseAndGaugeRewards() external {
        require(address(gauge) != address(0), "SinkManager: gauge not set");

        // Claim gauge rewards and deposit into owned veNFT
        uint256 amountResidual = velo.balanceOf(address(this));
        address[] memory rewards = new address[](1);
        rewards[0] = address(velo);
        gauge.getReward(address(this), rewards);
        uint256 amountAfterReward = velo.balanceOf(address(this));
        uint256 amountRewarded = amountAfterReward - amountResidual;
        if (amountAfterReward > 0) {
            ve.increase_amount(ownedTokenId, amountAfterReward);
        }

        // Claim rebases
        uint256 amountRebased = rewardsDistributor.claimable(ownedTokenId);
        if (amountRebased > 0) {
            rewardsDistributor.claim(ownedTokenId);
        }

        // increase locktime to max if possible
        uint256 unlockTime = ((block.timestamp + MAXTIME) / WEEK) * WEEK;
        (, uint256 end) = ve.locked(ownedTokenId);
        if (unlockTime > end) {
            ve.increase_unlock_time(ownedTokenId, MAXTIME);
        }

        // poke vote to update voting balance to gauge
        voter.poke(ownedTokenId);

        emit ClaimRebaseAndGaugeRewards(_msgSender(), amountResidual, amountRewarded, amountRebased, block.timestamp);
    }

    // --------------------------------------------------------------------
    // Admin
    // --------------------------------------------------------------------
    /// @notice Initial setup of the ownedTokenId, the v1 veNFT which votes for the SinkDrain
    function setOwnedTokenId(uint256 tokenId) external onlyOwner {
        require(ownedTokenId == 0, "SinkManager: tokenId already set");
        require(ve.ownerOf(tokenId) == address(this), "SinkManager: not owner");
        ownedTokenId = tokenId;
    }

    /// @notice Deposit all of SinkDrain token to gauge to earn 100% of rewards
    /// And vote for the gauge to allocate rewards
    function setupSinkDrain(address _gauge) external onlyOwner {
        require(ownedTokenId != 0, "SinkManager: tokenId not set");
        require(address(gauge) == address(0), "SinkManager: gauge already set");

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
        voter.vote(ownedTokenId, poolVote, weights);
    }

    /// @inheritdoc ISinkManager
    function captured(uint256 _timestamp) external view returns (uint256 _amount) {
        _amount = _captured[VelodromeTimeLibrary.epochStart(_timestamp)];
    }
}

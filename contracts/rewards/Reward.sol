// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IReward} from "../interfaces/IReward.sol";
import {IVoter} from "../interfaces/IVoter.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {VelodromeTimeLibrary} from "../libraries/VelodromeTimeLibrary.sol";
import {SafeCastLibrary} from "../libraries/SafeCastLibrary.sol";
import {BalanceLogicLibrary} from "../libraries/BalanceLogicLibrary.sol";
import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";

/// @title Reward
/// @author velodrome.finance, @figs999, @pegahcarter
/// @notice Base reward contract for distribution of rewards
abstract contract Reward is IReward, ERC2771Context, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;
    using SafeCastLibrary for int128;
    using SafeCastLibrary for uint256;

    /// @inheritdoc IReward
    uint256 public constant DURATION = 7 days;

    /// @inheritdoc IReward
    address public immutable voter;
    /// @inheritdoc IReward
    address public immutable ve;
    /// @inheritdoc IReward
    address public authorized;
    /// @inheritdoc IReward
    uint256 public permanentLockBalance;
    /// @inheritdoc IReward
    uint256 public epoch;
    /// @inheritdoc IReward
    mapping(address => mapping(uint256 => uint256)) public tokenRewardsPerEpoch;
    /// @inheritdoc IReward
    mapping(address => mapping(uint256 => uint256)) public lastEarn;

    address[] public rewards;
    /// @inheritdoc IReward
    mapping(address => bool) public isReward;
    /// @inheritdoc IReward
    mapping(uint256 => uint256) public userRewardEpoch;
    /// @inheritdoc IReward
    mapping(uint256 => int128) public biasCorrections;
    /// @inheritdoc IReward
    mapping(uint256 => int128) public slopeChanges;
    /// @dev stores the lock expiry and the bias correctionfor each tokenId
    ///      the bias correction takes effect at the lock expiry time
    mapping(uint256 => IReward.LockExpiryAndBiasCorrection) internal _lockExpiryAndBiasCorrection;
    /// @dev we can reuse these structs and inherently use BalanceLogicLibrary for the balance and supply calculations
    ///      since we run the same calculations on a subset of the total weights
    mapping(uint256 => IVotingEscrow.GlobalPoint) internal _globalRewardPointHistory; // epoch -> unsigned global point
    mapping(uint256 => IVotingEscrow.UserPoint[1000000000]) internal _userRewardPointHistory;

    constructor(address _forwarder, address _voter) ERC2771Context(_forwarder) {
        voter = _voter;
        ve = IVoter(_voter).ve();
    }

    /// @inheritdoc IReward
    function rewardsListLength() external view returns (uint256) {
        return rewards.length;
    }

    /// @inheritdoc IReward
    function lockExpiry(uint256 tokenId) external view returns (uint256) {
        return _lockExpiryAndBiasCorrection[tokenId].lockExpiry;
    }

    /// @inheritdoc IReward
    function biasCorrection(uint256 tokenId) external view returns (int128) {
        return _lockExpiryAndBiasCorrection[tokenId].biasCorrection;
    }

    /// @inheritdoc IReward
    function lockExpiryAndBiasCorrection(uint256 tokenId)
        external
        view
        returns (IReward.LockExpiryAndBiasCorrection memory)
    {
        return _lockExpiryAndBiasCorrection[tokenId];
    }

    /// @inheritdoc IReward
    function globalRewardPointHistory(uint256 _epoch) external view returns (IVotingEscrow.GlobalPoint memory) {
        return _globalRewardPointHistory[_epoch];
    }

    /// @inheritdoc IReward
    function userRewardPointHistory(uint256 tokenId, uint256 _userRewardEpoch)
        external
        view
        returns (IVotingEscrow.UserPoint memory)
    {
        return _userRewardPointHistory[tokenId][_userRewardEpoch];
    }

    /// @inheritdoc IReward
    function getPriorSupplyIndex(uint256 timestamp) public view returns (uint256) {
        return BalanceLogicLibrary.getPastGlobalPointIndex({
            _epoch: epoch,
            _pointHistory: _globalRewardPointHistory,
            _timestamp: timestamp
        });
    }

    /// @inheritdoc IReward
    function supplyAt(uint256 timestamp) public view returns (uint256) {
        return BalanceLogicLibrary.supplyAt({
            _slopeChanges: slopeChanges,
            _pointHistory: _globalRewardPointHistory,
            _epoch: epoch,
            _t: timestamp
        });
    }

    /// @inheritdoc IReward
    function getPriorBalanceIndex(uint256 tokenId, uint256 timestamp) public view returns (uint256) {
        return BalanceLogicLibrary.getPastUserPointIndex({
            _userPointEpoch: userRewardEpoch,
            _userPointHistory: _userRewardPointHistory,
            _tokenId: tokenId,
            _timestamp: timestamp
        });
    }

    /// @inheritdoc IReward
    function balanceOfNFTAt(uint256 tokenId, uint256 timestamp) public view returns (uint256) {
        return BalanceLogicLibrary.balanceOfNFTAt({
            _userPointEpoch: userRewardEpoch,
            _userPointHistory: _userRewardPointHistory,
            _tokenId: tokenId,
            _t: timestamp
        });
    }

    /// @inheritdoc IReward
    function earned(address token, uint256 tokenId) public view returns (uint256) {
        if (userRewardEpoch[tokenId] == 0) {
            return 0;
        }

        uint256 reward = 0;
        uint256 _supply = 1;
        uint256 _currTs = VelodromeTimeLibrary.epochStart({timestamp: lastEarn[token][tokenId]}); // take epoch last claimed in as starting point
        uint256 _index = getPriorBalanceIndex({tokenId: tokenId, timestamp: _currTs});

        // accounts for case where lastEarn is before first checkpoint
        _currTs = Math.max({
            a: _currTs,
            b: VelodromeTimeLibrary.epochStart({timestamp: _userRewardPointHistory[tokenId][_index].ts})
        });

        // get epochs between current epoch and first checkpoint in same epoch as last claim
        uint256 numEpochs = (VelodromeTimeLibrary.epochStart({timestamp: block.timestamp}) - _currTs) / DURATION;

        uint256 balance;
        if (numEpochs > 0) {
            for (uint256 i = 0; i < numEpochs; i++) {
                balance = balanceOfNFTAt({tokenId: tokenId, timestamp: _currTs + DURATION - 1});
                _supply = Math.max({a: supplyAt({timestamp: _currTs + DURATION - 1}), b: 1});
                reward += (balance * tokenRewardsPerEpoch[token][_currTs]) / _supply;

                _currTs += DURATION;
            }
        }

        return reward;
    }

    /// @inheritdoc IReward
    function _deposit(uint256 amount, uint256 tokenId) external {
        address sender = _msgSender();
        if (sender != authorized) revert NotAuthorized();

        IVotingEscrow.LockedBalance memory locked = IVotingEscrow(ve).locked({_tokenId: tokenId});

        IVotingEscrow.UserPoint memory userRewardPoint =
            IVotingEscrow.UserPoint({bias: 0, slope: 0, permanent: 0, ts: block.timestamp});

        uint256 userEpoch = userRewardEpoch[tokenId];
        IVotingEscrow.UserPoint memory prevUserRewardPoint = _userRewardPointHistory[tokenId][userEpoch];

        uint256 newLockEnd = locked.end;
        uint256 _biasCorrection;

        // normal permanent lock or managed nft
        if (locked.isPermanent || (locked.amount == 0 && newLockEnd == 0 && locked.isPermanent == false)) {
            permanentLockBalance += amount;
            userRewardPoint.permanent = amount;
        } else {
            _lockExpiryAndBiasCorrection[tokenId].lockExpiry = newLockEnd;
            int128 newBias = amount.toInt128();
            userRewardPoint.bias = newBias;
            userRewardPoint.slope = (newBias / (newLockEnd - block.timestamp).toInt128());

            _biasCorrection =
                _getBiasCorrection({tokenId: tokenId, amount: amount, rewardPointSlope: userRewardPoint.slope});

            _lockExpiryAndBiasCorrection[tokenId].biasCorrection = _biasCorrection.toInt128();
        }

        _saveUserRewardPoint({
            userRewardPoint: userRewardPoint,
            prevUserRewardPoint: prevUserRewardPoint,
            tokenId: tokenId,
            userEpoch: userEpoch
        });
        _createGlobalRewardPoints({userRewardPoint: userRewardPoint, prevUserRewardPoint: prevUserRewardPoint});

        if (newLockEnd > block.timestamp) {
            slopeChanges[newLockEnd] -= userRewardPoint.slope;
            biasCorrections[newLockEnd] -= _biasCorrection.toInt128();
        }

        emit Deposit({from: sender, tokenId: tokenId, amount: amount});
    }

    /// @dev it assumes that the whole amount is being removed
    /// @inheritdoc IReward
    function _withdraw(uint256 amount, uint256 tokenId) external {
        address sender = _msgSender();
        if (sender != authorized) revert NotAuthorized();

        IVotingEscrow.UserPoint memory userRewardPoint =
            IVotingEscrow.UserPoint({bias: 0, slope: 0, permanent: 0, ts: block.timestamp});

        uint256 userEpoch = userRewardEpoch[tokenId];
        IVotingEscrow.UserPoint memory prevUserRewardPoint = _userRewardPointHistory[tokenId][userEpoch];

        if (prevUserRewardPoint.permanent != 0) permanentLockBalance -= amount;

        _saveUserRewardPoint({
            userRewardPoint: userRewardPoint,
            prevUserRewardPoint: prevUserRewardPoint,
            tokenId: tokenId,
            userEpoch: userEpoch
        });

        uint256 prevLockEnd = _lockExpiryAndBiasCorrection[tokenId].lockExpiry;

        // only update global bias and slope if the nft is not expired
        if (prevLockEnd < block.timestamp) prevUserRewardPoint.ts = type(uint256).max;

        _createGlobalRewardPoints({userRewardPoint: userRewardPoint, prevUserRewardPoint: prevUserRewardPoint});

        // cancel out slope and bias correction
        if (prevLockEnd > block.timestamp) {
            slopeChanges[prevLockEnd] += prevUserRewardPoint.slope;
            biasCorrections[prevLockEnd] += _lockExpiryAndBiasCorrection[tokenId].biasCorrection;
        }
        delete _lockExpiryAndBiasCorrection[tokenId];

        emit Withdraw({from: sender, tokenId: tokenId, amount: amount});
    }

    /// @inheritdoc IReward
    function getReward(uint256 tokenId, address[] memory tokens) external virtual nonReentrant {}

    /// @dev used with all getReward implementations
    function _getReward(address recipient, uint256 tokenId, address[] memory tokens) internal {
        uint256 _length = tokens.length;
        for (uint256 i = 0; i < _length; i++) {
            uint256 _reward = earned({token: tokens[i], tokenId: tokenId});
            lastEarn[tokens[i]][tokenId] = block.timestamp;
            if (_reward > 0) IERC20(tokens[i]).safeTransfer({to: recipient, value: _reward});

            emit ClaimRewards({from: recipient, reward: tokens[i], amount: _reward});
        }
    }

    /// @inheritdoc IReward
    function notifyRewardAmount(address token, uint256 amount) external virtual nonReentrant {}

    /// @dev used within all notifyRewardAmount implementations
    function _notifyRewardAmount(address sender, address token, uint256 amount) internal {
        if (amount == 0) revert ZeroAmount();
        IERC20(token).safeTransferFrom({from: sender, to: address(this), value: amount});

        uint256 epochStart = VelodromeTimeLibrary.epochStart({timestamp: block.timestamp});
        tokenRewardsPerEpoch[token][epochStart] += amount;

        emit NotifyReward({from: sender, reward: token, epoch: epochStart, amount: amount});
    }

    /// @dev 1 checkpoint per epoch
    function _saveUserRewardPoint(
        IVotingEscrow.UserPoint memory userRewardPoint,
        IVotingEscrow.UserPoint memory prevUserRewardPoint,
        uint256 tokenId,
        uint256 userEpoch
    ) internal {
        // if we already created a checkpoint in this epoch overwrite the last urph
        // else create the new urph (urph index starts from 1)
        if (
            userEpoch != 0
                && VelodromeTimeLibrary.epochStart({timestamp: prevUserRewardPoint.ts})
                    == VelodromeTimeLibrary.epochStart({timestamp: block.timestamp})
        ) {
            _userRewardPointHistory[tokenId][userEpoch] = userRewardPoint;
        } else {
            userRewardEpoch[tokenId] = ++userEpoch;
            _userRewardPointHistory[tokenId][userEpoch] = userRewardPoint;
        }
    }

    /// @dev adapted from VotingEscrow._checkpoint
    function _createGlobalRewardPoints(
        IVotingEscrow.UserPoint memory userRewardPoint,
        IVotingEscrow.UserPoint memory prevUserRewardPoint
    ) internal {
        uint256 _epoch = epoch;

        IVotingEscrow.GlobalPoint memory lastPoint = _epoch > 0
            ? _globalRewardPointHistory[_epoch]
            : IVotingEscrow.GlobalPoint({bias: 0, slope: 0, ts: block.timestamp, permanentLockBalance: 0});
        uint256 lastCheckpoint = lastPoint.ts;

        // Go over weeks to fill history and calculate what the current point is
        {
            uint256 t_i = (lastCheckpoint / DURATION) * DURATION;
            for (uint256 i = 0; i < 255; ++i) {
                // Hopefully it won't happen that this won't get used in 5 years!
                // If it does, users will be able to withdraw but vote weight will be broken
                t_i += DURATION; // Initial value of t_i is always larger than the ts of the last point
                int128 d_slope = 0;
                int128 _biasCorrection = 0;
                if (t_i > block.timestamp) {
                    t_i = block.timestamp;
                } else {
                    d_slope = slopeChanges[t_i];
                    _biasCorrection = biasCorrections[t_i];
                }
                lastPoint.bias -= lastPoint.slope * (t_i - lastCheckpoint).toInt128();
                lastPoint.bias += _biasCorrection;
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
                ++_epoch;
                if (t_i == block.timestamp) {
                    break;
                } else {
                    _globalRewardPointHistory[_epoch] = lastPoint;
                }
            }
        }

        if (userRewardPoint.permanent != 0 || userRewardPoint.bias != 0) {
            // deposit (previous is always 0)
            lastPoint.bias += userRewardPoint.bias;
            lastPoint.slope += userRewardPoint.slope;
        } else {
            // withdraw (current is always 0)
            // if expired skip
            if (block.timestamp > prevUserRewardPoint.ts) {
                int128 decay = prevUserRewardPoint.slope * (block.timestamp - prevUserRewardPoint.ts).toInt128();
                lastPoint.bias -= (prevUserRewardPoint.bias - decay);
                lastPoint.slope -= prevUserRewardPoint.slope;
            }
        }

        if (lastPoint.slope < 0) {
            lastPoint.slope = 0;
        }
        if (lastPoint.bias < 0) {
            lastPoint.bias = 0;
        }
        lastPoint.permanentLockBalance = permanentLockBalance;

        // @note one checkpoint per epoch
        // If timestamp of last global point is in the current epoch, overwrite the last global point
        // Else record the new global point into history
        // Exclude epoch 0 (note: _epoch is always >= 1, see above)
        // Two possible outcomes:
        // Missing global checkpoints in prior epochs. In this case, _epoch = epoch + x, where x > 1
        // No missing global checkpoints, but no cp written in this epoch. Create new checkpoint.
        // No missing global checkpoints, but cp already written in this epoch. Overwrite last checkpoint.
        if (
            _epoch != 1
                && VelodromeTimeLibrary.epochStart({timestamp: _globalRewardPointHistory[_epoch].ts})
                    == VelodromeTimeLibrary.epochStart({timestamp: block.timestamp})
        ) {
            // _epoch = epoch + 1, so we do not increment epoch
            _globalRewardPointHistory[_epoch] = lastPoint;
        } else {
            // more than one global point may have been written, so we update epoch
            // we subtract 1 because we calculated the cp at block.timestamp as well, but we have to overwrite the latest cp (start of the epoch) since it's the same epoch
            if (_epoch != 1) _epoch -= 1;
            epoch = _epoch;
            _globalRewardPointHistory[_epoch] = lastPoint;
        }
    }

    /// @dev because of the nature of the operations while we calculate the user reward slope
    ///      some precision loss can occur which can lead to leftover global bias when the nft
    ///      expires. For this we have to track the residual bias and remove it when votes are
    ///      withdrawn or the nft expires.
    function _getBiasCorrection(uint256 tokenId, uint256 amount, int128 rewardPointSlope)
        internal
        view
        returns (uint256 _biasCorrection)
    {
        uint256 totalWeight = IVotingEscrow(ve).balanceOfNFT({_tokenId: tokenId});

        if (totalWeight == amount) return 0;

        int128 mainSlope = IVotingEscrow(ve).userPointHistory({
            _tokenId: tokenId,
            _loc: IVotingEscrow(ve).userPointEpoch({_tokenId: tokenId})
        }).slope;

        uint256 ratio = totalWeight / amount;

        uint256 dT = VelodromeTimeLibrary.epochNext({timestamp: block.timestamp}) - block.timestamp - 1;

        // calculate what would be the total user bias at the end of the epoch
        uint256 epochEndTotalBias = totalWeight - (mainSlope.toUint256() * dT);
        // calculate what will be the reward user bias at the end of the epoch
        uint256 epochEndRewardBias = amount - (rewardPointSlope.toUint256() * dT);
        // divide total bias based on vote distribution
        uint256 epochEndRatioedTotalBias = epochEndTotalBias / ratio;

        _biasCorrection = epochEndRewardBias > epochEndRatioedTotalBias
            ? epochEndRewardBias - epochEndRatioedTotalBias
            : epochEndRatioedTotalBias - epochEndRewardBias;
    }
}

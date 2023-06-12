// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IRewardsDistributor} from "./interfaces/IRewardsDistributor.sol";
import {IVotingEscrow} from "./interfaces/IVotingEscrow.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/*
 * @title Curve Fee Distribution modified for ve(3,3) emissions
 * @author Curve Finance, andrecronje
 * @license MIT
 */
contract RewardsDistributor is IRewardsDistributor {
    using SafeERC20 for IERC20;
    uint256 constant WEEK = 7 * 86400;

    uint256 public startTime;
    mapping(uint256 => uint256) public timeCursorOf;

    uint256 public lastTokenTime;
    uint256[1000000000000000] public tokensPerWeek;

    IVotingEscrow public immutable ve;
    address public token;
    address public depositor;
    uint256 public tokenLastBalance;

    constructor(address _ve) {
        uint256 _t = (block.timestamp / WEEK) * WEEK;
        startTime = _t;
        lastTokenTime = _t;
        ve = IVotingEscrow(_ve);
        address _token = ve.token();
        token = _token;
        depositor = msg.sender;
        IERC20(_token).safeApprove(_ve, type(uint256).max);
    }

    function _checkpointToken() internal {
        uint256 tokenBalance = IERC20(token).balanceOf(address(this));
        uint256 toDistribute = tokenBalance - tokenLastBalance;
        tokenLastBalance = tokenBalance;

        uint256 t = lastTokenTime;
        uint256 sinceLast = block.timestamp - t;
        lastTokenTime = block.timestamp;
        uint256 thisWeek = (t / WEEK) * WEEK;
        uint256 nextWeek = 0;
        uint256 timestamp = block.timestamp;

        for (uint256 i = 0; i < 20; i++) {
            nextWeek = thisWeek + WEEK;
            if (timestamp < nextWeek) {
                if (sinceLast == 0 && timestamp == t) {
                    tokensPerWeek[thisWeek] += toDistribute;
                } else {
                    tokensPerWeek[thisWeek] += (toDistribute * (timestamp - t)) / sinceLast;
                }
                break;
            } else {
                if (sinceLast == 0 && nextWeek == t) {
                    tokensPerWeek[thisWeek] += toDistribute;
                } else {
                    tokensPerWeek[thisWeek] += (toDistribute * (nextWeek - t)) / sinceLast;
                }
            }
            t = nextWeek;
            thisWeek = nextWeek;
        }
        emit CheckpointToken(timestamp, toDistribute);
    }

    /// @inheritdoc IRewardsDistributor
    function checkpointToken() external {
        assert(msg.sender == depositor);
        _checkpointToken();
    }

    function _claim(uint256 _tokenId, uint256 _lastTokenTime) internal returns (uint256) {
        (uint256 toDistribute, uint256 epochStart, uint256 weekCursor) = _claimable(_tokenId, _lastTokenTime);
        timeCursorOf[_tokenId] = weekCursor;
        if (toDistribute == 0) return 0;

        emit Claimed(_tokenId, epochStart, weekCursor, toDistribute);
        return toDistribute;
    }

    function _claimable(
        uint256 _tokenId,
        uint256 _lastTokenTime
    ) internal view returns (uint256 toDistribute, uint256 weekCursorStart, uint256 weekCursor) {
        uint256 _startTime = startTime;
        weekCursor = timeCursorOf[_tokenId];
        weekCursorStart = weekCursor;

        // case where token does not exist
        uint256 maxUserEpoch = ve.userPointEpoch(_tokenId);
        if (maxUserEpoch == 0) return (0, weekCursorStart, weekCursor);

        // case where token exists but has never been claimed
        if (weekCursor == 0) {
            IVotingEscrow.UserPoint memory userPoint = ve.userPointHistory(_tokenId, 1);
            weekCursor = ((userPoint.ts + WEEK - 1) / WEEK) * WEEK;
            weekCursorStart = weekCursor;
        }
        if (weekCursor >= lastTokenTime) return (0, weekCursorStart, weekCursor);
        if (weekCursor < _startTime) weekCursor = _startTime;

        for (uint256 i = 0; i < 50; i++) {
            if (weekCursor >= _lastTokenTime) break;

            uint256 balance = ve.balanceOfNFTAt(_tokenId, weekCursor - 1);
            uint256 supply = ve.totalSupplyAt(weekCursor - 1);
            supply = supply == 0 ? 1 : supply;
            toDistribute += (balance * tokensPerWeek[weekCursor]) / supply;
            weekCursor += WEEK;
        }
    }

    /// @inheritdoc IRewardsDistributor
    function claimable(uint256 _tokenId) external view returns (uint256 claimable_) {
        uint256 _lastTokenTime = (lastTokenTime / WEEK) * WEEK;
        (claimable_, , ) = _claimable(_tokenId, _lastTokenTime);
    }

    /// @inheritdoc IRewardsDistributor
    function claim(uint256 _tokenId) external returns (uint256) {
        uint256 _timestamp = block.timestamp;
        uint256 _lastTokenTime = lastTokenTime;
        _lastTokenTime = (_lastTokenTime / WEEK) * WEEK;
        uint256 amount = _claim(_tokenId, _lastTokenTime);
        if (amount != 0) {
            IVotingEscrow.LockedBalance memory _locked = IVotingEscrow(ve).locked(_tokenId);
            if (_timestamp > _locked.end && !_locked.isPermanent) {
                address _owner = IVotingEscrow(ve).ownerOf(_tokenId);
                IERC20(token).safeTransfer(_owner, amount);
            } else {
                IVotingEscrow(ve).depositFor(_tokenId, amount);
            }
            tokenLastBalance -= amount;
        }
        return amount;
    }

    /// @inheritdoc IRewardsDistributor
    function claimMany(uint256[] calldata _tokenIds) external returns (bool) {
        uint256 _timestamp = block.timestamp;
        uint256 _lastTokenTime = lastTokenTime;
        _lastTokenTime = (_lastTokenTime / WEEK) * WEEK;
        uint256 total = 0;
        uint256 _length = _tokenIds.length;

        for (uint256 i = 0; i < _length; i++) {
            uint256 _tokenId = _tokenIds[i];
            if (_tokenId == 0) break;
            uint256 amount = _claim(_tokenId, _lastTokenTime);
            if (amount != 0) {
                IVotingEscrow.LockedBalance memory _locked = IVotingEscrow(ve).locked(_tokenId);
                if (_timestamp > _locked.end && !_locked.isPermanent) {
                    address _owner = IVotingEscrow(ve).ownerOf(_tokenId);
                    IERC20(token).safeTransfer(_owner, amount);
                } else {
                    IVotingEscrow(ve).depositFor(_tokenId, amount);
                }
                total += amount;
            }
        }
        if (total != 0) {
            tokenLastBalance -= total;
        }

        return true;
    }

    /// @inheritdoc IRewardsDistributor
    function setDepositor(address _depositor) external {
        if (msg.sender != depositor) revert NotDepositor();
        depositor = _depositor;
    }

    function max(int128 a, int128 b) internal pure returns (int128) {
        return a > b ? a : b;
    }
}

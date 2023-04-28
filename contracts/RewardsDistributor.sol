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
    uint256 public timeCursor;
    mapping(uint256 => uint256) public timeCursorOf;
    mapping(uint256 => uint256) public userEpochOf;

    uint256 public lastTokenTime;
    uint256[1000000000000000] public tokensPerWeek;

    address public immutable ve;
    address public token;
    uint256 public tokenLastBalance;

    uint256[1000000000000000] public veSupply;

    address public depositor;

    constructor(address _ve) {
        uint256 _t = (block.timestamp / WEEK) * WEEK;
        startTime = _t;
        lastTokenTime = _t;
        timeCursor = _t;
        address _token = IVotingEscrow(_ve).token();
        token = _token;
        ve = _ve;
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

    function checkpointToken() external {
        assert(msg.sender == depositor);
        _checkpointToken();
    }

    /// @dev Fetches last global checkpoint prior to timestamp
    function _findTimestampEpoch(uint256 _timestamp) internal view returns (uint256) {
        address _ve = ve;
        uint256 _min = 0;
        uint256 _max = IVotingEscrow(_ve).epoch();
        for (uint256 i = 0; i < 128; i++) {
            if (_min >= _max) break;
            uint256 _mid = (_min + _max + 2) / 2;
            IVotingEscrow.GlobalPoint memory pt = IVotingEscrow(_ve).pointHistory(_mid);
            if (pt.ts <= _timestamp) {
                _min = _mid;
            } else {
                _max = _mid - 1;
            }
        }
        return _min;
    }

    function _findTimestampUserEpoch(
        uint256 _tokenId,
        uint256 _timestamp,
        uint256 _maxUserEpoch
    ) internal view returns (uint256) {
        uint256 _min = 0;
        uint256 _max = _maxUserEpoch;
        for (uint256 i = 0; i < 128; i++) {
            if (_min >= _max) break;
            uint256 _mid = (_min + _max + 2) / 2;
            IVotingEscrow.UserPoint memory pt = IVotingEscrow(ve).userPointHistory(_tokenId, _mid);
            if (pt.ts <= _timestamp) {
                _min = _mid;
            } else {
                _max = _mid - 1;
            }
        }
        return _min;
    }

    function veForAt(uint256 _tokenId, uint256 _timestamp) external view returns (uint256) {
        address _ve = ve;
        uint256 maxUserEpoch = IVotingEscrow(_ve).userPointEpoch(_tokenId);
        uint256 epoch = _findTimestampUserEpoch(_tokenId, _timestamp, maxUserEpoch);
        IVotingEscrow.UserPoint memory pt = IVotingEscrow(_ve).userPointHistory(_tokenId, epoch);
        if (pt.permanent != 0) {
            return pt.permanent;
        } else {
            return uint256(int256(max(pt.bias - pt.slope * int128(int256(_timestamp - pt.ts)), 0)));
        }
    }

    function _checkpointTotalSupply() internal {
        address _ve = ve;
        uint256 t = timeCursor;
        uint256 roundedTimestamp = (block.timestamp / WEEK) * WEEK;
        IVotingEscrow(_ve).checkpoint();

        for (uint256 i = 0; i < 20; i++) {
            if (t > roundedTimestamp) {
                break;
            } else {
                // fetch last global checkpoint prior to time t
                uint256 epoch = _findTimestampEpoch(t);
                IVotingEscrow.GlobalPoint memory pt = IVotingEscrow(_ve).pointHistory(epoch);
                int128 dt = 0;
                if (t > pt.ts) {
                    dt = int128(int256(t - pt.ts));
                }
                // walk forward voting power to time t
                veSupply[t] = uint256(int256(max(pt.bias - pt.slope * dt, 0))) + pt.permanentLockBalance;
            }
            t += WEEK;
        }
        timeCursor = t;
    }

    function checkpointTotalSupply() external {
        _checkpointTotalSupply();
    }

    function _claim(uint256 _tokenId, uint256 _lastTokenTime) internal returns (uint256) {
        uint256 userEpoch = 0;
        uint256 toDistribute = 0;
        address _ve = ve;

        uint256 maxUserEpoch = IVotingEscrow(_ve).userPointEpoch(_tokenId);
        uint256 _startTime = startTime;

        if (maxUserEpoch == 0) return 0;

        uint256 weekCursor = timeCursorOf[_tokenId];
        if (weekCursor == 0) {
            userEpoch = _findTimestampUserEpoch(_tokenId, _startTime, maxUserEpoch);
        } else {
            userEpoch = userEpochOf[_tokenId];
        }

        if (userEpoch == 0) userEpoch = 1;

        IVotingEscrow.UserPoint memory userPoint = IVotingEscrow(_ve).userPointHistory(_tokenId, userEpoch);

        if (weekCursor == 0) weekCursor = ((userPoint.ts + WEEK - 1) / WEEK) * WEEK;
        if (weekCursor >= lastTokenTime) return 0;
        if (weekCursor < _startTime) weekCursor = _startTime;

        IVotingEscrow.UserPoint memory oldUserPoint;

        for (uint256 i = 0; i < 50; i++) {
            if (weekCursor >= _lastTokenTime) break;

            if (weekCursor >= userPoint.ts && userEpoch <= maxUserEpoch) {
                userEpoch += 1;
                oldUserPoint = userPoint;
                if (userEpoch > maxUserEpoch) {
                    userPoint = IVotingEscrow.UserPoint(0, 0, 0, 0, 0);
                } else {
                    userPoint = IVotingEscrow(_ve).userPointHistory(_tokenId, userEpoch);
                }
            } else {
                int128 dt = int128(int256(weekCursor - oldUserPoint.ts));
                uint256 balance;
                if (oldUserPoint.permanent != 0) {
                    balance = oldUserPoint.permanent;
                } else {
                    balance = uint256(int256(max(oldUserPoint.bias - dt * oldUserPoint.slope, 0)));
                }
                if (balance == 0 && userEpoch > maxUserEpoch) break;
                if (balance != 0) {
                    toDistribute += (balance * tokensPerWeek[weekCursor]) / veSupply[weekCursor];
                }
                weekCursor += WEEK;
            }
        }

        userEpoch = Math.min(maxUserEpoch, userEpoch - 1);
        userEpochOf[_tokenId] = userEpoch;
        timeCursorOf[_tokenId] = weekCursor;

        emit Claimed(_tokenId, userEpoch, maxUserEpoch, toDistribute);

        return toDistribute;
    }

    function _claimable(uint256 _tokenId, uint256 _lastTokenTime) internal view returns (uint256) {
        address _ve = ve;
        uint256 userEpoch = 0;
        uint256 toDistribute = 0;

        uint256 maxUserEpoch = IVotingEscrow(_ve).userPointEpoch(_tokenId);
        uint256 _startTime = startTime;

        if (maxUserEpoch == 0) return 0;

        uint256 weekCursor = timeCursorOf[_tokenId];
        if (weekCursor == 0) {
            userEpoch = _findTimestampUserEpoch(_tokenId, _startTime, maxUserEpoch);
        } else {
            userEpoch = userEpochOf[_tokenId];
        }

        if (userEpoch == 0) userEpoch = 1;

        IVotingEscrow.UserPoint memory userPoint = IVotingEscrow(_ve).userPointHistory(_tokenId, userEpoch);

        if (weekCursor == 0) weekCursor = ((userPoint.ts + WEEK - 1) / WEEK) * WEEK;
        if (weekCursor >= lastTokenTime) return 0;
        if (weekCursor < _startTime) weekCursor = _startTime;

        IVotingEscrow.UserPoint memory oldUserPoint;

        for (uint256 i = 0; i < 50; i++) {
            if (weekCursor >= _lastTokenTime) break;

            if (weekCursor >= userPoint.ts && userEpoch <= maxUserEpoch) {
                userEpoch += 1;
                oldUserPoint = userPoint;
                if (userEpoch > maxUserEpoch) {
                    userPoint = IVotingEscrow.UserPoint(0, 0, 0, 0, 0);
                } else {
                    userPoint = IVotingEscrow(_ve).userPointHistory(_tokenId, userEpoch);
                }
            } else {
                int128 dt = int128(int256(weekCursor - oldUserPoint.ts));
                uint256 balance;
                if (oldUserPoint.permanent != 0) {
                    balance = oldUserPoint.permanent;
                } else {
                    balance = uint256(int256(max(oldUserPoint.bias - dt * oldUserPoint.slope, 0)));
                }
                if (balance == 0 && userEpoch > maxUserEpoch) break;
                if (balance != 0) {
                    toDistribute += (balance * tokensPerWeek[weekCursor]) / veSupply[weekCursor];
                }
                weekCursor += WEEK;
            }
        }

        return toDistribute;
    }

    function claimable(uint256 _tokenId) external view returns (uint256) {
        uint256 _lastTokenTime = (lastTokenTime / WEEK) * WEEK;
        return _claimable(_tokenId, _lastTokenTime);
    }

    function claim(uint256 _tokenId) external returns (uint256) {
        uint256 _timestamp = block.timestamp;
        if (_timestamp >= timeCursor) _checkpointTotalSupply();
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

    function claimMany(uint256[] memory _tokenIds) external returns (bool) {
        uint256 _timestamp = block.timestamp;
        if (_timestamp >= timeCursor) _checkpointTotalSupply();
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

    // Once off event on contract initialize
    function setDepositor(address _depositor) external {
        if (msg.sender != depositor) revert NotDepositor();
        depositor = _depositor;
    }

    function max(int128 a, int128 b) internal pure returns (int128) {
        return a > b ? a : b;
    }
}

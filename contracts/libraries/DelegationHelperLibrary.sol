// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";
import {IReward} from "contracts/interfaces/IReward.sol";
import {VelodromeTimeLibrary} from "contracts/libraries/VelodromeTimeLibrary.sol";
import {SafeCastLibrary} from "./SafeCastLibrary.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

library DelegationHelperLibrary {
    uint256 public constant DURATION = 7 days;

    /// Helper function to fetch the checkpoint for the last voting checkpoint prior to a timepoint
    /// Adapted from DelegationLogicLibrary.sol:getPastVotesIndex(uint256 tokenId, uint256 timestamp)
    function getPastCheckpointIndex(
        IVotingEscrow ve,
        uint256 mTokenId,
        uint256 timepoint
    ) internal view returns (uint48) {
        uint48 nCheckpoints = ve.numCheckpoints(mTokenId);
        if (nCheckpoints == 0) return 0;
        // First check most recent balance
        if (ve.checkpoints(mTokenId, nCheckpoints - 1).fromTimestamp <= timepoint) return (nCheckpoints - 1);
        // Next check implicit zero balance
        if (ve.checkpoints(mTokenId, 0).fromTimestamp > timepoint) return 0;

        uint48 lower = 0;
        uint48 upper = nCheckpoints - 1;
        IVotingEscrow.Checkpoint memory cp;
        while (upper > lower) {
            uint48 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            cp = ve.checkpoints(mTokenId, center);
            if (cp.fromTimestamp == timepoint) {
                return center;
            } else if (cp.fromTimestamp < timepoint) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return lower;
    }

    /// Helper function to calculate the locked balance owed to a locked nft at a certain timepoint
    /// It calculates the rewards until the end of the current epoch. As rewards are lagged by one epoch
    /// This means it includes rewards that the user is projected to get in the following epoch.
    /// These rewards are not immediately claimable, but the user can vote as if they claimed it.
    /// Adapted from Reward.sol:earned(address token, uint256 tokenId)
    function earned(
        IVotingEscrow ve,
        uint256 mTokenId,
        uint256 tokenId,
        uint256 timepoint
    ) internal view returns (uint256) {
        IReward lmr = IReward(ve.managedToLocked(mTokenId));
        if (lmr.numCheckpoints(tokenId) == 0) {
            return 0;
        }

        address _rewardToken = ve.token();
        uint256 reward = 0;
        uint256 _supply = 1;
        uint256 _currTs = VelodromeTimeLibrary.epochStart(lmr.lastEarn(_rewardToken, tokenId)); // take epoch last claimed in as starting point
        uint256 _index = lmr.getPriorBalanceIndex(tokenId, _currTs);
        (uint256 _cpTs, uint256 _cpBalanceOf) = lmr.checkpoints(tokenId, _index);

        // accounts for case where lastEarn is before first checkpoint
        _currTs = Math.max(_currTs, VelodromeTimeLibrary.epochStart(_cpTs));

        // get epochs between end of the current epoch and first checkpoint in same epoch as last claim
        uint256 numEpochs = (VelodromeTimeLibrary.epochNext(timepoint) - _currTs) / DURATION;
        uint256 _priorSupply;

        if (numEpochs > 0) {
            for (uint256 i = 0; i < numEpochs; i++) {
                // get index of last checkpoint in this epoch
                _index = lmr.getPriorBalanceIndex(tokenId, _currTs + DURATION - 1);
                // get checkpoint in this epoch
                (_cpTs, _cpBalanceOf) = lmr.checkpoints(tokenId, _index);
                // get supply of last checkpoint in this epoch
                (, _priorSupply) = lmr.supplyCheckpoints(lmr.getPriorSupplyIndex(_currTs + DURATION - 1));
                _supply = Math.max(_priorSupply, 1);
                reward += (_cpBalanceOf * lmr.tokenRewardsPerEpoch(_rewardToken, _currTs)) / _supply;
                _currTs += DURATION;
            }
        }

        return reward;
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IVoter} from "contracts/interfaces/IVoter.sol";
import {IVotingEscrow} from "contracts/interfaces/IVotingEscrow.sol";
import {IReward} from "contracts/interfaces/IReward.sol";
import {IVelo} from "contracts/interfaces/IVelo.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Example Manager contract that works as a relay for users to deposit their veNFTs into
/// @dev In this example, any VELO earned is auto-compounded into the managed locked balance, and
///          all other earned tokens are distributed into free managed rewards for users to claim
/// @dev This contract is like a wrapper which shows how simple it is to trust a manager contract
contract MockManager is Ownable {
    uint256 public ownedManagedTokenId;
    IVoter public voter;
    IVotingEscrow public ve;
    IVelo public velo;

    constructor(address _voter) {
        voter = IVoter(_voter);
        ve = IVotingEscrow(voter.ve());
        velo = IVelo(ve.token());
    }

    function createManagedLock() external {
        require(ownedManagedTokenId == 0, "Already called");
        ownedManagedTokenId = ve.createManagedLockFor(address(this));
    }

    function vote(address[] calldata _poolVote, uint256[] calldata _weights) external onlyOwner {
        voter.vote(ownedManagedTokenId, _poolVote, _weights);
    }

    function claimRewards(address[] memory _gauges) external {
        voter.claimRewards(_gauges);

        // deposit VELO to LockedManagedRewards if possible
        uint256 balance = velo.balanceOf(address(this));
        if (balance > 0) {
            ve.increaseAmount(ownedManagedTokenId, balance);
        }
    }

    function claimBribes(address[] memory _bribes, address[][] memory _tokens) external {
        voter.claimBribes(_bribes, _tokens, ownedManagedTokenId);

        // deposit VELO to FreeManagedRewards if possible
        uint256 balance = velo.balanceOf(address(this));
        if (balance > 0) {
            IReward(ve.managedToFree(ownedManagedTokenId)).notifyRewardAmount(address(velo), balance);
        }
    }

    function claimFees(address[] memory _fees, address[][] memory _tokens) external {
        voter.claimFees(_fees, _tokens, ownedManagedTokenId);

        // deposit VELO to FreeManagedRewards if possible
        uint256 balance = velo.balanceOf(address(this));
        if (balance > 0) {
            IReward(ve.managedToFree(ownedManagedTokenId)).notifyRewardAmount(address(velo), balance);
        }
    }

    /// @notice add token rewards to FreeManagedRewards if earned from bribes / fees
    /// @dev VELO is already distributed when possible
    /// @param _token address of token sent to FreeManagedRewards
    function notifyRewardAmount(address _token) external {
        require(_token != address(velo), "Cannot reward VELO to FreeManagedRewards");
        uint256 balance = IERC20(_token).balanceOf(address(this));
        if (balance > 0) {
            IReward(ve.managedToFree(ownedManagedTokenId)).notifyRewardAmount(_token, balance);
        }
    }
}

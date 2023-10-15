// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";
import {IVotes} from "./IVotes.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {GovernorSimple} from "./GovernorSimple.sol";
import {IVotingEscrow} from "contracts/interfaces/IVotingEscrow.sol";
import {DelegationHelperLibrary} from "contracts/libraries/DelegationHelperLibrary.sol";

/**
 * @dev Modified lightly from OpenZeppelin's GovernorVotes
 */
abstract contract GovernorSimpleVotes is GovernorSimple {
    using DelegationHelperLibrary for IVotingEscrow;

    IVotes public immutable token;
    IVotingEscrow public immutable ve;

    constructor(IVotes tokenAddress) {
        token = IVotes(address(tokenAddress));
        ve = IVotingEscrow(address(token));
    }

    /**
     * @dev Clock (as specified in EIP-6372) is set to match the token's clock. Fallback to block numbers if the token
     * does not implement EIP-6372.
     */
    function clock() public view virtual override returns (uint48) {
        try IERC6372(address(token)).clock() returns (uint48 timepoint) {
            return timepoint;
        } catch {
            return SafeCast.toUint48(block.number);
        }
    }

    /**
     * @dev Machine-readable description of the clock as specified in EIP-6372.
     */
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public view virtual override returns (string memory) {
        try IERC6372(address(token)).CLOCK_MODE() returns (string memory clockmode) {
            return clockmode;
        } catch {
            return "mode=blocknumber&from=default";
        }
    }

    /**
     * Read the voting weight from the token's built in snapshot mechanism (see {Governor-_getVotes}).
     */
    function _getVotes(
        address account,
        uint256 tokenId,
        uint256 timepoint,
        bytes memory /*params*/
    ) internal view virtual override returns (uint256) {
        IVotingEscrow.EscrowType escrowType = ve.escrowType(tokenId);
        require(escrowType != IVotingEscrow.EscrowType.MANAGED, "EpochGovernor: managed nft cannot vote");

        if (escrowType == IVotingEscrow.EscrowType.NORMAL) {
            return token.getPastVotes(account, tokenId, timepoint);
        }

        // only allow locked veNFT voting if underlying nft not delegating at timepoint
        uint256 mTokenId = ve.idToManaged(tokenId);
        uint48 index = ve.getPastCheckpointIndex(mTokenId, timepoint);
        uint256 delegatee = ve.checkpoints(mTokenId, index).delegatee;
        if (delegatee == 0) {
            // if mveNFT not delegating, voting balance = delegated balance +
            // initial contribution to mveNFT + accrued locked rewards
            uint256 delegatedBalance = token.getPastVotes(account, tokenId, timepoint);
            uint256 weight = ve.weights(tokenId, mTokenId); // initial deposit weight
            uint256 _earned = ve.earned(mTokenId, tokenId, timepoint); // accrued rewards
            return weight + _earned + delegatedBalance;
        }

        // nft locked and underlying nft delegating
        // balance will only be delegated balance
        return token.getPastVotes(account, tokenId, timepoint);
    }

    function getVotes(uint256 tokenId, uint256 timepoint) external view returns (uint256) {
        address account = ve.ownerOf(tokenId);
        return _getVotes(account, tokenId, timepoint, "");
    }
}

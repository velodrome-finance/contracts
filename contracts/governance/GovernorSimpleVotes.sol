// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";
import {IERC5805} from "@openzeppelin/contracts/interfaces/IERC5805.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

import {IVotes} from "./IVotes.sol";
import {GovernorSimple} from "./GovernorSimple.sol";
import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";

/**
 * @dev Modified lightly from OpenZeppelin's GovernorVotes
 */
abstract contract GovernorSimpleVotes is GovernorSimple {
    IERC5805 private immutable _token;
    IVotingEscrow public immutable ve;

    constructor(IVotes _tokenAddress) {
        _token = IERC5805(address(_tokenAddress));
        ve = IVotingEscrow(address(_token));
    }

    /**
     * @dev The token that voting power is sourced from.
     */
    function token() public view virtual returns (IERC5805) {
        return _token;
    }

    /**
     * @dev Clock (as specified in ERC-6372) is set to match the token's clock. Fallback to block numbers if the token
     * does not implement ERC-6372.
     */
    function clock() public view virtual override returns (uint48) {
        try token().clock() returns (uint48 timepoint) {
            return timepoint;
        } catch {
            return Time.blockNumber();
        }
    }

    /**
     * @dev Machine-readable description of the clock as specified in ERC-6372.
     */
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public view virtual override returns (string memory) {
        try token().CLOCK_MODE() returns (string memory clockmode) {
            return clockmode;
        } catch {
            return "mode=blocknumber&from=default";
        }
    }

    /**
     * Read the voting weight from the token's built in snapshot mechanism (see {Governor-_getVotes}).
     */
    function _getVotes(address _account, uint256 _tokenId, uint256 _timepoint, bytes memory /*_params*/ )
        internal
        view
        virtual
        override
        returns (uint256)
    {
        return ve.getPastVotes({account: _account, tokenId: _tokenId, timestamp: _timepoint});
    }

    function getVotes(uint256 _tokenId, uint256 _timepoint) external view returns (uint256) {
        address account = ve.ownerOf({tokenId: _tokenId});
        return _getVotes(account, _tokenId, _timepoint, "");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {GovernorSimple} from "./GovernorSimple.sol";

/**
 * @dev Modified lightly from OpenZeppelin's GovernorVotes
 */
abstract contract GovernorSimpleVotes is GovernorSimple {
    IVotes public immutable token;

    constructor(IVotes tokenAddress) {
        token = tokenAddress;
    }

    /**
     * Read the voting weight from the token's built in snapshot mechanism (see {Governor-_getVotes}).
     */
    function _getVotes(
        address account,
        uint256 blockNumber,
        bytes memory /*params*/
    ) internal view virtual override returns (uint256) {
        return token.getPastVotes(account, blockNumber);
    }
}

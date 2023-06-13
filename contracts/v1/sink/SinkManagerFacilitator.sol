// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IVotingEscrowV1} from "../../interfaces/v1/IVotingEscrowV1.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

/// @notice This contract is used to support merging into the Velodrome SinkManager
contract SinkManagerFacilitator is ERC721Holder {
    constructor() {}

    function merge(IVotingEscrowV1 _ve, uint256 _from, uint256 _to) external {
        _ve.merge(_from, _to);
    }
}

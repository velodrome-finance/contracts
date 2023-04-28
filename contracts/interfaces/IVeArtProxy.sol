// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IVeArtProxy {
    function tokenURI(uint256 _tokenId) external view returns (string memory output);
}

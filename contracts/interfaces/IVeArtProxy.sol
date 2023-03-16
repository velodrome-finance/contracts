pragma solidity 0.8.13;

interface IVeArtProxy {
    function tokenURI(uint256 _tokenId) external view returns (string memory output);
}

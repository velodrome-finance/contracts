// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRewardsDistributorV1 {
    function claimable(uint256 _tokenId) external view returns (uint256 _claimable);

    function claim(uint256 _tokenId) external returns (uint256 _amount);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAutoCompounder {
    error AlreadyInitialized();
    error InvalidPath();
    error NotFactory();
    error TokenIdAlreadySet();

    event RewardAndCompound(uint256 _tokenId, address _claimer, uint256 balanceRewarded, uint256 balanceCompounded);
    event SetRoute(address _from);
    event SetTokenId(uint256 _tokenId);
}

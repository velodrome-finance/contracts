// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IGaugeV1 {
    function balanceOf(address _account) external returns (uint256 _balance);

    function stake() external returns (address _stake);

    function totalSupply() external returns (uint256 _totalSupply);

    function getReward(address _account, address[] memory _tokens) external;

    function deposit(uint256 _amount, uint256 _tokenId) external;

    function notifyRewardAmount(address _token, uint256 _amount) external;
}

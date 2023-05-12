// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IVoterV1 {
    function governor() external returns (address _governor);

    function totalWeight() external returns (uint256 _totalWeight);

    function usedWeights(uint256 _tokenId) external returns (uint256 _weight);

    function votes(uint256 _tokenId, address _pool) external returns (uint256 _votes);

    function createGauge(address _pool) external returns (address _gauge);

    function gauges(address pool) external view returns (address);

    function distribute(address _gauge) external;

    function poke(uint256 _tokenId) external;

    function vote(uint256 _tokenId, address[] memory _pools, uint256[] memory _weights) external;
}

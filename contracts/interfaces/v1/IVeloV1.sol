// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IVeloV1 {
    function createGauge(address _pool) external returns (address _gauge);

    function totalWeight() external returns (uint256 _totalWeight);

    function usedWeights(uint256 _tokenId) external returns (uint256 _weight);

    function votes(uint256 _tokenId, address _pool) external returns (uint256 _votes);

    function distribute(address _gauge) external;

    function governor() external returns (address _governor);
}

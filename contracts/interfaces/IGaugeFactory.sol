pragma solidity 0.8.13;

interface IGaugeFactory {
    function createGauge(
        address _forwarder,
        address _pool,
        address _feesVotingReward,
        address _ve,
        bool isPair
    ) external returns (address);
}

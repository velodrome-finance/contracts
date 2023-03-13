pragma solidity 0.8.13;

interface IPairFactory {
    event PairCreated(address indexed token0, address indexed token1, bool stable, address pair, uint256);
    event SetCustomFee(address pair, uint256 fee);

    /// @notice returns the number of pairs created from this factory
    function allPairsLength() external view returns (uint256);

    /// @notice Is a valid pair created by this factory.
    /// @param .
    function isPair(address pair) external view returns (bool);

    /// @dev Only called once to set to Voter.sol - Voter does not have a function
    ///      to call this contract method, so once set it's immutable.
    ///      This also follows convention of setVoterAndDistributor() in VotingEscrow.sol
    /// @param _voter .
    function setVoter(address _voter) external;

    function setSinkConverter(
        address _sinkConvert,
        address _velo,
        address _veloV2
    ) external;

    function setPauser(address _pauser) external;

    function setPauseState(bool _state) external;

    function setFeeManager(address _feeManager) external;

    /// @notice Set default fee for stable and volatile pairs.
    /// @dev Throws if higher than maximum fee.
    ///      Throws if fee is zero.
    /// @param _stable Stable or volatile pair.
    /// @param _fee .
    function setFee(bool _stable, uint256 _fee) external;

    /// @notice Set overriding fee for a pair from the default
    /// @dev A custom fee of zero means the default fee will be used.
    function setCustomFee(address _pair, uint256 _fee) external;

    /// @notice Returns fee for a pair, as custom fees are possible.
    function getFee(address _pair, bool _stable) external view returns (uint256);

    function getPair(
        address tokenA,
        address token,
        bool stable
    ) external view returns (address);

    function createPair(
        address tokenA,
        address tokenB,
        bool stable
    ) external returns (address pair);

    function isPaused() external view returns (bool);

    function velo() external view returns (address);

    function veloV2() external view returns (address);

    function voter() external view returns (address);

    function sinkConverter() external view returns (address);

    function implementation() external view returns (address);
}

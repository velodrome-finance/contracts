// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IRouter} from "./IRouter.sol";

interface IAutoCompounder {
    error AlreadyInitialized();
    error AmountInTooHigh();
    error AmountInZero();
    error InvalidPath();
    error NotFactory();
    error NotKeeper();
    error SlippageTooHigh();
    error TokenIdAlreadySet();
    error TooSoon();
    error UnequalLengths();

    event RewardAndCompound(
        address indexed claimer,
        uint256 indexed tokenId,
        bool isCalledByKeeper,
        uint256 balanceRewarded,
        uint256 balanceCompounded
    );
    event SwapTokenToVELO(
        address indexed claimer,
        address indexed token,
        uint256 amountIn,
        uint256 amountOut,
        IRouter.Route[] routes
    );
    event SwapTokenToVELOKeeper(
        address indexed claimer,
        address indexed token,
        uint256 amountIn,
        uint256 amountOut,
        IRouter.Route[] routes
    );

    /// @notice Claim rebases by the RewardsDistributor and earned bribes earned by the managed tokenId and
    ///             compound by swapping to VELO, rewarding the caller, and depositing into the managed veNFT.
    ///         Publicly callable in the final 24 hours before the epoch flip.
    ///         Swapping is done through the optimal route determined from CompoundOptimizer by swapping the entire balance
    /// @dev Slippage values cannot exceed 500 (equivalent to 5%)
    /// @param _bribes          Addresses of BribeVotingRewards contracts
    /// @param _tokens          Array of array for which tokens to cleam for each BribeVotingRewards contract
    /// @param _tokensToSwap    Addresses of tokens to convert into VELO
    /// @param _slippages       Amount of slippage per token to swap, in basis points
    function claimBribesAndCompound(
        address[] calldata _bribes,
        address[][] calldata _tokens,
        address[] calldata _tokensToSwap,
        uint256[] calldata _slippages
    ) external;

    /// @notice Same as claimBribesAndCompound() but for FeesVotingRewards contracts
    /// @param _fees .
    /// @param _tokens .
    /// @param _tokensToSwap .
    /// @param _slippages .
    function claimFeesAndCompound(
        address[] calldata _fees,
        address[][] calldata _tokens,
        address[] calldata _tokensToSwap,
        uint256[] calldata _slippages
    ) external;

    /// @notice Swap tokens held by the autoCompounder into VELO using the optimal route determined by
    ///             the CompoundOptimizer
    ///         Publicly callable in the final 24 hours before the epoch flip
    /// @param _tokensToSwap .
    /// @param _slippages .
    function swapTokensToVELOAndCompound(address[] memory _tokensToSwap, uint256[] memory _slippages) external;

    /// @notice Additional functionality for ALLOWED_CALLER to deposit more VELO into the managed tokenId.
    ///         This is effectively a bribe bonus for users that deposited into the autocompounder.
    function increaseAmount(uint256 _value) external;

    /// @notice Vote for Velodrome pools with the given weights.
    ///         Only callable by ALLOWED_CALLER.
    /// @dev Refer to IVoter.vote()
    function vote(address[] calldata _poolVote, uint256[] calldata _weights) external;

    /// @notice Claim rebases by the RewardsDistributor and earned bribes earned by the managed tokenId and
    ///             compound by swapping to VELO and depositing into the managed veNFT.
    ///         Only callable by keepers added by VotingEscrow.team() within AutoCompounderFactory.
    ///         Swapping is done with routes and amounts swapped determined by the keeper.
    /// @dev _amountsIn and _amountsOutMin cannot be 0.
    /// @param _bribes          Addresses of BribeVotingRewards contracts
    /// @param _tokens          Array of arrays for which tokens to claim for each BribeVotingRewards contract
    /// @param _allRoutes       Array of arrays for which swap routes to execute
    /// @param _amountsIn       Amount of token in for each swap route
    /// @param _amountsOutMin   Minimum amount of token received for each swap route
    function claimBribesAndCompoundKeeper(
        address[] calldata _bribes,
        address[][] calldata _tokens,
        IRouter.Route[][] calldata _allRoutes,
        uint256[] calldata _amountsIn,
        uint256[] calldata _amountsOutMin
    ) external;

    /// @notice Same as claimFeesAndCompoundKeeper() but for FeesVotingRewards contracts
    /// @param _fees .
    /// @param _tokens .
    /// @param _allRoutes .
    /// @param _amountsIn .
    /// @param _amountsOutMin .
    function claimFeesAndCompoundKeeper(
        address[] calldata _fees,
        address[][] calldata _tokens,
        IRouter.Route[][] calldata _allRoutes,
        uint256[] calldata _amountsIn,
        uint256[] calldata _amountsOutMin
    ) external;

    /// @notice Convert tokens held by the autoCompounder into VELO using routes given by the caller and deposit
    ///             into the managed tokenId.
    ///         Only callable by keepers added by VotingEscrow.team() within AutoCompounderFactory.
    /// @param _allRoutes       Array of arrays for which swap routes to execute
    /// @param _amountsIn       Amount of token in for each swap route
    /// @param _amountsOutMin   Minimum amount of token received for each swap route
    /// @dev _amountsIn and _amountsOutMin cannot be 0.
    function swapTokensToVELOAndCompoundKeeper(
        IRouter.Route[][] calldata _allRoutes,
        uint256[] calldata _amountsIn,
        uint256[] calldata _amountsOutMin
    ) external;
}

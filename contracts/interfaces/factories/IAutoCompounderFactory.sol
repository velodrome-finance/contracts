// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAutoCompounderFactory {
    error AmountOutOfAcceptableRange();
    error AmountSame();
    error NotTeam();
    error HighLiquidityTokenAlreadyExists();
    error KeeperAlreadyExists();
    error KeeperDoesNotExist();
    error TokenIdNotApproved();
    error TokenIdNotManaged();
    error TokenIdZero();
    error ZeroAddress();

    event AddKeeper(address indexed _keeper);
    event AddHighLiquidityToken(address indexed _token);
    event CreateAutoCompounder(address indexed _from, address indexed _admin, address indexed _autoCompounder);
    event RemoveKeeper(address indexed _keeper);
    event SetRewardAmount(uint256 _rewardAmount);

    /// @notice Maximum fixed VELO reward rate from calling AutoCompounder.claimXAndCompound()
    ///         Set to 1,000 VELO
    function MAX_REWARD_AMOUNT() external view returns (uint256);

    /// @notice Minimum fixed VELO reward rate from calling AutoCompounder.claimXAndCompound()
    ///         Set to 0.1 VELO
    function MIN_REWARD_AMOUNT() external view returns (uint256);

    /// @notice The amount rewarded per token a caller earns from calling AutoCompounder.claimXAndCompound()
    function rewardAmount() external view returns (uint256);

    /// @notice Create an AutoCompounder for a (m)veNFT
    /// @param _admin Admin address to set slippage tolerance / manage ALLOWED_CALLER
    /// @param _tokenId .
    function createAutoCompounder(address _admin, uint256 _tokenId) external returns (address autoCompounder);

    /// @notice Set the amount of VELO to reward a public caller of `AutoCompounder.claimXAndCompound()`
    ///         Callable by FactoryRegistry.owner()
    /// @param _rewardAmount Amount of VELO
    function setRewardAmount(uint256 _rewardAmount) external;

    /// @notice Register a token address with high liquidity
    ///         Callable by FactoryRegistry.owner()
    /// @dev Once an address is added, it cannot be removed
    /// @param _token Address of token to register
    function addHighLiquidityToken(address _token) external;

    /// @notice View if an address is registered as a high liquidity token
    ///         This indicates a token has significant liquidity to swap route into VELO
    ///         If a token address returns true, it cannot be swept from an AutoCompounder
    /// @param _token Address of token to query
    /// @return True if token is registered as a high liquidity token, else false
    function isHighLiquidityToken(address _token) external view returns (bool);

    /// @notice View for all registered high liquidity tokens
    /// @return Array of high liquidity tokens
    function highLiquidityTokens() external view returns (address[] memory);

    /// @notice Get the count of registered high liquidity tokens
    /// @return Count of registered high liquidity tokens
    function highLiquidityTokensLength() external view returns (uint256);

    /// @notice Add an authorized keeper to call `AutoCompounder.claimXAndCompoundKeeper()`
    ///         Callable by FactoryRegistry.owner()
    /// @param _keeper Address of keeper to approve
    function addKeeper(address _keeper) external;

    /// @notice Remove an authorized keeper from calling `AutoCompounder.claimXAndCompoundKeeper()`
    ///         Callable by FactoryRegistry.owner()
    /// @param _keeper Address of keeper to remove
    function removeKeeper(address _keeper) external;

    /// @notice View if an address is an approved keeper
    /// @param _keeper Address of keeper queried
    /// @return True if keeper, else false
    function isKeeper(address _keeper) external view returns (bool);

    /// @notice View for all approved keepers
    /// @return Array of keepers
    function keepers() external view returns (address[] memory);

    /// @notice Get the count of approved keepers
    /// @return Count of approved keepers
    function keepersLength() external view returns (uint256);

    /// @notice View for all created AutoCompounders
    /// @return Array of AutoCompounders
    function autoCompounders() external view returns (address[] memory);

    /// @notice Get the count of created AutoCompounders
    /// @return Count of created AutoCompounders
    function autoCompoundersLength() external view returns (uint256);

    /// @notice View for an address is an AutoCompounder contract created by this factory
    /// @param _autoCompounder Address of AutoCompounder queried
    /// @return True if AutoCompounder, else false
    function isAutoCompounder(address _autoCompounder) external view returns (bool);
}

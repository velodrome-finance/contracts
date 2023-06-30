// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {ICompoundOptimizer} from "./interfaces/ICompoundOptimizer.sol";
import {IRouter} from "./interfaces/IRouter.sol";
import {IAutoCompounder} from "./interfaces/IAutoCompounder.sol";
import {IAutoCompounderFactory} from "./interfaces/factories/IAutoCompounderFactory.sol";
import {IVelo} from "./interfaces/IVelo.sol";
import {IVoter} from "./interfaces/IVoter.sol";
import {IVotingEscrow} from "./interfaces/IVotingEscrow.sol";
import {IRewardsDistributor} from "./interfaces/IRewardsDistributor.sol";
import {IRouter} from "./interfaces/IRouter.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

/// @title Velodrome AutoCompounder for Managed veNFTs
/// @author velodrome.finance, @figs999, @pegahcarter
/// @notice Auto-Compound voting rewards earned from a Managed veNFT back into the veNFT through call incentivization
contract AutoCompounder is IAutoCompounder, ERC721Holder, ERC2771Context, ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;
    bytes32 public constant ALLOWED_CALLER = keccak256("ALLOWED_CALLER");
    uint256 internal constant WEEK = 7 days;
    uint256 public constant MAX_SLIPPAGE = 500;
    uint256 public constant POINTS = 3;

    address public immutable factory;
    IRouter public immutable router;
    IVoter public immutable voter;
    IVotingEscrow public immutable ve;
    IVelo public immutable velo;
    IRewardsDistributor public immutable distributor;
    ICompoundOptimizer public immutable optimizer;

    uint256 public tokenId;

    constructor(
        address _forwarder,
        address _router,
        address _voter,
        address _optimizer,
        address _admin
    ) ERC2771Context(_forwarder) {
        factory = _msgSender();
        router = IRouter(_router);
        voter = IVoter(_voter);
        optimizer = ICompoundOptimizer(_optimizer);

        ve = IVotingEscrow(voter.ve());
        velo = IVelo(ve.token());
        distributor = IRewardsDistributor(ve.distributor());

        // max approval is safe because of the immutability of ve.
        // This approval is only ever utilized from ve.increaseAmount() calls.
        velo.approve(address(ve), type(uint256).max);

        // Default admin can grant/revoke ALLOWED_CALLER roles
        // See `ALLOWED_CALLER functions` section for permissions
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ALLOWED_CALLER, _admin);
    }

    /// @dev Called within the creation transaction
    function initialize(uint256 _tokenId) external {
        if (_msgSender() != factory) revert NotFactory();
        if (tokenId != 0) revert AlreadyInitialized();

        tokenId = _tokenId;
    }

    /// @dev Validate timestamp is within the final 24 hours before the epoch flip
    modifier onLastDayOfEpoch(uint256 timestamp) {
        uint256 lastDayStart = timestamp - (timestamp % WEEK) + WEEK - 1 days;
        if (timestamp < lastDayStart) revert TooSoon();
        _;
    }

    /// @dev Validate msg.sender is a keeper added by Velodrome team
    modifier onlyKeeper(address sender) {
        if (!IAutoCompounderFactory(factory).isKeeper(sender)) revert NotKeeper();
        _;
    }

    // -------------------------------------------------
    // Public functions
    // -------------------------------------------------

    /// @inheritdoc IAutoCompounder
    function claimBribesAndCompound(
        address[] calldata _bribes,
        address[][] calldata _tokens,
        address[] calldata _tokensToSwap,
        uint256[] calldata _slippages
    ) external onLastDayOfEpoch(block.timestamp) {
        voter.claimBribes(_bribes, _tokens, tokenId);
        swapTokensToVELOAndCompound(_tokensToSwap, _slippages);
    }

    /// @inheritdoc IAutoCompounder
    function claimFeesAndCompound(
        address[] calldata _fees,
        address[][] calldata _tokens,
        address[] calldata _tokensToSwap,
        uint256[] calldata _slippages
    ) external onLastDayOfEpoch(block.timestamp) {
        voter.claimFees(_fees, _tokens, tokenId);
        swapTokensToVELOAndCompound(_tokensToSwap, _slippages);
    }

    /// @inheritdoc IAutoCompounder
    function swapTokensToVELOAndCompound(
        address[] memory _tokensToSwap,
        uint256[] memory _slippages
    ) public nonReentrant onLastDayOfEpoch(block.timestamp) {
        uint256 length = _tokensToSwap.length;
        if (length != _slippages.length) revert UnequalLengths();

        for (uint256 i = 0; i < _tokensToSwap.length; i++) {
            uint256 slippage = _slippages[i];
            if (slippage > MAX_SLIPPAGE) revert SlippageTooHigh();
            address token = _tokensToSwap[i];
            if (token == address(velo)) continue; // Do not need to swap from velo => velo
            uint256 balance = IERC20(token).balanceOf(address(this));
            if (balance == 0) revert AmountInZero();

            IRouter.Route[] memory routes = optimizer.getOptimalTokenToVeloRoute(token, balance);
            uint256 amountOutMin = optimizer.getOptimalAmountOutMin(routes, balance, POINTS, slippage);

            // swap
            _handleRouterApproval(IERC20(token), balance);
            uint256[] memory amountsOut = router.swapExactTokensForTokens(
                balance,
                amountOutMin,
                routes,
                address(this),
                block.timestamp
            );

            emit SwapTokenToVELO(_msgSender(), token, balance, amountsOut[amountsOut.length - 1], routes);
        }
        _rewardAndCompound();
    }

    // -------------------------------------------------
    // ALLOWED_CALLER functions
    // -------------------------------------------------

    /// @inheritdoc IAutoCompounder
    function increaseAmount(uint256 _value) external onlyRole(ALLOWED_CALLER) {
        velo.transferFrom(_msgSender(), address(this), _value);
        ve.increaseAmount(tokenId, _value);
    }

    /// @inheritdoc IAutoCompounder
    function vote(address[] calldata _poolVote, uint256[] calldata _weights) external onlyRole(ALLOWED_CALLER) {
        voter.vote(tokenId, _poolVote, _weights);
    }

    // -------------------------------------------------
    // Keeper functions
    // -------------------------------------------------

    // TODO: events
    /// @inheritdoc IAutoCompounder
    function claimBribesAndCompoundKeeper(
        address[] calldata _bribes,
        address[][] calldata _tokens,
        IRouter.Route[][] calldata _allRoutes,
        uint256[] calldata _amountsIn,
        uint256[] calldata _amountsOutMin
    ) external onlyKeeper(msg.sender) nonReentrant {
        voter.claimBribes(_bribes, _tokens, tokenId);
        _swapTokensToVELOAndCompoundKeeper(_allRoutes, _amountsIn, _amountsOutMin);
    }

    // TODO: events
    /// @inheritdoc IAutoCompounder
    function claimFeesAndCompoundKeeper(
        address[] calldata _fees,
        address[][] calldata _tokens,
        IRouter.Route[][] calldata _allRoutes,
        uint256[] calldata _amountsIn,
        uint256[] calldata _amountsOutMin
    ) external onlyKeeper(msg.sender) nonReentrant {
        voter.claimFees(_fees, _tokens, tokenId);
        _swapTokensToVELOAndCompoundKeeper(_allRoutes, _amountsIn, _amountsOutMin);
    }

    /// @inheritdoc IAutoCompounder
    function swapTokensToVELOAndCompoundKeeper(
        IRouter.Route[][] calldata _allRoutes,
        uint256[] calldata _amountsIn,
        uint256[] calldata _amountsOutMin
    ) external onlyKeeper(msg.sender) nonReentrant {
        _swapTokensToVELOAndCompoundKeeper(_allRoutes, _amountsIn, _amountsOutMin);
    }

    function _swapTokensToVELOAndCompoundKeeper(
        IRouter.Route[][] memory _allRoutes,
        uint256[] memory _amountsIn,
        uint256[] memory _amountsOutMin
    ) internal {
        uint256 length = _allRoutes.length;
        if (length != _amountsIn.length || length != _amountsOutMin.length) revert UnequalLengths();

        for (uint256 i = 0; i < length; i++) {
            _swapTokenToVELOKeeper(_allRoutes[i], _amountsIn[i], _amountsOutMin[i]);
        }

        _rewardAndCompound();
    }

    function _swapTokenToVELOKeeper(IRouter.Route[] memory routes, uint256 amountIn, uint256 amountOutMin) internal {
        if (amountIn == 0) revert AmountInZero();
        if (amountOutMin == 0) revert SlippageTooHigh();
        if (routes[routes.length - 1].to != address(velo)) revert InvalidPath();
        address from = routes[0].from;
        if (from == address(velo)) revert InvalidPath();

        uint256 balance = IERC20(from).balanceOf(address(this));
        if (amountIn > balance) revert AmountInTooHigh();

        _handleRouterApproval(IERC20(from), amountIn);
        uint256[] memory amountsOut = router.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            routes,
            address(this),
            block.timestamp
        );

        emit SwapTokenToVELOKeeper(_msgSender(), from, amountIn, amountsOut[amountsOut.length - 1], routes);
    }

    // -------------------------------------------------
    // Helpers
    // -------------------------------------------------

    /// @dev Claim any rebase by the RewardsDistributor, reward the caller if publicly called, and deposit VELO
    ///          into the managed veNFT.
    function _rewardAndCompound() internal {
        address sender = _msgSender();
        bool isCalledByKeeper = IAutoCompounderFactory(factory).isKeeper(sender);
        uint256 balance = velo.balanceOf(address(this));
        uint256 _tokenId = tokenId;
        uint256 reward;

        // claim rebase if possible
        if (distributor.claimable(tokenId) > 0) {
            distributor.claim(tokenId);
        }

        if (balance > 0) {
            // reward callers if they are not a keeper
            if (!isCalledByKeeper) {
                // reward the caller the minimum of:
                // - 1% of the VELO designated for compounding
                // - The constant VELO reward set by team in AutoCompounderFactory
                uint256 compoundRewardAmount = balance / 100;
                uint256 factoryRewardAmount = IAutoCompounderFactory(factory).rewardAmount();
                reward = compoundRewardAmount < factoryRewardAmount ? compoundRewardAmount : factoryRewardAmount;

                if (reward > 0) {
                    velo.transfer(sender, reward);
                    balance -= reward;
                }
            }

            // Deposit the remaining balance into the nft
            ve.increaseAmount(_tokenId, balance);
        }

        emit RewardAndCompound(sender, _tokenId, isCalledByKeeper, reward, balance);
    }

    /// @dev resets approval if needed then approves transfer of tokens to router
    function _handleRouterApproval(IERC20 token, uint256 amount) internal {
        uint256 allowance = token.allowance(address(this), address(router));
        if (allowance > 0) token.safeDecreaseAllowance(address(router), allowance);
        token.safeIncreaseAllowance(address(router), amount);
    }

    // -------------------------------------------------
    // Overrides
    // -------------------------------------------------

    function _msgData() internal view override(ERC2771Context, Context) returns (bytes calldata) {
        return ERC2771Context._msgData();
    }

    function _msgSender() internal view override(ERC2771Context, Context) returns (address) {
        return ERC2771Context._msgSender();
    }
}

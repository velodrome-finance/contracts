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

    IAutoCompounderFactory public immutable autoCompounderFactory;
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
        autoCompounderFactory = IAutoCompounderFactory(_msgSender());
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
        if (_msgSender() != address(autoCompounderFactory)) revert NotFactory();
        if (tokenId != 0) revert AlreadyInitialized();

        tokenId = _tokenId;
    }

    /// @dev Validate timestamp is within the final 24 hours before the epoch flip
    modifier onlyLastDayOfEpoch() {
        uint256 timestamp = block.timestamp;
        uint256 lastDayStart = timestamp - (timestamp % WEEK) + WEEK - 1 days;
        if (timestamp < lastDayStart) revert TooSoon();
        _;
    }

    modifier onlyFirstDayOfEpoch(bool _yes) {
        uint256 timestamp = block.timestamp;
        uint256 firstDayEnd = timestamp - (timestamp % WEEK) + 1 days;
        if (_yes) {
            if (timestamp >= firstDayEnd) revert TooLate();
        } else {
            if (timestamp < firstDayEnd) revert TooSoon();
        }
        _;
    }

    /// @dev Validate msg.sender is a keeper added by Velodrome team.
    ///      Can only call permissioned functions 1 day after epoch flip
    modifier onlyKeeper(address _sender) {
        if (!autoCompounderFactory.isKeeper(_sender)) revert NotKeeper();
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
    ) external {
        IRouter.Route[][] memory optionalRoutes = new IRouter.Route[][](_tokensToSwap.length);
        claimBribesAndCompound(_bribes, _tokens, _tokensToSwap, optionalRoutes, _slippages);
    }

    /// @inheritdoc IAutoCompounder
    function claimBribesAndCompound(
        address[] memory _bribes,
        address[][] memory _tokens,
        address[] memory _tokensToSwap,
        IRouter.Route[][] memory _optionalRoutes,
        uint256[] memory _slippages
    ) public onlyLastDayOfEpoch {
        voter.claimBribes(_bribes, _tokens, tokenId);
        swapTokensToVELOAndCompound(_tokensToSwap, _optionalRoutes, _slippages);
    }

    /// @inheritdoc IAutoCompounder
    function claimFeesAndCompound(
        address[] calldata _fees,
        address[][] calldata _tokens,
        address[] calldata _tokensToSwap,
        uint256[] calldata _slippages
    ) external {
        IRouter.Route[][] memory optionalRoutes = new IRouter.Route[][](_tokensToSwap.length);
        claimFeesAndCompound(_fees, _tokens, _tokensToSwap, optionalRoutes, _slippages);
    }

    /// @inheritdoc IAutoCompounder
    function claimFeesAndCompound(
        address[] memory _fees,
        address[][] memory _tokens,
        address[] memory _tokensToSwap,
        IRouter.Route[][] memory _optionalRoutes,
        uint256[] memory _slippages
    ) public onlyLastDayOfEpoch {
        voter.claimFees(_fees, _tokens, tokenId);
        swapTokensToVELOAndCompound(_tokensToSwap, _optionalRoutes, _slippages);
    }

    /// @inheritdoc IAutoCompounder
    function swapTokensToVELOAndCompound(address[] calldata _tokensToSwap, uint256[] calldata _slippages) external {
        IRouter.Route[][] memory optionalRoutes = new IRouter.Route[][](_tokensToSwap.length);
        swapTokensToVELOAndCompound(_tokensToSwap, optionalRoutes, _slippages);
    }

    /// @inheritdoc IAutoCompounder
    function swapTokensToVELOAndCompound(
        address[] memory _tokensToSwap,
        IRouter.Route[][] memory _optionalRoutes,
        uint256[] memory _slippages
    ) public nonReentrant onlyLastDayOfEpoch {
        uint256 length = _tokensToSwap.length;
        if (length != _optionalRoutes.length || length != _slippages.length) revert UnequalLengths();

        for (uint256 i = 0; i < _tokensToSwap.length; i++) {
            uint256 slippage = _slippages[i];
            if (slippage > MAX_SLIPPAGE) revert SlippageTooHigh();
            address token = _tokensToSwap[i];
            if (token == address(velo)) continue; // Do not need to swap from velo => velo
            uint256 balance = IERC20(token).balanceOf(address(this));
            if (balance == 0) revert AmountInZero();

            IRouter.Route[] memory routes = optimizer.getOptimalTokenToVeloRoute(token, balance);
            uint256 amountOutMin = optimizer.getOptimalAmountOutMin(routes, balance, POINTS, slippage);

            // If an optional route was provided, compare the amountOut with the hardcoded optimizer amountOut to determine which
            // route has a better rate
            // Used if optional route is not direct token => VELO as this route is already calculated by CompoundOptimizer
            IRouter.Route[] memory optionalRoutes = _optionalRoutes[i];
            uint256 optionalRoutesLen = optionalRoutes.length;
            if (optionalRoutesLen > 1) {
                if (optionalRoutes[0].from != token) revert InvalidPath();
                if (optionalRoutes[optionalRoutesLen - 1].to != address(velo)) revert InvalidPath();
                // Ensure route only uses high liquidity tokens
                for (uint256 x = 1; x < optionalRoutesLen; x++) {
                    if (!autoCompounderFactory.isHighLiquidityToken(optionalRoutes[x].from))
                        revert NotHighLiquidityToken();
                }

                uint256 optionalAmountOutMin = optimizer.getOptimalAmountOutMin(
                    optionalRoutes,
                    balance,
                    POINTS,
                    slippage
                );
                if (optionalAmountOutMin > amountOutMin) {
                    routes = optionalRoutes;
                    amountOutMin = optionalAmountOutMin;
                }
            }
            if (amountOutMin == 0) revert NoRouteFound();

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
    // DEFAULT_ADMIN_ROLE functions
    // -------------------------------------------------

    /// @inheritdoc IAutoCompounder
    function claimBribesAndSweep(
        address[] calldata _bribes,
        address[][] calldata _tokens,
        address[] calldata _tokensToSweep,
        address[] calldata _recipients
    ) external onlyRole(DEFAULT_ADMIN_ROLE) onlyFirstDayOfEpoch(true) nonReentrant {
        voter.claimBribes(_bribes, _tokens, tokenId);
        _sweep(_tokensToSweep, _recipients);
    }

    /// @inheritdoc IAutoCompounder
    function claimFeesAndSweep(
        address[] calldata _fees,
        address[][] calldata _tokens,
        address[] calldata _tokensToSweep,
        address[] calldata _recipients
    ) external onlyRole(DEFAULT_ADMIN_ROLE) onlyFirstDayOfEpoch(true) nonReentrant {
        voter.claimFees(_fees, _tokens, tokenId);
        _sweep(_tokensToSweep, _recipients);
    }

    /// @inheritdoc IAutoCompounder
    function sweep(
        address[] calldata _tokensToSweep,
        address[] calldata _recipients
    ) external onlyRole(DEFAULT_ADMIN_ROLE) onlyFirstDayOfEpoch(true) nonReentrant {
        _sweep(_tokensToSweep, _recipients);
    }

    function _sweep(address[] memory _tokensToSweep, address[] memory _recipients) internal {
        uint256 length = _tokensToSweep.length;
        if (length != _recipients.length) revert UnequalLengths();
        for (uint256 i = 0; i < length; i++) {
            address token = _tokensToSweep[i];
            if (autoCompounderFactory.isHighLiquidityToken(token)) revert HighLiquidityToken();
            address recipient = _recipients[i];
            if (recipient == address(0)) revert ZeroAddress();
            uint256 balance = IERC20(token).balanceOf(address(this));
            if (balance > 0) {
                IERC20(token).safeTransfer(recipient, balance);
                emit Sweep(token, msg.sender, recipient, balance);
            }
        }
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

    /// @inheritdoc IAutoCompounder
    function claimAndCompoundKeeper(
        address[] memory _bribes,
        address[][] memory _bribesTokens,
        address[] memory _fees,
        address[][] memory _feesTokens,
        IRouter.Route[][] calldata _allRoutes,
        uint256[] calldata _amountsIn,
        uint256[] calldata _amountsOutMin
    ) external onlyKeeper(msg.sender) onlyFirstDayOfEpoch(false) nonReentrant {
        if (_allRoutes.length != _amountsIn.length || _allRoutes.length != _amountsOutMin.length)
            revert UnequalLengths();
        voter.claimBribes(_bribes, _bribesTokens, tokenId);
        voter.claimFees(_fees, _feesTokens, tokenId);
        for (uint256 i = 0; i < _allRoutes.length; i++) {
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
        bool isCalledByKeeper = autoCompounderFactory.isKeeper(sender);
        uint256 balance = velo.balanceOf(address(this));
        uint256 _tokenId = tokenId;
        uint256 reward;

        // claim rebase if possible
        if (distributor.claimable(_tokenId) > 0) {
            distributor.claim(_tokenId);
        }

        if (balance > 0) {
            // reward callers if they are not a keeper
            if (!isCalledByKeeper) {
                // reward the caller the minimum of:
                // - 1% of the VELO designated for compounding (Rounds down)
                // - The constant VELO reward set by team in AutoCompounderFactory
                uint256 compoundRewardAmount = balance / 100;
                uint256 factoryRewardAmount = autoCompounderFactory.rewardAmount();
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

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

    function initialize(uint256 _tokenId) external {
        if (_msgSender() != factory) revert NotFactory();
        if (tokenId != 0) revert AlreadyInitialized();

        tokenId = _tokenId;
    }

    // -------------------------------------------------
    // Public functions
    // -------------------------------------------------

    /// @notice wrapper to claim earned bribes earned by the managed tokenId and compound
    ///         by swapping to VELO, rewarding the caller, and depositing into the managed veNFT
    /// @param _bribes addresses of BribeVotingRewards contracts
    /// @param _tokens array of array for which tokens to cleam for each BribeVotingRewards contract
    /// @param _tokensToSwap Addresses of tokens to convert into VELO
    function claimBribesAndCompound(
        address[] memory _bribes,
        address[][] memory _tokens,
        address[] memory _tokensToSwap
    ) external nonReentrant {
        voter.claimBribes(_bribes, _tokens, tokenId);
        _swapTokensToVELOAndCompound(_tokensToSwap);
    }

    /// @notice Similar to claimBribesAndCompound but for FeesVotingRewards contracts
    /// @param _fees .
    /// @param _tokens .
    /// @param _tokensToSwap .
    function claimFeesAndCompound(
        address[] memory _fees,
        address[][] memory _tokens,
        address[] memory _tokensToSwap
    ) external nonReentrant {
        voter.claimFees(_fees, _tokens, tokenId);
        _swapTokensToVELOAndCompound(_tokensToSwap);
    }

    function _swapTokensToVELOAndCompound(address[] memory _tokensToSwap) internal {
        for (uint256 i = 0; i < _tokensToSwap.length; i++) {
            address token = _tokensToSwap[i];
            if (token == address(velo)) continue; // Do not need to swap from velo => velo
            uint256 balance = IERC20(token).balanceOf(address(this));
            if (balance == 0) continue; // only swap if there is a balance

            IRouter.Route[] memory routes = optimizer.getOptimalTokenToVeloRoute(token, balance);

            // swap
            _handleRouterApproval(IERC20(token), balance);
            router.swapExactTokensForTokens(
                balance,
                0, // amountOutMin
                routes,
                address(this),
                block.timestamp
            );
        }
        _rewardAndCompound();
    }

    function _rewardAndCompound() internal {
        address sender = _msgSender();
        uint256 balance = velo.balanceOf(address(this));
        uint256 reward;

        // claim rebase if possible
        if (distributor.claimable(tokenId) > 0) {
            distributor.claim(tokenId);
        }

        if (balance > 0) {
            // reward callers if they are not the ALLOWED_CALLER
            if (!hasRole(ALLOWED_CALLER, sender)) {
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
            ve.increaseAmount(tokenId, balance);
        }

        emit RewardAndCompound(tokenId, sender, reward, balance);
    }

    // -------------------------------------------------
    // ALLOWED_CALLER functions
    // -------------------------------------------------

    /// @notice Additional functionality for ALLOWED_CALLER to deposit more VELO into the managed tokenId. This
    ///         is effectively a bribe bonus for users that deposited into the autocompounder.
    function increaseAmount(uint256 _value) external onlyRole(ALLOWED_CALLER) {
        velo.transferFrom(_msgSender(), address(this), _value);
        ve.increaseAmount(tokenId, _value);
    }

    /// @notice Vote for Velodrome pools with the given weights
    /// @dev Refer to IVoter.vote()
    function vote(address[] calldata _poolVote, uint256[] calldata _weights) external onlyRole(ALLOWED_CALLER) {
        voter.vote(tokenId, _poolVote, _weights);
    }

    /// @notice Convert tokens held by this contract into VELO using a route given by ALLOWED_CALLER and compound
    ///         into the managed tokenId.  As there is an incentive to convert tokens held by this contract into VELO and
    ///         compound, this method is only needed when `from`:
    ///             - does not have a pool with USDC, WETH, OP, and VELO
    ///             - does not have enough liquidity in USDC, WETH, OP, or VELO to incentivize public calling
    /// @dev This method does not reward the ALLOWED_CALLER for compounding
    function swapTokenToVELOAndCompound(
        IRouter.Route[] calldata routes
    ) external onlyRole(ALLOWED_CALLER) nonReentrant {
        if (routes[routes.length - 1].to != address(velo)) revert InvalidPath();
        address from = routes[0].from;
        if (from == address(velo)) revert InvalidPath();

        uint256 balance = IERC20(from).balanceOf(address(this));
        if (balance > 0) {
            _handleRouterApproval(IERC20(from), balance);
            router.swapExactTokensForTokens(balance, 0, routes, address(this), block.timestamp);
        }
        _rewardAndCompound();
    }

    // -------------------------------------------------
    // Helpers
    // -------------------------------------------------

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

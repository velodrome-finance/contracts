// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "../AutoCompounder.t.sol";

contract AutoCompounderFlow is AutoCompounderTest {
    uint256 public immutable PRECISION = 1e12;
    uint256 public immutable MAX_TIME = 4 * 365 * 86400;
    uint256 bribeToken = TOKEN_1 / 1000;
    uint256 bribeUSDC = USDC_1 / 1000; // low enough for liq testing

    function _createBribeWithAmount(BribeVotingReward _bribeVotingReward, address _token, uint256 _amount) internal {
        IERC20(_token).approve(address(_bribeVotingReward), _amount);
        _bribeVotingReward.notifyRewardAmount(address(_token), _amount);
    }

    function _createFeesWithAmount(FeesVotingReward _feesVotingReward, address _token, uint256 _amount) internal {
        deal(_token, address(gauge), _amount);
        vm.startPrank(address(gauge));
        IERC20(_token).approve(address(_feesVotingReward), _amount);
        _feesVotingReward.notifyRewardAmount(address(_token), _amount);
        vm.stopPrank();
    }

    function testClaimBribesAndCompound() public {
        address[] memory pools = new address[](1);
        uint256[] memory weights = new uint256[](1);
        address[] memory rewards = new address[](3);
        pools[0] = address(pool);
        weights[0] = 10000;
        rewards[0] = address(DAI);
        rewards[1] = address(USDC);
        rewards[2] = address(FRAX);

        bribes.push(address(bribeVotingReward));
        tokensToClaim.push(rewards);
        slippages.push(0);

        // Epoch 0: DAI bribed => voted for DAI bribe
        // Epoch 1: DAI bribed => passive vote
        // Epoch 2: Accrued DAI claimed & compounded => FRAX & USDC bribed => poked
        // Epoch 3: USDC claimed & compounded => USDC bribed => passive vote
        // Epoch 4: DAI & USDC bribed => FRAX claimed & compounded => poked
        // Epoch 5: FRAX & USDC bribed => passive vote
        // Epoch 6: FRAX, DAI, & Accrued USDC claimed

        // Epoch 0

        _createBribeWithAmount(bribeVotingReward, address(DAI), bribeToken);
        autoCompounder.vote(pools, weights);
        skipToNextEpoch(1);

        // Epoch 1

        _createBribeWithAmount(bribeVotingReward, address(DAI), bribeToken);
        skipToNextEpoch(6 days + 1);

        // Epoch 2

        assertEq(DAI.balanceOf(address(bribeVotingReward)), bribeToken * 2);
        uint256 preNFTBalance = escrow.balanceOfNFT(mTokenId);
        uint256 preCallerVELO = VELO.balanceOf(address(owner2));

        vm.prank(address(owner2));
        tokensToSwap = new address[](1);
        tokensToSwap[0] = address(DAI);
        slippages = new uint256[](1);
        slippages[0] = 500;
        autoCompounder.claimBribesAndCompound(bribes, tokensToClaim, tokensToSwap, slippages);

        assertEq(DAI.balanceOf(address(bribeVotingReward)), 0);
        assertEq(DAI.balanceOf(address(autoCompounder)), 0);
        assertGt(VELO.balanceOf(address(owner2)), preCallerVELO);
        assertGt(escrow.balanceOfNFT(mTokenId), preNFTBalance);

        _createBribeWithAmount(bribeVotingReward, address(FRAX), bribeToken);
        _createBribeWithAmount(bribeVotingReward, address(USDC), bribeUSDC);
        voter.poke(mTokenId);
        skipToNextEpoch(6 days + 1);

        // Epoch 3

        assertEq(USDC.balanceOf(address(bribeVotingReward)), bribeUSDC);
        assertEq(FRAX.balanceOf(address(bribeVotingReward)), bribeToken);
        preNFTBalance = escrow.balanceOfNFT(mTokenId);
        preCallerVELO = VELO.balanceOf(address(owner2));

        tokensToClaim = new address[][](1);
        tokensToClaim[0] = [address(USDC)];
        tokensToSwap[0] = address(USDC);
        vm.prank(address(owner2));
        autoCompounder.claimBribesAndCompound(bribes, tokensToClaim, tokensToSwap, slippages);

        assertEq(USDC.balanceOf(address(bribeVotingReward)), 0);
        assertEq(FRAX.balanceOf(address(bribeVotingReward)), bribeToken);
        assertEq(USDC.balanceOf(address(autoCompounder)), 0);
        assertGt(VELO.balanceOf(address(owner2)), preCallerVELO);
        assertGt(escrow.balanceOfNFT(mTokenId), preNFTBalance);

        _createBribeWithAmount(bribeVotingReward, address(USDC), bribeUSDC);
        skipToNextEpoch(6 days + 1);

        // Epoch 4

        _createBribeWithAmount(bribeVotingReward, address(DAI), bribeToken);
        _createBribeWithAmount(bribeVotingReward, address(USDC), bribeUSDC);

        preNFTBalance = escrow.balanceOfNFT(mTokenId);
        preCallerVELO = VELO.balanceOf(address(owner2));

        tokensToClaim[0] = [address(FRAX)];
        tokensToSwap[0] = address(FRAX);
        vm.prank(address(owner2));
        autoCompounder.claimBribesAndCompound(bribes, tokensToClaim, tokensToSwap, slippages);

        assertEq(DAI.balanceOf(address(bribeVotingReward)), bribeToken);
        assertEq(USDC.balanceOf(address(bribeVotingReward)), bribeUSDC * 2);
        assertEq(FRAX.balanceOf(address(bribeVotingReward)), 0);
        assertEq(FRAX.balanceOf(address(autoCompounder)), 0);
        assertGt(VELO.balanceOf(address(owner2)), preCallerVELO);
        assertGt(escrow.balanceOfNFT(mTokenId), preNFTBalance);

        voter.poke(mTokenId);
        skipToNextEpoch(6 days + 1);

        // Epoch 5

        _createBribeWithAmount(bribeVotingReward, address(FRAX), bribeToken);
        _createBribeWithAmount(bribeVotingReward, address(USDC), bribeUSDC);
        skipToNextEpoch(6 days + 1);

        assertEq(DAI.balanceOf(address(bribeVotingReward)), bribeToken);
        assertEq(USDC.balanceOf(address(bribeVotingReward)), bribeUSDC * 3);
        assertEq(FRAX.balanceOf(address(bribeVotingReward)), bribeToken);

        preNFTBalance = escrow.balanceOfNFT(mTokenId);
        preCallerVELO = VELO.balanceOf(address(owner2));

        tokensToClaim[0] = [address(DAI), address(USDC), address(FRAX)];
        vm.prank(address(owner2));
        tokensToSwap = new address[](3);
        tokensToSwap = [address(DAI), address(FRAX), address(USDC)];
        slippages = new uint256[](3);
        slippages = [500, 500, 500];
        autoCompounder.claimBribesAndCompound(bribes, tokensToClaim, tokensToSwap, slippages);

        assertEq(DAI.balanceOf(address(bribeVotingReward)), 0);
        assertEq(USDC.balanceOf(address(bribeVotingReward)), 0);
        assertEq(FRAX.balanceOf(address(bribeVotingReward)), 0);
        assertEq(DAI.balanceOf(address(autoCompounder)), 0);
        assertEq(USDC.balanceOf(address(autoCompounder)), 0);
        assertEq(FRAX.balanceOf(address(autoCompounder)), 0);
        assertEq(VELO.balanceOf(address(autoCompounder)), 0);
        assertGt(VELO.balanceOf(address(owner2)), preCallerVELO);
        assertGt(escrow.balanceOfNFT(mTokenId), preNFTBalance);
    }

    function testClaimFeesAndCompound() public {
        address[] memory pools = new address[](1);
        uint256[] memory weights = new uint256[](1);
        address[] memory rewards = new address[](3);
        pools[0] = address(pool);
        weights[0] = 10000;
        rewards[0] = address(USDC);
        rewards[1] = address(FRAX);

        fees.push(address(feesVotingReward));
        tokensToClaim.push(rewards);
        slippages.push(0);

        // Epoch 0: FRAX fees => voted for FRAX fees
        // Epoch 1: FRAX fees => passive vote
        // Epoch 2: Accrued FRAX claimed & compounded => FRAX & USDC fees => poked
        // Epoch 3: USDC claimed & compounded => USDC fees => passive vote
        // Epoch 4: FRAX & USDC fees => FRAX claimed & compounded => poked
        // Epoch 5: FRAX & USDC fees => passive vote
        // Epoch 6: FRAX & Accrued USDC claimed

        // Epoch 0

        _createFeesWithAmount(feesVotingReward, address(FRAX), bribeToken);
        autoCompounder.vote(pools, weights);
        skipToNextEpoch(1);

        // Epoch 1

        _createFeesWithAmount(feesVotingReward, address(FRAX), bribeToken);
        skipToNextEpoch(6 days + 1);

        // Epoch 2

        assertEq(FRAX.balanceOf(address(feesVotingReward)), bribeToken * 2);
        uint256 preNFTBalance = escrow.balanceOfNFT(mTokenId);
        uint256 preCallerVELO = VELO.balanceOf(address(owner2));

        tokensToSwap = new address[](1);
        tokensToSwap[0] = address(FRAX);
        slippages = new uint256[](1);
        slippages[0] = 500;
        vm.prank(address(owner2));
        autoCompounder.claimFeesAndCompound(fees, tokensToClaim, tokensToSwap, slippages);

        assertEq(FRAX.balanceOf(address(feesVotingReward)), 0);
        assertEq(FRAX.balanceOf(address(autoCompounder)), 0);
        assertGt(VELO.balanceOf(address(owner2)), preCallerVELO);
        assertGt(escrow.balanceOfNFT(mTokenId), preNFTBalance);

        _createFeesWithAmount(feesVotingReward, address(FRAX), bribeToken);
        _createFeesWithAmount(feesVotingReward, address(USDC), bribeUSDC);
        voter.poke(mTokenId);
        skipToNextEpoch(6 days + 1);

        // Epoch 3

        assertEq(USDC.balanceOf(address(feesVotingReward)), bribeUSDC);
        assertEq(FRAX.balanceOf(address(feesVotingReward)), bribeToken);
        preNFTBalance = escrow.balanceOfNFT(mTokenId);
        preCallerVELO = VELO.balanceOf(address(owner2));

        tokensToClaim = new address[][](1);
        tokensToClaim[0] = [address(USDC)];
        tokensToSwap[0] = address(USDC);
        vm.prank(address(owner2));
        autoCompounder.claimFeesAndCompound(fees, tokensToClaim, tokensToSwap, slippages);

        assertEq(USDC.balanceOf(address(feesVotingReward)), 0);
        assertEq(FRAX.balanceOf(address(feesVotingReward)), bribeToken);
        assertEq(USDC.balanceOf(address(autoCompounder)), 0);
        assertGt(VELO.balanceOf(address(owner2)), preCallerVELO);
        assertGt(escrow.balanceOfNFT(mTokenId), preNFTBalance);

        _createFeesWithAmount(feesVotingReward, address(USDC), bribeUSDC);
        skipToNextEpoch(6 days + 1);

        // Epoch 4

        _createFeesWithAmount(feesVotingReward, address(FRAX), bribeToken);
        _createFeesWithAmount(feesVotingReward, address(USDC), bribeUSDC);

        preNFTBalance = escrow.balanceOfNFT(mTokenId);
        preCallerVELO = VELO.balanceOf(address(owner2));

        tokensToClaim[0] = [address(FRAX)];
        tokensToSwap[0] = address(FRAX);
        vm.prank(address(owner2));
        autoCompounder.claimFeesAndCompound(fees, tokensToClaim, tokensToSwap, slippages);

        assertEq(FRAX.balanceOf(address(feesVotingReward)), bribeToken);
        assertEq(USDC.balanceOf(address(feesVotingReward)), bribeUSDC * 2);
        assertEq(FRAX.balanceOf(address(autoCompounder)), 0);
        assertGt(VELO.balanceOf(address(owner2)), preCallerVELO);
        assertGt(escrow.balanceOfNFT(mTokenId), preNFTBalance);

        voter.poke(mTokenId);
        skipToNextEpoch(6 days + 1);

        // Epoch 5

        _createFeesWithAmount(feesVotingReward, address(FRAX), bribeToken);
        _createFeesWithAmount(feesVotingReward, address(USDC), bribeUSDC);
        skipToNextEpoch(6 days + 1);

        assertEq(FRAX.balanceOf(address(feesVotingReward)), bribeToken * 2);
        assertEq(USDC.balanceOf(address(feesVotingReward)), bribeUSDC * 3);

        preNFTBalance = escrow.balanceOfNFT(mTokenId);
        preCallerVELO = VELO.balanceOf(address(owner2));

        vm.prank(address(owner2));
        tokensToClaim[0] = [address(FRAX), address(USDC)];
        tokensToSwap.push(address(USDC));
        slippages.push(500);
        autoCompounder.claimFeesAndCompound(fees, tokensToClaim, tokensToSwap, slippages);

        assertEq(FRAX.balanceOf(address(feesVotingReward)), 0);
        assertEq(USDC.balanceOf(address(feesVotingReward)), 0);
        assertEq(FRAX.balanceOf(address(autoCompounder)), 0);
        assertEq(USDC.balanceOf(address(autoCompounder)), 0);
        assertEq(VELO.balanceOf(address(autoCompounder)), 0);
        assertGt(VELO.balanceOf(address(owner2)), preCallerVELO);
        assertGt(escrow.balanceOfNFT(mTokenId), preNFTBalance);
    }
}

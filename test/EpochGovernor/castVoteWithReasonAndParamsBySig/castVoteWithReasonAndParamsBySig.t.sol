// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IGovernor} from "contracts/governance/IGovernor.sol";

import "test/BaseTest.sol";

contract CastVoteWithReasonAndParamsBySigTest is BaseTest {
    uint256 pid;
    uint256 nftBalance;
    address alice;
    uint256 alicePk;
    uint256 tokenId;

    function _setUp() public override {
        (alice, alicePk) = makeAddrAndKey("alice");

        deal(address(VELO), alice, TOKEN_10M);

        vm.startPrank(alice);

        VELO.approve(address(escrow), TOKEN_1);
        tokenId = escrow.createLock(TOKEN_1, MAXTIME); // 1
        vm.roll(block.number + 1);

        skipToNextEpoch(0);

        skip(epochGovernor.proposalWindow());

        address[] memory targets = new address[](1);
        targets[0] = address(minter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(minter.nudge.selector);
        string memory description = "";

        pid = epochGovernor.propose(tokenId, targets, values, calldatas, description);

        skipAndRoll(2);
        nftBalance = escrow.balanceOfNFT(tokenId);
        skipAndRoll(1); // allow voting
    }

    function test_WhenTheSignatureIsInvalid() external {
        // It should revert with {GovernorInvalidSignature}

        bytes memory voteFractionsParam =
            abi.encodePacked(uint128(nftBalance / 3), uint128(nftBalance / 3), uint128(nftBalance / 3));

        vm.expectPartialRevert(IGovernor.GovernorInvalidSignature.selector);
        epochGovernor.castVoteWithReasonAndParamsBySig(pid, tokenId, 1, alice, "", voteFractionsParam, bytes(""));
    }

    function test_WhenTheSignatureIsValid() external {
        // It should cast vote
        // It should emit {VoteCastWithParams}

        bytes32 TYPE_HASH =
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

        bytes32 domainSeparator = keccak256(
            abi.encode(
                TYPE_HASH,
                keccak256(bytes("Epoch Governor")),
                keccak256(bytes("1")),
                block.chainid,
                address(epochGovernor)
            )
        );

        bytes memory voteFractionsParam =
            abi.encodePacked(uint128(nftBalance / 3), uint128(nftBalance / 3), uint128(nftBalance / 3));

        bytes32 structHash = keccak256(
            abi.encode(
                epochGovernor.EXTENDED_BALLOT_TYPEHASH(),
                pid,
                tokenId,
                255,
                alice,
                0,
                keccak256(bytes("")),
                keccak256(voteFractionsParam)
            )
        );

        bytes32 digest = MessageHashUtils.toTypedDataHash(domainSeparator, structHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectEmit(address(epochGovernor));
        emit IGovernor.VoteCastWithParams({
            _voter: alice,
            _tokenId: tokenId,
            _proposalId: pid,
            _support: 255,
            _weight: nftBalance,
            _reason: "",
            _params: voteFractionsParam
        });
        epochGovernor.castVoteWithReasonAndParamsBySig(pid, tokenId, 255, alice, "", voteFractionsParam, signature);

        assertEq(epochGovernor.hasVoted(pid, tokenId), true);
        assertApproxEqAbs(epochGovernor.usedVotes(pid, tokenId), nftBalance, 1);

        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = epochGovernor.proposalVotes(pid);

        assertEq(againstVotes, nftBalance / 3);
        assertEq(forVotes, nftBalance / 3);
        assertEq(abstainVotes, nftBalance / 3);
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IGovernor} from "contracts/governance/IGovernor.sol";

import "test/BaseTest.sol";

contract CastVoteBySigTest is BaseTest {
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

        nftBalance = escrow.balanceOfNFT(tokenId);
        skipAndRoll(1); // allow voting
    }

    function test_WhenTheSignatureIsInvalid() external {
        // It should revert with {GovernorInvalidSignature}

        vm.expectPartialRevert(IGovernor.GovernorInvalidSignature.selector);
        epochGovernor.castVoteBySig(pid, tokenId, 1, alice, bytes(""));
    }

    function test_WhenTheSignatureIsValid() external {
        // It should cast vote
        // It should emit {VoteCast}

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
        bytes32 structHash = keccak256(abi.encode(epochGovernor.BALLOT_TYPEHASH(), pid, tokenId, 1, alice, 0));

        bytes32 digest = MessageHashUtils.toTypedDataHash(domainSeparator, structHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectEmit(address(epochGovernor));
        emit IGovernor.VoteCast({
            _voter: alice,
            _tokenId: tokenId,
            _proposalId: pid,
            _support: 1,
            _weight: nftBalance,
            _reason: ""
        });
        epochGovernor.castVoteBySig(pid, tokenId, 1, alice, signature);

        assertEq(epochGovernor.hasVoted(pid, tokenId), true);
        assertEq(epochGovernor.usedVotes(pid, tokenId), nftBalance);

        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = epochGovernor.proposalVotes(pid);

        assertEq(againstVotes, 0);
        assertEq(forVotes, nftBalance);
        assertEq(abstainVotes, 0);
    }
}

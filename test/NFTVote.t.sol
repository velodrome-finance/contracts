pragma solidity 0.8.13;

// import "openzeppelin-contracts/contracts/access/Ownable.sol";
// import "./BaseTest.sol";
// import "utils/TestL2Governance.sol";

// contract FlagCondition is Ownable {
//     bool public flag;

//     function setFlag(bool _to) public onlyOwner {
//         flag = _to;
//     }
// }

// contract NFTVoteTest is BaseTest {
//     VotingEscrow escrow;
//     TestL2Governance gov;
//     FlagCondition flag;

//     function setUp() public {
//         super.setUp();
//         deployCoins();

//         VeArtProxy artProxy = new VeArtProxy();
//         escrow = new VotingEscrow(address(VELO), address(artProxy));
//         gov = new TestL2Governance(escrow);

//         // test variable to vote on
//         flag = new FlagCondition();
//         flag.transferOwnership(address(gov));

//         VELO.mint(address(this), 1e21);
//         vm.roll(block.number + 1);
//     }

//     function testLockAndPropose() public {
//         uint256 fourYears = 4 * 365 * 24 * 3600;
//         VELO.approve(address(escrow), 1e21);
//         escrow.create_lock(1e21, fourYears);
//         uint256 quorum = gov.quorum(block.timestamp);
//         uint256 numVotes = gov.getVotes(address(this), block.timestamp);
//         uint256 thresh = gov.proposalThreshold(); // 0 for now
//         assertGt(numVotes, thresh);
//         assertGt(numVotes, quorum); // owner will win

//         // vote to set the flag to true
//         address[] memory targets = new address[](1);
//         targets[0] = address(flag);
//         uint256[] memory values = new uint256[](1);
//         values[0] = 0;
//         bytes[] memory calldatas = new bytes[](1);
//         bytes memory data = abi.encodeCall(flag.setFlag, (true));
//         calldatas[0] = data;
//         string memory description = "no description";

//         uint256 proposal_id = gov.propose(targets, values, calldatas, description);

//         // start block is at 2
//         vm.warp(block.timestamp + 2);
//         vm.roll(block.number + 1);
//         gov.castVote(
//             proposal_id,
//             uint8(L2GovernorCountingSimple.VoteType.For) // 1
//         );

//         vm.warp(block.timestamp + 7);
//         vm.roll(block.number + 1); // voting period over
//         assertEq(uint8(gov.state(proposal_id)), 4); // 3 = defeated, 4 = succeeded

//         uint256 executed_proposal_id = gov.execute(
//             targets,
//             values,
//             calldatas,
//             keccak256(bytes(description))
//         );
//         assertEq(executed_proposal_id, proposal_id);
//         assertTrue(flag.flag());
//     }
// }

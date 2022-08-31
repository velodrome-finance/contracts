pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {ManagedRewardsFactory} from "contracts/factories/ManagedRewardsFactory.sol";
import {VotingRewardsFactory} from "contracts/factories/VotingRewardsFactory.sol";
import {GaugeFactory} from "contracts/factories/GaugeFactory.sol";
import {PairFactory} from "contracts/factories/PairFactory.sol";
import {IPairFactory} from "contracts/interfaces/IPairFactory.sol";
import {FactoryRegistry} from "contracts/FactoryRegistry.sol";
import {Reward} from "contracts/rewards/Reward.sol";
import {FeesVotingReward} from "contracts/rewards/FeesVotingReward.sol";
import {BribeVotingReward} from "contracts/rewards/BribeVotingReward.sol";
import {FreeManagedReward} from "contracts/rewards/FreeManagedReward.sol";
import {LockedManagedReward} from "contracts/rewards/LockedManagedReward.sol";
import {Gauge} from "contracts/Gauge.sol";
import {Minter} from "contracts/Minter.sol";
import {Pair} from "contracts/Pair.sol";
import {PairFees} from "contracts/PairFees.sol";
import {RewardsDistributor} from "contracts/RewardsDistributor.sol";
import {IRouter, Router} from "contracts/Router.sol";
import {IVelo, Velo} from "contracts/Velo.sol";
import {VelodromeLibrary} from "contracts/VelodromeLibrary.sol";
import {Voter} from "contracts/Voter.sol";
import {VeArtProxy} from "contracts/VeArtProxy.sol";
import {IVotingEscrow, VotingEscrow} from "contracts/VotingEscrow.sol";
import {TestOwner} from "utils/TestOwner.sol";
import {MockERC20} from "utils/MockERC20.sol";
import {MockWETH} from "utils/MockWETH.sol";
import {VeloGovernor} from "contracts/VeloGovernor.sol";
import {EpochGovernor} from "contracts/EpochGovernor.sol";
import {SinkManager} from "contracts/v1/sink/SinkManager.sol";
import {SinkDrain} from "contracts/v1/sink/SinkDrain.sol";
import {SinkConverter} from "contracts/v1/sink/SinkConverter.sol";
import {IGaugeV1} from "contracts/interfaces/v1/IGaugeV1.sol";
import {IVoterV1} from "contracts/interfaces/v1/IVoterV1.sol";
import {IVotingEscrowV1} from "contracts/interfaces/v1/IVotingEscrowV1.sol";
import {IWETH} from "contracts/interfaces/IWETH.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

abstract contract BaseTest is Test, TestOwner {
    uint256 constant USDC_1 = 1e6;
    uint256 constant USDC_10K = 1e10; // 1e4 = 10K tokens with 6 decimals
    uint256 constant USDC_100K = 1e11; // 1e5 = 100K tokens with 6 decimals
    uint256 constant TOKEN_1 = 1e18;
    uint256 constant TOKEN_10K = 1e22; // 1e4 = 10K tokens with 18 decimals
    uint256 constant TOKEN_100K = 1e23; // 1e5 = 100K tokens with 18 decimals
    uint256 constant TOKEN_1M = 1e24; // 1e6 = 1M tokens with 18 decimals
    uint256 constant TOKEN_10M = 1e25; // 1e7 = 10M tokens with 18 decimals
    uint256 constant TOKEN_100M = 1e26; // 1e8 = 100M tokens with 18 decimals
    uint256 constant TOKEN_10B = 1e28; // 1e10 = 10B tokens with 18 decimals
    uint256 constant PAIR_1 = 1e9;

    uint256 constant DURATION = 7 days;
    uint256 constant WEEK = 1 weeks;
    /// @dev Use same value as in voting escrow
    uint256 constant MAXTIME = 4 * 365 * 86400;
    uint256 constant MAX_BPS = 10_000;
    address constant ETHER = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    TestOwner owner;
    TestOwner owner2;
    TestOwner owner3;
    TestOwner owner4;
    TestOwner owner5;
    address[] owners;
    IERC20 USDC;
    IERC20 FRAX;
    IERC20 DAI;
    IWETH WETH; // Mock WETH token
    Velo VELO;
    MockERC20 LR; // late reward

    /// @dev Core v2 Deployment
    Router router;
    VelodromeLibrary lib;
    Pair pair;
    Pair pair2;
    Pair pair3;

    VotingEscrow escrow;
    PairFactory factory;
    FactoryRegistry factoryRegistry;
    GaugeFactory gaugeFactory;
    VotingRewardsFactory votingRewardsFactory;
    ManagedRewardsFactory managedRewardsFactory;
    Voter voter;
    RewardsDistributor distributor;
    Minter minter;
    Gauge gauge;
    VeloGovernor governor;
    EpochGovernor epochGovernor;
    FeesVotingReward feesVotingReward;
    BribeVotingReward bribeVotingReward;
    Gauge gauge2;
    FeesVotingReward feesVotingReward2;
    BribeVotingReward bribeVotingReward2;
    Gauge gauge3;
    FeesVotingReward feesVotingReward3;
    BribeVotingReward bribeVotingReward3;

    /// @dev v1 contracts for fork testing
    Velo vVELO;
    IVotingEscrowV1 vEscrow;
    IVoterV1 vVoter;
    PairFactory vFactory;
    Router vRouter;
    VeloGovernor vGov;
    RewardsDistributor vDistributor;
    Minter vMinter;

    /// @dev additional contracts required by v2
    SinkManager sinkManager;
    IGaugeV1 gaugeSinkDrain;
    SinkDrain sinkDrain;
    SinkConverter sinkConverter;
    /// @dev tokenId of nft owned by black hole
    uint256 ownedTokenId;

    uint256 optimismFork;
    /// @dev set OPTIMISM_RPC_URL in .env to run mainnet tests
    string OPTIMISM_RPC_URL = vm.envString("OPTIMISM_RPC_URL");
    /// @dev optionally set FORK_BLOCK_NUMBER in .env / test set up for faster tests / fixed tests
    uint256 BLOCK_NUMBER = vm.envOr("FORK_BLOCK_NUMBER", uint256(0));

    enum Deployment {
        DEFAULT,
        FORK,
        CUSTOM
    }

    /// Misc Testing TODO:
    // - [ ] create e2e tests for gauge (low priority)
    // - [ ] proper tests for rewards distributor, incl with managed nfts

    /// @dev Determines whether or not to use the base set up configuration
    ///      Local v2 deployment used by default
    Deployment deploymentType;

    /// @dev Default set up of local v2 deployment run if Deployment.DEFAULT selected
    ///      Mainnet fork + v2 deployment + sink deployed if Deployment.FORK selected
    ///      Only _setUp function run if Deployment.CUSTOM selected
    ///      _setUp can be overriden to provide additional configuration if desired
    ///      To set up mainnet forks from a certain block (e.g. to fix venft balances for testing)
    ///      Use a CUSTOM deployment, and call _forkSetUp with the desired block number
    function setUp() public {
        if (deploymentType == Deployment.DEFAULT) {
            _baseSetUp();
        } else if (deploymentType == Deployment.FORK) {
            _forkSetUp(BLOCK_NUMBER);
        }
        _setUp();
    }

    /// @dev Implement this if you want a custom configured deployment
    function _setUp() public virtual {}

    /// @dev Default configuration (local v2 deployment)
    ///      Note that most permissions are given to owner
    function _baseSetUp() public {
        // seed set up with initial time
        skip(1 weeks);

        deployOwners();
        deployCoins();
        mintStables();
        uint256[] memory amounts = new uint256[](5);
        amounts[0] = TOKEN_10M;
        amounts[1] = TOKEN_10M;
        amounts[2] = TOKEN_10M;
        amounts[3] = TOKEN_10M;
        amounts[4] = TOKEN_10M;
        mintToken(address(VELO), owners, amounts);
        mintToken(address(LR), owners, amounts);
        deployFactoriesAndRouter();

        VeArtProxy artProxy = new VeArtProxy();
        escrow = new VotingEscrow(address(VELO), address(artProxy), address(factoryRegistry), address(owner));

        // deployVoter()
        voter = new Voter(address(escrow), address(factoryRegistry));

        router = new Router(address(factory), address(voter), address(WETH));
        lib = new VelodromeLibrary(address(router));
        deployPairWithOwner(address(owner));

        escrow.setVoter(address(voter));
        escrow.setAllowedManager(address(owner));

        // deployMinter()
        distributor = new RewardsDistributor(address(escrow));
        minter = new Minter(address(voter), address(escrow), address(distributor));
        distributor.setDepositor(address(minter));
        VELO.setMinter(address(minter));
        address[] memory tokens = new address[](6);
        tokens[0] = address(USDC);
        tokens[1] = address(FRAX);
        tokens[2] = address(DAI);
        tokens[3] = address(VELO);
        tokens[4] = address(LR);
        tokens[5] = address(WETH);
        voter.initialize(tokens, address(minter));

        governor = new VeloGovernor(escrow);
        epochGovernor = new EpochGovernor(escrow, address(minter));
        voter.setEpochGovernor(address(epochGovernor));
        voter.setGovernor(address(governor));

        // USDC - FRAX stable
        gauge = Gauge(
            voter.createGauge(address(factory), address(votingRewardsFactory), address(gaugeFactory), address(pair))
        );
        feesVotingReward = FeesVotingReward(voter.gaugeToFees(address(gauge)));
        bribeVotingReward = BribeVotingReward(voter.gaugeToBribe(address(gauge)));

        // USDC - FRAX unstable
        gauge2 = Gauge(
            voter.createGauge(address(factory), address(votingRewardsFactory), address(gaugeFactory), address(pair2))
        );
        feesVotingReward2 = FeesVotingReward(voter.gaugeToFees(address(gauge2)));
        bribeVotingReward2 = BribeVotingReward(voter.gaugeToBribe(address(gauge2)));

        // FRAX - DAI stable
        gauge3 = Gauge(
            voter.createGauge(address(factory), address(votingRewardsFactory), address(gaugeFactory), address(pair3))
        );
        feesVotingReward3 = FeesVotingReward(voter.gaugeToFees(address(gauge3)));
        bribeVotingReward3 = BribeVotingReward(voter.gaugeToBribe(address(gauge3)));

        vm.label(address(owner), "Owner");
        vm.label(address(owner2), "Owner 2");
        vm.label(address(owner3), "Owner 3");
        vm.label(address(owner4), "Owner 4");
        vm.label(address(owner5), "Owner 5");
        vm.label(address(USDC), "USDC");
        vm.label(address(FRAX), "FRAX");
        vm.label(address(DAI), "DAI");
        vm.label(address(WETH), "WETH");
        vm.label(address(LR), "Bribe Voting Reward");
        vm.label(address(factory), "Pair Factory");
        vm.label(address(factoryRegistry), "Factory Registry");
        vm.label(address(router), "Router");
        vm.label(address(lib), "Velodrome Library");
        vm.label(address(pair), "Pair");
        vm.label(address(pair2), "Pair 2");
        vm.label(address(pair3), "Pair 3");

        vm.label(address(escrow), "Voting Escrow");
        vm.label(address(gaugeFactory), "Gauge Factory");
        vm.label(address(votingRewardsFactory), "Voting Rewards Factory");
        vm.label(address(voter), "Voter");
        vm.label(address(distributor), "Distributor");
        vm.label(address(minter), "Minter");
        vm.label(address(gauge), "Gauge");
        vm.label(address(governor), "Governor");
        vm.label(address(feesVotingReward), "Fees Voting Reward");
        vm.label(address(bribeVotingReward), "Bribe Voting Reward");
        vm.label(address(gauge2), "Gauge 2");
        vm.label(address(feesVotingReward2), "Fees Voting Reward 2");
        vm.label(address(bribeVotingReward2), "Bribe Voting Reward 2");
        vm.label(address(gauge3), "Gauge 3");
        vm.label(address(feesVotingReward3), "Fees Voting Reward 3");
        vm.label(address(bribeVotingReward3), "Bribe Voting Reward 3");
    }

    function _forkSetUp(uint256 _blockNumber) public {
        if (_blockNumber != 0) {
            optimismFork = vm.createFork(OPTIMISM_RPC_URL, _blockNumber);
        } else {
            optimismFork = vm.createFork(OPTIMISM_RPC_URL);
        }
        vm.selectFork(optimismFork);

        // fetch version one from mainnet fork
        vVELO = Velo(0x3c8B650257cFb5f272f799F5e2b4e65093a11a05);
        vEscrow = IVotingEscrowV1(0x9c7305eb78a432ced5C4D14Cac27E8Ed569A2e26);
        vVoter = IVoterV1(0x09236cfF45047DBee6B921e00704bed6D6B8Cf7e);
        vFactory = PairFactory(0x25CbdDb98b35ab1FF77413456B31EC81A6B6B746);
        vRouter = Router(payable(0x9c12939390052919aF3155f41Bf4160Fd3666A6f));
        vGov = VeloGovernor(payable(0x64DD805aa894dc001f8505e000c7535179D96C9E));
        vDistributor = RewardsDistributor(0x5d5Bea9f0Fc13d967511668a60a3369fD53F784F);
        vMinter = Minter(0x3460Dc71A8863710D1C907B8d9D5DBC053a4102d);

        // set up v2 core deployment on fork
        _baseSetUp();

        // mint v1 velo so we can create v1 nfts for testing
        uint256[] memory amounts = new uint256[](5);
        amounts[0] = 1e25;
        amounts[1] = 1e25;
        amounts[2] = 1e25;
        amounts[3] = 1e25;
        amounts[4] = 1e25;
        mintToken(address(vVELO), owners, amounts);

        // layer on additional contracts required by v2 deployment
        sinkManager = new SinkManager(
            address(vVoter),
            address(vVELO),
            address(VELO),
            address(vEscrow),
            address(escrow),
            address(vDistributor)
        );

        // create v1 nft to seed black hole
        vVELO.approve(address(vEscrow), TOKEN_1 / 4);
        ownedTokenId = vEscrow.create_lock(TOKEN_1 / 4, 4 * 365 * 86400);
        vEscrow.safeTransferFrom(address(owner), address(sinkManager), ownedTokenId);
        sinkManager.setOwnedTokenId(ownedTokenId);

        // Move forward in time as escrow transfer above has balance to 0 for flash tx protection
        skip(1);
        vm.roll(block.number + 1);

        // Setup SinkDrain
        sinkDrain = new SinkDrain(address(sinkManager));
        assertEq(sinkDrain.totalSupply(), sinkDrain.balanceOf(address(sinkManager)));
        vm.prank(vVoter.governor());
        gaugeSinkDrain = IGaugeV1(vVoter.createGauge(address(sinkDrain)));
        sinkManager.setupSinkDrain(address(gaugeSinkDrain));

        // Setup SinkConverter
        sinkConverter = new SinkConverter(address(sinkManager));
        factory.setSinkConverter(address(sinkConverter), address(vVELO), address(VELO));

        vm.prank(address(owner));
        VELO.setSinkManager(address(sinkManager));

        vm.label(address(vVELO), "V1 Velo");
        vm.label(address(vEscrow), "V1 Voting Escrow");
        vm.label(address(vVoter), "V1 Voter");
        vm.label(address(vFactory), "V1 Pair Factory");
        vm.label(address(vGov), "V1 Velo Governor");
        vm.label(address(vDistributor), "V1 Rewards vDistributor");
        vm.label(address(vMinter), "V1 Minter");
        vm.label(address(gaugeSinkDrain), "Gauge Sink Drain");
        vm.label(address(sinkManager), "Sink Manager");
        vm.label(address(sinkDrain), "Sink Drain");
        vm.label(address(sinkConverter), "Sink Converter");
    }

    function deployOwners() public {
        owner = TestOwner(payable(address(this)));
        owner2 = new TestOwner();
        owner3 = new TestOwner();
        owner4 = new TestOwner();
        owner5 = new TestOwner();
        owners = new address[](5);
        owners[0] = address(owner);
        owners[1] = address(owner2);
        owners[2] = address(owner3);
        owners[3] = address(owner4);
        owners[4] = address(owner5);
    }

    function deployCoins() public {
        if (deploymentType == Deployment.FORK) {
            USDC = IERC20(0x7F5c764cBc14f9669B88837ca1490cCa17c31607);
            DAI = IERC20(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1);
            WETH = IWETH(0x4200000000000000000000000000000000000006);
            FRAX = IERC20(0x2E3D870790dC77A83DD1d18184Acc7439A53f475);
        } else {
            USDC = IERC20(new MockERC20("USDC", "USDC", 6));
            DAI = IERC20(new MockERC20("DAI", "DAI", 18));
            WETH = IWETH(new MockWETH());
            FRAX = new MockERC20("FRAX", "FRAX", 18);
        }
        VELO = new Velo();
        LR = new MockERC20("LR", "LR", 18);
    }

    function mintStables() public {
        for (uint256 i = 0; i < owners.length; i++) {
            deal(address(USDC), owners[i], 1e12 * USDC_1, true);
            deal(address(FRAX), owners[i], 1e12 * TOKEN_1, true);
            deal(address(DAI), owners[i], 1e12 * TOKEN_1, true);
        }
    }

    function mintToken(
        address _token,
        address[] memory _accounts,
        uint256[] memory _amounts
    ) public {
        if (_token == address(WETH)) {
            for (uint256 i = 0; i < _amounts.length; i++) {
                vm.deal(_accounts[i], _amounts[i]);
                vm.prank(address(_accounts[i]));
                WETH.deposit{value: _amounts[i]}();
            }
        } else {
            for (uint256 i = 0; i < _amounts.length; i++) {
                deal(address(_token), _accounts[i], _amounts[i], true);
            }
        }
    }

    function dealETH(address[] memory _accounts, uint256[] memory _amounts) public {
        for (uint256 i = 0; i < _accounts.length; i++) {
            vm.deal(_accounts[i], _amounts[i]);
        }
    }

    function deployFactoriesAndRouter() public {
        factory = new PairFactory();
        assertEq(factory.allPairsLength(), 0);
        factory.setFee(true, 1); // set fee back to 0.01% for old tests
        factory.setFee(false, 1);

        votingRewardsFactory = new VotingRewardsFactory();
        gaugeFactory = new GaugeFactory();
        managedRewardsFactory = new ManagedRewardsFactory();
        factoryRegistry = new FactoryRegistry(
            address(factory),
            address(votingRewardsFactory),
            address(gaugeFactory),
            address(managedRewardsFactory)
        );
    }

    function deployPairWithOwner(address _owner) public {
        _addLiquidityToPool(_owner, address(router), address(FRAX), address(USDC), true, TOKEN_1, USDC_1);
        _addLiquidityToPool(_owner, address(router), address(FRAX), address(USDC), false, TOKEN_1, USDC_1);
        _addLiquidityToPool(_owner, address(router), address(FRAX), address(DAI), true, TOKEN_1, TOKEN_1);
        assertEq(factory.allPairsLength(), 3);

        // last arg default as these are all v2 pairs
        address create2address = router.pairFor(address(FRAX), address(USDC), true, address(0));
        address address1 = factory.getPair(address(FRAX), address(USDC), true);
        pair = Pair(address1);
        address address2 = factory.getPair(address(FRAX), address(USDC), false);
        pair2 = Pair(address2);
        address address3 = factory.getPair(address(FRAX), address(DAI), true);
        pair3 = Pair(address3);
        assertEq(address(pair), create2address);
        assertGt(lib.getAmountOut(USDC_1, address(USDC), address(FRAX), true, address(factory)), 0);
    }

    /// @dev Helper utility to forward time to next week
    ///      note epoch requires at least one second to have
    ///      passed into the new epoch
    function skipToNextEpoch(uint256 offset) public {
        uint256 ts = block.timestamp;
        uint256 nextEpoch = ts - (ts % (1 weeks)) + (1 weeks);
        vm.warp(nextEpoch + offset);
        vm.roll(block.number + 1);
    }

    function skipAndRoll(uint256 timeOffset) public {
        skip(timeOffset);
        vm.roll(block.number + 1);
    }

    /// @dev Helper utility to get start of epoch based on timestamp
    function _getEpochStart(uint256 _timestamp) internal pure returns (uint256) {
        return _timestamp - (_timestamp % (7 days));
    }

    /// @dev Helper function to add rewards to gauge from voter
    function _addRewardToGauge(
        address _voter,
        address _gauge,
        uint256 _amount
    ) internal {
        deal(address(VELO), _voter, _amount);
        vm.startPrank(_voter);
        // do not overwrite approvals if already set
        if (VELO.allowance(_voter, _gauge) < _amount) {
            VELO.approve(_gauge, _amount);
        }
        Gauge(_gauge).notifyRewardAmount(_amount);
        vm.stopPrank();
    }

    /// @dev Helper function to deposit liquidity into pool
    function _addLiquidityToPool(
        address _owner,
        address _router,
        address _token0,
        address _token1,
        bool _stable,
        uint256 _amount0,
        uint256 _amount1
    ) internal {
        vm.startPrank(_owner);
        IERC20(_token0).approve(address(_router), _amount0);
        IERC20(_token1).approve(address(_router), _amount1);
        Router(payable(_router)).addLiquidity(
            _token0,
            _token1,
            _stable,
            _amount0,
            _amount1,
            0,
            0,
            address(_owner),
            block.timestamp
        );
        vm.stopPrank();
    }
}

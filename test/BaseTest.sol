// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Forwarder} from "@opengsn/contracts/src/forwarder/Forwarder.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {FeesVotingReward} from "contracts/rewards/FeesVotingReward.sol";
import {IncentiveVotingReward} from "contracts/rewards/IncentiveVotingReward.sol";
import {IGauge, Gauge} from "contracts/gauges/Gauge.sol";
import {ISinkGauge, SinkGauge} from "contracts/gauges/sink/SinkGauge.sol";
import {IWETH} from "contracts/interfaces/IWETH.sol";
import {IVelo, Velo} from "contracts/Velo.sol";
import {IRouter, Router} from "contracts/Router.sol";
import {IVoter, Voter} from "contracts/Voter.sol";
import {VeArtProxy} from "contracts/VeArtProxy.sol";
import {IVotingEscrow, VotingEscrow} from "contracts/VotingEscrow.sol";
import {ManagedRewardsFactory} from "contracts/factories/ManagedRewardsFactory.sol";
import {VotingRewardsFactory} from "contracts/factories/VotingRewardsFactory.sol";
import {GaugeFactory} from "contracts/factories/GaugeFactory.sol";
import {SinkGaugeFactory} from "contracts/factories/sink/SinkGaugeFactory.sol";
import {PoolFactory, IPoolFactory} from "contracts/factories/PoolFactory.sol";
import {SinkPoolFactory} from "contracts/factories/sink/SinkPoolFactory.sol";
import {IFactoryRegistry, FactoryRegistry} from "contracts/factories/FactoryRegistry.sol";
import {Pool} from "contracts/Pool.sol";
import {SinkPool} from "contracts/sink/SinkPool.sol";
import {IMinter, Minter} from "contracts/Minter.sol";
import {IReward, Reward} from "contracts/rewards/Reward.sol";
import {RewardsDistributor, IRewardsDistributor} from "contracts/RewardsDistributor.sol";
import {VeloGovernor} from "contracts/VeloGovernor.sol";
import {IGovernor, EpochGovernor} from "contracts/EpochGovernor.sol";
import {SimpleEpochGovernor} from "contracts/SimpleEpochGovernor.sol";
import {SafeCastLibrary} from "contracts/libraries/SafeCastLibrary.sol";
import {VelodromeTimeLibrary} from "contracts/libraries/VelodromeTimeLibrary.sol";

import {FreeManagedReward} from "contracts/rewards/FreeManagedReward.sol";
import {LockedManagedReward} from "contracts/rewards/LockedManagedReward.sol";

import {GovernorCommentable} from "contracts/governance/GovernorCommentable.sol";
import {IGovernorCommentable} from "contracts/governance/IGovernorCommentable.sol";
import {IGovernorProposalWindow} from "contracts/governance/IGovernorProposalWindow.sol";

import {IPool, Pool} from "contracts/Pool.sol";
import {TestOwner} from "test/utils/TestOwner.sol";
import {MockERC20} from "test/utils/MockERC20.sol";
import {MockWETH} from "test/utils/MockWETH.sol";
import {SigUtils} from "test/utils/SigUtils.sol";
import {MockRelay} from "test/utils/MockRelay.sol";

import {DeployVelodromeV2} from "../script/DeployVelodromeV2.s.sol";

abstract contract BaseTest is Test, TestOwner {
    using stdStorage for StdStorage;

    enum Deployment {
        DEFAULT,
        FORK,
        CUSTOM
    }

    /// @dev Determines whether or not to use the base set up configuration
    ///      Local v2 deployment used by default
    Deployment deploymentType;

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
    uint256 constant POOL_1 = 1e9;

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
    MockERC20 WEVE;
    MockERC20 LR; // late reward

    Pool pool;
    Pool pool2;
    Pool pool3;

    FeesVotingReward feesVotingReward;
    IncentiveVotingReward incentiveVotingReward;
    Gauge gauge2;
    FeesVotingReward feesVotingReward2;
    IncentiveVotingReward incentiveVotingReward2;
    Gauge gauge3;
    FeesVotingReward feesVotingReward3;
    IncentiveVotingReward incentiveVotingReward3;

    SinkPoolFactory sinkPoolFactory;
    SinkPool sinkPool;
    SinkGaugeFactory sinkGaugeFactory;
    SinkGauge sinkGauge;

    DeployVelodromeV2 deployVelodromeV2;

    address[] public tokens;

    IWETH public WETH;
    Velo public VELO;

    Forwarder public forwarder;
    Pool public implementation;
    Router public router;
    VotingEscrow public escrow;
    VeArtProxy public artProxy;
    PoolFactory public factory;
    FactoryRegistry public factoryRegistry;
    GaugeFactory public gaugeFactory;
    VotingRewardsFactory public votingRewardsFactory;
    ManagedRewardsFactory public managedRewardsFactory;
    Voter public voter;
    RewardsDistributor public distributor;
    Minter public minter;
    Gauge public gauge;
    VeloGovernor public governor;
    EpochGovernor public epochGovernor;

    /// @dev Global address to set
    address public allowedManager;

    SigUtils sigUtils;

    uint256 optimismFork;
    /// @dev set OPTIMISM_RPC_URL in .env to run mainnet tests
    string OPTIMISM_RPC_URL = vm.envString("OPTIMISM_RPC_URL");
    /// @dev optionally set FORK_BLOCK_NUMBER in .env / test set up for faster tests / fixed tests
    uint256 BLOCK_NUMBER = vm.envOr("FORK_BLOCK_NUMBER", uint256(0));

    /// @dev Default set up of local v2 deployment run if Deployment.DEFAULT selected
    ///      Mainnet fork + v2 deployment if Deployment.FORK selected
    ///      Only _setUp function run if Deployment.CUSTOM selected
    ///      _setUp can be overriden to provide additional configuration if desired
    ///      To set up mainnet forks from a certain block (e.g. to fix venft balances for testing)
    ///      Use a CUSTOM deployment, and call _forkSetUp with the desired block number
    function setUp() public {
        if (deploymentType == Deployment.DEFAULT) {
            _testSetup();
        } else if (deploymentType == Deployment.FORK) {
            _forkSetup();
        }
        _setUp();
    }

    /// @dev Implement this if you want a custom configured deployment
    function _setUp() public virtual {}

    /// @dev Note that most permissions are given to owner
    function _testSetup() public {
        _testSetupBefore();
        _deployAndSet();
        _testSetupAfter();
    }

    function _forkSetup() public {
        _forkSetupBefore();
        _testSetup();
    }

    function _deployAndSet() public {
        deployVelodromeV2 = new DeployVelodromeV2();
        stdstore.target(address(deployVelodromeV2)).sig("isTest()").checked_write(true);
        stdstore.target(address(deployVelodromeV2)).sig("deployerAddress()").checked_write(address(owner));
        stdstore.target(address(deployVelodromeV2)).sig("allowedManager()").checked_write(address(allowedManager)); //owner
        stdstore.target(address(deployVelodromeV2)).sig("WETH()").checked_write(address(WETH));

        deployVelodromeV2.run();

        implementation = deployVelodromeV2.implementation();
        factory = deployVelodromeV2.factory();
        votingRewardsFactory = deployVelodromeV2.votingRewardsFactory();
        gaugeFactory = deployVelodromeV2.gaugeFactory();
        factoryRegistry = deployVelodromeV2.factoryRegistry();
        managedRewardsFactory = deployVelodromeV2.managedRewardsFactory();

        forwarder = deployVelodromeV2.forwarder();
        router = deployVelodromeV2.router();
        escrow = deployVelodromeV2.escrow();
        artProxy = deployVelodromeV2.artProxy();
        voter = deployVelodromeV2.voter();
        distributor = deployVelodromeV2.distributor();
        minter = deployVelodromeV2.minter();

        VELO = deployVelodromeV2.VELO();

        uint256[] memory amounts = new uint256[](5);
        amounts[0] = TOKEN_10M;
        amounts[1] = TOKEN_10M;
        amounts[2] = TOKEN_10M;
        amounts[3] = TOKEN_10M;
        amounts[4] = TOKEN_10M;
        mintToken(address(VELO), owners, amounts);
        tokens.push(address(VELO));

        // re-initialize voter with the test tokens
        vm.prank(address(minter));
        voter.initialize(tokens, address(minter));
    }

    function deployFactories() public {
        implementation = new Pool();
        factory = new PoolFactory(address(implementation));

        votingRewardsFactory = new VotingRewardsFactory();
        gaugeFactory = new GaugeFactory();
        managedRewardsFactory = new ManagedRewardsFactory();
        factoryRegistry = new FactoryRegistry(
            address(factory), address(votingRewardsFactory), address(gaugeFactory), address(managedRewardsFactory)
        );
    }

    function _testSetupBefore() public {
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
        mintToken(address(LR), owners, amounts);

        tokens.push(address(USDC));
        tokens.push(address(FRAX));
        tokens.push(address(DAI));
        tokens.push(address(LR));
        tokens.push(address(WETH));

        allowedManager = address(owner);
    }

    function _testSetupAfter() public {
        // Setup governors
        governor = new VeloGovernor(escrow, IVoter(voter));
        epochGovernor = new EpochGovernor(escrow, address(minter), address(owner));
        voter.setEpochGovernor(address(epochGovernor));
        voter.setGovernor(address(governor));

        assertEq(factory.allPoolsLength(), 0);
        assertEq(router.defaultFactory(), address(factory));

        deployPoolWithOwner(address(owner));

        // USDC - FRAX stable
        gauge = Gauge(voter.createGauge(address(factory), address(pool)));
        feesVotingReward = FeesVotingReward(voter.gaugeToFees(address(gauge)));
        incentiveVotingReward = IncentiveVotingReward(voter.gaugeToIncentive(address(gauge)));

        // USDC - FRAX unstable
        gauge2 = Gauge(voter.createGauge(address(factory), address(pool2)));
        feesVotingReward2 = FeesVotingReward(voter.gaugeToFees(address(gauge2)));
        incentiveVotingReward2 = IncentiveVotingReward(voter.gaugeToIncentive(address(gauge2)));

        // FRAX - DAI stable
        gauge3 = Gauge(voter.createGauge(address(factory), address(pool3)));
        feesVotingReward3 = FeesVotingReward(voter.gaugeToFees(address(gauge3)));
        incentiveVotingReward3 = IncentiveVotingReward(voter.gaugeToIncentive(address(gauge3)));

        bytes32 domainSeparator = keccak256(
            abi.encode(
                escrow.DOMAIN_TYPEHASH(),
                keccak256(bytes(escrow.name())),
                keccak256(bytes(escrow.version())),
                block.chainid,
                address(escrow)
            )
        );
        sigUtils = new SigUtils(domainSeparator);

        vm.label(address(owner), "Owner");
        vm.label(address(owner2), "Owner 2");
        vm.label(address(owner3), "Owner 3");
        vm.label(address(owner4), "Owner 4");
        vm.label(address(owner5), "Owner 5");
        vm.label(address(USDC), "USDC");
        vm.label(address(FRAX), "FRAX");
        vm.label(address(DAI), "DAI");
        vm.label(address(WETH), "WETH");
        vm.label(address(LR), "Incentive Voting Reward");
        vm.label(address(factory), "Pool Factory");
        vm.label(address(factoryRegistry), "Factory Registry");
        vm.label(address(router), "Router");
        vm.label(address(pool), "Pool");
        vm.label(address(pool2), "Pool 2");
        vm.label(address(pool3), "Pool 3");

        vm.label(address(escrow), "Voting Escrow");
        vm.label(address(gaugeFactory), "Gauge Factory");
        vm.label(address(votingRewardsFactory), "Voting Rewards Factory");
        vm.label(address(voter), "Voter");
        vm.label(address(distributor), "Distributor");
        vm.label(address(minter), "Minter");
        vm.label(address(gauge), "Gauge");
        vm.label(address(governor), "Governor");
        vm.label(address(feesVotingReward), "Fees Voting Reward");
        vm.label(address(incentiveVotingReward), "Incentive Voting Reward");
        vm.label(address(gauge2), "Gauge 2");
        vm.label(address(feesVotingReward2), "Fees Voting Reward 2");
        vm.label(address(incentiveVotingReward2), "Incentive Voting Reward 2");
        vm.label(address(gauge3), "Gauge 3");
        vm.label(address(feesVotingReward3), "Fees Voting Reward 3");
        vm.label(address(incentiveVotingReward3), "Incentive Voting Reward 3");
    }

    function _forkSetupBefore() public {
        if (BLOCK_NUMBER != 0) {
            optimismFork = vm.createFork(OPTIMISM_RPC_URL, BLOCK_NUMBER);
        } else {
            optimismFork = vm.createFork(OPTIMISM_RPC_URL);
        }
        vm.selectFork(optimismFork);
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
        LR = new MockERC20("LR", "LR", 18);
    }

    function mintStables() public {
        for (uint256 i = 0; i < owners.length; i++) {
            deal(address(USDC), owners[i], 1e12 * USDC_1, true);
            deal(address(FRAX), owners[i], 1e12 * TOKEN_1, true);
            deal(address(DAI), owners[i], 1e12 * TOKEN_1, true);
        }
    }

    function mintToken(address _token, address[] memory _accounts, uint256[] memory _amounts) public {
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

    function deployPoolWithOwner(address _owner) public {
        _addLiquidityToPool(_owner, address(router), address(FRAX), address(USDC), true, TOKEN_1, USDC_1);
        _addLiquidityToPool(_owner, address(router), address(FRAX), address(USDC), false, TOKEN_1, USDC_1);
        _addLiquidityToPool(_owner, address(router), address(FRAX), address(DAI), true, TOKEN_1, TOKEN_1);
        assertEq(factory.allPoolsLength(), 3);

        // last arg default as these are all v2 pools
        address create2address = router.poolFor(address(FRAX), address(USDC), true, address(0));
        address address1 = factory.getPool(address(FRAX), address(USDC), true);
        pool = Pool(address1);
        address address2 = factory.getPool(address(FRAX), address(USDC), false);
        pool2 = Pool(address2);
        address address3 = factory.getPool(address(FRAX), address(DAI), true);
        pool3 = Pool(address3);
        assertEq(address(pool), create2address);
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
    function _addRewardToGauge(address _voter, address _gauge, uint256 _amount) internal {
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
            _token0, _token1, _stable, _amount0, _amount1, 0, 0, address(_owner), block.timestamp
        );
        vm.stopPrank();
    }

    /// @dev Used to convert IVotingEscrow int128s to uint256
    ///      These values are always positive
    function convert(int128 _amount) internal pure returns (uint256) {
        return uint256(uint128(_amount));
    }

    /// @dev Used to convert uint256 to int128s
    ///      Can be negative
    function toInt128(uint256 value) internal pure returns (int128) {
        return int128(uint128(value));
    }
}

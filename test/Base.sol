// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {ManagedRewardsFactory} from "contracts/factories/ManagedRewardsFactory.sol";
import {VotingRewardsFactory} from "contracts/factories/VotingRewardsFactory.sol";
import {GaugeFactory} from "contracts/factories/GaugeFactory.sol";
import {PoolFactory, IPoolFactory} from "contracts/factories/PoolFactory.sol";
import {IFactoryRegistry, FactoryRegistry} from "contracts/factories/FactoryRegistry.sol";
import {Pool} from "contracts/Pool.sol";
import {IMinter, Minter} from "contracts/Minter.sol";
import {IReward, Reward} from "contracts/rewards/Reward.sol";
import {FeesVotingReward} from "contracts/rewards/FeesVotingReward.sol";
import {BribeVotingReward} from "contracts/rewards/BribeVotingReward.sol";
import {FreeManagedReward} from "contracts/rewards/FreeManagedReward.sol";
import {LockedManagedReward} from "contracts/rewards/LockedManagedReward.sol";
import {IGauge, Gauge} from "contracts/gauges/Gauge.sol";
import {PoolFees} from "contracts/PoolFees.sol";
import {RewardsDistributor, IRewardsDistributor} from "contracts/RewardsDistributor.sol";
import {IRouter, Router} from "contracts/Router.sol";
import {IVelo, Velo} from "contracts/Velo.sol";
import {IVoter, Voter} from "contracts/Voter.sol";
import {VeArtProxy} from "contracts/VeArtProxy.sol";
import {IVotingEscrow, VotingEscrow} from "contracts/VotingEscrow.sol";
import {VeloGovernor} from "contracts/VeloGovernor.sol";
import {EpochGovernor} from "contracts/EpochGovernor.sol";
import {SafeCastLibrary} from "contracts/libraries/SafeCastLibrary.sol";
import {SinkManagerFacilitator} from "contracts/v1/sink/SinkManagerFacilitator.sol";
import {ISinkManager, SinkManager} from "contracts/v1/sink/SinkManager.sol";
import {SinkDrain} from "contracts/v1/sink/SinkDrain.sol";
import {SinkConverter} from "contracts/v1/sink/SinkConverter.sol";
import {IGaugeV1} from "contracts/interfaces/v1/IGaugeV1.sol";
import {IMinterV1} from "contracts/interfaces/v1/IMinterV1.sol";
import {IVoterV1} from "contracts/interfaces/v1/IVoterV1.sol";
import {IVotingEscrowV1} from "contracts/interfaces/v1/IVotingEscrowV1.sol";
import {IRewardsDistributorV1} from "contracts/interfaces/v1/IRewardsDistributorV1.sol";
import {IWETH} from "contracts/interfaces/IWETH.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SigUtils} from "test/utils/SigUtils.sol";
import {Forwarder} from "@opengsn/contracts/src/forwarder/Forwarder.sol";

import "forge-std/Script.sol";
import "forge-std/Test.sol";

/// @notice Base contract used for tests and deployment scripts
abstract contract Base is Script, Test {
    enum Deployment {
        DEFAULT,
        FORK,
        CUSTOM
    }
    /// @dev Determines whether or not to use the base set up configuration
    ///      Local v2 deployment used by default
    Deployment deploymentType;

    IWETH public WETH;
    Velo public VELO;
    address[] public tokens;

    /// @dev Core v2 Deployment
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

    /// @dev velodrome v1 contracts
    Velo public vVELO;
    IVotingEscrowV1 public vEscrow;
    IVoterV1 public vVoter;
    PoolFactory public vFactory;
    Router public vRouter;
    VeloGovernor public vGov;
    IRewardsDistributorV1 public vDistributor;
    IMinterV1 public vMinter;

    /// @dev additional contracts required by v2
    address public facilitatorImplementation;
    SinkManager public sinkManager;
    IGaugeV1 public gaugeSinkDrain;
    SinkDrain public sinkDrain;
    SinkConverter public sinkConverter;

    /// @dev tokenId of nft owned by sinkManager
    uint256 public ownedTokenId;

    /// @dev Global address to set
    address public allowedManager;

    function _coreSetup() public {
        deployFactories();

        forwarder = new Forwarder();

        escrow = new VotingEscrow(address(forwarder), address(VELO), address(factoryRegistry));
        artProxy = new VeArtProxy(address(escrow));
        escrow.setArtProxy(address(artProxy));

        // Setup voter and distributor
        distributor = new RewardsDistributor(address(escrow));
        voter = new Voter(address(forwarder), address(escrow), address(factoryRegistry), address(vFactory));

        escrow.setVoterAndDistributor(address(voter), address(distributor));
        escrow.setAllowedManager(allowedManager);

        // Setup router
        router = new Router(
            address(forwarder),
            address(factoryRegistry),
            address(vFactory),
            address(factory),
            address(voter),
            address(WETH)
        );

        // Setup minter
        minter = new Minter(address(voter), address(escrow), address(distributor));
        distributor.setMinter(address(minter));
        VELO.setMinter(address(minter));

        /// @dev tokens are already set in the respective setupBefore()
        voter.initialize(tokens, address(minter));
    }

    function _sinkSetup() public {
        // layer on additional contracts required by v2 deployment
        /// @dev manager.setOwnedTokenId()/setSinkDrain() ar(e) set in either forkSetupAfter()
        facilitatorImplementation = address(new SinkManagerFacilitator());
        sinkManager = new SinkManager(
            address(forwarder),
            address(sinkDrain),
            facilitatorImplementation,
            address(vVoter),
            address(vVELO),
            address(VELO),
            address(vEscrow),
            address(escrow),
            address(vDistributor)
        );

        sinkConverter = new SinkConverter(address(sinkManager));
        factory.setSinkConverter(address(sinkConverter), address(vVELO), address(VELO));
        VELO.setSinkManager(address(sinkManager));
    }

    function _loadV1(string memory constantsFilename) public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/script/constants/");
        path = string.concat(path, constantsFilename);

        string memory json = vm.readFile(path);

        vVELO = Velo(abi.decode(vm.parseJson(json, ".v1.VELO"), (address)));
        vEscrow = IVotingEscrowV1(abi.decode(vm.parseJson(json, ".v1.VotingEscrow"), (address)));
        vVoter = IVoterV1(abi.decode(vm.parseJson(json, ".v1.Voter"), (address)));
        vFactory = PoolFactory(abi.decode(vm.parseJson(json, ".v1.Factory"), (address)));
        vRouter = Router(payable(abi.decode(vm.parseJson(json, ".v1.Router"), (address))));
        vGov = VeloGovernor(payable(abi.decode(vm.parseJson(json, ".v1.Gov"), (address))));
        vDistributor = IRewardsDistributorV1(abi.decode(vm.parseJson(json, ".v1.Distributor"), (address)));
        vMinter = IMinterV1(abi.decode(vm.parseJson(json, ".v1.Minter"), (address)));
    }

    function deployFactories() public {
        implementation = new Pool();
        factory = new PoolFactory(address(implementation));

        votingRewardsFactory = new VotingRewardsFactory();
        gaugeFactory = new GaugeFactory();
        managedRewardsFactory = new ManagedRewardsFactory();
        factoryRegistry = new FactoryRegistry(
            address(factory),
            address(votingRewardsFactory),
            address(gaugeFactory),
            address(managedRewardsFactory)
        );
        // approve factory registry path to create gauges from v1 pools
        if (address(vFactory) != address(0)) {
            factoryRegistry.approve(address(vFactory), address(votingRewardsFactory), address(gaugeFactory));
        }
    }
}

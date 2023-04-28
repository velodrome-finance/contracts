// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/StdJson.sol";
import "../test/Base.sol";

contract DeployVelodromeV2 is Base {
    using stdJson for string;
    string basePath;
    string path;

    uint256 deployPrivateKey = vm.envUint("PRIVATE_KEY_DEPLOY");
    address deployPublicKey = vm.addr(deployPrivateKey);
    string constantsFilename = vm.envString("CONSTANTS_FILENAME");
    string outputFilename = vm.envString("OUTPUT_FILENAME");
    string jsonConstants;
    string jsonOutput;

    // Vars to be set in each deploy script
    address feeManager;
    address team;
    address sinkDrainAddr;
    address gaugeSinkDrainAddr;

    constructor() {
        string memory root = vm.projectRoot();
        basePath = string.concat(root, "/script/constants/");

        // load constants
        path = string.concat(basePath, constantsFilename);
        jsonConstants = vm.readFile(path);
        WETH = IWETH(abi.decode(vm.parseJson(jsonConstants, ".WETH"), (address)));
        allowedManager = abi.decode(vm.parseJson(jsonConstants, ".allowedManager"), (address));
        team = abi.decode(vm.parseJson(jsonConstants, ".team"), (address));
        feeManager = abi.decode(vm.parseJson(jsonConstants, ".feeManager"), (address));
    }

    function run() public {
        _loadV1(constantsFilename);
        _deploySetupBefore();
        _coreSetup();
        _sinkSetup();
        _deploySetupAfter();
    }

    function _deploySetupBefore() public {
        // more constants loading - this needs to be done in-memory and not storage
        address[] memory _tokens = abi.decode(vm.parseJson(jsonConstants, ".whitelistTokens"), (address[]));
        for (uint256 i = 0; i < _tokens.length; i++) {
            tokens.push(_tokens[i]);
        }

        // Loading output and use output path to later save deployed contracts
        basePath = string.concat(basePath, "output/");
        path = string.concat(basePath, "DeployVelodromeV2-");
        path = string.concat(path, outputFilename);
        jsonOutput = vm.readFile(path);
        sinkDrain = SinkDrain(abi.decode(vm.parseJson(jsonOutput, ".SinkDrain"), (address)));
        gaugeSinkDrainAddr = vVoter.gauges(address(sinkDrain));

        // block script from running if the sinkDrain gauge has not been created
        assertTrue(gaugeSinkDrainAddr != address(0));

        // block script if deployer does not have enough VELO to create a lock for sinkManager
        assertGt(vVELO.balanceOf(deployPublicKey), 1e18 - 1);

        // start broadcasting transactions
        vm.startBroadcast(deployPrivateKey);

        // deploy VELO
        VELO = new Velo();

        tokens.push(address(VELO));
    }

    function _deploySetupAfter() public {
        // Setup sinkManager
        vVELO.approve(address(vEscrow), 1e18);
        ownedTokenId = vEscrow.create_lock_for(1e18, 4 * 365 * 86400, address(sinkManager));
        sinkManager.setOwnedTokenId(ownedTokenId);
        sinkDrain.mint(address(sinkManager));
        sinkManager.setupSinkDrain(gaugeSinkDrainAddr);
        sinkManager.renounceOwnership();

        // Set protocol state to team
        escrow.setTeam(team);
        factory.setPauser(team);
        voter.setEmergencyCouncil(team);
        voter.setEpochGovernor(team);
        voter.setGovernor(team);
        factoryRegistry.transferOwnership(team);

        // Set contract vars
        factory.setFeeManager(feeManager);
        factory.setVoter(address(voter));

        // finish broadcasting transactions
        vm.stopBroadcast();

        // write to file
        vm.writeJson(vm.serializeAddress("v2", "SinkDrain", address(sinkDrain)), path);
        vm.writeJson(vm.serializeAddress("v2", "GaugeSinkDrain", gaugeSinkDrainAddr), path);
        vm.writeJson(vm.serializeAddress("v2", "VELO", address(VELO)), path);
        vm.writeJson(vm.serializeAddress("v2", "VotingEscrow", address(escrow)), path);
        vm.writeJson(vm.serializeAddress("v2", "Forwarder", address(forwarder)), path);
        vm.writeJson(vm.serializeAddress("v2", "ArtProxy", address(artProxy)), path);
        vm.writeJson(vm.serializeAddress("v2", "Distributor", address(distributor)), path);
        vm.writeJson(vm.serializeAddress("v2", "Voter", address(voter)), path);
        vm.writeJson(vm.serializeAddress("v2", "Router", address(router)), path);
        vm.writeJson(vm.serializeAddress("v2", "Minter", address(minter)), path);
        vm.writeJson(vm.serializeAddress("v2", "PairFactory", address(factory)), path);
        vm.writeJson(vm.serializeAddress("v2", "VotingRewardsFactory", address(votingRewardsFactory)), path);
        vm.writeJson(vm.serializeAddress("v2", "GaugeFactory", address(gaugeFactory)), path);
        vm.writeJson(vm.serializeAddress("v2", "ManagedRewardsFactory", address(managedRewardsFactory)), path);
        vm.writeJson(vm.serializeAddress("v2", "FactoryRegistry", address(factoryRegistry)), path);
        vm.writeJson(
            vm.serializeAddress("v2", "SinkManagerFacilitatorImplementation", address(facilitatorImplementation)),
            path
        );
        vm.writeJson(vm.serializeAddress("v2", "SinkManager", address(sinkManager)), path);
        vm.writeJson(vm.serializeAddress("v2", "SinkConverter", address(sinkConverter)), path);
        vm.writeJson(vm.serializeUint("v2", "ownedTokenId", ownedTokenId), path);
    }
}

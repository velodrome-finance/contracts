// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/StdJson.sol";
import "../test/Base.sol";

contract Deploy is Base {

    using stdJson for string;

    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address deployerPublicKey = vm.envAddress("PUBLIC_KEY");
    string chainName = vm.envString("CHAIN_NAME");
    string json;

    // Vars to be set in each deploy script
    address feeManager;

    struct Pair {
        bool stable;
        address tokenA;
        address tokenB;
    }

    constructor() {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/script/constants/");
        path = string.concat(path, chainName);
        path = string.concat(path, ".json");

        json = vm.readFile(path);
    }

    function run() public {
        _deploySetupBefore();
        _coreSetup();
        _loadV1(chainName);
        _sinkSetup();
        _deploySetupAfter();
    }

    function _deploySetupBefore() public {
        // Set state
        WETH = IWETH(abi.decode(vm.parseJson(json, "WETH"), (address)));
        ownedTokenId = abi.decode(vm.parseJson(json, ".ownedTokenId"), (uint256));
        allowedManager = abi.decode(vm.parseJson(json, ".allowedManager"), (address));
        team = abi.decode(vm.parseJson(json, ".team"), (address));
        feeManager = abi.decode(vm.parseJson(json, ".feeManager"), (address));
        address[] memory _tokens = abi.decode(vm.parseJson(json, ".tokens"), (address[]));
        for (uint256 i=0; i<_tokens.length; i++) {
            tokens.push(_tokens[i]);
        }

        // start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // deploy VELO
        VELO = new Velo();

        tokens.push(address(VELO));
    }

    function _deploySetupAfter() public {
        
        // Set contract vars and such
        factory.setFeeManager(feeManager);
        factory.setPauser(team);
        voter.setEmergencyCouncil(team);
        governor.setTeam(team);

        // Deploy all pairs and gauges
        Pair[] memory pairs = abi.decode(json.parseRaw(".pairs"), (Pair[]));

        address pair;
        for (uint256 i=0; i<pairs.length; i++) {
            pair = factory.createPair(pairs[i].tokenA, pairs[i].tokenB, pairs[i].stable);
            voter.createGauge(
                address(factory),
                address(votingRewardsFactory),
                address(gaugeFactory),
                pair
            );
        }

        // finish broadcasting transactions
        vm.stopBroadcast();
    }
}
// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/StdJson.sol";
import "../script/DeploySinkDrain.s.sol";
import "../script/DeployVelodromeV2.s.sol";
import "../script/DeployGaugesV1.s.sol";
import "../script/DeployGaugesAndPairsV2.s.sol";
import "../script/DeployGovernors.s.sol";

import "./BaseTest.sol";

contract TestDeploy is BaseTest {
    using stdJson for string;

    uint256 deployPrivateKey = vm.envUint("PRIVATE_KEY_DEPLOY");
    address deployPublicKey = vm.addr(deployPrivateKey);
    string constantsFilename = vm.envString("CONSTANTS_FILENAME");
    string jsonConstants;

    address feeManager;
    address team;

    struct PairV2 {
        bool stable;
        address tokenA;
        address tokenB;
    }

    // Scripts to test
    DeploySinkDrain deploySinkDrain;
    DeployVelodromeV2 deployVelodromeV2;
    DeployGaugesV1 deployGaugesV1;
    DeployGaugesAndPairsV2 deployGaugesAndPairsV2;
    DeployGovernors deployGovernors;

    constructor() {
        deploymentType = Deployment.CUSTOM;
    }

    function _setUp() public override {
        _forkSetupBefore(constantsFilename);
        deal(address(vVELO), deployPublicKey, 1e18);

        deploySinkDrain = new DeploySinkDrain();
        deployVelodromeV2 = new DeployVelodromeV2();
        deployGaugesV1 = new DeployGaugesV1();
        deployGaugesAndPairsV2 = new DeployGaugesAndPairsV2();
        deployGovernors = new DeployGovernors();

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/script/constants/");
        path = string.concat(path, constantsFilename);

        jsonConstants = vm.readFile(path);

        WETH = IWETH(abi.decode(vm.parseJson(jsonConstants, ".WETH"), (address)));
        allowedManager = abi.decode(vm.parseJson(jsonConstants, ".allowedManager"), (address));
        team = abi.decode(vm.parseJson(jsonConstants, ".team"), (address));
        feeManager = abi.decode(vm.parseJson(jsonConstants, ".feeManager"), (address));
    }

    function testLoadedState() public {
        // If tests fail at this point- you need to set the .env and the constants used for deployment.
        // Refer to script/README.md
        assertTrue(deployPublicKey != address(0));
        assertTrue(address(WETH) != address(0));
        assertTrue(allowedManager != address(0));
        assertTrue(team != address(0));
        assertTrue(feeManager != address(0));
    }

    function testDeployScript() public {
        deploySinkDrain.run();
        sinkDrain = deploySinkDrain.sinkDrain();

        // simulate gov creating a gauge of the sinkDrain
        vm.prank(vVoter.governor());
        vVoter.createGauge(address(sinkDrain));

        deployVelodromeV2.run();
        deployGaugesV1.run();
        deployGaugesAndPairsV2.run();
        deployGovernors.run();

        assertEq(deployVelodromeV2.voter().epochGovernor(), team);
        assertEq(deployVelodromeV2.voter().governor(), team);

        // Simulate team setting and accepting governance roles
        vm.startPrank(team);
        assertTrue(address(deployGovernors.governor()) != address(0));
        assertTrue(address(deployGovernors.epochGovernor()) != address(0));
        assertEq(deployGovernors.governor().pendingVetoer(), deployVelodromeV2.escrow().team());
        assertEq(deployGovernors.governor().vetoer(), deployPublicKey);
        deployVelodromeV2.voter().setEpochGovernor(address(deployGovernors.epochGovernor()));
        deployVelodromeV2.voter().setGovernor(address(deployGovernors.governor()));
        deployGovernors.governor().acceptVetoer();
        vm.stopPrank();

        // DeployVelodromeV2 checks

        // ensure all tokens are added to voter
        address[] memory _tokens = abi.decode(vm.parseJson(jsonConstants, ".whitelistTokens"), (address[]));
        for (uint256 i = 0; i < _tokens.length; i++) {
            address token = _tokens[i];
            assertTrue(deployVelodromeV2.voter().isWhitelistedToken(token));
        }
        assertTrue(deployVelodromeV2.voter().isWhitelistedToken(address(deployVelodromeV2.VELO())));

        assertTrue(address(deployVelodromeV2.vVELO()) != address(0));
        assertTrue(address(deployVelodromeV2.vEscrow()) != address(0));
        assertTrue(address(deployVelodromeV2.WETH()) == address(WETH));
        assertTrue(address(deployVelodromeV2.vDistributor()) != address(0));

        // PairFactory
        assertEq(deployVelodromeV2.factory().sinkConverter(), address(deployVelodromeV2.sinkConverter()));
        assertEq(deployVelodromeV2.factory().velo(), address(deployVelodromeV2.vVELO()));
        assertEq(deployVelodromeV2.factory().veloV2(), address(deployVelodromeV2.VELO()));

        // v2 core
        // From _coreSetup()
        assertTrue(address(deployVelodromeV2.forwarder()) != address(0));
        assertEq(address(deployVelodromeV2.artProxy().ve()), address(deployVelodromeV2.escrow()));
        assertEq(deployVelodromeV2.escrow().voter(), address(deployVelodromeV2.voter()));
        assertEq(deployVelodromeV2.escrow().artProxy(), address(deployVelodromeV2.artProxy()));
        assertEq(deployVelodromeV2.escrow().allowedManager(), allowedManager);
        assertEq(deployVelodromeV2.distributor().ve(), address(deployVelodromeV2.escrow()));
        assertEq(deployVelodromeV2.router().defaultFactory(), address(deployVelodromeV2.factory()));
        assertEq(deployVelodromeV2.router().voter(), address(deployVelodromeV2.voter()));
        assertEq(address(deployVelodromeV2.router().weth()), address(WETH));
        assertEq(deployVelodromeV2.distributor().depositor(), address(deployVelodromeV2.minter()));
        assertEq(deployVelodromeV2.VELO().minter(), address(deployVelodromeV2.minter()));
        assertEq(deployVelodromeV2.VELO().sinkManager(), address(deployVelodromeV2.sinkManager()));

        assertEq(deployVelodromeV2.voter().minter(), address(deployVelodromeV2.minter()));
        assertEq(address(deployVelodromeV2.minter().velo()), address(deployVelodromeV2.VELO()));
        assertEq(address(deployVelodromeV2.minter().voter()), address(deployVelodromeV2.voter()));
        assertEq(address(deployVelodromeV2.minter().ve()), address(deployVelodromeV2.escrow()));
        assertEq(address(deployVelodromeV2.minter().rewardsDistributor()), address(deployVelodromeV2.distributor()));

        // SinkManager
        assertTrue(deployVelodromeV2.facilitatorImplementation() != address(0));
        assertEq(
            deployVelodromeV2.sinkManager().facilitatorImplementation(),
            deployVelodromeV2.facilitatorImplementation()
        );
        assertEq(address(deployVelodromeV2.sinkManager().voter()), address(deployVelodromeV2.vVoter()));
        assertEq(address(deployVelodromeV2.sinkManager().velo()), address(deployVelodromeV2.vVELO()));
        assertEq(address(deployVelodromeV2.sinkManager().veloV2()), address(deployVelodromeV2.VELO()));
        assertEq(address(deployVelodromeV2.sinkManager().ve()), address(deployVelodromeV2.vEscrow()));
        assertEq(address(deployVelodromeV2.sinkManager().veV2()), address(deployVelodromeV2.escrow()));
        assertEq(
            address(deployVelodromeV2.sinkManager().rewardsDistributor()),
            address(deployVelodromeV2.vDistributor())
        );
        assertGt(deployVelodromeV2.sinkManager().ownedTokenId(), 0);
        assertTrue(address(deployVelodromeV2.sinkManager().gauge()) != address(0));
        assertEq(deployVelodromeV2.sinkManager().owner(), address(0));

        // Additional sets from DeployVelodromeV2 script
        assertEq(deployVelodromeV2.sinkDrain().owner(), address(0));
        assertEq(deployVelodromeV2.escrow().team(), team);
        assertEq(deployVelodromeV2.factory().pauser(), team);
        assertEq(deployVelodromeV2.voter().emergencyCouncil(), team);
        assertEq(deployVelodromeV2.factoryRegistry().owner(), team);
        assertEq(deployVelodromeV2.factory().feeManager(), feeManager);
        assertEq(deployVelodromeV2.factory().voter(), address(deployVelodromeV2.voter()));

        // ensure all gauges for v1 pairs were created - DeployGaugesV1
        address[] memory pairsV1 = abi.decode(jsonConstants.parseRaw(".pairsV1"), (address[]));
        for (uint256 i = 0; i < pairsV1.length; i++) {
            Pair p = Pair(pairsV1[i]);
            address pairAddr = deployVelodromeV2.vFactory().getPair(p.token0(), p.token1(), p.stable());
            assertTrue(pairAddr != address(0));
            address gaugeAddr = deployVelodromeV2.voter().gauges(pairAddr);
            assertTrue(gaugeAddr != address(0));
        }

        // ensure all v2 pairs were created with their respective gauges - DeployGaugesAndPairsV2
        PairV2[] memory pairsV2 = abi.decode(jsonConstants.parseRaw(".pairsV2"), (PairV2[]));
        for (uint256 i = 0; i < pairsV2.length; i++) {
            PairV2 memory p = pairsV2[i];
            address pairAddr = deployVelodromeV2.factory().getPair(p.tokenA, p.tokenB, p.stable);
            assertTrue(pairAddr != address(0));
            address gaugeAddr = deployVelodromeV2.voter().gauges(pairAddr);
            assertTrue(gaugeAddr != address(0));
        }

        // Check governors - DeployGovernor
        assertEq(deployVelodromeV2.voter().epochGovernor(), address(deployGovernors.epochGovernor()));
        assertEq(deployVelodromeV2.voter().governor(), address(deployGovernors.governor()));
        assertEq(deployGovernors.governor().pendingVetoer(), address(0));
        assertEq(deployGovernors.governor().vetoer(), deployVelodromeV2.escrow().team());
    }
}

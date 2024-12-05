// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "forge-std/Test.sol";
import "forge-std/StdJson.sol";
import "../script/DeployGovernors.s.sol";

import "./BaseTest.sol";

contract TestDeploy is BaseTest {
    using stdJson for string;
    using stdStorage for StdStorage;

    address public feeManager;
    address public team;
    address public notifyAdmin;
    address public emergencyCouncil;
    address public _weth;
    address public constant testDeployer = address(1);

    // Scripts to test
    DeployGovernors deployGovernors;

    constructor() {
        deploymentType = Deployment.CUSTOM;
    }

    function _setUp() public override {
        _forkSetupBefore();

        deployVelodromeV2 = new DeployVelodromeV2();
        deployGovernors = new DeployGovernors();

        stdstore.target(address(deployVelodromeV2)).sig("isTest()").checked_write(true);
        stdstore.target(address(deployGovernors)).sig("isTest()").checked_write(true);

        DeployVelodromeV2.DeploymentParameters memory params = deployVelodromeV2.params();

        WETH = IWETH(params.WETH);
        feeManager = params.feeManager;
        emergencyCouncil = params.emergencyCouncil;
        team = params.team;
        notifyAdmin = params.notifyAdmin;

        // Use test account for deployment
        stdstore.target(address(deployVelodromeV2)).sig("deployerAddress()").checked_write(testDeployer);
        stdstore.target(address(deployGovernors)).sig("deployerAddress()").checked_write(testDeployer);
        vm.deal(testDeployer, TOKEN_10K);
    }

    function testLoadedState() public {
        // If tests fail at this point- you need to set the .env and the constants used for deployment.
        // Refer to script/README.md
        assertTrue(address(WETH) != address(0));
        assertTrue(team != address(0));
        assertTrue(notifyAdmin != address(0));
        assertTrue(feeManager != address(0));
        assertTrue(emergencyCouncil != address(0));
    }

    function testDeployScript() public {
        deployVelodromeV2.run();

        assertEq(deployVelodromeV2.voter().epochGovernor(), team);
        assertEq(deployVelodromeV2.voter().governor(), team);

        // DeployVelodromeV2 checks

        // ensure all tokens are added to voter
        address[78] memory _tokens = deployVelodromeV2.whitelistTokens();
        for (uint256 i = 0; i < _tokens.length; i++) {
            address token = _tokens[i];
            assertTrue(deployVelodromeV2.voter().isWhitelistedToken(token));
        }
        assertTrue(deployVelodromeV2.voter().isWhitelistedToken(address(deployVelodromeV2.VELO())));

        assertTrue(address(deployVelodromeV2.WETH()) == address(WETH));

        // PoolFactory
        assertEq(deployVelodromeV2.factory().stableFee(), 5);
        assertEq(deployVelodromeV2.factory().volatileFee(), 30);

        // v2 core
        // From _coreSetup()
        assertTrue(address(deployVelodromeV2.forwarder()) != address(0));
        assertEq(address(deployVelodromeV2.artProxy().ve()), address(deployVelodromeV2.escrow()));
        assertEq(deployVelodromeV2.escrow().voter(), address(deployVelodromeV2.voter()));
        assertEq(deployVelodromeV2.escrow().artProxy(), address(deployVelodromeV2.artProxy()));
        assertEq(address(deployVelodromeV2.distributor().ve()), address(deployVelodromeV2.escrow()));
        assertEq(deployVelodromeV2.router().defaultFactory(), address(deployVelodromeV2.factory()));
        assertEq(deployVelodromeV2.router().voter(), address(deployVelodromeV2.voter()));
        assertEq(address(deployVelodromeV2.router().weth()), address(WETH));
        assertEq(deployVelodromeV2.distributor().minter(), address(deployVelodromeV2.minter()));
        assertEq(deployVelodromeV2.VELO().minter(), address(deployVelodromeV2.minter()));

        assertEq(deployVelodromeV2.voter().minter(), address(deployVelodromeV2.minter()));
        assertEq(address(deployVelodromeV2.minter().velo()), address(deployVelodromeV2.VELO()));
        assertEq(address(deployVelodromeV2.minter().voter()), address(deployVelodromeV2.voter()));
        assertEq(address(deployVelodromeV2.minter().ve()), address(deployVelodromeV2.escrow()));
        assertEq(address(deployVelodromeV2.minter().rewardsDistributor()), address(deployVelodromeV2.distributor()));

        // Permissions
        assertEq(address(deployVelodromeV2.minter().pendingTeam()), team);
        assertEq(deployVelodromeV2.escrow().team(), team);
        assertEq(deployVelodromeV2.escrow().allowedManager(), team);
        assertEq(deployVelodromeV2.factory().pauser(), team);
        assertEq(deployVelodromeV2.voter().emergencyCouncil(), emergencyCouncil);
        assertEq(deployVelodromeV2.voter().governor(), team);
        assertEq(deployVelodromeV2.voter().epochGovernor(), team);
        assertEq(deployVelodromeV2.factoryRegistry().owner(), team);
        assertEq(deployVelodromeV2.factory().poolAdmin(), team);
        assertEq(deployVelodromeV2.factory().feeManager(), feeManager);
        assertEq(deployVelodromeV2.gaugeFactory().notifyAdmin(), notifyAdmin);
    }

    function testDeployGovernors() public {
        deployGovernors.run();

        governor = deployGovernors.governor();
        epochGovernor = deployGovernors.epochGovernor();

        assertEq(address(governor.ve()), address(deployGovernors.escrow()));
        assertEq(address(governor.token()), address(deployGovernors.escrow()));
        assertEq(governor.vetoer(), address(testDeployer));
        assertEq(governor.pendingVetoer(), address(deployGovernors.vetoer()));
        assertEq(governor.team(), address(testDeployer));
        assertEq(governor.pendingTeam(), address(deployGovernors.team()));
        assertEq(address(governor.escrow()), address(deployGovernors.escrow()));
        assertEq(address(governor.voter()), address(deployGovernors.voter()));

        assertEq(address(epochGovernor.token()), address(deployGovernors.escrow()));
        assertEq(epochGovernor.minter(), address(deployGovernors.minter()));
        assertEq(address(governor.escrow()), address(deployGovernors.escrow()));
        assertEq(address(governor.voter()), address(deployGovernors.voter()));
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "forge-std/StdJson.sol";
import "forge-std/Script.sol";

import {ManagedRewardsFactory} from "contracts/factories/ManagedRewardsFactory.sol";
import {VotingRewardsFactory} from "contracts/factories/VotingRewardsFactory.sol";
import {GaugeFactory} from "contracts/factories/GaugeFactory.sol";
import {PoolFactory, IPoolFactory} from "contracts/factories/PoolFactory.sol";
import {IFactoryRegistry, FactoryRegistry} from "contracts/factories/FactoryRegistry.sol";
import {Pool} from "contracts/Pool.sol";
import {IMinter, Minter} from "contracts/Minter.sol";

import {RewardsDistributor, IRewardsDistributor} from "contracts/RewardsDistributor.sol";
import {IRouter, Router} from "contracts/Router.sol";
import {IVelo, Velo} from "contracts/Velo.sol";
import {IVoter, Voter} from "contracts/Voter.sol";
import {VeArtProxy} from "contracts/VeArtProxy.sol";
import {IVotingEscrow, VotingEscrow} from "contracts/VotingEscrow.sol";
import {VeloGovernor} from "contracts/VeloGovernor.sol";
import {IGovernor, EpochGovernor} from "contracts/EpochGovernor.sol";
import {SimpleEpochGovernor} from "contracts/SimpleEpochGovernor.sol";
import {SafeCastLibrary} from "contracts/libraries/SafeCastLibrary.sol";
import {VelodromeTimeLibrary} from "contracts/libraries/VelodromeTimeLibrary.sol";
import {IWETH} from "contracts/interfaces/IWETH.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Forwarder} from "@opengsn/contracts/src/forwarder/Forwarder.sol";

contract DeployBase is Script {
    struct DeploymentParameters {
        address allowedManager;
        address feeManager;
        address emergencyCouncil;
        address team;
        address notifyAdmin;
        address vetoer;
        address WETH;
        address forwarder;
        address minter;
        address votingEscrow;
        address voter;
        string outputFilename;
    }

    uint256 public deployPrivateKey = vm.envUint("PRIVATE_KEY_DEPLOY");
    address public deployerAddress = vm.addr(deployPrivateKey);

    DeploymentParameters public _params;
    address[78] internal _whitelistTokens;

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
    VeloGovernor public governor;
    EpochGovernor public epochGovernor;

    uint256 temp; // temp var to force isTest into a new package slot for checked_write
    /// @dev Used by tests to disable logging of output
    bool public isTest;

    constructor() {
        _params = DeploymentParameters({
            allowedManager: 0xBA4BB89f4d1E66AA86B60696534892aE0cCf91F5,
            feeManager: 0xBA4BB89f4d1E66AA86B60696534892aE0cCf91F5,
            emergencyCouncil: 0x838352F4E3992187a33a04826273dB3992Ee2b3f,
            team: 0xBA4BB89f4d1E66AA86B60696534892aE0cCf91F5,
            notifyAdmin: 0xBA4BB89f4d1E66AA86B60696534892aE0cCf91F5,
            vetoer: 0xBA4BB89f4d1E66AA86B60696534892aE0cCf91F5,
            WETH: 0x4200000000000000000000000000000000000006,
            forwarder: 0x06824df38D1D77eADEB6baFCB03904E27429Ab74, // from current
            minter: 0x6dc9E1C04eE59ed3531d73a72256C0da46D10982, // from current
            votingEscrow: 0xFAf8FD17D9840595845582fCB047DF13f006787d, // from current
            voter: 0x41C914ee0c7E1A5edCD0295623e6dC557B5aBf3C, // from current
            outputFilename: "optimism.json"
        });

        _runWhitelistTokens();
    }

    function _coreSetup() public {
        VELO = new Velo();
        tokens.push(address(VELO));

        implementation = new Pool();
        factory = new PoolFactory(address(implementation));

        votingRewardsFactory = new VotingRewardsFactory();
        gaugeFactory = new GaugeFactory();
        managedRewardsFactory = new ManagedRewardsFactory();
        factoryRegistry = new FactoryRegistry(
            address(factory), address(votingRewardsFactory), address(gaugeFactory), address(managedRewardsFactory)
        );

        forwarder = new Forwarder();

        escrow = new VotingEscrow(address(forwarder), address(VELO), address(factoryRegistry));
        artProxy = new VeArtProxy(address(escrow));
        escrow.setArtProxy(address(artProxy));

        // Setup voter and distributor
        distributor = new RewardsDistributor(address(escrow));
        voter = new Voter(address(forwarder), address(escrow), address(factoryRegistry));

        escrow.setVoterAndDistributor(address(voter), address(distributor));
        escrow.setAllowedManager(allowedManager());

        // Setup router
        router =
            new Router(address(forwarder), address(factoryRegistry), address(factory), address(voter), address(WETH()));

        // Setup minter
        minter = new Minter(address(voter), address(escrow), address(distributor));
        distributor.setMinter(address(minter));
        VELO.setMinter(address(minter));

        voter.initialize(tokens, address(minter));
    }

    // HELPERS

    function params() public returns (DeploymentParameters memory) {
        return _params;
    }

    function whitelistTokens() public returns (address[78] memory) {
        return _whitelistTokens;
    }

    function allowedManager() public returns (address) {
        return _params.allowedManager;
    }

    function WETH() public returns (IWETH) {
        return IWETH(_params.WETH);
    }

    function _runWhitelistTokens() private {
        _whitelistTokens[0] = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
        _whitelistTokens[1] = 0x4200000000000000000000000000000000000006;
        _whitelistTokens[2] = 0x8aE125E8653821E851F12A49F7765db9a9ce7384;
        _whitelistTokens[3] = 0x8c6f28f2F1A3C87F0f938b96d27520d9751ec8d9;
        _whitelistTokens[4] = 0x1F32b1c2345538c0c6f582fCB022739c4A194Ebb;
        _whitelistTokens[5] = 0x9Bcef72be871e61ED4fBbc7630889beE758eb81D;
        _whitelistTokens[6] = 0x340fE1D898ECCAad394e2ba0fC1F93d27c7b717A;
        _whitelistTokens[7] = 0xdFA46478F9e5EA86d57387849598dbFB2e964b02;
        _whitelistTokens[8] = 0x73cb180bf0521828d8849bc8CF2B920918e23032;
        _whitelistTokens[9] = 0x4200000000000000000000000000000000000042;
        _whitelistTokens[10] = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
        _whitelistTokens[11] = 0x296F55F8Fb28E498B858d0BcDA06D955B2Cb3f97;
        _whitelistTokens[12] = 0xc40F949F8a4e094D1b49a23ea9241D289B7b2819;
        _whitelistTokens[13] = 0x6806411765Af15Bddd26f8f544A34cC40cb9838B;
        _whitelistTokens[14] = 0xbfD291DA8A403DAAF7e5E9DC1ec0aCEaCd4848B9;
        _whitelistTokens[15] = 0xdb4eA87fF83eB1c80b8976FC47731Da6a31D35e5;
        _whitelistTokens[16] = 0x2E3D870790dC77A83DD1d18184Acc7439A53f475;
        _whitelistTokens[17] = 0xc5b001DC33727F8F26880B184090D3E252470D45;
        _whitelistTokens[18] = 0xCa0E54b636DB823847B29F506BFFEE743F57729D;
        _whitelistTokens[19] = 0x3E29D3A9316dAB217754d13b28646B76607c5f04;
        _whitelistTokens[20] = 0x970D50d09F3a656b43E11B0D45241a84e3a6e011;
        _whitelistTokens[21] = 0xCB8FA9a76b8e203D8C3797bF438d8FB81Ea3326A;
        _whitelistTokens[22] = 0xB153FB3d196A8eB25522705560ac152eeEc57901;
        _whitelistTokens[23] = 0xE405de8F52ba7559f9df3C368500B6E6ae6Cee49;
        _whitelistTokens[24] = 0x94b008aA00579c1307B0EF2c499aD98a8ce58e58;
        _whitelistTokens[25] = 0x920Cf626a271321C151D027030D5d08aF699456b;
        _whitelistTokens[26] = 0x484c2D6e3cDd945a8B2DF735e079178C1036578c;
        _whitelistTokens[27] = 0x217D47011b23BB961eB6D93cA9945B7501a5BB11;
        _whitelistTokens[28] = 0x4E720DD3Ac5CFe1e1fbDE4935f386Bb1C66F4642;
        _whitelistTokens[29] = 0xB0B195aEFA3650A6908f15CdaC7D92F8a5791B0B;
        _whitelistTokens[30] = 0x3417E54A51924C225330f8770514aD5560B9098D;
        _whitelistTokens[31] = 0x5d47bAbA0d66083C52009271faF3F50DCc01023C;
        _whitelistTokens[32] = 0x1DB2466d9F5e10D7090E7152B68d62703a2245F0;
        _whitelistTokens[33] = 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb;
        _whitelistTokens[34] = 0x9485aca5bbBE1667AD97c7fE7C4531a624C8b1ED;
        _whitelistTokens[35] = 0x8700dAec35aF8Ff88c16BdF0418774CB3D7599B4;
        _whitelistTokens[36] = 0x375488F097176507e39B9653b88FDc52cDE736Bf;
        _whitelistTokens[37] = 0xFdb794692724153d1488CcdBE0C56c252596735F;
        _whitelistTokens[38] = 0x79AF5dd14e855823FA3E9ECAcdF001D99647d043;
        _whitelistTokens[39] = 0xAF9fE3B5cCDAe78188B1F8b9a49Da7ae9510F151;
        _whitelistTokens[40] = 0x1610e3c85dd44Af31eD7f33a63642012Dca0C5A5;
        _whitelistTokens[41] = 0x9e1028F5F1D5eDE59748FFceE5532509976840E0;
        _whitelistTokens[42] = 0xFBc4198702E81aE77c06D58f81b629BDf36f0a71;
        _whitelistTokens[43] = 0xa50B23cDfB2eC7c590e84f403256f67cE6dffB84;
        _whitelistTokens[44] = 0x46f21fDa29F1339e0aB543763FF683D399e393eC;
        _whitelistTokens[45] = 0x929B939f8524c3Be977af57A4A0aD3fb1E374b50;
        _whitelistTokens[46] = 0xc5102fE9359FD9a28f877a67E36B0F050d81a3CC;
        _whitelistTokens[47] = 0x7aE97042a4A0eB4D1eB370C34BfEC71042a056B7;
        _whitelistTokens[48] = 0x9e5AAC1Ba1a2e6aEd6b32689DFcF62A509Ca96f3;
        _whitelistTokens[49] = 0x39FdE572a18448F8139b7788099F0a0740f51205;
        _whitelistTokens[50] = 0xc3864f98f2a61A7cAeb95b039D031b4E2f55e0e9;
        _whitelistTokens[51] = 0x9a2e53158e12BC09270Af10C16A466cb2b5D7836;
        _whitelistTokens[52] = 0xa00E3A3511aAC35cA78530c85007AFCd31753819;
        _whitelistTokens[53] = 0x00a35FD824c717879BF370E70AC6868b95870Dfb;
        _whitelistTokens[54] = 0x15e770B95Edd73fD96b02EcE0266247D50895E76;
        _whitelistTokens[55] = 0xfDeFFc7Ad816BF7867C642dF7eBC2CC5554ec265;
        _whitelistTokens[56] = 0xB0ae108669CEB86E9E98e8fE9e40d98b867855fD;
        _whitelistTokens[57] = 0x676f784d19c7F1Ac6C6BeaeaaC78B02a73427852;
        _whitelistTokens[58] = 0x6c2f7b6110a37b3B0fbdd811876be368df02E8B0;
        _whitelistTokens[59] = 0x47536F17F4fF30e64A96a7555826b8f9e66ec468;
        _whitelistTokens[60] = 0x2513486f18eeE1498D7b6281f668B955181Dd0D9;
        _whitelistTokens[61] = 0x12ff4a259e14D4DCd239C447D23C9b00F7781d8F;
        _whitelistTokens[62] = 0xC26921B5b9ee80773774d36C84328ccb22c3a819;
        _whitelistTokens[63] = 0xcB59a0A753fDB7491d5F3D794316F1adE197B21E;
        _whitelistTokens[64] = 0x67CCEA5bb16181E7b4109c9c2143c24a1c2205Be;
        _whitelistTokens[65] = 0x3e7eF8f50246f725885102E8238CBba33F276747;
        _whitelistTokens[66] = 0x374Ad0f47F4ca39c78E5Cc54f1C9e426FF8f231A;
        _whitelistTokens[67] = 0xD8737CA46aa6285dE7B8777a8e3db232911baD41;
        _whitelistTokens[68] = 0xfD389Dc9533717239856190F42475d3f263a270d;
        _whitelistTokens[69] = 0x395Ae52bB17aef68C2888d941736A71dC6d4e125;
        _whitelistTokens[70] = 0x3F56e0c36d275367b8C502090EDF38289b3dEa0d;
        _whitelistTokens[71] = 0x68f180fcCe6836688e9084f035309E29Bf0A2095;
        _whitelistTokens[72] = 0xE3AB61371ECc88534C522922a026f2296116C109;
        _whitelistTokens[73] = 0x298B9B95708152ff6968aafd889c6586e9169f1D;
        _whitelistTokens[74] = 0x8B21e9b7dAF2c4325bf3D18c1BeB79A347fE902A;
        _whitelistTokens[75] = 0x9C9e5fD8bbc25984B178FdCE6117Defa39d2db39;
        _whitelistTokens[76] = 0x10010078a54396F62c96dF8532dc2B4847d47ED3;
        _whitelistTokens[77] = 0x61BAADcF22d2565B0F471b291C475db5555e0b76;
    }
}

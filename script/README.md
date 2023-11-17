## Deploy Velodrome v2

Velodrome v2 deployment is a multi-step process.  Unlike testing, we cannot impersonate governance to submit transactions and must wait on the necessary protocol actions to complete setup.  This README goes through the necessary instructions to deploy the Velodrome v2 upgrade.

### Environment setup
1. Copy-pasta `.env.sample` into a new `.env` and set the environment variables. `PRIVATE_KEY_DEPLOY` is the private key to deploy all scripts.
2. Copy-pasta `script/constants/TEMPLATE.json` into a new file `script/constants/{CONSTANTS_FILENAME}`. For example, "Optimism.json" in the .env would be a file of `script/constants/Optimism.json`.  Set the variables in the new file.

3. Run tests to ensure deployment state is configured correctly:
```ml
forge init
forge build
forge test
```

*Note that this will create a `script/constants/output/{OUTPUT_FILENAME}` file with the contract addresses created in testing.  If you are using the same constants for multiple deployments (for example, deploying in a local fork and then in prod), you can rename `OUTPUT_FILENAME` to store the new contract addresses while using the same constants.

4. Ensure all v2 deployments are set properly. In project directory terminal:
```
source .env
```

### Deployment
- Note that if deploying to a chain other than Optimism/Optimism Goerli, if you have a different .env variable name used for `RPC_URL`, `SCAN_API_KEY` and `ETHERSCAN_VERIFIER_URL`, you will need to use the corresponding chain name by also updating `foundry.toml`.  For this example we're deploying onto Optimism.

1. Deploy Velodrome v2 Core
```
forge script script/DeployVelodromeV2.s.sol:DeployVelodromeV2 --broadcast --slow --rpc-url optimism --verify -vvvv
```
2. Accept pending team as team. This needs to be done by the `minter.pendingTeam()` address. Within the deployed `Minter` contract call `acceptTeam()`.

3. Deploy v2 gauges and v2 pools.  These gauges are built on Velodrome v2 using newly created v2 pools.
```
forge script script/DeployGaugesAndPoolsV2.s.sol:DeployGaugesAndPoolsV2 --broadcast --slow --rpc-url optimism --verify -vvvv
```

4. Deploy governor contracts. From the above output of 1, copy the forwarder, minter and voting escrow addresses into your constants file under the key "current":

e.g. 
```
    "current": {
        "Forwarder": "0x...",
        "Minter": "0x...",
        "VotingEscrow": "0x..."
    }
```

This is done as a sanity check in the event that the governor is not deployed alongside the rest of the contracts so that the governor will always be pointing to valid contracts. 

```
forge script script/DeployGovernors.s.sol:DeployGovernors --broadcast --slow --rpc-url optimism --verify -vvvv
```

5.  Update the governor addresses on v2.  This needs to be done by the v2 `Voter.governor()` address.  Within v2 `voter`:
 - call `setEpochGovernor()` using the `EpochGovernor` address located in `script/constants/output/{OUTPUT_FILENAME}`
 - call `setGovernor()` using the `Governor` address located in the same file.

6. Accept governor vetoer status.  This also needs to be done by the v2 `escrow.team()` address.  Within the deployed `Governor` contract call `acceptVetoer()`.

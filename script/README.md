## Deploy Velodrome v2

Velodrome v2 deployment is a multi-step process.  Unlike testing, we cannot impersonate governance to submit transactions and must wait on the necessary protocol actions to complete setup.  This README goes through the necessary instructions to deploy the Velodrome v2 upgrade.

### Environment setup
1. Copy-pasta `.env.sample` into a new `.env` and set the environment variables. The `PUBLIC_KEY` should be for the given `PRIVATE_KEY`.
2. Given the `CHAIN_NAME` env variable set (for example, "Optimism"), create a `script/constants/{CHAIN_NAME}.json` and set the corresponding state.

### Deploy
1. Deploy v2 protocol
```
forge script script/Deploy.s.sol:Deploy --broadcast --rpc-url $OPTIMISM_RPC_URL --etherscan-api-key $OPTIMISM_SCAN_API_KEY --verifier-url OPTIMISM_ETHERSCAN_VERIFIER_URL --verify -vvvv
```

2. Velodrome v1 governance creates a custom gauge on v1 using the address of the `SinkDrain` deployed.  The contract address can be located within `broadcast/Deploy.s.sol/{chain id}/run-latest.json` by searching `SinkDrain`.  This is done through calling the v1 `voter.createGauge()` with the function argument being the `SinkDrain` address.

3. Set `SinkDrain` address within the created json in step 2, and follow similar steps to set `SinkManager`

4. Finish setting up the `sinkManager`.  To do this, you need to
    1. create a max-locked v1 veNFT with any balance and send it to the deployer address
    2. Set `ownedTokenId` within the json created in environment setup to the veNFT owned by the deployer address
    3. Set `SinkManager` within the same json following step 2 above
    ```
    forge script script/SetupSinkManager.s.sol:SetupSinkManager --broadcast --rpc-url $OPTIMISM_RPC_URL -vvvv
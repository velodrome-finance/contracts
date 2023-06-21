# Hardhat Deployment Instructions

Hardhat support was included as a way to provide an easy way to test the contracts on Tenderly with contract verification. 

## Set Up

1. Create a new fork on Tenderly. Once you have the fork, copy the fork id number (the component after `/fork`/ in the URL) and set it as your `TENDERLY_FORK_ID` in the `.env` file. The other fields that must be set include `PRIVATE_KEY_DEPLOY`, set to a private key used for testing.
2. Install packages via `npm install` or `yarn install`.
3. Follow the instructions of the [tenderly hardhat package](https://github.com/Tenderly/hardhat-tenderly/tree/master/packages/tenderly-hardhat) to install the tenderly cli and login.

## Deployment

1. Deploy the `SinkDrain` with the following command:

`npx hardhat run script/hardhat/DeploySinkDrain.ts --network tenderly`

Note the `SinkDrain` address, as you will need it in the following section.

2. Use the tenderly dashboard to simulate a transaction. We will create a special gauge for the `SinkDrain`.

Create a transaction calling `createGauge` on the V1 Voter at `0x09236cfF45047DBee6B921e00704bed6D6B8Cf7e` with the address of the `SinkDrain` deployed above. Tenderly allows you to overwrite the value of `governor` in the above contract so you can use any `from` address so long as you overwrite the state. 

3. Update the SinkDrain address in `script/hardhat/DeployVelodromeV2.ts`.

Deploy the remaining VelodromeV2 contracts:

`npx hardhat run script/hardhat/DeployVelodromeV2.ts --network tenderly`

The contracts that were deployed will be saved in `script/constants/output/VelodromeV2Output.json`. 

4. Deploy V2 pools and create gauges for them.

`npx hardhat run script/hardhat/DeployGaugesAndPoolsV2.ts --network tenderly`

5. Deploy Governors. You will need to set the governors manually in tenderly. 

`npx hardhat run script/hardhat/DeployGovernors.ts --network tenderly`
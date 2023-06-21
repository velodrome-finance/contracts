import { getContractAt, deploy } from "./utils/helpers";
import { VeloGovernor, EpochGovernor } from "../../artifacts/types";
import jsonConstants from "../constants/Optimism.json";
import deployedContracts from "../constants/output/VelodromeV2Output.json";

async function main() {
  const governor = await deploy<VeloGovernor>(
    "VeloGovernor",
    undefined,
    deployedContracts.votingEscrow
  );
  const epochGovernor = await deploy<EpochGovernor>(
    "EpochGovernor",
    undefined,
    deployedContracts.forwarder,
    deployedContracts.votingEscrow,
    deployedContracts.minter
  );

  await governor.setVetoer(jsonConstants.team);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

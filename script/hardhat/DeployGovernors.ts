import { deploy } from "./utils/helpers";
import { VeloGovernor, EpochGovernor } from "../../artifacts/types";
import jsonConstants from "../constants/Optimism.json";

async function main() {
  const governor = await deploy<VeloGovernor>(
    "VeloGovernor",
    undefined,
    jsonConstants.current.VotingEscrow
  );
  const epochGovernor = await deploy<EpochGovernor>(
    "EpochGovernor",
    undefined,
    jsonConstants.current.Forwarder,
    jsonConstants.current.VotingEscrow,
    jsonConstants.current.Minter
  );

  await governor.setVetoer(jsonConstants.team);
  console.log(`Governor deployed to: ${governor.address}`);
  console.log(`EpochGovernor deployed to: ${epochGovernor.address}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

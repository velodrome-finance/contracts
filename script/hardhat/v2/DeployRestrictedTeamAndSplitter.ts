import { deploy } from "./utils/helpers";
import { RestrictedTeam, Splitter } from "../../artifacts/types";
import deployedContracts from "../constants/output/DeployVelodromeV2-Optimism.json";

async function main() {
  const restrictedTeam = await deploy<RestrictedTeam>(
    "RestrictedTeam",
    undefined,
    deployedContracts.VotingEscrow
  );
  const splitter = await deploy<Splitter>(
    "Splitter",
    undefined,
    deployedContracts.VotingEscrow
  );

  console.log("RestrictedTeam deployed at: ", restrictedTeam.address);
  console.log("Splitter deployed at: ", splitter.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

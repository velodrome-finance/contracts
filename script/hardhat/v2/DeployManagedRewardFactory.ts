import { deploy } from "../utils/helpers";
import { PatchedManagedRewardsFactory } from "../../artifacts/types";

async function main() {
  const managedRewardsFactory = await deploy<PatchedManagedRewardsFactory>(
    "PatchedManagedRewardsFactory"
  );

  console.log(
    "Managed Rewards Factory deployed at: ",
    managedRewardsFactory.address
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

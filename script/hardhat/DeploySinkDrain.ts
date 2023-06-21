import { deploy } from "./utils/helpers";
import { SinkDrain } from "../../artifacts/types";

async function main() {
  const sinkDrain = await deploy<SinkDrain>("SinkDrain");
  console.log(`SinkDrain deployed to: ${sinkDrain.address}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

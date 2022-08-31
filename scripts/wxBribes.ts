import fs from "fs";
import { ethers, run } from "hardhat";
import j from "./xBribes/xBribes.json"

async function main () {
    const delay = ms => new Promise(res => setTimeout(res, ms));

    const voter = "0x09236cfF45047DBee6B921e00704bed6D6B8Cf7e"; // mainnet
    let wxBribes: {xBribe: string; wxBribe: string}[] = [];

    const WrappedExternalBribeFactory = await ethers.getContractFactory("WrappedExternalBribeFactory");
    const wxBribeFactory = await WrappedExternalBribeFactory.deploy(voter);
    console.log(wxBribeFactory.address);
    for (var i = 0; i < j.addresses.length; i++) {
        let xBribe = j.addresses[i];
        await wxBribeFactory.createBribe(xBribe);
        await delay(10000);
        let wxBribe = await wxBribeFactory.oldBribeToNew(xBribe);
        wxBribes.push({xBribe: xBribe, wxBribe: wxBribe});
    }
    fs.writeFileSync(
        './scripts/xBribes/wxBribesEarned.json',
        JSON.stringify(wxBribes, undefined, 2)
    );
    // verify wrapped bribe : NOTE - factory needs to be verified through forge
    const {xBribe, wxBribe} = wxBribes[wxBribes.length - 1];
    await run("verify:verify", {
        contract: "contracts/WrappedExternalBribe.sol:WrappedExternalBribe",
        address: wxBribe,
        constructorArguments: [voter, xBribe],
    });
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
import { readConfig, parseAccount } from "./common";
import { AptosAccount, HexString } from "aptos";
import { BaseCoinClient } from "./client";

let config = readConfig();
let profile = process.argv[2];
console.log("profile", profile);
let { rest_url: nodeUrl, private_key: privateKey, account } = config.profiles[profile];
let deployer = parseAccount(config, profile);
console.log("nodeUrl", nodeUrl);
console.log("privateKey", privateKey);
console.log("account", account);
console.log("----------------------------");

class CoinClient extends BaseCoinClient {
    constructor(deployer: AptosAccount, moduleName: string) {
        super(nodeUrl, deployer, moduleName);
    }
}

async function mintTo(coinName: string, to: HexString, amount: number) {
    const client = new CoinClient(deployer, coinName);
    console.log(`deployer: ${deployer.address()}`);
    console.log(`to: ${to}`);
    await client.mint(deployer, to, amount);
}

async function regisgerAndMintTo(coinName: string, tester: AptosAccount, amount: number) {
    const client = new CoinClient(deployer, coinName);
    console.log(`deployer: ${deployer.address()}`);
    console.log(`tester: ${tester.address()}`);

    if (!(await client.isRegistered(tester.address()))) {
        console.log("register");
        await client.register(deployer.address(), tester);
    }
    console.log(`balance: ${await client.getBalance(tester.address())}`);
    console.log("mint");
    await client.mint(deployer, tester.address(), amount);
    console.log(`balance: ${await client.getBalance(tester.address())}`);
}

async function main() {
    let bob = parseAccount(config, "bob");
    await regisgerAndMintTo("VeKEPL", bob, 100);
    //await mintTo("KEPL", bob.address(), 2e6 * 100);
    //await mintTo("KEME", bob.address(), 2e6 * 100);

    //let xuWallet = new HexString("0x3f65414a639f1a83bed131dafb4f70e938bbb82c5a3a8a331670ad6a63ed9f76");
    //console.log("xuWallet", xuWallet);
    //await mintTo("PreKEPL", xuWallet, 1e6 * 5000000);
}

if (require.main === module) {
    main().catch((e) => console.error(e));
}

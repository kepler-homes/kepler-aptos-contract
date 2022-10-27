import { readConfig, parseAccount } from "./common";
import { AptosAccount } from "aptos";
import { BaseCoinClient } from "./client";

class CoinClient extends BaseCoinClient {
    constructor(deployer: AptosAccount, moduleName: string) {
        super(deployer, moduleName);
    }
}

async function main() {
    let config = readConfig();
    let deployer = parseAccount(config, "default");
    let tester = parseAccount(config, "bob");

    const client = new CoinClient(deployer, "KEME");
    console.log(`deployer: ${deployer.address()}`);
    console.log(`tester: ${tester.address()}`);

    if (!(await client.isRegistered(tester.address()))) {
        console.log("register");
        await client.register(deployer.address(), tester);
    }
    console.log(`balance: ${await client.getBalance(tester.address())}`);
    console.log("mint");
    await client.mint(deployer, tester.address(), 100);
    console.log(`balance: ${await client.getBalance(tester.address())}`);
}

if (require.main === module) {
    main().catch((e) => console.error(e));
}

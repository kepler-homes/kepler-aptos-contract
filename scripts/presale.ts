import { readConfig, parseAccount, toHexString } from "./common";
import { AptosAccount, MaybeHexString, HexString, BCS, TxnBuilderTypes } from "aptos";
import { BaseClient } from "./client";

const APT = 1e6;
function aptToGasUnit(n: number): number {
    return Math.trunc(n * APT);
}

let config = readConfig();
let profile = process.argv[2];
console.log("profile", profile);
let { rest_url: nodeUrl, private_key: privateKey, account } = config.profiles[profile];
let deployer = parseAccount(config, profile);
console.log("nodeUrl", nodeUrl);
console.log("privateKey", privateKey);
console.log("account", account);
console.log("----------------------------");

let moduleName = "presale_002";

let bob = parseAccount(config, "bob");
let tom = parseAccount(config, "tom");
let vault = parseAccount(config, "vault");
let currency = "0x1::aptos_coin::AptosCoin";
let token1 = `${deployer.address()}::VeKEPL::T`;
let token2 = `${deployer.address()}::KEPL::T`;

interface AnyObject {
    [key: string]: any;
}

class PresaleClient extends BaseClient {
    constructor() {
        super(nodeUrl, deployer, moduleName);
    }

    async queryModuleStorage(): Promise<any> {
        return await this.queryModuleResource(this.deployer.address(), `ModuleStorage`);
    }

    async isInitialized(): Promise<boolean> {
        let resource = await this.queryModuleStorage();
        return resource != null;
    }

    async initialize() {
        if (await this.isInitialized()) return;
        let claimTimes: AnyObject = {
            mainnet: 1664553599,
            testnet: 1658733411,
        };

        let claimIntervals: AnyObject = {
            mainnet: 30 * 3600 * 24,
            testnet: 60 * 5,
        };

        let typeArgs = [currency, token1, token2];
        let args = {
            basePrice: 0.2 * APT,
            claimStartTime: claimTimes[profile],
            commissionRate: "5",
            feeWallet: `${vault.address()}`,
            //10万每轮,共10轮100万usd
            saleAmountPerRound: aptToGasUnit(100000),
            claimInterval: claimIntervals[profile],
            minBuyAmount: aptToGasUnit(2000),
            maxBuyAmount: aptToGasUnit(100000),
            refeererMinBuyAmount: aptToGasUnit(10000),
            seed: `${Date.now()}`,
        };
        console.log("initialize, type args: ", typeArgs);
        console.log("initialize, args: ", args);
        await this.submitAndConfirmPayload(
            this.deployer,
            {
                type: "script_function_payload",
                function: `${this.moduleType}::initialize`,
                type_arguments: typeArgs,
                arguments: Object.values(args),
            },
            true
        );
    }
}

async function checkTokenBalance() {
    if (profile == "mainnet") return;
}

async function main() {
    const client = new PresaleClient();
    await client.initialize();
}

if (require.main === module) {
    main().catch((e) => console.error(e));
}

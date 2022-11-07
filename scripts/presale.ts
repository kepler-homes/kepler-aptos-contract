import { readConfig, parseAccount, toHexString } from "./common";
import { AptosAccount, MaybeHexString, HexString, BCS, TxnBuilderTypes } from "aptos";
import { BaseClient, BaseCoinClient } from "./client";

interface SimpleKeyValueObject {
    [key: string]: any;
}

let module_name = "presale_005";
const GAS_UNIT = 1;
const APT = GAS_UNIT * 1e6;
const EMPTY_ADDRESS = "0x0000000000000000000000000000000000000000000000000000000000000000";
function apt_to_gas_unit(n: number): number {
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

let bob = parseAccount(config, "bob");
let tom = parseAccount(config, "tom");
let vault = parseAccount(config, "vault");
let currency = "0x1::aptos_coin::AptosCoin";
let token1 = `${deployer.address()}::VeKEPL::T`;
let token2 = `${deployer.address()}::KEPL::T`;

function hexToString(hex: string): string {
    return Buffer.from(hex.replace("0x", ""), "hex").toString();
}

function tokenToString(t: any) {
    return `${t.account_address}::${hexToString(t.module_name)}::${hexToString(t.struct_name)}`;
}

class PresaleClient extends BaseClient {
    constructor() {
        super(nodeUrl, deployer, module_name);
    }

    async queryModuleStorage(): Promise<any> {
        return await this.queryModuleResource(this.deployer.address(), `ModuleStorage`);
    }

    async isInitialized(): Promise<boolean> {
        let resource = await this.queryModuleStorage();
        return resource != null;
    }

    get_config(profile: string): SimpleKeyValueObject {
        let config = {
            mainnet: {
                claim_time: 1664553599,
                claim_interval: 30 * 3600 * 24,
                base_price: apt_to_gas_unit(0.1),
                sale_amount_per_round: apt_to_gas_unit(100000),
                min_buy_amount: apt_to_gas_unit(2000),
                max_buy_amount: apt_to_gas_unit(100000),
                refeerer_min_buy_amount: apt_to_gas_unit(10000),
            },
        }[profile] || {
            //testnet
            claim_time: 9658733411,
            claim_interval: 20,
            base_price: apt_to_gas_unit(0.00001),
            sale_amount_per_round: apt_to_gas_unit(10),
            min_buy_amount: apt_to_gas_unit(0.2),
            max_buy_amount: apt_to_gas_unit(1),
            refeerer_min_buy_amount: apt_to_gas_unit(1),
        };
        return {
            types: { currency, token1, token2 },
            values: {
                base_price: config.base_price,
                claim_start_time: config.claim_time,
                commission_rate: "5",
                fee_wallet: `${vault.address()}`,
                //10万每轮,共10轮100万usd
                sale_amount_per_round: config.sale_amount_per_round,
                claim_interval: config.claim_interval,
                min_buy_amount: config.min_buy_amount,
                max_buy_amount: config.max_buy_amount,
                refeerer_min_buy_amount: config.refeerer_min_buy_amount,
            },
        };
    }

    async initialize() {
        if (await this.isInitialized()) return;
        let { types, values } = this.get_config(profile);
        let payload = {
            type: "script_function_payload",
            function: `${this.moduleType}::initialize`,
            type_arguments: Object.values(types),
            arguments: [...Object.values(values), `${Date.now()}`],
        };
        console.log("initialize, payload: ", payload);
        await this.submitAndConfirmPayload(this.deployer, payload, true);
    }

    async need_update_config() {
        let { data } = (await this.queryModuleStorage()) || {};
        let { types, values } = this.get_config(profile);
        for (let key of Object.keys(types)) {
            if (types[key] != tokenToString(data[key])) return true;
        }
        for (let key of Object.keys(values)) {
            if (`${values[key]}` != `${data[key]}`) return true;
        }
        return false;
    }

    async update_config() {
        if (await this.need_update_config()) {
            let { types, values } = this.get_config(profile);
            let payload = {
                type: "script_function_payload",
                function: `${this.moduleType}::update_config`,
                type_arguments: Object.values(types),
                arguments: [...Object.values(values)],
            };
            console.log("update_config, payload: ", payload);
            await this.submitAndConfirmPayload(this.deployer, payload, true);
        }
    }
    async buy_token1(user: AptosAccount) {
        let { types, values } = this.get_config(profile);
        let type_arguments = { currency, token1 };
        let args = { payment: values.min_buy_amount + 1, lock_periods: 6, referrer: EMPTY_ADDRESS };
        let payload = {
            type: "script_function_payload",
            function: `${this.moduleType}::buy_token1`,
            type_arguments: Object.values(type_arguments),
            arguments: [...Object.values(args)],
        };
        console.log("buy_token1, payload: ", payload);
        await this.submitAndConfirmPayload(user, payload, true);
    }

    async claim_token2(user: AptosAccount) {
        let payload = {
            type: "script_function_payload",
            function: `${this.moduleType}::claim_token2`,
            type_arguments: [token1, token2],
            arguments: [],
        };
        console.log("claim_token2, payload: ", payload);
        await this.submitAndConfirmPayload(user, payload, true);
    }
}

async function main() {
    const client = new PresaleClient();
    let token1Client = new BaseCoinClient(nodeUrl, deployer, "VeKEPL");
    let token2Client = new BaseCoinClient(nodeUrl, deployer, "KEPL");
    await client.initialize();
    await client.update_config();
    if (profile != "mainnet") {
        let storage = await client.queryModuleStorage();
        console.log("storage", storage);
        //await token1Client.mint(deployer, storage.data.signer_capability.account, APT * 100000000);
        //await token2Client.mint(deployer, storage.data.signer_capability.account, APT * 100000000);
    }
    let balance1 = await token1Client.getBalance(bob.address());
    console.log("balance1", balance1);
    await client.buy_token1(bob);

    let balance2 = await token1Client.getBalance(bob.address());
    console.log("balance2", balance2);

    await client.claim_token2(bob);
}

if (require.main === module) {
    main().catch((e) => console.error(e));
}

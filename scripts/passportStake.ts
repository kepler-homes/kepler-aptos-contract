import { readConfig, parseAccount, toHexString } from "./common";
import { AptosAccount, MaybeHexString, HexString, BCS, TxnBuilderTypes } from "aptos";
import { BaseClient } from "./client";

const GAS_UNIT = 1;
const APT = GAS_UNIT * 1e6;
function apt_to_gas_unit(n: number): number {
    return Math.trunc(n * APT);
}

const UNIT = 1e6;
const EMPTY_ADDRESS = "0x0000000000000000000000000000000000000000000000000000000000000000";

let config = readConfig();
let profile = process.argv[2];
console.log("profile", profile);
let { rest_url: nodeUrl, private_key: privateKey, account } = config.profiles[profile];
let deployer = parseAccount(config, profile);
console.log("nodeUrl", nodeUrl);
console.log("privateKey", privateKey);
console.log("account", account);
console.log("----------------------------");
let rewardToken = `${deployer.address()}::PreKEPL::T`;
import fetch from "cross-fetch";

let moduleName = "passport_stake_003";

interface StringObject {
    [key: string]: string;
}

class Client extends BaseClient {
    constructor() {
        super(nodeUrl, deployer, moduleName);
    }
    async queryTokens(userAddress: MaybeHexString, network: string): Promise<any> {
        let url =
            network == "mainnet"
                ? "https://wqb9q2zgw7i7-mainnet.hasura.app/v1/graphql"
                : "https://knmpjhsurbz8-testnet.hasura.app/v1/graphql";
        let postData = {
            operationName: "AccountTokensData",
            variables: {
                owner_address: `${userAddress}`,
                limit: 993,
                offset: 0,
            },
            query: 'query AccountTokensData($owner_address: String, $limit: Int, $offset: Int) {\n  current_token_ownerships(\n    where: {owner_address: {_eq: $owner_address}, amount: {_gt: "0"}}\n    limit: $limit\n    offset: $offset\n  ) {\n    token_data_id_hash\n    name\n    collection_name\n    table_type\n    property_version\n    amount\n    __typename\n  }\n}',
        };
        let headers = { "Content-Type": "application/json" };
        const response = await fetch(url, { method: "POST", headers, body: JSON.stringify(postData) });
        if (response.status == 200) {
            let json = await response.json();
            return json && json.data && json.data.current_token_ownerships;
        } else {
            return [];
        }
    }

    async initialize() {
        if (await this.isInitialized()) return;
        const payload = {
            type: "script_function_payload",
            function: `${this.moduleType}::initialize`,
            type_arguments: [rewardToken],
            arguments: [toU64Hex(Date.now())],
        };
        await this.submitAndConfirmPayload(this.deployer, payload, true);
    }

    async add_collection() {
        //     public entry fun add_collection<CoinType>(
        //     sender: &signer,
        //     collection_creator: address,
        //     collection_name: vector<u8>,
        //     total_reward_per_drawing: u64,
        //     min_stake_time: u64,
        //     lock_unit_span: u64,
        // )
        let args = {
            collection_creator: `${deployer.address()}`,
            collection_name: [...Buffer.from("Kepler Passport", "utf-8")],
            total_reward_per_drawing: apt_to_gas_unit(10000),
            min_stake_time: 10, //秒
            lock_unit_span: 30, //秒
        };
        const payload = {
            type: "script_function_payload",
            function: `${this.moduleType}::add_collection`,
            type_arguments: [rewardToken],
            arguments: Object.values(args),
        };
        await this.submitAndConfirmPayload(this.deployer, payload, true);
    }

    async queryModuleStore(): Promise<any> {
        return await this.queryModuleResource(this.deployer.address(), `ModuleStore`);
    }

    async isInitialized(): Promise<boolean> {
        let resource = await this.queryModuleStore();
        //console.log("ModuleStore", resource);
        return resource != null;
    }
}

async function main() {
    let bob = parseAccount(config, "bob");
    const client = new Client();
    await client.initialize();
    await client.add_collection();
    let tokens = await client.queryTokens(bob.address(), profile);
    console.log(tokens);
}

if (require.main === module) {
    main().catch((e) => console.error(e));
}

function toU64Hex(n: number): string {
    const buf = Buffer.allocUnsafe(8);
    buf.writeBigInt64BE(BigInt(n));
    return buf.toString("hex");
}

function toU8Hex(n: number): string {
    let v = n.toString(16);
    if (v.length == 1) {
        v = `0${v}`;
    }
    return v;
}

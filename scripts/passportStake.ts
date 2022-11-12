import { readConfig, parseAccount } from "./common";
import { AptosAccount, MaybeHexString } from "aptos";
import { BaseClient, BaseCoinClient } from "./client";
import { readModuleResource, saveModuleResource } from "./utils/resource";

const GAS_UNIT = 1;
const APT = GAS_UNIT * 1e6;
function apt_to_gas_unit(n: number): number {
    return Math.trunc(n * APT);
}

let config = readConfig();
let network = process.argv[2];
console.log("network", network);
let { rest_url: nodeUrl, private_key: privateKey, account } = config.profiles[network];
let deployer = parseAccount(config, network);
let bob = parseAccount(config, "bob");
let resourceKey = "passport_stake";

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

    async queryUserStore(userAddress: string): Promise<any> {
        return await this.queryModuleResource(userAddress, `UserStore`);
    }

    async queryTokens(userAddress: MaybeHexString): Promise<any> {
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

    async stake(
        user: AptosAccount,
        collectionCreator: string,
        collectionName: string,
        tokenName: string,
        property_version: number,
        lock_units: number
    ) {
        let args = {
            collection_creator: collectionCreator,
            collection_name: [...Buffer.from(collectionName, "utf-8")],
            token_name: [...Buffer.from(tokenName, "utf-8")],
            property_version,
            lock_units,
        };
        const payload = {
            type: "script_function_payload",
            function: `${this.moduleType}::stake`,
            type_arguments: [],
            arguments: Object.values(args),
        };
        await this.submitAndConfirmPayload(user, payload, true);
    }

    async unstake(
        user: AptosAccount,
        collectionCreator: string,
        collectionName: string,
        tokenName: string,
        property_version: number
    ) {
        let args = {
            collection_creator: collectionCreator,
            collection_name: [...Buffer.from(collectionName, "utf-8")],
            token_name: [...Buffer.from(tokenName, "utf-8")],
            property_version,
        };
        const payload = {
            type: "script_function_payload",
            function: `${this.moduleType}::unstake`,
            type_arguments: [],
            arguments: Object.values(args),
        };
        await this.submitAndConfirmPayload(user, payload, true);
    }

    async draw(collection_creator: string, collection_name: string) {
        let args = {
            collection_creator,
            collection_name: [...Buffer.from(collection_name, "utf-8")],
        };

        const payload = {
            type: "script_function_payload",
            function: `${this.moduleType}::draw`,
            type_arguments: [],
            arguments: Object.values(args),
        };
        await this.submitAndConfirmPayload(this.deployer, payload, true);
    }

    async claim(user: AptosAccount, collection_creator: string, collection_name: string) {
        let args = {
            collection_creator,
            collection_name: [...Buffer.from(collection_name, "utf-8")],
        };

        const payload = {
            type: "script_function_payload",
            function: `${this.moduleType}::claim`,
            type_arguments: [rewardToken],
            arguments: Object.values(args),
        };
        await this.submitAndConfirmPayload(user, payload, true);
    }

    async add_collection(collection_creator: string, collection_name: string) {
        let args = {
            collection_creator,
            collection_name: [...Buffer.from(collection_name, "utf-8")],
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

    async queryCollecitonData(handle: string, collection_creator: string, collection_name: string) {
        return this.queryTableItem(
            handle,
            `${deployer.address()}::${moduleName}::CollectionId`,
            `${deployer.address()}::${moduleName}::CollectionData`,
            {
                creator: collection_creator,
                name: Buffer.from(collection_name, "utf-8").toString("hex"),
            }
        );
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

let collectionCreator: string;
let collectionName: string;
async function main() {
    let info = loadCollectionInfo();
    if (!info) {
        console.error("passport_mint not deployed");
        return;
    }
    collectionCreator = info.collectionCreator;
    collectionName = info.collectionName;
    const client = new Client();
    //await deploy(client);
    await verify(client);
}

function loadCollectionInfo(): StringObject | null {
    let passport_mint_resource = readModuleResource(network, "passport_mint");
    if (!passport_mint_resource) {
        return null;
    }
    let data = passport_mint_resource["kepler_collection_config"]["data"];
    let collectionCreator = data.resource_signer_cap.account;
    let collectionName = Buffer.from(data.name.replace("0x", ""), "hex").toString("utf-8");
    return { collectionCreator, collectionName };
}

async function deploy(client: Client) {
    await client.initialize();

    let moduleResource = readModuleResource(network, resourceKey);
    let module_store = await client.queryModuleStore();
    let handle = module_store.data.collections.handle;

    let collectionData = await client.queryCollecitonData(handle, collectionCreator, collectionName);
    if (!collectionData) {
        await client.add_collection(collectionCreator, collectionName);
    }

    moduleResource["module_store"] = module_store;
    moduleResource["kepler_collection_data"] = collectionData;
    saveModuleResource(network, resourceKey, moduleResource);
    let vekeplClient = new BaseCoinClient(nodeUrl, deployer, "PreKEPL");
    await vekeplClient.mint(deployer, module_store.data.resource_signer_capability.account, APT * 100000000);
}

async function verify(client: Client) {
    //await stake(client, bob);
    //await unstake(client, bob);
    //await client.draw(collectionCreator, collectionName);
    await claim(client, bob);
}

async function stake(client: Client, user: AptosAccount) {
    let tokens = (await client.queryTokens(user.address())).filter(
        (item: any) => item.collection_name == collectionName && item.amount > 0
    );
    console.log(tokens);
    if (tokens.length > 0) {
        let token = tokens[0];
        await client.stake(bob, collectionCreator, token.collection_name, token.name, token.property_version, 1);
    }
}

async function unstake(client: Client, user: AptosAccount) {
    let user_store = await client.queryUserStore(`${user.address()}`);
    console.log("user_store", user_store);
    if (user_store) {
        let escrows = user_store.data.escrows;
        console.log("escrows", escrows);
        if (escrows.length > 0) {
            let {
                token_data_id: { collection, creator, name },
                property_version,
            } = escrows[0].token_id;
            console.log(creator, collection, name, property_version);
            await client.unstake(user, creator, collection, name, property_version);
        }
    }
}

async function claim(client: Client, user: AptosAccount) {
    let user_store = await client.queryUserStore(`${user.address()}`);
    console.log("user_store", user_store);
    if (!user_store) return;
    let pending_reward = user_store.data.pending_reward;
    if (pending_reward > 0) {
        await client.claim(user, collectionCreator, collectionName);
    }
}

if (require.main === module) {
    main().catch((e) => console.error(e));
}

function toU64Hex(n: number): string {
    const buf = Buffer.allocUnsafe(8);
    buf.writeBigInt64BE(BigInt(n));
    return buf.toString("hex");
}

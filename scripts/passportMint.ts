import { readConfig, parseAccount, toHexString } from "./common";
import { AptosAccount, MaybeHexString, HexString, BCS, TxnBuilderTypes } from "aptos";
import { BaseClient } from "./client";
import * as ed from "@noble/ed25519";
const UNIT = 1e6;
const EMPTY_ADDRESS = "0x0000000000000000000000000000000000000000000000000000000000000000";
const BUY_TYPE_PB = 1;
const BUY_TYPE_PT = 2;
const BUY_TYPE_OG = 3;
let config = readConfig();
let profile = process.argv[2];
console.log("profile", profile);
let { rest_url: nodeUrl, private_key: privateKey, account } = config.profiles[profile];
let deployer = parseAccount(config, profile);
console.log("nodeUrl", nodeUrl);
console.log("privateKey", privateKey);
console.log("account", account);
console.log("----------------------------");

let moduleName = "passport_mint_003";

interface StringObject {
    [key: string]: string;
}

class Client extends BaseClient {
    coinType: string;
    signatureSigner: AptosAccount;
    vault: string;
    constructor(signatureSigner: AptosAccount, vault: string, coinType: string) {
        super(nodeUrl, deployer, moduleName);
        this.coinType = coinType;
        this.signatureSigner = signatureSigner;
        this.vault = vault;
    }

    async configureKeplerPassport(collectionName: string, force = false) {
        if (!force && (await this.queryKeplerPassportConfig())) return;
        let args = {
            collectionName: Uint8Array.from(Buffer.from(collectionName, "utf-8")),
            pbPrice: 1.4 * UNIT,
            pbSupply: 100,
            ptStage1Supply: 2000,
            ptStage1Price: 1.2 * UNIT,
            ptStage2Supply: 2000,
            ptStage2Price: 1.3 * UNIT,
            ogPrice: 1 * UNIT,
            ogSupply: 500,
            ogStartTime: 0,
        };
        await this.submitAndConfirmPayload(
            this.deployer,
            {
                type: "script_function_payload",
                function: `${this.moduleType}::configure_kepler_passport`,
                type_arguments: [],
                arguments: Object.values(args),
            },
            true
        );
    }

    async initialize() {
        if (await this.isInitialized()) return;
        let signatureSigner = this.signatureSigner.signingKey.publicKey.slice(0, 32);
        console.log(this.vault);
        await this.submitAndConfirmPayload(
            this.deployer,
            {
                type: "script_function_payload",
                function: `${this.moduleType}::initialize`,
                type_arguments: [this.coinType],
                arguments: [signatureSigner, this.vault],
            },
            true
        );
    }

    async buy(buyer: AptosAccount, referrer: string, buy_type: number, amount: number) {
        let args = {
            buyer: `${buyer.address()}`.replace("0x", ""),
            referrer: referrer.replace("0x", ""),
            buy_type: toU64Hex(amount),
            amount: toU64Hex(amount),
        };

        let fun_arguments = [...Object.values(args), await this.sign(args)].map((item) =>
            Uint8Array.from(Buffer.from(item, "hex"))
        );

        let payload = {
            type: "script_function_payload",
            function: `${this.moduleType}::buy`,
            type_arguments: [this.coinType],
            arguments: fun_arguments,
        };
        console.log("buy", payload);
        await this.submitAndConfirmPayload(buyer, payload, true);
    }

    async sign(args: StringObject): Promise<string> {
        let data = Object.values(args);
        let message = Uint8Array.from(Buffer.concat(data.map((item) => Buffer.from(item, "hex"))));
        let signature = await ed.sign(message, this.signatureSigner.signingKey.secretKey.slice(0, 32));
        return Buffer.from(signature).toString("hex");
    }

    async queryModuleStorage(): Promise<any> {
        return await this.queryModuleResource(this.deployer.address(), `ModuleStorage`);
    }

    async queryKeplerPassportConfig(): Promise<any> {
        return await this.queryModuleResource(this.deployer.address(), `KeplerPassportConfig`);
    }

    async isInitialized(): Promise<boolean> {
        let resource = await this.queryModuleStorage();
        //console.log("ModuleStorage", resource);
        return resource != null;
    }

    async queryResourceAccount(collectionName: string): Promise<any> {
        let storage = await this.queryModuleStorage();
        let tableHandler = storage && storage.data.resource_accounts.handle;
        let account =
            tableHandler &&
            (await this.queryTableItem(`${tableHandler}`, "0x1::string::String", "address", collectionName));
        console.log("resourceAccount", account);
        return account;
    }

    async queryCollectionConfig(collectionName: string): Promise<any> {
        let resourceAccount = await this.queryResourceAccount(collectionName);
        return resourceAccount && (await this.queryModuleResource(resourceAccount, `CollectionConfig`));
    }

    async createCollection(name: string, description: string, uri: string) {
        if (await this.queryCollectionConfig(name)) {
            return;
        }
        let args = {
            name: Buffer.from(name, "utf-8").toString("hex"),
            description: Buffer.from(description, "utf-8").toString("hex"),
            uri: Buffer.from(uri, "utf-8").toString("hex"),
            seed: toU64Hex(Date.now()),
        };
        //console.log("createCollection :", args);
        await this.submitAndConfirmPayload(
            this.deployer,
            {
                type: "script_function_payload",
                function: `${this.moduleType}::create_collection`,
                type_arguments: [],
                arguments: Object.values(args).map((item) => Uint8Array.from(Buffer.from(item, "hex"))),
            },
            true
        );
    }
}

async function main() {
    let keplerCollectionName = "Kepler Passport";
    let signatureSigner = parseAccount(config, "alice");
    let bob = parseAccount(config, "bob");
    let vault = parseAccount(config, "vault");
    let coinType = "0x1::aptos_coin::AptosCoin";
    const client = new Client(signatureSigner, `${vault.address()}`, coinType);
    await client.initialize();

    let url = "https://www.kepler.homes/";
    await client.createCollection(keplerCollectionName, `${keplerCollectionName} description"`, url);
    await client.configureKeplerPassport(keplerCollectionName, false);

    let amount = 1;
    await client.buy(bob, EMPTY_ADDRESS, BUY_TYPE_PB, amount);
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

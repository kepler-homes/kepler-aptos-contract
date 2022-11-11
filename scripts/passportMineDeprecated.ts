import { readConfig, parseAccount, toHexString } from "./common";
import { AptosAccount, MaybeHexString, HexString, BCS, TxnBuilderTypes } from "aptos";
import { BaseClient } from "./client";
import * as ed from "@noble/ed25519";
const UNIT = 1e6;

let config = readConfig();
let profile = process.argv[2];
console.log("profile", profile);
let { rest_url: nodeUrl, private_key: privateKey, account } = config.profiles[profile];
let deployer = parseAccount(config, profile);
console.log("nodeUrl", nodeUrl);
console.log("privateKey", privateKey);
console.log("account", account);
console.log("----------------------------");

let moduleName = "passport_mine_006";

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
            publicPrice: 1.4 * UNIT,
            publicMaxSupply: 100,
            promotionStage1Supply: 1000,
            promotionStage1Price: 1.2 * UNIT,
            promotionStage2Supply: 3000,
            promotionStage2Price: 1.3 * UNIT,
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

    async configureUniversePassport(collectionName: string, force = false) {
        if (!force && (await this.queryUniversePassportConfig())) return;
        let args = {
            collectionName: Uint8Array.from(Buffer.from(collectionName, "utf-8")),
            publicPrice: 3.6 * UNIT,
            promotionPrice: 3.3 * UNIT,
            maxSupply: 1000,
        };

        await this.submitAndConfirmPayload(
            this.deployer,
            {
                type: "script_function_payload",
                function: `${this.moduleType}::configure_uinverse_passport`,
                type_arguments: [],
                arguments: Object.values(args),
            },
            true
        );
    }

    async verifySignature(orderId: number, amount: number) {
        let pubkey = Buffer.from(this.signatureSigner.signingKey.publicKey.slice(0, 32)).toString("hex");
        let args = { orderId: toU64Hex(orderId), amount: toU64Hex(amount) };
        let message = Uint8Array.from(Buffer.concat(Object.values(args).map((hex) => Buffer.from(hex, "hex"))));
        let signature = await ed.sign(message, this.signatureSigner.signingKey.secretKey.slice(0, 32));
        let signatureHex = Buffer.from(signature).toString("hex");
        let fun_arguments = [...Object.values(args), pubkey, signatureHex].map((item) =>
            Uint8Array.from(Buffer.from(item, "hex"))
        );
        //console.log("verify_signature :", fun_arguments);
        await this.submitAndConfirmPayload(
            this.deployer,
            {
                type: "script_function_payload",
                function: `${this.moduleType}::verify_signature`,
                type_arguments: [],
                arguments: fun_arguments,
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
    //isPromotional, 0表示否,1表示是
    async buyKeplerPassport(buyer: AptosAccount, amount: number, isPromotional: number, referrer: string) {
        this.buyPassport("buy_kepler_passport", buyer, amount, isPromotional, referrer);
    }

    async buyUniversePassport(buyer: AptosAccount, amount: number, isPromotional: number, referrer: string) {
        this.buyPassport("buy_universe_passport", buyer, amount, isPromotional, referrer);
    }

    async buyPassport(fun: string, buyer: AptosAccount, amount: number, isPromotional: number, referrer: string) {
        let args = {
            buyerAddr: `${buyer.address()}`.substring(2),
            amount: toU64Hex(amount),
            isPromotional: toU64Hex(isPromotional),
            referrer: referrer.replace("0x", ""),
        };
        //console.log("buyPassport: ", args);
        let message = Uint8Array.from(Buffer.concat(Object.values(args).map((item) => Buffer.from(item, "hex"))));
        let signature = await ed.sign(message, this.signatureSigner.signingKey.secretKey.slice(0, 32));
        //console.log("signature", signature);
        let signatureHex = Buffer.from(signature).toString("hex");
        let fun_arguments = [...Object.values(args), signatureHex].map((item) =>
            Uint8Array.from(Buffer.from(item, "hex"))
        );
        // //console.log("verify_signature :", fun_arguments);
        await this.submitAndConfirmPayload(
            buyer,
            {
                type: "script_function_payload",
                function: `${this.moduleType}::${fun}`,
                type_arguments: [this.coinType],
                arguments: fun_arguments,
            },
            true
        );
    }

    async queryModuleStorage(): Promise<any> {
        return await this.queryModuleResource(this.deployer.address(), `ModuleStorage`);
    }

    async queryKeplerPassportConfig(): Promise<any> {
        return await this.queryModuleResource(this.deployer.address(), `KeplerPassportConfig`);
    }
    async queryKeplerPassportPromotionSaleStorage(): Promise<any> {
        return await this.queryModuleResource(this.deployer.address(), `KeplerPassportPromotionSaleStorage`);
    }
    async queryUniversePassportConfig(): Promise<any> {
        return await this.queryModuleResource(this.deployer.address(), `UniversePassportConfig`);
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
        //console.log("resourceAccount", account);
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
    let universeCollectionName = "Universe Passport";

    let signatureSigner = parseAccount(config, "alice");
    let bob = parseAccount(config, "bob");
    let tom = parseAccount(config, "tom");
    let vault = parseAccount(config, "vault");
    let coinType = "0x1::aptos_coin::AptosCoin";
    const client = new Client(signatureSigner, `${vault.address()}`, coinType);
    await client.initialize();

    let url = "http://www.baidu.com";
    await client.createCollection(keplerCollectionName, `${keplerCollectionName} description"`, url);
    await client.configureKeplerPassport(keplerCollectionName, false);

    await client.createCollection(universeCollectionName, `${universeCollectionName} description"`, url);
    await client.configureUniversePassport(universeCollectionName, false);

    let isPromotional = 1;
    let amount = 1;
    //await client.buyKeplerPassport(bob, amount, isPromotional, `${tom.address()}`);
    await client.buyUniversePassport(bob, amount, isPromotional, `${tom.address()}`);
}

if (require.main === module) {
    main().catch((e) => console.error(e));
}

function toU64Hex(n: number): string {
    const buf = Buffer.allocUnsafe(8);
    buf.writeBigInt64BE(BigInt(n));
    return buf.toString("hex");
}

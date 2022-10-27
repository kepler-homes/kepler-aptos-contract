import { readConfig, parseAccount, toHexString } from "./common";
import { AptosAccount, MaybeHexString, HexString, BCS, TxnBuilderTypes } from "aptos";
import { BaseClient } from "./client";
import * as ed from "@noble/ed25519";
const UNIT = 1e6;

class Client extends BaseClient {
    coinType: string;
    signatureSigner: AptosAccount;
    constructor(deployer: AptosAccount, signatureSigner: AptosAccount, coinType: string) {
        super(deployer, "passport_mine_011");
        this.coinType = coinType;
        this.signatureSigner = signatureSigner;
    }

    async configureKeplerPassportPublicSale(collectionName: string, price: number, maxSupply: number) {
        let args = {
            collectionName: Uint8Array.from(Buffer.from(collectionName, "utf-8")),
            price,
            maxSupply,
        };
        await this.submitAndConfirmPayload(
            this.deployer,
            {
                type: "script_function_payload",
                function: `${this.moduleType}::configure_kepler_passport_public_sale`,
                type_arguments: [],
                arguments: Object.values(args),
            },
            true
        );
    }

    async configureKeplerPassportPromotionSale(
        collectionName: string,
        stage1Supply: number,
        stage1Price: number,
        stage2Supply: number,
        stage2Price: number
    ) {
        let args = {
            collectionName: Uint8Array.from(Buffer.from(collectionName, "utf-8")),
            stage1Supply,
            stage1Price,
            stage2Supply,
            stage2Price,
        };
        await this.submitAndConfirmPayload(
            this.deployer,
            {
                type: "script_function_payload",
                function: `${this.moduleType}::configure_kepler_passport_promotion_sale`,
                type_arguments: [],
                arguments: Object.values(args),
            },
            true
        );
    }

    async configurePromotionPassportSale(
        collectionName: string,
        publicPrice: number,
        promotionPrice: number,
        maxSupply: number
    ) {
        let args = {
            collectionName: Uint8Array.from(Buffer.from(collectionName, "utf-8")),
            publicPrice,
            promotionPrice,
            maxSupply,
        };
        await this.submitAndConfirmPayload(
            this.deployer,
            {
                type: "script_function_payload",
                function: `${this.moduleType}::configure_promotion_passport_sale`,
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
        await this.submitAndConfirmPayload(
            this.deployer,
            {
                type: "script_function_payload",
                function: `${this.moduleType}::initialize`,
                type_arguments: [this.coinType],
                arguments: [signatureSigner],
            },
            true
        );
    }
    //isPromotional, 0表示否,1表示是
    async buyKeplerPassport(buyer: AptosAccount, amount: number, isPromotional: number, referrer: string) {
        let args = {
            amount: toU64Hex(amount),
            isPromotional: toU64Hex(isPromotional),
            referrer: referrer,
        };

        let message = Uint8Array.from(Buffer.concat(Object.values(args).map((item) => Buffer.from(item, "hex"))));
        let signature = await ed.sign(message, this.signatureSigner.signingKey.secretKey.slice(0, 32));
        let signatureHex = Buffer.from(signature).toString("hex");
        let fun_arguments = [...Object.values(args), signatureHex].map((item) =>
            Uint8Array.from(Buffer.from(item, "hex"))
        );
        // //console.log("verify_signature :", fun_arguments);
        await this.submitAndConfirmPayload(
            buyer,
            {
                type: "script_function_payload",
                function: `${this.moduleType}::buy_kepler_passport`,
                type_arguments: [this.coinType],
                arguments: fun_arguments,
            },
            true
        );
        //      public entry fun buy_kepler_passport(
        //     buyer: &signer,
        //     amount: vector<u8>,
        //     referrer: vector<u8>,
        //     is_promotional: vector<u8>,
        //     signature: vector<u8>,
        // ) acquires GlobalStorage{
    }

    async queryGlobalStorage(): Promise<any> {
        return await this.queryModuleResource(this.deployer.address(), `GlobalStorage`);
    }
    async isInitialized(): Promise<boolean> {
        let resource = await this.queryGlobalStorage();
        console.log("GlobalStorage", resource);
        return resource != null;
    }

    async queryResourceAccount(collectionName: string): Promise<any> {
        let storage = await this.queryGlobalStorage();
        let tableHandler = storage && storage.data.resource_accounts.handle;
        let account =
            tableHandler &&
            (await this.queryTableItem(`${tableHandler}`, "0x1::string::String", "address", collectionName));
        console.log("resourceAccount", account);
        return account;
    }

    async queryKeplerCollection(collectionName: string): Promise<any> {
        let resourceAccount = await this.queryResourceAccount(collectionName);
        return resourceAccount && (await this.queryModuleResource(resourceAccount, `KeplerCollection`));
    }

    async createCollection(name: string, description: string, uri: string) {
        if (await this.queryKeplerCollection(name)) {
            return;
        }

        let args = {
            name: Uint8Array.from(Buffer.from(name, "utf-8")),
            description: Uint8Array.from(Buffer.from(description, "utf-8")),
            uri: Uint8Array.from(Buffer.from(uri, "utf-8")),
        };
        //console.log("createCollection args :", args);
        await this.submitAndConfirmPayload(
            this.deployer,
            {
                type: "script_function_payload",
                function: `${this.moduleType}::create_collection`,
                type_arguments: [],
                arguments: Object.values(args),
            },
            true
        );
    }
    async createTokenData(collectionName: string, name: string, description: string, uri: string) {
        let args = {
            collectionName: Uint8Array.from(Buffer.from(collectionName, "utf-8")),
            name: Uint8Array.from(Buffer.from(name, "utf-8")),
            description: Uint8Array.from(Buffer.from(description, "utf-8")),
            uri: Uint8Array.from(Buffer.from(uri, "utf-8")),
        };
        //console.log("createTokenData args :", args);
        await this.submitAndConfirmPayload(
            this.deployer,
            {
                type: "script_function_payload",
                function: `${this.moduleType}::create_tokendata`,
                type_arguments: [],
                arguments: Object.values(args),
            },
            true
        );
    }
    async mintToken(buyer: AptosAccount, collectionName: string, name: string) {
        let args = {
            collectionName: Uint8Array.from(Buffer.from(collectionName, "utf-8")),
            name: Uint8Array.from(Buffer.from(name, "utf-8")),
        };
        await this.submitAndConfirmPayload(
            buyer,
            {
                type: "script_function_payload",
                function: `${this.moduleType}::mint_token`,
                type_arguments: ["0x1::aptos_coin::AptosCoin"],
                arguments: Object.values(args),
            },
            true
        );
    }
}

async function main() {
    let config = readConfig();
    let deployer = parseAccount(config, "default");
    let signatureSigner = parseAccount(config, "alice");
    let tester = parseAccount(config, "bob");
    let coinType = "0x1::aptos_coin::AptosCoin";
    const client = new Client(deployer, signatureSigner, coinType);
    //await client.verifySignature(Date.now(), 12);
    await client.initialize();

    let collectionName = "Kepler Passport A ";
    //await client.configureKeplerPassportPublicSale(collectionName, 200, 1000);
    //await client.configureKeplerPassportPromotionSale(collectionName, 1000, 100, 1000, 120);
    //await client.configurePromotionPassportSale(collectionName, 111, 222, 1000);

    await client.createCollection(collectionName, `${collectionName} description"`, "http://www.baidu.com");

    await client.buyKeplerPassport(tester, 1, 1, `${deployer.address}`);

    return;

    const randomId = Math.ceil(Math.random() * 5000);
    let tokenName = `${collectionName} #${randomId}`;
    //let url = `https://aptos-api-testnet.bluemove.net/uploads/aptos-shogun/${randomId}.jpg`;

    //https://storage.googleapis.com/keplernft/passport/kepler/K0001.png
    //https://storage.googleapis.com/keplernft/passport/kepler/K5000.png
    let url = `https://storage.googleapis.com/keplernft/passport/kepler/K${String(randomId).padStart(4, "0")}.png`;
    console.log(url);
    await client.createTokenData(collectionName, tokenName, `${tokenName} description`, url);
    await client.mintToken(tester, collectionName, tokenName);
}

if (require.main === module) {
    main().catch((e) => console.error(e));
}

function toU64Hex(n: number): string {
    const buf = Buffer.allocUnsafe(8);
    buf.writeBigInt64BE(BigInt(n));
    return buf.toString("hex");
}

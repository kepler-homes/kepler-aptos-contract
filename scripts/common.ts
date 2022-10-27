import path from "path";
import fs from "fs";
import YAML from "yaml";
import { AptosAccount } from "aptos";

export const NODE_URL = process.env.APTOS_NODE_URL || "https://fullnode.devnet.aptoslabs.com";
export const FAUCET_URL = process.env.APTOS_FAUCET_URL || "https://faucet.devnet.aptoslabs.com";
//<:!:section_1

export const aptosCoinStore = "0x1::coin::CoinStore<0x1::aptos_coin::AptosCoin>";

export const projectPath = path.resolve(`${__dirname}/../`);

export function readConfig(): any {
    let configPath = path.join(projectPath, ".aptos", "config.yaml");
    const file = fs.readFileSync(configPath, "utf8");
    return YAML.parse(file);
}

export function parseAccount(config: any, accountName: string): AptosAccount {
    let deployerKey: string = config.profiles[accountName].private_key.substring(2);
    return new AptosAccount(Uint8Array.from(Buffer.from(deployerKey, "hex")));
}

export function toHexString(s: string): string {
    return Buffer.from(s, "utf-8").toString("hex");
}

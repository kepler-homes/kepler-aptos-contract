import { AptosAccount, AptosClient, MaybeHexString, HexString } from "aptos";
import assert from "assert";
import fetch from "cross-fetch";

export class BaseClient extends AptosClient {
    moduleName: string;
    deployer: AptosAccount;
    moduleType: string;
    moduleAddress: HexString;

    constructor(nodeUrl: string, deployer: AptosAccount, moduleName: string) {
        super(nodeUrl);
        this.moduleName = moduleName;
        this.deployer = deployer;
        this.moduleAddress = deployer.address();
        this.moduleType = `${this.moduleAddress}::${this.moduleName}`;
    }

    async getTransaction(hash: string): Promise<any> {
        let url = `${this.nodeUrl}/transactions/${hash}`;
        //console.log("getTransaction: ", url);
        const response = await fetch(url, { method: "GET" });
        if (response.status == 404) {
            //throw new Error(`Waiting for transaction ${hash} error, invalid url`);
            return { type: "pending_transaction" };
        }
        if (response.status != 200) {
            assert(response.status == 200, await response.text());
        }
        return await response.json();
    }

    async queryResource(userAddress: MaybeHexString, resourceType: string): Promise<any> {
        let url = `${this.nodeUrl}/accounts/${userAddress}/resource/${resourceType}`;
        //console.log("queryResource", url);
        const response = await fetch(url, { method: "GET" });
        if (response.status == 404) {
            return null;
        }
        if (response.status != 200) {
            assert(response.status == 200, await response.text());
        }
        return await response.json();
    }

    async queryModules(moduleAddress: MaybeHexString): Promise<Array<any>> {
        let url = `${this.nodeUrl}/accounts/${moduleAddress}/modules`;
        console.log("queryModules: ", url);
        const response = await fetch(url, { method: "GET" });
        if (response.status == 404) {
            return [];
        }
        if (response.status != 200) {
            assert(response.status == 200, await response.text());
        }
        return await response.json();
    }

    async queryModuleResource(user: MaybeHexString, structName: string): Promise<any> {
        let resourceType = `${this.moduleType}::${structName}`;
        return await this.queryResource(user, resourceType);
    }

    async queryTableItem(tableHandler: string, keyType: string, valueType: string, key: string): Promise<any> {
        let url = `${this.nodeUrl}/tables/${tableHandler}/item`;
        let data = { key_type: keyType, value_type: valueType, key };
        let headers = { "Content-Type": "application/json" };
        //console.log("queryTableItem", url, data);
        const response = await fetch(url, { method: "POST", headers, body: JSON.stringify(data) });
        if (response.status == 200) {
            return await response.json();
        } else {
            return null;
        }
    }

    async submitAndConfirmPayload(userAccount: AptosAccount, payload: any, showTransaction = false): Promise<any> {
        //console.log("submitAndConfirmPayload", payload);
        const rawTxn = await this.generateTransaction(userAccount.address(), payload);
        const bcsTxn = await this.signTransaction(userAccount, rawTxn);
        const pendingTxn = await this.submitTransaction(bcsTxn);
        let result = await this.waitForTransactionWithResult(pendingTxn.hash, { checkSuccess: true });
        if (showTransaction) {
            this.showTransaction(payload.function, result);
        }
        return result;
    }

    showTransaction(prefix: string, transaction: any) {
        console.log(prefix, { hash: transaction.hash, success: transaction.success, message: transaction.vm_status });
    }
}

export class BaseCoinClient extends BaseClient {
    tokenType: String;

    constructor(nodeUrl: string, deployer: AptosAccount, moduleName: string) {
        super(nodeUrl, deployer, moduleName);
        this.tokenType = `${this.moduleType}::T`;
    }

    async isRegistered(accountAddress: MaybeHexString): Promise<boolean> {
        let resourceType = `0x1::coin::CoinStore<${this.tokenType}>`;
        let resource = await this.queryResource(accountAddress, resourceType);
        return resource && resource.type == resourceType;
    }

    async register(coinTypeAddress: HexString, userAccount: AptosAccount): Promise<any> {
        return this.submitAndConfirmPayload(
            userAccount,
            {
                function: "0x1::managed_coin::register",
                type_arguments: [`${coinTypeAddress.hex()}::${this.moduleName}::T`],
                arguments: [],
            },
            true
        );
    }

    async mint(minter: AptosAccount, user: any, amount: number | bigint): Promise<any> {
        return this.submitAndConfirmPayload(
            minter,
            {
                function: "0x1::managed_coin::mint",
                type_arguments: [`${minter.address()}::${this.moduleName}::T`],
                arguments: [`${user}`, amount],
            },
            true
        );
    }
    async getBalance(accountAddress: MaybeHexString): Promise<string | number> {
        try {
            let resourceType = `0x1::coin::CoinStore<${this.tokenType}>`;
            const resource = await this.queryResource(accountAddress, resourceType);
            if (resource) {
                return parseInt((resource.data as any)["coin"]["value"]);
            }
        } catch (_) {}
        return 0;
    }
}

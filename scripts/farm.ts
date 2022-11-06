import { readConfig, parseAccount, toHexString } from "./common";
import { AptosAccount, MaybeHexString } from "aptos";
import { BaseClient } from "./client";

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

class FarmClient extends BaseClient {
    constructor(deployer: AptosAccount, moduleName: string) {
        super(nodeUrl, deployer, moduleName);
    }

    async initialize(rewardTokenType: string): Promise<any> {
        let maxLockUnits = 12;
        let maxMultiplier = 2;

        let lockUnitMultiplier = Math.trunc((maxMultiplier * UNIT) / maxLockUnits);

        let initArgs = {
            resourceSignerSeed: toHexString(this.moduleName),

            //每秒分发多少奖励
            rewardsPerSecond: Math.trunc(UNIT / 1000).toString(),

            //一个锁定周期是多少时间(秒)
            lockUnitDuration: "6",

            //一个锁定周期对应多少奖励加成
            lockUnitMultiplier: lockUnitMultiplier.toString(),

            //每秒分发多少奖励
            maxLockUnits: maxLockUnits.toString(),

            ///领取周期,每隔多长时间领取一次,需要初始化
            ///TODO,change
            lockedRewardWithdrawInterval: "5",

            ///锁定奖励奖励的加权倍数, 2.0/12,需要初始化
            lockedRewardMultiplier: Math.trunc(Math.round((UNIT * 2.0) / 12.0)).toString(),

            ///被锁定的奖励分12期领取
            lockedRewardWithdrawCount: "12",

            ///预先给服务器mint多少rewardToken,

            rewardTokenAmount: "223372036854775800",
        };
        console.log("intArgs", initArgs);
        return await this.submitAndConfirmPayload(this.deployer, {
            function: `${this.moduleType}::initialize`,
            type_arguments: [rewardTokenType],
            arguments: [...Object.values(initArgs)],
        });
    }

    async addPool(stakeTokenType: string): Promise<any> {
        let args = {
            poolWeight: "100",
        };
        return await this.submitAndConfirmPayload(this.deployer, {
            type: "script_function_payload",
            function: `${this.moduleType}::add_pool`,
            type_arguments: [stakeTokenType],
            arguments: [...Object.values(args)],
        });
    }

    async stake(user: AptosAccount, stakeTokenType: string, amount: number, lockUnits: number): Promise<any> {
        let args = Object.values({
            amount: amount.toString(),
            lockUnits: lockUnits.toString(),
        });
        return await this.submitAndConfirmPayload(user, {
            type: "script_function_payload",
            function: `${this.moduleType}::stake`,
            type_arguments: [stakeTokenType],
            arguments: args,
        });
    }

    async unstake(user: AptosAccount, stakeTokenType: string, depositId: number): Promise<any> {
        let args = Object.values({
            depositId: depositId.toString(),
        });
        return await this.submitAndConfirmPayload(user, {
            type: "script_function_payload",
            function: `${this.moduleType}::unstake`,
            type_arguments: [stakeTokenType],
            arguments: args,
        });
    }

    async claim(user: AptosAccount, rewardTokenType: string, stakeTokenType: string, depositId: number): Promise<any> {
        let args = Object.values({
            depositId: depositId.toString(),
        });
        return await this.submitAndConfirmPayload(user, {
            type: "script_function_payload",
            function: `${this.moduleType}::claim`,
            type_arguments: [rewardTokenType, stakeTokenType],
            arguments: args,
        });
    }

    async withdraw(user: AptosAccount, rewardTokenType: string, stakeTokenType: string, claimId: number): Promise<any> {
        let args = Object.values({
            depositId: claimId.toString(),
        });
        return await this.submitAndConfirmPayload(user, {
            type: "script_function_payload",
            function: `${this.moduleType}::withdraw`,
            type_arguments: [rewardTokenType, stakeTokenType],
            arguments: args,
        });
    }

    async queryGlobalStorage(): Promise<any> {
        return await this.queryModuleResource(this.deployer.address(), `GlobalStorage`);
    }
    async queryResourceAccount(): Promise<any> {
        return await this.queryModuleResource(this.deployer.address(), `ResourceAccount`);
    }

    async queryUserStorage(user: MaybeHexString): Promise<any> {
        return await this.queryModuleResource(user, `UserStorage`);
    }

    async queryPool(coinSymbol: string, tableHandler: string | null = null): Promise<any> {
        if (tableHandler == null) {
            let storage = await this.queryGlobalStorage();
            tableHandler = storage && storage.data.pools.handle;
        }
        let keyType = "0x1::string::String";
        let valueType = `${this.moduleType}::Pool`;
        return !tableHandler ? null : await this.queryTableItem(`${tableHandler}`, keyType, valueType, coinSymbol);
    }
}

async function main() {
    let tester = parseAccount(config, "bob");
    const client = new FarmClient(deployer, "farm_003");
    let coinType = `${deployer.address()}::KEME::T`;
    let globalStorage = await client.queryGlobalStorage();
    console.log("globalStorage", globalStorage);
    if (!globalStorage) {
        showTransaction("initialize: ", await client.initialize(coinType));
    }
    let pool = await client.queryPool("KEME");
    console.log("KEME POOL", pool);
    if (!pool) {
        showTransaction("addPool: ", await client.addPool(coinType));
    }
    showTransaction("stake: ", await client.stake(tester, coinType, 123, 5));
    //showTransaction("claim: ", await client.claim(tester, coinType, coinType, 0));
    //showTransaction("withdraw: ", await client.withdraw(tester, coinType, coinType, 0));
    //showTransaction("unstake: ", await client.unstake(tester, coinType, 0));
    console.log("global storage", await client.queryGlobalStorage());
    console.log("keme pool", await client.queryPool("KEME"));
    console.log("user storage", JSON.stringify(await client.queryUserStorage(tester.address()), null, 2));
    console.log("queryResourceAccount", await client.queryResourceAccount());
}

function showTransaction(prefix: string, transaction: any) {
    console.log(prefix, { hash: transaction.hash, success: transaction.success, message: transaction.vm_status });
}

if (require.main === module) {
    main().catch((e) => console.error(e));
}

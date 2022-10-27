/* eslint-disable no-console */
import dotenv from "dotenv";
dotenv.config();
import { readConfig, parseAccount, toHexString } from "./common";
import { AptosClient, AptosAccount, FaucetClient, TokenClient, CoinClient } from "aptos";
import { NODE_URL, FAUCET_URL } from "./common";

(async () => {
    const client = new AptosClient(NODE_URL);
    const faucetClient = new FaucetClient(NODE_URL, FAUCET_URL);
    const tokenClient = new TokenClient(client);
    const coinClient = new CoinClient(client);

    let config = readConfig();
    let deployer = parseAccount(config, "default");
    let bob = parseAccount(config, "bob");

    console.log(`Deployer: ${deployer.address()}`);
    console.log(`Bob: ${bob.address()}`);
    console.log("");

    //await faucetClient.fundAccount(deployer.address(), 100_000_000);
    //await faucetClient.fundAccount(bob.address(), 100_000_000);

    //console.log(`Deployer: ${await coinClient.checkBalance(deployer)}`);
    //console.log(`Bob: ${await coinClient.checkBalance(bob)}`);
    //console.log("");

    console.log("=== Creating Collection and Token ===");
    const collectionName = "Deployer's Collection";
    const collectionDescription = "Deployer's simple collection ";
    const collectionUrl = "https://alice.com";
    const tokenName = "Deployer's Token";
    const tokenPropertyVersion = 0;

    const tokenId = {
        token_data_id: { creator: deployer.address().hex(), collection: collectionName, name: tokenName },
        property_version: `${tokenPropertyVersion}`,
    };

    const txnHash1 = await tokenClient.createCollection(deployer, collectionName, collectionDescription, collectionUrl);
    await client.waitForTransaction(txnHash1, { checkSuccess: true });
    console.log("createCollection", txnHash1);

    const txnHash2 = await tokenClient.createToken(deployer, collectionName, tokenName, "Deployer's simple token", 1, "https://aptos.dev/img/nyan.jpeg"); // <:!:section_5
    await client.waitForTransaction(txnHash2, { checkSuccess: true });
    console.log("createToken", txnHash2);

    // Print the collection data.
    // :!:>section_6
    const collectionData = await tokenClient.getCollectionData(deployer.address(), collectionName);
    console.log(`Deployer's collection: ${JSON.stringify(collectionData, null, 4)}`);

    const aliceToken = await tokenClient.getToken(deployer.address(), collectionName, tokenName, `${tokenPropertyVersion}`);
    console.log(`Deployer's token ${JSON.stringify(aliceToken, null, 4)}`);

    const tokenData = await tokenClient.getTokenData(deployer.address(), collectionName, tokenName);
    console.log(`Deployer's token data: ${JSON.stringify(tokenData, null, 4)}`); // <:!:section_8

    //////
    console.log("\n=== Transferring the token to Bob ===");
    const txnHash3 = await tokenClient.offerToken(deployer, bob.address(), deployer.address(), collectionName, tokenName, 1, tokenPropertyVersion); // <:!:section_9
    await client.waitForTransaction(txnHash3, { checkSuccess: true });
    console.log("offerToken", txnHash3);

    // Bob claims the token Deployer offered him.
    // :!:>section_10
    const txnHash4 = await tokenClient.claimToken(bob, deployer.address(), deployer.address(), collectionName, tokenName, tokenPropertyVersion); // <:!:section_10
    await client.waitForTransaction(txnHash4, { checkSuccess: true });
    console.log("claimToken", txnHash4);

    // Print their balances.
    const aliceBalance2 = await tokenClient.getToken(deployer.address(), collectionName, tokenName, `${tokenPropertyVersion}`);
    const bobBalance2 = await tokenClient.getTokenForAccount(bob.address(), tokenId);
    console.log(`Deployer's token balance: ${aliceBalance2["amount"]}`);
    console.log(`Bob's token balance: ${bobBalance2["amount"]}`);

    console.log("\n=== Transferring the token back to Deployer using MultiAgent ===");
    // :!:>section_11
    let txnHash5 = await tokenClient.directTransferToken(bob, deployer, deployer.address(), collectionName, tokenName, 1, tokenPropertyVersion); // <:!:section_11
    await client.waitForTransaction(txnHash5, { checkSuccess: true });
    console.log("directTransferToken", txnHash5);

    // Print out their balances one last time.
    const aliceBalance3 = await tokenClient.getToken(deployer.address(), collectionName, tokenName, `${tokenPropertyVersion}`);
    const bobBalance3 = await tokenClient.getTokenForAccount(bob.address(), tokenId);
    console.log(`Deployer's token balance: ${aliceBalance3["amount"]}`);
    console.log(`Bob's token balance: ${bobBalance3["amount"]}`);
})();

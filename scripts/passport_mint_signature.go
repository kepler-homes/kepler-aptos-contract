package main

import (
	"crypto/ed25519"
	"encoding/hex"
	"fmt"
)

func main() {

	//用于签名的账号私钥
	privateKeyHex := "05abd7c927e66846e537a4385fdc12064c8a14fb75068192b87c397f9b1936b5"
	//用于签名的账号公钥
	publicKeyHex := "f5939323197c31b8f96c02e65a7334f1beba81a2110464bdbae305da10dd81fd"

	privateKey, _ := hex.DecodeString(privateKeyHex + publicKeyHex)
	publicKey, _ := hex.DecodeString(publicKeyHex)

	//买家地址
	buyerAddr, _ := hex.DecodeString("2f78e9793be1b6804b665eeaabd11777e6720c5b9054b71c30ab3764dc8d1b93")

	//买多少PASSPORT
	//u64
	amount, _ := hex.DecodeString("0000000000000001")

	//是否以白名单价格购买, 必须是白名单用户才可以.
	// 1:是,0:否
	isPromotional, _ := hex.DecodeString("0000000000000001")

	//推荐人地址
	//u64
	referrer, _ := hex.DecodeString("c6d0c4e76483557fb4472093a70f2ce5361070e6420eba96470c166951ac8727")

	message := make([]byte, 0)
	message = append(message, buyerAddr...)
	message = append(message, amount...)
	message = append(message, isPromotional...)
	message = append(message, referrer...)

	signature := ed25519.Sign(privateKey, message)

	//结果: 11802c5edfac04432592f6647a50dfaed03d0bc3758de9a3560a5646584302f3c0f9431824cbd4ef16a116da5bdb7da5660de71186c4451fe347f9dc69126f01
	fmt.Println("signature:", hex.EncodeToString(signature))

	fmt.Println("verify:", ed25519.Verify(publicKey, message, signature))
}

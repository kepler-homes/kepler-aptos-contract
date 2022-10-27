module kepler::passport_mine_011 {
    use std::vector;
    use std::signer;
    use std::string::{Self,String};
    use std::error;
    use std::ed25519::{Self,ValidatedPublicKey};
    use aptos_std::table::{Self,Table};
    use aptos_std::type_info::{Self,TypeInfo};
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::resource_account;
    use aptos_framework::event::{Self,EventHandle};
    use aptos_framework::timestamp;
    use aptos_framework::util;
    use aptos_token::token::{Self,Token,TokenDataId,TokenId,deposit_token,withdraw_token,merge,split};


    const ENOT_ADMIN                                    :u64 = 0x1001;
    const ENOT_DEPLOYER                                 :u64 = 0x1002;
    const ECOIN_NOT_IN_WHITELIST                        :u64 = 0x1003;
    const EINVALID_SIGNATURE                            :u64 = 0x1004;
    const ECOLLECTION_NOT_CREATED                       :u64 = 0x1005;
    const EINVALID_COLLECTION_OWNER                     :u64 = 0x1006;
    const EINVALID_VECTOR_LENGTH                        :u64 = 0x1007;
    const EFREN_NOT_FOUND                               :u64 = 0x1008;
    const EFRENS_NOT_AVAILABLE                          :u64 = 0x1009;
    const EINVALID_BALANCE                              :u64 = 0x1010;
    const EALREADY_INITIALIZED                          :u64 = 0x1011;
    const ENOT_INITIALIZED                              :u64 = 0x1012;
    const EKEPLER_PASSPORT_PUBLIC_SALE_NOT_CONFIGURED   :u64 = 0x1013;
    const EKEPLER_PASSPORT_PROMOTION_SALE_NOT_CONFIGURED:u64 = 0x1014;
    const EUNIVERSE_PASSPORT_SALE_NOT_CONFIGURED        :u64 = 0x1015;
    const EINVALID_U64_BYTE_LENGTH                      :u64 = 0x1016;

    struct GlobalStorage has key{
        resource_accounts: table::Table<vector<u8>,address>,
        signature_signer: vector<u8>,
        currency: TypeInfo,
    }  

    struct UserStorage has key, store{
        reference_records: vector<ReferenceRecord>,
        buy_records: vector<BuyRecord>,
    }

    struct KeplerToken has store {
        name: vector<u8>,
        description: vector<u8>,
        token_data: token::TokenDataId

    }

    struct KeplerCollection has key {
        name: vector<u8>,
        description: vector<u8>,
        tokens: vector<KeplerToken>,
        owner: address,
        resource_signer_cap: account::SignerCapability
    }

    struct KeplerPassportPublicSaleStorage has key{
        collection_name: vector<u8>,
        price: u64,
        max_supply:u64,
        sale_amount:u64,
    }

    struct KeplerPassportPromotionSaleStorage has key{
        collection_name: vector<u8>,
        stage1_supply: u64,
        stage1_price: u64,
        stage2_supply: u64,
        stage2_price: u64,
        sale_amount: u64,
    }

    struct UniversePassportSaleStorage has key{
        collection_name: vector<u8>,
        public_price: u64,
        promotion_price: u64,
        max_supply:u64,
        sale_amount:u64,
    }

    struct ReferenceRecord has store{
        buyer: address,
        collection_name: vector<u8>,
        buy_amount: u64,
        price: u64,
        reward: u64,
        buy_time: u64,
    }

    struct BuyRecord has store{
        collection_name: vector<u8>,
        buy_amount: u64,
        price: u64,
        buy_time: u64,
    }

    public entry fun initialize<CoinType>(deployer:&signer,signature_signer:vector<u8>,) {
        let addr = signer::address_of(deployer);
        assert!(addr==@kepler, ENOT_DEPLOYER);
        assert!(!exists<GlobalStorage>(addr), EALREADY_INITIALIZED);
        move_to(deployer, GlobalStorage{
            resource_accounts: table::new(),
            currency: type_info::type_of<CoinType>(),
            signature_signer: signature_signer,
        });
    }

    public entry fun configure_kepler_passport_public_sale (
        deployer:&signer,
        collection_name: vector<u8>,
        price: u64,
        max_supply:u64
    ) acquires KeplerPassportPublicSaleStorage {
        let addr = signer::address_of(deployer);
        assert!(addr==@kepler, ENOT_DEPLOYER);
        if (exists<KeplerPassportPublicSaleStorage>(addr)) {
            let storage =  borrow_global_mut<KeplerPassportPublicSaleStorage>(addr);
            storage.collection_name = collection_name;
            storage.price = price;
            storage.max_supply = max_supply;
        }else {
            move_to(deployer, KeplerPassportPublicSaleStorage{collection_name,price,max_supply,sale_amount:0});
        }
    }

    public entry fun configure_kepler_passport_promotion_sale (
        deployer:&signer,
        collection_name: vector<u8>,
        stage1_supply: u64,
        stage1_price: u64,
        stage2_supply: u64,
        stage2_price: u64,
    ) acquires KeplerPassportPromotionSaleStorage {
        let addr = signer::address_of(deployer);
        assert!(addr==@kepler, ENOT_DEPLOYER);
        if (exists<KeplerPassportPromotionSaleStorage>(addr)) {
            let storage =  borrow_global_mut<KeplerPassportPromotionSaleStorage>(addr);
            storage.collection_name = collection_name;
            storage.stage1_supply = stage1_supply;
            storage.stage1_price = stage1_price;
            storage.stage2_supply = stage2_supply;
            storage.stage2_price = stage2_price;
        }else {
            move_to(deployer, KeplerPassportPromotionSaleStorage{
                collection_name,
                stage1_supply,
                stage1_price,
                stage2_supply,
                stage2_price,
                sale_amount:0
            });
        }
    }

    public entry fun configure_promotion_passport_sale (
        deployer:&signer,
        collection_name: vector<u8>,
        public_price: u64,
        promotion_price: u64,
        max_supply:u64,
    ) acquires UniversePassportSaleStorage {
        let addr = signer::address_of(deployer);
        assert!(addr==@kepler, ENOT_DEPLOYER);
        if (exists<UniversePassportSaleStorage>(addr)) {
            let storage =  borrow_global_mut<UniversePassportSaleStorage>(addr);
            storage.collection_name = collection_name;
            storage.public_price = public_price;
            storage.promotion_price = promotion_price;
            storage.max_supply = max_supply;
        }else {
            move_to(deployer, UniversePassportSaleStorage{
                collection_name,
                public_price,
                promotion_price,
                max_supply,
                sale_amount:0
            });
        }
    }

    public entry fun buy_kepler_passport<CoinType>(
        buyer: &signer,
        amount: vector<u8>,
        is_promotional: vector<u8>,
        referrer: vector<u8>,
        signature: vector<u8>,
    ) acquires GlobalStorage{
        assert!(exists<GlobalStorage>(@kepler), ENOT_INITIALIZED);
        let global = borrow_global<GlobalStorage>(@kepler);
        let message = vector::empty<u8>();
        vector::append(&mut message,amount);
        vector::append(&mut message,is_promotional);
        vector::append(&mut message,referrer);
        let signature = ed25519::new_signature_from_bytes(signature);
        let pubkey = ed25519::new_unvalidated_public_key_from_bytes(global.signature_signer);
        let verified = ed25519::signature_verify_strict(&signature,&pubkey,message);
        assert!(verified,EINVALID_SIGNATURE);
    }

    fun vector_to_u64(v: &vector<u8>): u64{
        let length=vector::length(v);
        assert!(length==8,EINVALID_U64_BYTE_LENGTH);
        let value :u64 = 0;
        let i = 0;
        while(i < length){
            value = value+(*vector::borrow(v,i) as u64)<<(((length - i - 1) * 8) as u8);
            i = i + 1;
        };
        value
    }

    public entry fun buy_universe_passport(){}


    public entry fun create_collection(
        collection_owner: &signer,
        name: vector<u8>,
        description: vector<u8>,
        uri: vector<u8>
    ) acquires GlobalStorage {
        let addr = signer::address_of(collection_owner);
        assert!(exists<GlobalStorage>(addr), ENOT_INITIALIZED);
        let global = borrow_global_mut<GlobalStorage>(addr);

        let collection_owner_addr = signer::address_of(collection_owner);

        // creating a resource account which would create collection and mint tokens
        let (resource,resource_signer_cap) = account::create_resource_account(collection_owner, name);
        let collection = KeplerCollection {
            name,
            description,
            tokens: vector::empty<KeplerToken>(),
            owner: collection_owner_addr,
            resource_signer_cap
        };

        move_to(&resource,collection);
        // create a collection with the venue name and resource account as the creator
        token::create_collection(
            &resource,// signer
            string::utf8(name),// Name
            string::utf8(description),// Description
            string::utf8(uri),// URI
            0,// Maximum NFTs
            vector<bool>[false,false,false] // Mutable Config
        );
        table::add(&mut global.resource_accounts, name,signer::address_of(&resource));
    }

     public entry fun create_tokendata (
        collection_owner: &signer,
        collection_name: vector<u8>,
        name: vector<u8>,
        description: vector<u8>,
        uri: vector<u8>
    ) acquires KeplerCollection,GlobalStorage {
        assert!(exists<GlobalStorage>(@kepler), ENOT_INITIALIZED);

        let global = borrow_global<GlobalStorage>(@kepler);

        let venue_resource = *table::borrow(&global.resource_accounts, collection_name );

        assert!(exists<KeplerCollection>(venue_resource),ECOLLECTION_NOT_CREATED);
        
        let collection_owner_addr = signer::address_of(collection_owner);
        let collection_info = borrow_global_mut<KeplerCollection>(venue_resource);
        
        assert!(collection_info.owner == collection_owner_addr,EINVALID_COLLECTION_OWNER);

        let collection_resource_signer = account::create_signer_with_capability(&collection_info.resource_signer_cap);

        // Creating a token data for this particular type of fren which would be used to mint NFTs
        let token_mutability = token::create_token_mutability_config(&vector<bool>[false,false,false,false,false]);

        let token_data = token::create_tokendata(
            &collection_resource_signer,
            string::utf8(collection_info.name),// Collection Name
            string::utf8(name),// Token Name
            string::utf8(description),// Token description
            1,//maximum,
            string::utf8(uri),
            collection_info.owner,// royalty payee address
            100, //royalty_points_denominator
            5, //royalty_points_numerator
            token_mutability,//token_mutate_config
            vector<string::String>[], //property_keys
            vector<vector<u8>>[], //property_values
            vector<string::String>[] //property_types
        );
        let token = KeplerToken {name,description,token_data};
        vector::push_back(&mut collection_info.tokens,token);
    }


    public entry fun mint_token<CoinType>(
        buyer: &signer,
        collection_name: vector<u8>,
        name: vector<u8>
    ) acquires KeplerCollection,GlobalStorage {
        assert!(exists<GlobalStorage>(@kepler), ENOT_INITIALIZED);
        let global = borrow_global<GlobalStorage>(@kepler);
        let venue_resource = *table::borrow(&global.resource_accounts, collection_name );
        assert!(exists<KeplerCollection >(venue_resource),ECOLLECTION_NOT_CREATED);

        let collection_info = borrow_global_mut<KeplerCollection>(venue_resource);
        let token_count = vector::length(&collection_info.tokens);
        let i = 0;
        while (i < token_count) {
            let current = vector::borrow<KeplerToken>(&collection_info.tokens,i);
            if (current.name == name) {
                break
            };
            i = i +1;
        };

        assert!(i != token_count, EFREN_NOT_FOUND);
        let kepler_token = vector::borrow_mut<KeplerToken>(&mut collection_info.tokens,i);

        let price =20;
        coin::transfer<CoinType>(buyer,collection_info.owner,price);

        let collection_resource_signer = account::create_signer_with_capability(&collection_info.resource_signer_cap);
        let buyer_addr = signer::address_of(buyer);

        // the buyer should opt in direct transfer for the NFT to be minted
        token::opt_in_direct_transfer(buyer,true);
        // Mint the NFT to the buyer account
        token::mint_token_to(&collection_resource_signer,buyer_addr,kepler_token.token_data, 1);
    }


    public entry fun verify_signature(_user:&signer,order_id: vector<u8>,amount: vector<u8>,pubkey: vector<u8>,signature: vector<u8>){
        let message = vector::empty<u8>();
        vector::append(&mut message,order_id);
        vector::append(&mut message,amount);
        let signature = ed25519::new_signature_from_bytes(signature);
        let pubkey = ed25519::new_unvalidated_public_key_from_bytes(pubkey);
        let verified = ed25519::signature_verify_strict(&signature,&pubkey,message);
        assert!(verified,EINVALID_SIGNATURE);
    }

}
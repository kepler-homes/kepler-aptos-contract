module kepler::passport_mint_001 {
    use std::vector;
    use std::signer;
    use std::string;
    use std::math64;
    use std::ed25519;
    use aptos_std::table;
    use aptos_std::type_info;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::timestamp;
    use aptos_framework::util;
    use aptos_token::token;

    const MAX_BUY_COUNT             :u64 = 2;

    const ENOT_DEPLOYER             :u64 = 0x101;
    const EINVALID_SIGNATURE        :u64 = 0x102;
    const ECOLLECTION_NOT_CREATED   :u64 = 0x103;
    const EFREN_NOT_FOUND           :u64 = 0x104;
    const EINVALID_BALANCE          :u64 = 0x105;
    const EALREADY_INITIALIZED      :u64 = 0x106;
    const ENOT_INITIALIZED          :u64 = 0x107;
    const EINVALID_U64_BYTE_LENGTH  :u64 = 0x108;
    const EINVALID_PARAMETERS       :u64 = 0x109;
    const EEXCEED_MAX_BUY_AMOUNT    :u64 = 0x10a;
    const EEXCEED_SALE_SUPPLY       :u64 = 0x10b;
    const EINVALID_BUY_TIME         :u64 = 0x10c;

    struct ModuleStorage has key{
        resource_accounts: table::Table<vector<u8>,address>,
        signature_pubkey: vector<u8>,
        currency:  type_info::TypeInfo,
        vault: address,
    }

    struct CollectionConfig has key {
        name: vector<u8>,
        description: vector<u8>,
        uri: vector<u8>,
        resource_signer_cap: account::SignerCapability,
        next_token_id: u64,
    }

    struct UserStorage has key, store{
        buy_records: vector<BuyRecord>,
    }

    struct BuyRecord has store{
        collection_name: vector<u8>,
        buy_amount: u64,
        total_pay: u64,
        buy_time: u64,
    }

    struct KeplerPassportConfig has key{
        collection_name: vector<u8>,

        //public config
        pb_price: u64,
        pb_supply:u64,
        pb_sell_amount:u64,

        //promotion config
        pt_stage1_supply: u64,
        pt_stage1_price: u64,
        pt_stage2_supply: u64,
        pt_stage2_price: u64,
        pt_sell_amount: u64,

        //og config
        og_price: u64,
        og_supply:u64,
        og_sell_amount:u64,
        og_start_time: u64,
    }

    public entry fun initialize<CoinType>(deployer:&signer, signature_pubkey: vector<u8>, vault: address) {
        let addr = signer::address_of(deployer);
        assert!(addr==@kepler, ENOT_DEPLOYER);
        assert!(!exists<ModuleStorage>(addr), EALREADY_INITIALIZED);
        move_to(deployer, ModuleStorage{
            resource_accounts: table::new(),
            currency: type_info::type_of<CoinType>(),
            signature_pubkey: signature_pubkey,
            vault
        });
    }

    public entry fun create_collection(
        deployer: &signer,
        name: vector<u8>,
        description: vector<u8>,
        uri: vector<u8>,
        seed: vector<u8>,
    ) acquires ModuleStorage {
        let addr = signer::address_of(deployer);
        assert!(addr==@kepler, ENOT_DEPLOYER);
        assert!(exists<ModuleStorage>(addr), ENOT_INITIALIZED);
        let global = borrow_global_mut<ModuleStorage>(addr);
        // creating a resource account which would create collection and mint tokens
        let (resource,resource_signer_cap) = account::create_resource_account(deployer, seed);
        let collection = CollectionConfig {
            name,
            description,
            uri,
            resource_signer_cap,
            next_token_id: 1,
        };

        move_to(&resource,collection);
        token::create_collection(
            &resource,// signer
            string::utf8(name),// Name
            string::utf8(description),// Description
            string::utf8(uri),// URI
            0,// Maximum NFTs
            vector<bool>[false,false,false] // Mutable Config
        );
        table::add(&mut global.resource_accounts,name,signer::address_of(&resource));
    }

    public entry fun pb_buy<CoinType>(buyer: &signer, amount: vector<u8>)
        acquires ModuleStorage, UserStorage, CollectionConfig, KeplerPassportConfig {
        assert!(exists<ModuleStorage>(@kepler), ENOT_INITIALIZED);
        assert!(exists<KeplerPassportConfig>(@kepler), ENOT_INITIALIZED);
        let config = borrow_global_mut<KeplerPassportConfig>(@kepler);
        let amount = vector_to_u64(&amount);
        let (supply,sell_amount,total_pay) = (config.pb_supply,config.pb_sell_amount,config.pb_price*amount);
        buy_passport<CoinType>(buyer,amount,config.collection_name,supply,sell_amount,total_pay);
        number_add(&mut config.pb_sell_amount,amount);
    }


    public entry fun og_buy<CoinType>(buyer: &signer, buyer_addr: vector<u8>, amount: vector<u8>, signature: vector<u8>)
        acquires ModuleStorage, UserStorage, CollectionConfig, KeplerPassportConfig {
        assert!(util::address_from_bytes(buyer_addr)== signer::address_of(buyer), EINVALID_PARAMETERS);
        assert!(exists<ModuleStorage>(@kepler), ENOT_INITIALIZED);
        assert!(exists<KeplerPassportConfig>(@kepler), ENOT_INITIALIZED);
        verify_signature(buyer_addr, amount, signature);
        let config = borrow_global_mut<KeplerPassportConfig>(@kepler);
        assert!(config.og_start_time>0 && timestamp::now_seconds() > config.og_start_time, EINVALID_BUY_TIME);
        let amount = vector_to_u64(&amount);
        let (supply,sell_amount,total_pay) = (config.og_supply,config.og_sell_amount,config.og_price*amount);
        buy_passport<CoinType>(buyer,amount,config.collection_name,supply,sell_amount,total_pay);
        number_add(&mut config.pb_sell_amount,amount);
    }

    public entry fun pt_buy<CoinType>(buyer: &signer, buyer_addr: vector<u8>, amount: vector<u8>, signature: vector<u8>)
        acquires ModuleStorage, UserStorage, CollectionConfig, KeplerPassportConfig {
        assert!(util::address_from_bytes(buyer_addr)== signer::address_of(buyer), EINVALID_PARAMETERS);
        assert!(exists<ModuleStorage>(@kepler), ENOT_INITIALIZED);
        assert!(exists<KeplerPassportConfig>(@kepler), ENOT_INITIALIZED);
        verify_signature(buyer_addr, amount, signature);
        let config = borrow_global_mut<KeplerPassportConfig>(@kepler);
        let amount = vector_to_u64(&amount);
        let (supply,sell_amount,total_pay) = get_pt_parameters(config,amount);
        buy_passport<CoinType>(buyer,amount,config.collection_name,supply,sell_amount,total_pay);
        number_add(&mut config.pb_sell_amount,amount);
    }

    fun get_pt_parameters(config: &KeplerPassportConfig, amount :u64) : (u64,u64,u64) {
        let supply = config.pt_stage1_supply + config.pt_stage2_supply;
        let (i, total_pay, sell_amount) = (0, 0, config.pt_sell_amount);
        while (i < amount) {
            let price = if(sell_amount + i <= config.pt_stage1_supply) {config.pt_stage1_price} else {config.pt_stage2_price};
            total_pay = total_pay + price;
            i = i + 1;
        };
        (supply,sell_amount,total_pay)
    }

    fun verify_signature(buyer_addr: vector<u8>, amount: vector<u8>, signature: vector<u8>) acquires ModuleStorage {
        let module_storage = borrow_global<ModuleStorage>(@kepler);
        let message = vector::empty<u8>();
        vector::append(&mut message,buyer_addr);
        vector::append(&mut message,amount);

        let signature = ed25519::new_signature_from_bytes(signature);
        let pubkey = ed25519::new_unvalidated_public_key_from_bytes(module_storage.signature_pubkey);
        let verified = ed25519::signature_verify_strict(&signature,&pubkey,message);
        assert!(verified,EINVALID_SIGNATURE);
    }

    fun buy_passport<CoinType>(
        buyer: &signer,
        amount: u64,
        collection_name: vector<u8>,
        supply: u64,
        sell_amount:   u64,
        total_pay:u64
    ) acquires ModuleStorage, UserStorage, CollectionConfig
    {
        let addr = signer::address_of(buyer);
        let global = borrow_global<ModuleStorage>(@kepler);
        assert!(amount>0, EINVALID_PARAMETERS);
        if(!exists<UserStorage>(addr)){
            move_to(buyer,UserStorage {buy_records: vector::empty<BuyRecord>()});
        };
        let user_storage = borrow_global_mut<UserStorage>(addr);
        assert!(amount + vector::length(&user_storage.buy_records)<= MAX_BUY_COUNT, EEXCEED_MAX_BUY_AMOUNT);
        assert!(amount + sell_amount <= supply, EEXCEED_SALE_SUPPLY);
        assert!(table::contains(&global.resource_accounts, collection_name), ECOLLECTION_NOT_CREATED);
        let collection_resource = *table::borrow(&global.resource_accounts, collection_name);
        assert!(exists<CollectionConfig>(collection_resource),ECOLLECTION_NOT_CREATED);
        let collection  = borrow_global_mut<CollectionConfig>(collection_resource);

        mint_token_to(buyer,collection);
        coin::transfer<CoinType>(buyer,global.vault,total_pay );
        // add buy records
        vector::push_back(&mut user_storage.buy_records,BuyRecord{
            collection_name,
            buy_amount: amount,
            total_pay,
            buy_time: timestamp::now_seconds(),
        });
    }
 
    public entry fun configure_kepler_passport (
        deployer:&signer,
        collection_name: vector<u8>,
        pb_price: u64,
        pb_supply:u64,
        pt_stage1_supply: u64,
        pt_stage1_price: u64,
        pt_stage2_supply: u64,
        pt_stage2_price: u64,
        og_price: u64,
        og_supply: u64,
        og_start_time: u64,
    ) acquires KeplerPassportConfig {
        let addr = signer::address_of(deployer);
        assert!(addr==@kepler, ENOT_DEPLOYER);
        if (exists<KeplerPassportConfig>(addr)) {
            let storage =  borrow_global_mut<KeplerPassportConfig>(addr);
            storage.collection_name = collection_name;
            storage.pb_price = pb_price;
            storage.pb_supply = pb_supply;
            storage.pt_stage1_supply = pt_stage1_supply;
            storage.pt_stage1_price = pt_stage1_price;
            storage.pt_stage2_supply = pt_stage2_supply;
            storage.pt_stage2_price = pt_stage2_price;
            storage.og_price=og_price;
            storage.og_supply=og_supply;
            storage.og_start_time=og_start_time;
        }else {
            move_to(deployer, KeplerPassportConfig{
                collection_name,
                pb_price,
                pb_supply,
                pb_sell_amount:0,
                pt_stage1_supply,
                pt_stage1_price,
                pt_stage2_supply,
                pt_stage2_price,
                pt_sell_amount:0,
                og_price: og_price,
                og_supply: og_supply,
                og_sell_amount: 0,
                og_start_time: og_start_time,
            });
        }
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

    fun mint_token_to(buyer: &signer,collection: &mut CollectionConfig) {
        let token_id= u64_to_raw_string(collection.next_token_id,4);
        number_add(&mut collection.next_token_id,1);
        let name = vector::empty<u8>();
        vector::append(&mut name, collection.name);
        vector::append(&mut name, b"# ");
        vector::append(&mut name, token_id);
        let description= name;
        let uri = vector::empty<u8>();
        //https://storage.googleapis.com/keplernft/passport/kepler/K0001.png
        vector::append(&mut uri, b"https://storage.googleapis.com/keplernft/passport/kepler/K");
        vector::append(&mut uri, token_id);
        vector::append(&mut uri, b".png");

        let resource_signer = account::create_signer_with_capability(&collection.resource_signer_cap);
        let token_data_id = create_token_data_id(&resource_signer,collection.name,name,description,uri);
        // the buyer should opt in direct transfer for the NFT to be minted
        token::opt_in_direct_transfer(buyer,true);
        // Mint the NFT to the buyer account
        let buyer_addr = signer::address_of(buyer);
        token::mint_token_to(&resource_signer,buyer_addr, token_data_id, 1);
    }

     fun create_token_data_id(
        resource_signer :&signer,
        collection_name:vector<u8>,
        name: vector<u8>,
        description: vector<u8>,
        uri: vector<u8>,) : token::TokenDataId {
        let token_mutability = token::create_token_mutability_config(&vector<bool>[false,false,false,false,false]);
        token::create_tokendata(
            resource_signer,
            string::utf8(collection_name),// Collection Name
            string::utf8(name),// Token Name
            string::utf8(description),// Token description
            1,//maximum,
            string::utf8(uri),
            @kepler,// royalty payee address
            100, //royalty_points_denominator
            5, //royalty_points_numerator
            token_mutability,//token_mutate_config
            vector<string::String>[], //property_keys
            vector<vector<u8>>[], //property_values
            vector<string::String>[] //property_types
        )
    }

    fun number_add(number: &mut u64, value: u64){
        *number = *number + value;
    }

    fun u64_to_raw_string(token_id: u64, length:u64) :vector<u8> {
        let v = vector::empty<u8>();
        let i:u64 = 0;
        while (i < length) {
            let char = 48 + token_id%math64::pow(10,length-i)/math64::pow(10,length-i-1);
            vector::push_back(&mut v,(char as u8));
            i = i+1 ;
        };
        v
    }
}
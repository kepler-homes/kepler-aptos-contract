module kepler::passport_mine_006 {
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
    use aptos_token::token ;

    const EMPTY_ADDRESS                                 :address = @0x0000000000000000000000000000000000000000000000000000000000000000;
    const MAX_BUY_COUNT                                 :u64 = 4;
    const COMMISSION_RATE                               :u64 = 5;

    const ENOT_DEPLOYER                                 :u64 = 0x1000;
    const EINVALID_SIGNATURE                            :u64 = 0x1001;
    const ECOLLECTION_NOT_CREATED                       :u64 = 0x1002;
    const EALREADY_INITIALIZED                          :u64 = 0x1003;
    const ENOT_INITIALIZED                              :u64 = 0x1004;
    const EINVALID_U64_BYTE_LENGTH                      :u64 = 0x1005;
    const EINVALID_PARAMETERS                           :u64 = 0x1006;
    const EEXCEED_MAX_BUY_AMOUNT                        :u64 = 0x1007;
    const EEXCEED_SALE_SUPPLY                           :u64 = 0x1008;

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
        reference_records: table::Table<address,vector<ReferenceRecord>>,
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
        public_price: u64,
        public_total_supply:u64,
        public_sale_amount:u64,
 
        promotion_stage1_supply: u64,
        promotion_stage1_price: u64,
        promotion_stage2_supply: u64,
        promotion_stage2_price: u64,
        promotion_sale_amount: u64,
    }

    struct UniversePassportConfig has key{
        collection_name: vector<u8>,
        public_price: u64,
        promotion_price: u64,
        total_supply:u64,
        sale_amount:u64,
    }

    struct ReferenceRecord has store{
        buyer: address,
        collection_name: vector<u8>,
        buy_amount: u64,
        total_pay: u64,
        reward: u64,
        buy_time: u64,
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
            reference_records:table::new(),
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


    public entry fun buy_kepler_passport<CoinType>(
        buyer: &signer,
        buyer_addr: vector<u8>,
        amount: vector<u8>,
        is_promotional: vector<u8>,
        referrer: vector<u8>,
        signature: vector<u8>,
    ) acquires ModuleStorage, UserStorage, CollectionConfig, KeplerPassportConfig
    {
        assert!(util::address_from_bytes(buyer_addr)== signer::address_of(buyer), EINVALID_PARAMETERS);
        assert!(exists<ModuleStorage>(@kepler), ENOT_INITIALIZED);
        let global = borrow_global<ModuleStorage>(@kepler);
        verify_buy_signature(buyer_addr, amount,is_promotional,referrer,signature,global.signature_pubkey);
        let amount = vector_to_u64(&amount);
        let is_promotional = vector_to_u64(&is_promotional);
        let referrer = util::address_from_bytes(referrer);
        let config = borrow_global_mut<KeplerPassportConfig>(@kepler);
        let (total_supply,sale_amount,total_pay) = get_kepler_parameters(config,is_promotional,amount);

        buy_passport<CoinType>(buyer,amount,referrer,config.collection_name,total_supply,sale_amount,total_pay); 
        
        if(is_promotional==1){
            number_add(&mut config.promotion_sale_amount,amount);
        }else {
            number_add(&mut config.public_sale_amount,amount);
        };
    }

        public entry fun buy_universe_passport<CoinType>(
            buyer: &signer,
            buyer_addr: vector<u8>,
            amount: vector<u8>,
            is_promotional: vector<u8>,
            referrer: vector<u8>,
            signature: vector<u8>,
        ) acquires ModuleStorage, UserStorage, CollectionConfig, UniversePassportConfig
    {
        assert!(util::address_from_bytes(buyer_addr)== signer::address_of(buyer), EINVALID_PARAMETERS);
        assert!(exists<ModuleStorage>(@kepler), ENOT_INITIALIZED);
        let global = borrow_global<ModuleStorage>(@kepler);
        verify_buy_signature(buyer_addr, amount,is_promotional,referrer,signature,global.signature_pubkey);
        let amount = vector_to_u64(&amount);
        let is_promotional = vector_to_u64(&is_promotional);
        let referrer = util::address_from_bytes(referrer);
        let config = borrow_global_mut<UniversePassportConfig>(@kepler);
        let (total_supply,sale_amount,total_pay) = get_universe_parameters(config,is_promotional,amount);
        buy_passport<CoinType>(buyer,amount,referrer,config.collection_name,total_supply,sale_amount,total_pay);
        number_add(&mut config.sale_amount,amount);
    }

    fun buy_passport<CoinType>(
        buyer: &signer,
        amount: u64,
        referrer: address,
        collection_name: vector<u8>,
        total_supply: u64,
        sale_amount:   u64,
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
        assert!(amount + vector::length(&user_storage.buy_records)<=MAX_BUY_COUNT, EEXCEED_MAX_BUY_AMOUNT);
        assert!(amount + sale_amount <= total_supply, EEXCEED_SALE_SUPPLY);
        assert!(table::contains(&global.resource_accounts, collection_name), ECOLLECTION_NOT_CREATED);
        let collection_resource = *table::borrow(&global.resource_accounts, collection_name);
        
        assert!(exists<CollectionConfig>(collection_resource),ECOLLECTION_NOT_CREATED);
        let collection  = borrow_global_mut<CollectionConfig>(collection_resource);
        
        //mint nft to buyer
        mint_token_to(buyer,collection);
        
        // transfer coin to valut and referrer
        let reward= if(referrer == EMPTY_ADDRESS) {0} else {total_pay*COMMISSION_RATE/100};
        coin::transfer<CoinType>(buyer,global.vault,total_pay-reward);
        
        if(reward>0){
            coin::transfer<CoinType>(buyer,referrer, reward);
        };

        // add buy records
        vector::push_back(&mut user_storage.buy_records,BuyRecord{
            collection_name,
            buy_amount: amount,
            total_pay,
            buy_time: timestamp::now_seconds(),
        });

        // add reference records
        if(!table::contains(&collection.reference_records, referrer)){
            table::add(&mut collection.reference_records,referrer, vector::empty<ReferenceRecord>());
        };
        let reference_records = table::borrow_mut(&mut collection.reference_records, referrer);
        vector::push_back(reference_records , ReferenceRecord{
            buyer: addr,
            collection_name,
            buy_amount: amount,
            total_pay,
            reward ,
            buy_time: timestamp::now_seconds(),
        });
    }


    fun get_kepler_parameters(storage: &KeplerPassportConfig, is_promotional: u64, amount :u64) : (u64,u64,u64) {
            if(is_promotional==1){
            let total_supply = storage.promotion_stage1_supply + storage.promotion_stage2_supply;
            let i = 0;
            let total_pay = 0;
            let sale_amount = storage.promotion_sale_amount;
            while (i < amount) {
                let price = if(sale_amount+i <= storage.promotion_stage1_supply) {storage.promotion_stage1_price} else {storage.promotion_stage2_price};
                total_pay = total_pay + price;
                i = i + 1;
            };
            (total_supply,sale_amount,total_pay)
        }else {
            let total_supply = storage.public_total_supply;
            let total_pay = amount * storage.public_price;
            let sale_amount = storage.public_sale_amount;
            (total_supply,sale_amount,total_pay)
        }
    }

    fun get_universe_parameters(storage: &UniversePassportConfig,is_promotional: u64, amount :u64) : (u64,u64,u64) {
        let price = if(is_promotional==1) {storage.promotion_price} else {storage.public_price};
        (storage.total_supply,storage.sale_amount, amount* price)
    }

    fun verify_buy_signature(
        buyer_addr: vector<u8>,
        amount: vector<u8>,
        is_promotional: vector<u8>,
        referrer: vector<u8>,
        signature: vector<u8>,
        signature_pubkey: vector<u8>,
    ) {
        let message = vector::empty<u8>();
        vector::append(&mut message,buyer_addr);
        vector::append(&mut message,amount);
        vector::append(&mut message,is_promotional);
        vector::append(&mut message,referrer);
        let signature = ed25519::new_signature_from_bytes(signature);
        let pubkey = ed25519::new_unvalidated_public_key_from_bytes(signature_pubkey);
        let verified = ed25519::signature_verify_strict(&signature,&pubkey,message);
        assert!(verified,EINVALID_SIGNATURE);
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

    public entry fun configure_kepler_passport (
        deployer:&signer,
        collection_name: vector<u8>,
        public_price: u64,
        public_total_supply:u64,
        promotion_stage1_supply: u64,
        promotion_stage1_price: u64,
        promotion_stage2_supply: u64,
        promotion_stage2_price: u64,
    ) acquires KeplerPassportConfig {
        let addr = signer::address_of(deployer);
        assert!(addr==@kepler, ENOT_DEPLOYER);
        if (exists<KeplerPassportConfig>(addr)) {
            let storage =  borrow_global_mut<KeplerPassportConfig>(addr);
            storage.collection_name = collection_name;
            storage.public_price = public_price;
            storage.public_total_supply = public_total_supply;
            storage.promotion_stage1_supply = promotion_stage1_supply;
            storage.promotion_stage1_price = promotion_stage1_price;
            storage.promotion_stage2_supply = promotion_stage2_supply;
            storage.promotion_stage2_price = promotion_stage2_price;

        }else {
            move_to(deployer, KeplerPassportConfig{
                collection_name,
                public_price,
                public_total_supply,
                public_sale_amount:0,
                promotion_stage1_supply,
                promotion_stage1_price,
                promotion_stage2_supply,
                promotion_stage2_price,
                promotion_sale_amount:0
            });
        }
    }

    public entry fun configure_uinverse_passport (
        deployer:&signer,
        collection_name: vector<u8>,
        public_price: u64,
        promotion_price: u64,
        total_supply:u64,
    ) acquires UniversePassportConfig {
        let addr = signer::address_of(deployer);
        assert!(addr==@kepler, ENOT_DEPLOYER);
        if (exists<UniversePassportConfig>(addr)) {
            let storage =  borrow_global_mut<UniversePassportConfig>(addr);
            storage.collection_name = collection_name;
            storage.public_price = public_price;
            storage.promotion_price = promotion_price;
            storage.total_supply = total_supply;
        }else {
            move_to(deployer, UniversePassportConfig{
                collection_name,
                public_price,
                promotion_price,
                total_supply,
                sale_amount:0
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

    fun number_mul(number: &mut u64, value: u64){
        *number = *number * value;
    }

    fun number_div(number: &mut u64, value: u64){
        *number = *number / value;
    }

    fun number_sub(number: &mut u64, value: u64){
        *number = *number - value;
    }

    fun number_set(number: &mut u64, value: u64){
        *number = value;
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
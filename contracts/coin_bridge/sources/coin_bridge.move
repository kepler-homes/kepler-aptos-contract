module kepler::coin_bridge_V0020{
    use std::vector;
    use std::signer;
    use aptos_std::signature;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::managed_coin;
    use aptos_framework::timestamp;
    use kepler::number;

    const ENOT_DEPLOYER             :u64 = 0x1001;
    const EALREADY_INITIALIZED      :u64 = 0x1002;
    const ENOT_INITIALIZED          :u64 = 0x1003;
    const EINVALID_PUBKEY           :u64 = 0x1004;
    const EINVALID_SIGNATURE        :u64 = 0x1005;
    const EINSUFFICIENT_BALANCE     :u64 = 0x1006;
    const EINVALID_AMOUNT           :u64 = 0x1007;
    const EEXPIRED                  :u64 = 0x1008;
    const EDUPLICATE_ORDER_ID       :u64 = 0x1009;

    struct ResourceAccount has key {
        signer_capability: account::SignerCapability
    }

    struct Config has key,store{
        signature_pubkey: vector<u8>,
        fee_rate: u64,
    }

    struct UserStorage<phantom CoinType> has key,store{
        applies: vector<Apply>,
        claims: vector<Claim>,
    }

    struct Order has store {
        order_id: vector<u8>,
        amount: vector<u8>,
    }

    struct Apply has store {
        order_id: vector<u8>,
        to_chain_id: vector<u8>,
        to_token: vector<u8>,
        receipient: vector<u8>,
        amount: vector<u8>,
    }

    struct Claim has store {
        order_id: vector<u8>,
        from_chain_id: vector<u8>,
        from_token: vector<u8>,
        applicant: vector<u8>,
        amount: vector<u8>,
    }

   
    public entry fun initialize(deployer:&signer, signature_pubkey: vector<u8>,fee_rate: u64,resource_signer_seed:vector<u8>) {
        let addr = signer::address_of(deployer);
        assert!(addr==@kepler, ENOT_DEPLOYER);
        assert!(!exists<Config>(addr), EALREADY_INITIALIZED);
        assert!(signature::ed25519_validate_pubkey(signature_pubkey),EINVALID_PUBKEY);
        move_to(deployer, Config{ signature_pubkey, fee_rate });
        create_resource_signer(deployer,resource_signer_seed);
    }

    public entry fun update_signature_pubkey(deployer:&signer, signature_pubkey: vector<u8>) acquires Config{
        let addr = signer::address_of(deployer);
        assert!(addr==@kepler, ENOT_DEPLOYER);
        assert!(exists<Config>(addr), ENOT_INITIALIZED);
        assert!(signature::ed25519_validate_pubkey(signature_pubkey),EINVALID_PUBKEY);
        let config = borrow_global_mut<Config>(@kepler);
        let key = &mut config.signature_pubkey;
        *key=signature_pubkey;
    }

    public entry fun update_fee_rate(deployer:&signer, fee_rate: u64) acquires Config{
        let addr = signer::address_of(deployer);
        assert!(addr==@kepler, ENOT_DEPLOYER);
        assert!(exists<Config>(addr), ENOT_INITIALIZED);
        let config = borrow_global_mut<Config>(@kepler);
        number::set(&mut config.fee_rate,fee_rate);
    }

     public entry fun register_coin<CoinType>(deployer:&signer,mint_amount: u64) acquires ResourceAccount{
        let addr = signer::address_of(deployer);
        assert!(addr==@kepler, ENOT_DEPLOYER);
        assert!(exists<Config>(addr), ENOT_INITIALIZED);
        let resource_signer= get_resource_signer();
        let resource_addr = signer::address_of(&resource_signer);
        if(!coin::is_account_registered<CoinType>(resource_addr)){
             managed_coin::register<CoinType>(&resource_signer);
        };
        
        if(mint_amount > 0){
            managed_coin::mint<CoinType>(deployer,resource_addr,mint_amount);
        };
     }

    

  public entry fun apply<CoinType>(
        user:&signer,
        order_id: vector<u8>,
        to_chain_id: vector<u8>,
        to_token: vector<u8>,
        receipient: vector<u8>,
        amount: vector<u8>,
        deadline: vector<u8>,
        signature: vector<u8>
    ) acquires UserStorage,Config,ResourceAccount{
        assert!(vector_to_u64(&deadline) > timestamp::now_seconds(), EEXPIRED);
        assert!(exists<Config>(@kepler), ENOT_INITIALIZED);
        let config = borrow_global<Config>(@kepler);

        //verify signature
        let message = vector::empty<u8>();
        vector::append(&mut message, order_id);
        vector::append(&mut message, to_chain_id);
        vector::append(&mut message, to_token);
        vector::append(&mut message, receipient);
        vector::append(&mut message, amount);
        vector::append(&mut message, deadline);
        assert!(signature::ed25519_verify(signature,config.signature_pubkey,message),EINVALID_SIGNATURE);

        let user_addr = signer::address_of(user);

        //create user storage if not exists
        if(!exists<UserStorage<CoinType>>(user_addr)){
            move_to(user,UserStorage<CoinType>{applies: vector::empty(), claims:  vector::empty()});
        };

        //update user storage
        let storage = borrow_global_mut<UserStorage<CoinType>>(user_addr);
       
        //check order_id
        let length = vector::length(&storage.applies);
        let i = 0;
        while(i < length){
            assert!(vector::borrow(&storage.applies,i).order_id != order_id, EDUPLICATE_ORDER_ID);
            i = i + 1;
        };

       vector::push_back(&mut storage.applies, Apply{order_id,to_chain_id,to_token,receipient,amount});

        //transfer coin from user to resource_addr
        let resource_signer = get_resource_signer();
        let resource_addr = signer::address_of(&resource_signer);
        let transfer_amount = vector_to_u64(&amount);
        assert!(coin::balance<CoinType>(user_addr) >= transfer_amount, EINSUFFICIENT_BALANCE);
        coin::transfer<CoinType>(user, resource_addr, transfer_amount);
 }


     public entry fun claim<CoinType>(
        user:&signer,
        order_id: vector<u8>,
        from_chain_id: vector<u8>,
        from_token: vector<u8>,
        applicant: vector<u8>,
        amount: vector<u8>,
        deadline: vector<u8>,
        signature: vector<u8>
    ) acquires UserStorage,Config,ResourceAccount{
        assert!(vector_to_u64(&deadline) > timestamp::now_seconds(), EEXPIRED);
        assert!(exists<Config>(@kepler), ENOT_INITIALIZED);
        let config = borrow_global<Config>(@kepler);

        //verify signature
        let message = vector::empty<u8>();
        vector::append(&mut message, order_id);
        vector::append(&mut message, from_chain_id);
        vector::append(&mut message, from_token);
        vector::append(&mut message, applicant);
        vector::append(&mut message, amount);
        vector::append(&mut message, deadline);
        assert!(signature::ed25519_verify(signature,config.signature_pubkey,message),EINVALID_SIGNATURE);

        let user_addr = signer::address_of(user);

        //create user storage if not exists
        if(!exists<UserStorage<CoinType>>(user_addr)){
            move_to(user,UserStorage<CoinType>{applies: vector::empty(), claims:  vector::empty()});
        };
        //update user storage
        let storage = borrow_global_mut<UserStorage<CoinType>>(user_addr);

        //check order_id
        let length = vector::length(&storage.claims);
        let i = 0;
        while(i < length){
            assert!(vector::borrow(&storage.claims,i).order_id != order_id, EDUPLICATE_ORDER_ID);
            i = i + 1;
        };

        let resource_signer = get_resource_signer();
        let resource_addr = signer::address_of(&resource_signer);

        //transfer coin from user to resource_addr
        let transfer_amount = vector_to_u64(&amount);
        assert!(coin::balance<CoinType>(resource_addr) >= transfer_amount, EINSUFFICIENT_BALANCE);
        if(!coin::is_account_registered<CoinType>(user_addr)){
             managed_coin::register<CoinType>(user);
        };
        coin::transfer<CoinType>(&resource_signer, user_addr, transfer_amount);

        vector::push_back(&mut storage.claims, Claim{order_id,from_chain_id,from_token,applicant,amount});
 }


    fun get_resource_signer(): signer acquires ResourceAccount{
        let r = borrow_global<ResourceAccount>(@kepler);
        account::create_signer_with_capability(&r.signer_capability)
    }

    fun create_resource_signer(deployer:&signer,seed: vector<u8>):signer {
        let (resource_signer, signer_capability) = account::create_resource_account(deployer, seed);
        move_to(deployer, ResourceAccount {signer_capability});
        resource_signer
    } 

    fun vector_to_u64(v: &vector<u8>): u64{
        let length=vector::length(v);
        assert!(length==8,EINVALID_AMOUNT);
        let value :u64 = 0;
        let i = 0;
        while(i < length){
            value = value+(*vector::borrow(v,i) as u64)<<(((length - i - 1) * 8) as u8);
            i = i + 1;
        };
        value
    }
}
module kepler::passport_stake_005 {
    use std::vector;
    use std::signer;
    use std::string;
    use std::bcs;
    use std::hash;

    use aptos_std::type_info;
    use aptos_std::table;

    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::block;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::managed_coin;
    use aptos_framework::timestamp;

    use aptos_token::token;

    const INDEX_NOT_FOUND :u64 = 0xffffffffff;

    const ENOT_DEPLOYER                 :u64 = 0x1001;
    const EINITIALIZED                  :u64 = 0x1002;
    const ENOT_INITIALIZED              :u64 = 0x1002;
    const EUNSUPPORTED_COLLECTION       :u64 = 0x1004;
    const EEMPTY_STAKE                  :u64 = 0x1005;
    const EDUPLICATE_STAKE              :u64 = 0x1006;
    const ETOKEN_NOT_FOUND              :u64 = 0x1007;
    const EUNSTAKE_BEFORE_LOCKUP_TIME   :u64 = 0x1008;
    const EUSER_STORE_NOT_FOUND         :u64 = 0x1009;
    const ETOKEN_ID_NOT_IN_COLLECTION   :u64 = 0x100A;
    const EESCROW_NOT_FOUND             :u64 = 0x100B;
    const ECOIN_TYPE_NOT_SUPPORTED      :u64 = 0x100C;


    /// TokenEscrow holds the tokens that cannot be withdrawn or transferred
    struct TokenEscrow has store, drop,copy{
        token_id: token::TokenId,
        token_uri: string::String,
        lock_units: u64,
        stake_time: u64,
    }

    //lucky reward
    struct LuckyReward has store{
        draw_sequence: u64,
        token_id: token::TokenId,
        reward: u64,
        draw_time: u64,
    }

    struct UserStore  has key{
        pending_reward: u64,
        escrows: vector<TokenEscrow>,
        tokens: table::Table<token::TokenId, token::Token>,
        rewards: vector<LuckyReward>
    }

    //stake event
    struct StakeEvent has drop, store {
        token_id: token::TokenId,
         //lock units
        lock_units: u64,
    }

    //unstake event
    struct UnstakeEvent has drop, store {
        token_id: token::TokenId,
     }

    //draw event
    struct DrawEvent has drop, store {
        //draw sequence
        draw_sequence : u64,
        //lucky nft names
        lucky_token_ids: vector<token::TokenId>,
    }

    struct CollectionId has copy, drop{
        creator: address,
        name: vector<u8>,
    }

    struct CollectionData has store{
        next_draw_sequence: u64,
        reward_token: type_info::TypeInfo,
        total_reward_per_drawing: u64,
        min_stake_time: u64,
        lock_unit_span: u64,
        escrows: vector<TokenEscrow>,
        token_ids: table::Table<token::TokenId, address>,
        //draw_sequence
        draws: vector<Draw>,
    }

    struct Draw has store {
        draw_time: u64,
        draw_sequence: u64,
        lucky_token_ids: vector<token::TokenId>,
    }

    struct ModuleStore has key {
        resource_signer_capability: account::SignerCapability,
        collections : table::Table<CollectionId, CollectionData>,
        stake_events: EventHandle<StakeEvent>,
        unstake_events: EventHandle<UnstakeEvent>,
        draw_events: EventHandle<DrawEvent>,
    }

    public entry fun initialize<CoinType>(deployer: &signer,seed: vector<u8>) {
        let addr = signer::address_of(deployer);
        assert!(addr==@kepler, ENOT_DEPLOYER);
        assert!(!exists<ModuleStore>(addr), EINITIALIZED);
        let (resource_signer, signer_capability) = account::create_resource_account(deployer, seed);
        move_to(deployer, ModuleStore{
            resource_signer_capability: signer_capability,
            collections: table::new(),
            stake_events: account::new_event_handle<StakeEvent>(deployer),
            unstake_events: account::new_event_handle<UnstakeEvent>(deployer),
            draw_events: account::new_event_handle<DrawEvent>(deployer),
        });
        managed_coin::register<CoinType>(&resource_signer);
    }

    public entry fun add_collection<CoinType>(
        sender: &signer,
        collection_creator: address,
        collection_name: vector<u8>,
        total_reward_per_drawing: u64,
        min_stake_time: u64,
        lock_unit_span: u64,
    ) acquires ModuleStore {
        assert!(signer::address_of(sender) == @kepler, ENOT_DEPLOYER);
        assert!(exists<ModuleStore>(@kepler), ENOT_INITIALIZED);
        let store = borrow_global_mut<ModuleStore>(@kepler);
        let collection_id = create_collection_id(collection_creator,collection_name);
        let collection = CollectionData{
            next_draw_sequence: 1,
            reward_token: type_info::type_of<CoinType>(),
            total_reward_per_drawing,
            min_stake_time,
            lock_unit_span,
            escrows: vector::empty(),
            token_ids: table::new(),
            draws: vector::empty(),
        };
        table::add(&mut store.collections, collection_id, collection);
    } 

    fun create_collection_id(collection_creator: address, collection_name: vector<u8>):CollectionId {
        CollectionId{creator:collection_creator,name:collection_name}
    }

    public entry fun stake(
        sender: &signer,
        collection_creator: address,
        collection_name: vector<u8>,
        token_name: vector<u8>,
        property_version: u64,
        lock_units: u64,
    ) acquires ModuleStore,UserStore  {
        let addr = signer::address_of(sender);
        assert!(exists<ModuleStore>(@kepler), ENOT_INITIALIZED);
        let module_store = borrow_global_mut<ModuleStore>(@kepler);
        let collection_id = create_collection_id(collection_creator,collection_name);
        assert!(table::contains(&module_store.collections,collection_id),EUNSUPPORTED_COLLECTION);
        let collection = table::borrow_mut(&mut module_store.collections,collection_id);
        let collection_name =string::utf8(collection_name);
        let token_name = string::utf8(token_name);
        let token_id = token::create_token_id_raw(
            collection_creator,
            collection_name,
            token_name,
            property_version
        );
        assert!(!table::contains(&collection.token_ids,token_id),EDUPLICATE_STAKE);
        table::add(&mut collection.token_ids,token_id,addr);

        initialize_user_store(sender);

        let user_store =  borrow_global_mut<UserStore>(addr);

        deposit_token_to_user_store(user_store,sender,token_id);

        let token_uri = token::get_tokendata_uri(collection_creator,token::create_token_data_id(
            collection_creator, collection_name, token_name
        ));

        let escrow = TokenEscrow {token_id, token_uri,lock_units,stake_time:timestamp::now_seconds()};
        vector::push_back(&mut collection.escrows,escrow);
        vector::push_back(&mut user_store.escrows,escrow);

        let event = StakeEvent { token_id, lock_units };
        event::emit_event<StakeEvent>(&mut module_store.stake_events,event)
    }

    public entry fun unstake(
        sender: &signer,
        collection_creator: address,
        collection_name: vector<u8>,
        token_name: vector<u8>,
        property_version: u64,
    ) acquires ModuleStore,UserStore  {
        let addr = signer::address_of(sender);
        assert!(exists<ModuleStore>(@kepler), ENOT_INITIALIZED);
        assert!(exists<UserStore>(addr), EUSER_STORE_NOT_FOUND);
        let module_store = borrow_global_mut<ModuleStore>(@kepler);
 
        let collection_id = create_collection_id(collection_creator,collection_name);
        assert!(table::contains(&module_store.collections,collection_id),EUNSUPPORTED_COLLECTION);
        let collection = table::borrow_mut(&mut module_store.collections,collection_id);

        let token_id = token::create_token_id_raw(
            collection_creator,
            string::utf8(collection_name),
            string::utf8(token_name),
            property_version
        );

        //make sure token is staked
        assert!(table::contains(&collection.token_ids, token_id),ETOKEN_ID_NOT_IN_COLLECTION);
        table::remove(&mut collection.token_ids,token_id);

        let user_store = borrow_global_mut<UserStore>(addr);

        let index = index_of_escrow(&user_store.escrows,token_id);
        assert!(index!=INDEX_NOT_FOUND, EESCROW_NOT_FOUND);

        let escrow = vector::borrow(&user_store.escrows,index);

        assert!(escrow.stake_time+escrow.lock_units*collection.lock_unit_span<=timestamp::now_seconds(), EUNSTAKE_BEFORE_LOCKUP_TIME);

        token::deposit_token(sender,withdraw_token_from_user_store(user_store,token_id));

        vector::swap_remove(&mut user_store.escrows,index);

        let index = index_of_escrow(&collection.escrows,token_id);
        assert!(index!=INDEX_NOT_FOUND,EESCROW_NOT_FOUND);
        vector::swap_remove(&mut collection.escrows,index);

        event::emit_event<UnstakeEvent>(&mut module_store.unstake_events,UnstakeEvent{token_id})
    }

    public entry fun claim<CoinType>(sender: &signer,collection_creator: address, collection_name: vector<u8>) 
        acquires ModuleStore,UserStore
    {
        let addr = signer::address_of(sender);
        assert!(exists<UserStore>(addr), EUSER_STORE_NOT_FOUND);
        let user_store = borrow_global_mut<UserStore>(addr);
        let module_store = borrow_global_mut<ModuleStore>(@kepler);
        let collection_id = create_collection_id(collection_creator,collection_name);
        assert!(table::contains(&module_store.collections,collection_id),EUNSUPPORTED_COLLECTION);
        let collection = table::borrow_mut(&mut module_store.collections,collection_id);
        assert!(collection.reward_token==type_info::type_of<CoinType>(),ECOIN_TYPE_NOT_SUPPORTED);
        if(user_store.pending_reward>0) {
            let resource_signer = account::create_signer_with_capability(&module_store.resource_signer_capability);
            transfer_coin_to_user<CoinType>(&resource_signer,sender,user_store.pending_reward);
            number_set(&mut user_store.pending_reward,0);
        }
    }

    public entry fun draw(
        sender: &signer,
        collection_creator: address,
        collection_name: vector<u8>
    ) acquires ModuleStore,UserStore  {
        let addr = signer::address_of(sender);
        assert!(addr == @kepler, ENOT_DEPLOYER);
        assert!(exists<ModuleStore>(@kepler), ENOT_INITIALIZED);
        let module_store = borrow_global_mut<ModuleStore>(@kepler);

        let collection_id = create_collection_id(collection_creator,collection_name);
        assert!(table::contains(&module_store.collections,collection_id),EUNSUPPORTED_COLLECTION);
        let collection = table::borrow_mut(&mut module_store.collections,collection_id);

        let escrows = &collection.escrows;
        let length = vector::length(escrows);
        assert!(length > 0, EEMPTY_STAKE);
        let lock_units_vector: vector<u64> = extract_lock_units(escrows,collection.min_stake_time);
        let lucky_count = if(length > 10) {length/10} else {1};
        let reward_by_lucky = collection.total_reward_per_drawing/lucky_count;
        let lucky_token_ids :vector<token::TokenId> =  vector::empty();
        let i = 0;
        let draw_sequence = collection.next_draw_sequence;
        let draw_time = timestamp::now_seconds();
        while(i < lucky_count) {
            let index = draw_one_index(&lock_units_vector,length,random_number(addr,i));
            number_set(vector::borrow_mut(&mut lock_units_vector,index),0);
            let escrow = vector::borrow(escrows,index);
            vector::push_back(&mut lucky_token_ids,escrow.token_id);
            let lucky_user = table::borrow(&collection.token_ids,escrow.token_id);
            let user_store = borrow_global_mut<UserStore>(*lucky_user);
            number_add(&mut user_store.pending_reward,reward_by_lucky);
            vector::push_back(&mut user_store.rewards, LuckyReward{
                draw_sequence ,
                token_id: escrow.token_id,
                reward: reward_by_lucky,
                draw_time,
            });
            i = i + 1;
        };


        vector::push_back(&mut collection.draws, Draw {
            draw_time,draw_sequence,lucky_token_ids,
        });

        number_add(&mut collection.next_draw_sequence,1);

        let event = DrawEvent { draw_sequence, lucky_token_ids };
        event::emit_event<DrawEvent>(&mut module_store.draw_events,event)
    }

    fun extract_lock_units(escrows: &vector<TokenEscrow>,min_stake_time: u64): vector<u64> {
        let lock_units_vector: vector<u64> = vector::empty();
        let (i, length,now) = (0, vector::length(escrows),timestamp::now_seconds());
        while(i < length) {
            let escrow = vector::borrow(escrows,i);
            let lock_units = escrow.lock_units;
            if(now - escrow.stake_time < min_stake_time) {
                lock_units = 0;
            };
            vector::push_back(&mut lock_units_vector, lock_units);
            i = i + 1;
        };
        lock_units_vector
    }


    fun draw_one_index(lock_units_vector: &vector<u64>, length: u64, random_number: u64): u64 {
        let (ticket,i,tickets)  = (0,0, vector::empty());
        while(i < length) {
            let item = *vector::borrow(lock_units_vector,i);
            if(item==0){
                vector::push_back(&mut tickets, 0);
            }else {
                ticket = ticket + *vector::borrow(lock_units_vector,i) * 1000;
                vector::push_back(&mut tickets, ticket);
            };
            i = i + 1;
        };

        let (last_ticket,i,random_ticket) = (0,0,random_number % ticket);
        while(i < length) {
            let ticket = *vector::borrow(&tickets,i);
            if( last_ticket < random_ticket && random_ticket <= ticket ){
                return i
            };
            last_ticket = ticket;
            i = i + 1;
        };
        0
    }

    fun transfer_coin_to_user<CoinType>(resource_signer: &signer,user: &signer, amount: u64)  {
        if(amount > 0 ){
            let addr=  signer::address_of(user);
            if(!coin::is_account_registered<CoinType>(addr)){
                managed_coin::register<CoinType>(user);
            };
            coin::transfer<CoinType>(resource_signer, addr,amount);
        }
    }

    fun initialize_user_store(sender: &signer) {
        if(!exists<UserStore>(signer::address_of(sender))){
            move_to(sender,UserStore{
                pending_reward: 0,
                tokens: table::new(),
                escrows: vector::empty(),
                rewards: vector::empty()
            });
        };
    }

    fun deposit_token_to_user_store(user_store: &mut UserStore, user: &signer, token_id: token::TokenId)  {
        let token = token::withdraw_token(user, token_id, 1);
        let tokens = &mut user_store.tokens;
        if (table::contains(tokens, token_id)) {
            let dst = table::borrow_mut(tokens, token_id);
            token::merge(dst, token);
        } else {
            table::add(tokens, token_id, token);
        };
    }

    fun withdraw_token_from_user_store( user_store: &mut UserStore, token_id: token::TokenId): token::Token {
        let tokens = &mut user_store.tokens;
        assert!(table::contains(tokens, token_id), ETOKEN_NOT_FOUND);
        table::remove(tokens, token_id)
    }

    fun index_of_escrow(token_ids: &vector<TokenEscrow>, token_id: token::TokenId): u64 {
        let length = vector::length(token_ids);
        let i = 0 ;
        while(i < length) {
            if(vector::borrow(token_ids,i).token_id == token_id){ return i };
            i = i + 1;
        };
        INDEX_NOT_FOUND
    }
 
    fun random_number(addr: address,seed: u64) : u64{
        let bytes = bcs::to_bytes<address>(&addr);
        vector::append(&mut bytes, bcs::to_bytes<u64>(&seed));
        vector::append(&mut bytes, bcs::to_bytes<u64>(&account::get_sequence_number(addr)));
        vector::append(&mut bytes, bcs::to_bytes<u64>(&timestamp::now_microseconds()));
        vector::append(&mut bytes, bcs::to_bytes<u64>(&block::get_current_block_height()));
        bytes_to_u64(hash::sha3_256(bytes))
    }

    fun bytes_to_u64(bytes: vector<u8>): u64 {
        let value = 0u64;
        let i = 0u64;
        while (i < 8) {
            value = value | ((*vector::borrow(&bytes, i) as u64) << ((8 * (7 - i)) as u8));
            i = i + 1;
        };
        value
    }

    fun number_set(number: &mut u64, value: u64){
        *number = value;
    }

    fun number_add(number: &mut u64, value: u64){
        *number = *number + value;
    }
}
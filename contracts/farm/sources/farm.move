module kepler::farm_003{
    use std::vector;
    use std::string;
    use std::signer;
    //use std::debug;
    //use std::error;
    use aptos_framework::account;
    use aptos_framework::managed_coin;
    use aptos_framework::coin;
    use aptos_std::table;
    use aptos_framework::timestamp;

    const ENOT_DEPLOYER             :u64 = 1001;
    const EALREADY_INITIALIZED      :u64 = 1002;
    const ENOT_INITIALIZED          :u64 = 1003;
    const EALREADY_PAUSED           :u64 = 1004;
    const EINSUFFICIENT_BALANCE     :u64 = 1005;
    const ERESOURCE_NO_EXISTS       :u64 = 1006;
    const EALREADY_REGISTERED       :u64 = 1007;
    const ENOT_REGISTERED           :u64 = 1008;
    const EUSER_STORAGE_NOT_FOUND   :u64 = 1009;
    const EDEPOSIT_ID_NOT_FOUND     :u64 = 1010;
    const ECLAIM_ID_NOT_FOUND       :u64 = 1011;
    const EINVALID_REWARD_COIN      :u64 = 1012;
    const EREWARD_POOL_NOT_FOUND    :u64 = 1013;
    const EDEPOSIT_POOL_NOT_FOUND   :u64 = 1014;
    const ENOTHING_TO_WITHDRAW      :u64 = 1015;
    const EALREADY_UNSTAKED         :u64 = 1016;
    const EWITHDRAW_FINISHED        :u64 = 1017;
    const ESTAKE_POOL_NOT_FOUND     :u64 = 1018;
    const ENOTHING_TO_CLAIM         :u64 = 1019;

    const UNIT: u64 = 100000000;

    struct ResourceAccount has key {
        signer_capability: account::SignerCapability
    }

 
    struct UserStorage has key{
     
        deposits: vector<Deposit>,
 
        claims: vector<Claim>,
    }

 
    struct Deposit has store,drop {
        amount: u64,
        reward_index_mul: u64,
        weighted_amount: u64,
        stake_time: u64,
        lock_units: u64,
        unstake_time: u64,
    }

  
    struct Claim has store ,drop{
        deposit_id: u64,
        amount: u64,
        remaing_amount: u64,
        reward_index_mul: u64,
        lock_time: u64,
        last_withdraw_time: u64,
        withdrawn_count: u64,
        withdraw_finish_time: u64,
    }

 
    struct Pool has key,store,drop,copy {
        pool_weight: u64,
        staking_amount: u64,
        weighted_staking_amount: u64,
        reward_index_mul: u64,
        distributed_rewards: u64,
        total_locked_rewards: u64,
        last_distribute_time: u64,
    }

 
    struct GlobalStorage has key{
        reward_coin_symbol: string::String,
        rewards_per_second: u64,
        locked_reward_withdraw_interval: u64,
        locked_reward_multiplier_mul: u64,
        locked_reward_withdraw_count: u64,
        total_pool_weight: u64,
        lock_unit_duration: u64,
        lock_unit_multiplier_mul: u64,
        max_lock_units: u64,
        total_distributed_rewards: u64,
        stake_coin_symbols: vector<string::String>,
        pools: table::Table<string::String,Pool>
    }

    public entry fun initialize<RewardCoinType>(
        deployer:&signer,
        resource_signer_seed: vector<u8>,
        rewards_per_second: u64,
        lock_unit_duration: u64,
        lock_unit_multiplier_mul: u64,
        max_lock_units: u64,
        locked_reward_withdraw_interval :u64,
        locked_reward_multiplier_mul :u64,
        locked_reward_withdraw_count :u64,
        reward_coin_mint_amount:u64,
    )
    {
        let addr = signer::address_of(deployer);
        assert!(addr==@kepler, ENOT_DEPLOYER);
        assert!(!exists<GlobalStorage>(addr), EALREADY_INITIALIZED);
        move_to(deployer, GlobalStorage{
            reward_coin_symbol: coin::symbol<RewardCoinType>(),
            rewards_per_second,
            lock_unit_duration,
            lock_unit_multiplier_mul,
            max_lock_units,
            locked_reward_withdraw_interval ,
            locked_reward_multiplier_mul,
            locked_reward_withdraw_count,
            total_pool_weight: 0,
            total_distributed_rewards: 0,
            stake_coin_symbols: vector::empty(),
            pools: table::new(),
        });
        let resource_signer = create_resource_signer(deployer,resource_signer_seed);
        managed_coin::register<RewardCoinType>(&resource_signer);

        //mint some reward token
        if(reward_coin_mint_amount>0){
            managed_coin::mint<RewardCoinType>(
                deployer,
                signer::address_of(&resource_signer),
                reward_coin_mint_amount
            );
        };
    }

     public entry fun add_pool<StakeCoinType>(deployer:&signer, pool_weight: u64) acquires GlobalStorage,ResourceAccount {
        let addr = signer::address_of(deployer);
        assert!(addr==@kepler, ENOT_DEPLOYER);
        assert!(exists<GlobalStorage>(addr), ENOT_INITIALIZED);

        let global = borrow_global_mut<GlobalStorage>(addr);
        let coin_symbol = coin::symbol<StakeCoinType>();
        assert!(!table::contains(&global.pools,coin_symbol), EALREADY_REGISTERED);

        number_add(&mut global.total_pool_weight, pool_weight);

        let resource_signer= get_resource_signer();

        if(!coin::is_account_registered<StakeCoinType>(signer::address_of(&resource_signer))){
            managed_coin::register<StakeCoinType>(&resource_signer);
        };

        vector::push_back(&mut global.stake_coin_symbols,coin_symbol);
        table::add(&mut global.pools,coin_symbol,Pool{
            pool_weight,
            staking_amount: 0,
            weighted_staking_amount: 0,
            reward_index_mul: 0,
            distributed_rewards: 0,
            total_locked_rewards: 0,
            last_distribute_time: 0,
        })
    }

    public fun query_pool<CoinType>(): Pool acquires GlobalStorage{
        assert!(exists<GlobalStorage>(@kepler), ENOT_INITIALIZED);
        let global = borrow_global<GlobalStorage>(@kepler);
        *table::borrow(&global.pools,coin::symbol<CoinType>())
    }

    //stake
    public entry fun stake<StakeCoinType>(user:&signer, amount: u64, lock_units: u64) acquires GlobalStorage,ResourceAccount, UserStorage {
        assert!(exists<GlobalStorage>(@kepler), ENOT_INITIALIZED);
        let global = borrow_global_mut<GlobalStorage>(@kepler);
        let symbol = coin::symbol<StakeCoinType>();
        assert!(table::contains(&global.pools,symbol), ENOT_REGISTERED);

        let pool = table::borrow_mut(&mut global.pools,symbol);

        let addr = signer::address_of(user);
        //check user balance
        let user_balance = coin::balance<StakeCoinType>(addr);
        assert!(user_balance >= amount, EINSUFFICIENT_BALANCE);
        let resource_signer= get_resource_signer();
        let resource_addr = signer::address_of(&resource_signer);
        coin::transfer<StakeCoinType>(user, resource_addr, amount);
        if(!exists<UserStorage>(addr)){
            move_to(user,UserStorage{ deposits: vector::empty(), claims:  vector::empty()});
        };
        let user_storage = borrow_global_mut<UserStorage>(addr);

        let lock_unit_multiplier_mul = global.lock_unit_multiplier_mul;
        let weighted_amount = calculate_weighted_amount( amount, lock_units, lock_unit_multiplier_mul );
        let deposit = Deposit {
            amount:amount,
            reward_index_mul: pool.reward_index_mul,
            weighted_amount,
            stake_time: timestamp::now_seconds(),
            lock_units:lock_units,
            unstake_time:0,
        };
        vector::push_back(&mut user_storage.deposits,deposit);
        number_add(&mut pool.weighted_staking_amount,weighted_amount);
        number_add(&mut pool.staking_amount,amount);

        distribute_rewards();
     }

    //unstake
     public entry fun unstake<StakeCoinType>(user:&signer, deposit_id: u64) acquires ResourceAccount, UserStorage, GlobalStorage {

        let addr = signer::address_of(user);
        assert!(exists<GlobalStorage>(@kepler), ENOT_INITIALIZED);
        let global = borrow_global_mut<GlobalStorage>(@kepler);

        assert!(exists<UserStorage>(addr), EUSER_STORAGE_NOT_FOUND);
        let user_storage = borrow_global_mut<UserStorage>(addr);

        let symbol = coin::symbol<StakeCoinType>();
        assert!(table::contains(&global.pools,symbol), ENOT_REGISTERED);
        let pool = table::borrow_mut(&mut global.pools,symbol);


        let resource_signer= get_resource_signer();
        let resource_addr = signer::address_of(&resource_signer);

        assert!(vector::length(&user_storage.deposits)>deposit_id,EDEPOSIT_ID_NOT_FOUND);
        let deposit= vector::borrow_mut(&mut user_storage.deposits,deposit_id);
        assert!(deposit.unstake_time == 0, EALREADY_UNSTAKED);

        number_sub(&mut pool.weighted_staking_amount ,deposit.weighted_amount);
        number_sub(&mut pool.staking_amount, deposit.amount);

        assert!(coin::balance<StakeCoinType>(resource_addr) >= deposit.amount, EINSUFFICIENT_BALANCE);
        coin::transfer<StakeCoinType>(&resource_signer, addr, deposit.amount);

        number_set(&mut deposit.unstake_time,timestamp::now_seconds());

        distribute_rewards();
     }

    //cliam
    public entry fun claim<RewardCoinType,StakeCoinType>(user:&signer, deposit_id: u64) acquires  UserStorage, GlobalStorage {
        distribute_rewards();
        let addr = signer::address_of(user);
        assert!(exists<GlobalStorage>(@kepler), ENOT_INITIALIZED);
        let global = borrow_global_mut<GlobalStorage>(@kepler);

        assert!(exists<UserStorage>(addr), EUSER_STORAGE_NOT_FOUND);
        let user_storage = borrow_global_mut<UserStorage>(addr);

        let stake_coin_symbol = coin::symbol<StakeCoinType>();
        let reward_amounts=0;
        let weighted_amount=0;
        if(true){
            assert!(table::contains(&global.pools,stake_coin_symbol),ESTAKE_POOL_NOT_FOUND);
            let deposit_pool = table::borrow_mut(&mut global.pools,stake_coin_symbol);

            assert!(vector::length(&user_storage.deposits)> deposit_id,EDEPOSIT_ID_NOT_FOUND);

            let deposit = vector::borrow_mut(&mut user_storage.deposits,deposit_id);
            assert!(deposit.unstake_time==0,EALREADY_UNSTAKED);

            reward_amounts = calculate_rewards(deposit, deposit_pool.reward_index_mul);
            if(reward_amounts>0){
                number_add(&mut deposit_pool.total_locked_rewards,reward_amounts);
                number_set(&mut deposit.reward_index_mul,deposit_pool.reward_index_mul);
                weighted_amount = calculate_weighted_claim_amount(reward_amounts,global.locked_reward_multiplier_mul);
            };
        };

        assert!(reward_amounts>0,ENOTHING_TO_CLAIM);
        let reward_coin_symbol = coin::symbol<RewardCoinType>();
        assert!(table::contains(&global.pools,reward_coin_symbol), ENOT_REGISTERED);
        let reward_pool = table::borrow_mut(&mut global.pools,reward_coin_symbol);
        number_add(&mut reward_pool.staking_amount,reward_amounts);
        number_add(&mut reward_pool.weighted_staking_amount,weighted_amount);

        let claim = new_cliam(deposit_id,reward_amounts,reward_pool.reward_index_mul);
        vector::push_back(&mut user_storage.claims,claim);
    }

    //withdraw
    public entry fun withdraw<RewardCoinType,StakeCoinType>(user:&signer, claim_id: u64) acquires  UserStorage, GlobalStorage,ResourceAccount {
        distribute_rewards();

        let addr = signer::address_of(user);
        assert!(exists<GlobalStorage>(@kepler), ENOT_INITIALIZED);
        let global = borrow_global_mut<GlobalStorage>(@kepler);

        assert!(global.reward_coin_symbol==coin::symbol<RewardCoinType>(),EINVALID_REWARD_COIN);

        assert!(exists<UserStorage>(addr), EUSER_STORAGE_NOT_FOUND);
        let user_storage = borrow_global_mut<UserStorage>(addr);

        assert!(vector::length(&user_storage.claims)>claim_id,ECLAIM_ID_NOT_FOUND);

        let claim = vector::borrow_mut(&mut user_storage.claims,claim_id);
        assert!(claim.withdraw_finish_time==0,EWITHDRAW_FINISHED);

        let max_withdraw_count = global.locked_reward_withdraw_count;
        let multiplier_mul = global.locked_reward_multiplier_mul;
        let withdraw_interval = global.locked_reward_withdraw_interval;

        assert!(table::contains(&global.pools,global.reward_coin_symbol),EREWARD_POOL_NOT_FOUND);

        let withdraw_amount=0;
        let now = timestamp::now_seconds();
        let expect_withdrawn_count = math_min((now-claim.lock_time)/withdraw_interval,max_withdraw_count);
        assert!(expect_withdrawn_count > claim.withdrawn_count, ENOTHING_TO_WITHDRAW);
        let withdraw_count = expect_withdrawn_count - claim.withdrawn_count;
        let withdraw_amount_per = claim.amount / max_withdraw_count ;

        let weighted_withdraw_amount = calculate_weighted_claim_amount( withdraw_amount_per, multiplier_mul);
        
        if(true){//to avoid borrow_mut twice;
            let resource_signer= get_resource_signer();
            let resource_addr = signer::address_of(&resource_signer);
            let reward_pool = table::borrow_mut(&mut global.pools, global.reward_coin_symbol);
            let reward_amount = calcuate_rewards_amount(
                withdraw_amount_per + weighted_withdraw_amount,
                reward_pool.reward_index_mul,
                claim.reward_index_mul
            );

            withdraw_amount = withdraw_amount_per * withdraw_count ;
            let weighted_withdraw_amount = weighted_withdraw_amount * withdraw_count;
            let reward_amount = reward_amount * withdraw_count;

            number_sub(&mut reward_pool.staking_amount,withdraw_amount);
            number_sub(&mut reward_pool.weighted_staking_amount,weighted_withdraw_amount);
            number_add(&mut claim.withdrawn_count,1);
            number_set(&mut  claim.last_withdraw_time,now);
            number_sub(&mut claim.remaing_amount,withdraw_amount);
            number_set(&mut claim.reward_index_mul,reward_pool.reward_index_mul);
            if(claim.withdrawn_count >= max_withdraw_count){
                number_set(&mut claim.withdraw_finish_time,now);
            };

            let transfer_amount = reward_amount + withdraw_amount;
            assert!(coin::balance<RewardCoinType>(resource_addr) >= transfer_amount, EINSUFFICIENT_BALANCE);
            coin::transfer<RewardCoinType>(&resource_signer, addr, transfer_amount);
        };

        if(withdraw_amount>0){
            let symbol = coin::symbol<StakeCoinType>();
            assert!(table::contains(&global.pools,symbol),EDEPOSIT_POOL_NOT_FOUND);
            let deposit_pool = table::borrow_mut(&mut global.pools, symbol);
            number_sub(&mut deposit_pool.total_locked_rewards,withdraw_amount);
        };

     }

    fun calcuate_rewards_amount( amount: u64, pool_index_mul: u64, claim_index_mul: u64 ) : u64 {
        let index_mul =  pool_index_mul - claim_index_mul ;
        amount  * index_mul /  UNIT
    }

    public entry fun emergency_withdraw<CoinType>(deployer:&signer, amount: u64) acquires ResourceAccount{
        assert!(signer::address_of(deployer)==@kepler, ENOT_DEPLOYER);
        let resource_signer= get_resource_signer();
        let resource_addr = signer::address_of(&resource_signer);
        assert!(coin::balance<CoinType>(resource_addr) >= amount, EINSUFFICIENT_BALANCE);
        let addr = signer::address_of(deployer);
        coin::transfer<CoinType>(&resource_signer, addr, amount);
    }

    fun calculate_weighted_amount( amount: u64, lock_units: u64, lock_unit_multiplier_mul: u64, ) : u64 {
        let multiplier =  (lock_units as u64) * lock_unit_multiplier_mul;
        amount * multiplier /UNIT
    }

    fun get_resource_signer(): signer acquires ResourceAccount{
        assert!(exists<ResourceAccount>(@kepler), ERESOURCE_NO_EXISTS);
        let r = borrow_global<ResourceAccount>(@kepler);
        account::create_signer_with_capability(&r.signer_capability)
    }

    fun create_resource_signer(deployer:&signer,seed: vector<u8>):signer {
        let (resource_signer, signer_capability) = account::create_resource_account(deployer, seed);
        move_to(deployer, ResourceAccount {signer_capability});
        resource_signer
    }

    //distribute reward coins to each pools
    fun distribute_rewards () acquires GlobalStorage{
        assert!(exists<GlobalStorage>(@kepler), ENOT_INITIALIZED);
        let global = borrow_global_mut<GlobalStorage>(@kepler);
        let rewards_per_second = global.rewards_per_second ;
        let total_pool_weight = global.total_pool_weight ;
        if (global.total_pool_weight > 0) {
            let pool_count = vector::length(&global.stake_coin_symbols);
            let i = 0;
            let all_rewards = 0;
            while (i < pool_count ){
                let symbol = vector::borrow(&global.stake_coin_symbols,i);
                let pool = table::borrow_mut(&mut global.pools, *symbol);
                let (rewards, index_mul) = calculate_distribute(pool, rewards_per_second, total_pool_weight);
                if (rewards > 0) {
                    number_add(&mut pool.reward_index_mul ,index_mul);
                    number_add(&mut pool.distributed_rewards,rewards);
                    all_rewards = all_rewards + rewards;
                };
                number_set(&mut pool.last_distribute_time,timestamp::now_seconds());
                i=i+1;
            };
            number_set(&mut global.total_distributed_rewards,all_rewards);
        };
     }

    fun calculate_distribute(pool: &mut Pool, rewards_per_second: u64, total_pool_weight: u64) : (u64, u64) {
        let now = timestamp::now_seconds();
        let pool_weight = pool.pool_weight;
        let last_distribute_time = pool.last_distribute_time;
        if(last_distribute_time > 0 && now > last_distribute_time) {
            let passed_time =  now - last_distribute_time ;
            let rewards = passed_time * rewards_per_second * pool_weight / total_pool_weight;
            if (rewards > 0) {
                 let amount =  pool.staking_amount + pool.weighted_staking_amount ;
                 let index_mul =  rewards *  UNIT / amount ;
                 return (rewards,index_mul)
            };
        };
        (0, 0)
    }

    fun calculate_weighted_claim_amount(amount: u64, multiplier: u64) : u64 {
         multiplier* amount / UNIT
    }

    fun new_cliam( deposit_id:u64,amount: u64, reward_index_mul: u64,) : Claim {
         let now = timestamp::now_seconds();
         Claim {
            deposit_id,
            amount,
            remaing_amount: amount,
            reward_index_mul,
            lock_time: now,
            last_withdraw_time: 0,
            withdrawn_count: 0,
            withdraw_finish_time: 0,
        }
    }

    fun calculate_rewards(deposit: &Deposit, reward_index_mul: u64) : u64 {
        let pool_index = reward_index_mul  ;
        let depoist_index = deposit.reward_index_mul  ;
        let diff_index = pool_index - depoist_index;
        if (diff_index > 0) {
            let amount = deposit.amount + deposit.weighted_amount;
            return diff_index * amount / UNIT
        } else {
            0
        }
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

    fun math_min(a: u64, b: u64): u64 {
        if (a < b) a else b
    }
}
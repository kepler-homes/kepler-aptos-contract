// buy token1 with apt
// claim token2 with token1
// burn token1
module kepler::presale_002 {
    use std::vector;
    use std::signer;
    use std::math64;
    use aptos_std::type_info;
    use aptos_framework::account;
    use aptos_framework::managed_coin;
    use aptos_framework::coin;
    use aptos_framework::timestamp;

    struct BuyRecord has store{
        payment: u64,
        token1_amount : u64,
        referrer: address,
        referrer_reward: u64,
        buy_time: u64,
        lock_periods: u64,
    }

    struct ClaimRecord has store {
        index :u64,
        amount :u64,
        claim_time: u64,
    }

    struct UserStorage has key{
        buy_records:  vector<BuyRecord>,
        claim_records:  vector<ClaimRecord>,
        claimed_count: u64,
        total_payments: u64,
        max_claim_count: u64,
    }

    struct ModuleStorage has key{
        signer_capability: account::SignerCapability,
        base_price: u64,
        claim_start_time: u64,
        commission_rate: u64,
        currency: type_info::TypeInfo,
        token1: type_info::TypeInfo,
        token2: type_info::TypeInfo,
        fee_wallet: address,
        sale_amount_per_round: u64,
        claim_interval: u64,
        min_buy_amount: u64,
        max_buy_amount: u64,
        refeerer_min_buy_amount: u64,
        round_prices: vector<u64>,
        saled_amount: u64,
    }

    const EMPTY_ADDRESS :address = @0x0000000000000000000000000000000000000000000000000000000000000000;

    const ENOT_DEPLOYER                         :u64 = 0x1001;
    const EALREADY_INITIALIZED                  :u64 = 0x1002;
    const ENOT_INITIALIZED                      :u64 = 0x1003;
    const EBUY_FORBIDDEN_AFTER_CLAIM_STARTED    :u64 = 0x1004;
    const EINVALID_REFERRER                     :u64 = 0x1005;
    const EINSUFFICIENT_BUY_AMOUNT              :u64 = 0x1006;
    const EEXCEED_BUY_AMOUNT                    :u64 = 0x1007;
    const EINVALID_LOCK_MONTH                   :u64 = 0x1008;
    const EINVLAID_CURRENCY                     :u64 = 0x1009;
    const EINVLAID_TOKEN1                       :u64 = 0x100A;
    const EINVLAID_TOKEN2                       :u64 = 0x100B;
    const EINSUFFICIENT_TOKEN1_BALANCE          :u64 = 0x100C;
    const EINSUFFICIENT_TOKEN2_BALANCE          :u64 = 0x100D;
    const ENOT_BUYER                            :u64 = 0x100E;

    public entry fun initialize<Currency,Token1,Token2>(
        deployer:&signer,
        base_price: u64,
        claim_start_time: u64,
        commission_rate: u64,
        fee_wallet: address,
        sale_amount_per_round: u64,
        claim_interval: u64,
        min_buy_amount: u64,
        max_buy_amount: u64,
        refeerer_min_buy_amount: u64,
        seed: vector<u8>,
    ) {
        let addr = signer::address_of(deployer);
        assert!(addr==@kepler, ENOT_DEPLOYER);
        assert!(!exists<ModuleStorage>(addr), EALREADY_INITIALIZED);
        let (resource_signer, signer_capability) = account::create_resource_account(deployer, seed);
        managed_coin::register<Token1>(&resource_signer);
        managed_coin::register<Token2>(&resource_signer);
        move_to(deployer, ModuleStorage{
            base_price,
            claim_start_time,
            commission_rate,
            currency: type_info::type_of<Currency>(),
            token1: type_info::type_of<Token1>(),
            token2: type_info::type_of<Token2>(),
            fee_wallet,
            sale_amount_per_round,
            claim_interval,
            min_buy_amount,
            max_buy_amount,
            refeerer_min_buy_amount,
            round_prices: calculate_round_prices(base_price),
            saled_amount: 0,
            signer_capability,
        });
    }

     public entry fun update_config<Currency,Token1,Token2>(
        deployer:&signer,
        base_price: u64,
        claim_start_time: u64,
        commission_rate: u64,
        fee_wallet: address,
        sale_amount_per_round: u64,
        claim_interval: u64,
        min_buy_amount: u64,
        max_buy_amount: u64,
        refeerer_min_buy_amount: u64,
    ) acquires ModuleStorage {
        let addr = signer::address_of(deployer);
        assert!(addr==@kepler, ENOT_DEPLOYER);
        assert!(exists<ModuleStorage>(addr), ENOT_INITIALIZED);
        let global = borrow_global_mut<ModuleStorage>(addr);
        global.base_price=base_price;
        global.claim_start_time=claim_start_time;
        global.commission_rate=commission_rate;
        global.currency= type_info::type_of<Currency>();
        global.token1= type_info::type_of<Token1>();
        global.token2= type_info::type_of<Token2>();
        global.fee_wallet=fee_wallet;
        global.sale_amount_per_round=sale_amount_per_round;
        global.claim_interval=claim_interval;
        global.min_buy_amount=min_buy_amount;
        global.max_buy_amount=max_buy_amount;
        global.refeerer_min_buy_amount= refeerer_min_buy_amount;
        global.round_prices= calculate_round_prices(base_price);

    }

    public entry fun buy_token1<Currency,Token1>(
        buyer:&signer,
        payment: u64,
        lock_periods:u64,
        referrer: address
    ) acquires ModuleStorage, UserStorage {
        assert!(exists<ModuleStorage>(@kepler), ENOT_INITIALIZED);
        let global = borrow_global_mut<ModuleStorage>(@kepler);
        let now = timestamp::now_seconds();
        assert!(now < global.claim_start_time,EBUY_FORBIDDEN_AFTER_CLAIM_STARTED);
        let buyer_addr = signer::address_of(buyer);
        assert!(buyer_addr != referrer,EINVALID_REFERRER );
        assert!(payment >= global.min_buy_amount, EINSUFFICIENT_BUY_AMOUNT);
        assert!(payment <= global.max_buy_amount, EEXCEED_BUY_AMOUNT);
        assert!(lock_periods >= 6 && lock_periods <= 60, EINVALID_LOCK_MONTH);
        assert!(type_info::type_of<Currency>() == global.currency, EINVLAID_CURRENCY);
        assert!(type_info::type_of<Token1>() == global.token1, EINVLAID_TOKEN1);
        let token1_amount = get_buyable_token1_amount(global,payment);
        let referrer_reward = 0;
        if(referrer!=EMPTY_ADDRESS){
            if(exists<UserStorage>(referrer)){
                let referrer_storage = borrow_global<UserStorage>(referrer);
                if(referrer_storage.total_payments >= global.refeerer_min_buy_amount){
                    referrer_reward = payment * global.commission_rate/100;
                }
            }
        };
        if(!exists<UserStorage>(buyer_addr)){
            move_to(buyer, UserStorage{
                buy_records: vector::empty(),
                claim_records: vector::empty(),
                claimed_count: 0 ,
                total_payments: 0,
                max_claim_count: 0,
            });
        };

        let user_storage = borrow_global_mut<UserStorage>(buyer_addr);
        number_add(&mut global.saled_amount,payment);
        vector::push_back(&mut user_storage.buy_records,BuyRecord{
            payment,
            token1_amount,
            referrer,
            referrer_reward,
            buy_time: now,
            lock_periods,
        });

        if(user_storage.max_claim_count< lock_periods) {
            number_set(&mut user_storage.max_claim_count,lock_periods);
        };

        coin::transfer<Currency>(buyer,global.fee_wallet,payment-referrer_reward);
        if(referrer_reward > 0 ){
            coin::transfer<Currency>(buyer,referrer, referrer_reward);
        };
        let resource_signer = account::create_signer_with_capability(&global.signer_capability);
        let resource_addr = signer::address_of(&resource_signer);
        assert!(coin::balance<Token1>(resource_addr) >= token1_amount, EINSUFFICIENT_TOKEN1_BALANCE);
        coin::transfer<Token1>(&resource_signer, buyer_addr, token1_amount);
    }

    public entry fun claim_token2< Token1,Token2>(buyer:&signer ) acquires ModuleStorage, UserStorage {
        let buyer_addr = signer::address_of(buyer);
        assert!(exists<ModuleStorage>(@kepler), ENOT_INITIALIZED);
        let global = borrow_global_mut<ModuleStorage>(@kepler);
        assert!(type_info::type_of<Token1>() == global.token1, EINVLAID_TOKEN1);
        assert!(type_info::type_of<Token2>() == global.token2, EINVLAID_TOKEN2);
        assert!(exists<UserStorage>(buyer_addr),ENOT_BUYER);
        let user_storage = borrow_global_mut<UserStorage>(buyer_addr);

        let claimables = queryClaimables(global,user_storage);
        let (i,total_amount,length) = (0, 0, vector::length(&claimables));

        while (i < length) {
            let record = vector::borrow(& user_storage.claim_records,i);
            total_amount = total_amount + record.amount;
            i = i + 1;
        };

        vector::append(&mut user_storage.claim_records,claimables);
        number_add(&mut user_storage.claimed_count,length);

        let resource_signer = account::create_signer_with_capability(&global.signer_capability);
        let resource_addr = signer::address_of(&resource_signer);
        coin::transfer<Token1>(buyer,global.fee_wallet,total_amount);

        assert!(coin::balance<Token2>(resource_addr) >= total_amount, EINSUFFICIENT_TOKEN2_BALANCE);
        coin::transfer<Token2>(&resource_signer, buyer_addr, total_amount);
    }

    fun queryClaimables(global: &ModuleStorage,user_storage: &UserStorage): vector<ClaimRecord> {
        let now = timestamp::now_seconds();
        let claimables = vector::empty<ClaimRecord>();
        if (now > global.claim_start_time) {
            let max_claim_count = math64::min(
                (now-global.claim_start_time)/global.claim_interval,
                user_storage.max_claim_count
            );
            let claimed_count = user_storage.claimed_count;
            if (max_claim_count > claimed_count) {
                let (i,length) = (0, max_claim_count - claimed_count);
                while(i < length) {
                    let index = i + claimed_count;
                    let amount = queryClaimAmount(user_storage,index);
                    vector::push_back(&mut claimables, ClaimRecord{index,amount,claim_time:now});
                    i= i + 1;
                };
            };
        };
        claimables
    }

    fun queryClaimAmount(user_storage: &UserStorage, claim_index:u64): u64 {
        let length = vector::length(&user_storage.buy_records);
        let i =0 ;
        let claim_amount = 0;
        while (i < length) {
            let buy_record = vector::borrow(&user_storage.buy_records,i);
            if (buy_record.lock_periods > claim_index) {
                claim_amount =claim_amount+ buy_record.token1_amount / buy_record.lock_periods;
            };
             i = i+1;
        };
        claim_amount
    }

    fun get_buyable_token1_amount(global: &ModuleStorage, payment: u64): u64 {
        let saled_amount = global.saled_amount;
        let sale_amount_per_round = global.sale_amount_per_round;
        let round = saled_amount / sale_amount_per_round;
        let token1_amount = 0 ;
        let round_prices = global.round_prices;
        let length = vector::length(& round_prices);
        let i = round;
        let multiplier = 10000000;
        while(i < length) {
            let price = * vector::borrow(&round_prices,i);
            let round_max_amount = (i + 1) * sale_amount_per_round;
            if (saled_amount + payment > round_max_amount) {
                // exceed current round
                let amount = round_max_amount - saled_amount;
                token1_amount = token1_amount + amount * multiplier / price;
                payment = payment -  amount;
                saled_amount = saled_amount +  amount;
            } else {
                token1_amount = token1_amount+ payment * multiplier / price;
                break
            };
            i = i + 1;
        };

        token1_amount/multiplier
    }

    fun calculate_round_prices(base_price: u64): vector<u64> {
        let round_count:u64 = 10;
        let inflation_rate:u64 = 5;
        let prices = vector::empty<u64>();
        let price = base_price;
        let i = 0;
        while(i < round_count){
            vector::push_back(&mut prices,price);
            price = price * (100+inflation_rate) / 100;
            i = i + 1;
        };
        prices
    }

    fun number_add(number: &mut u64, value: u64){
        *number = *number + value;
    }

    fun number_set(number: &mut u64, value: u64){
        *number = value;
    }
}
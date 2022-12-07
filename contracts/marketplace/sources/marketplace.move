module kepler::marketplace_v01 {

    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::timestamp;
    use aptos_framework::account;
    use aptos_framework::account::SignerCapability;
    use aptos_framework::guid;
    use aptos_std::event::{Self, EventHandle};
    use aptos_std::table::{Self, Table};
    use aptos_token::token::{Self, Token, TokenId};
    use std::signer;
    use std::option::{Self, Option, some};
    use std::string::String;
    use std::vector;

    // ERROR's
    const ERROR_ALREADY_INITIALIZED     : u64 = 0x1000;
    const ERROR_INVALID_BUYER           : u64 = 0x1000;
    const ERROR_ALREADY_CLAIMED         : u64 = 0x1001;
    const ERROR_INVALID_TOKEN_ID        : u64 = 0x1002;
    const ERROR_INVALID_OWNER           : u64 = 0x1003;
    const ERROR_NOT_ENOUGH_LENGTH       : u64 = 0x1004;
    const ERROR_EXPIRED_TIME_ACCEPT     : u64 = 0x1005;
    const ERROR_COIN_ESCROW_NOT_FOUND   : u64 = 0x1006;


    struct SignerCap has key {
        cap: SignerCapability,
    }

    struct MarketData has key {
        fee: u64,
        fund_address: address
    }

    // Set of data sent to the event stream during a listing of a token (for fixed price)
    struct ListEvent has drop, store {
        id: TokenId,
        amount: u64,
        timestamp: u64,
        listing_id: u64,
        seller_address: address,
        royalty_payee: address,
        royalty_numerator: u64,
        royalty_denominator: u64
    }

    struct DelistEvent has drop, store {
        id: TokenId,
        timestamp: u64,
        listing_id: u64,
        amount: u64,
        seller_address: address,
    }

    // Set of data sent to the event stream during a buying of a token (for fixed price)
    struct BuyEvent has drop, store {
        id: TokenId,
        timestamp: u64,
        listing_id: u64,
        seller_address: address,
        buyer_address: address
    }

    struct ListedItem has store {
        amount: u64,
        timestamp: u64,
        listing_id: u64,
        locked_token: Option<Token>,
        seller_address: address
    }

    struct ChangePriceEvent has drop, store {
        id: TokenId,
        amount: u64,
        listing_id: u64,
        timestamp: u64,
        seller_address: address,
    }

    struct ListData has key {
        listed_items: Table<TokenId, ListedItem>,
        list_events: EventHandle<ListEvent>,
        buy_events: EventHandle<BuyEvent>,
        delist_events: EventHandle<DelistEvent>,
        change_price_events: EventHandle<ChangePriceEvent>
    }

    struct Offerer has store, drop {
        offer_address: address,
        timestamp: u64,
        amount: u64,
        offer_id: u64,
        started_at: u64, // seconds enough
        duration: u64 // seconds enough
    }

    // offer mode
    struct OfferItem has key, store {
        offerers: vector<Offerer>,
        token: Option<TokenId>,
        claimable_token_address: address,
        claimable_offer_id: u64,
        accept_address: address
    }

    struct CoinEscrowOffer<phantom CoinType> has key {
        locked_coins: Table<TokenId, Coin<CoinType>>
    }

    struct OfferEvent has store, drop {
        id: TokenId,
        offer_id: u64,
        timestamp: u64,
        offerer: address,
        amount: u64,
        started_at: u64,
        duration: u64,
        royalty_payee: address,
        royalty_numerator: u64,
        royalty_denominator: u64
    }

    struct AcceptOfferEvent has store, drop {
        id: TokenId,
        offer_id: u64,
        timestamp: u64,
        offerer: address,
        amount: u64,
        owner_token: address
    }

    struct CancelOfferEvent has store, drop {
        id: TokenId,
        offer_id: u64,
        timestamp: u64,
        offerer: address
    }

    struct OfferData has key, store {
        offer_items: Table<TokenId, OfferItem>,
        offer_events: EventHandle<OfferEvent>,
        accept_offer_events: EventHandle<AcceptOfferEvent>,
        cancel_offer_events: EventHandle<CancelOfferEvent>
    }

    public entry fun change_fund_addess_script(sender:&signer,fund_address:address) acquires SignerCap,MarketData{
        let sender_addr = signer::address_of(sender);
        assert!(sender_addr == @kepler, ERROR_INVALID_OWNER);
        let market_cap = &borrow_global<SignerCap>(@kepler).cap;
        let market_signer = &account::create_signer_with_capability(market_cap);
        let market_signer_address = signer::address_of(market_signer);
        let market_data = borrow_global_mut<MarketData>(market_signer_address);
        *&mut market_data.fund_address=  fund_address;
    }

    public entry fun change_fee_script(sender:&signer,fee: u64) acquires SignerCap,MarketData{
        let sender_addr = signer::address_of(sender);
        assert!(sender_addr == @kepler, ERROR_INVALID_OWNER);
        let market_cap = &borrow_global<SignerCap>(@kepler).cap;
        let market_signer = &account::create_signer_with_capability(market_cap);
        let market_signer_address = signer::address_of(market_signer);
        let market_data = borrow_global_mut<MarketData>(market_signer_address);
        *&mut market_data.fee = fee;
    }

    public entry fun initial_market_script(sender: &signer,fund_address:address,fee:u64, seed:vector<u8>) {
        assert!(!exists<SignerCap>(@kepler),ERROR_ALREADY_INITIALIZED);
        let sender_addr = signer::address_of(sender);
        assert!(sender_addr == @kepler, ERROR_INVALID_OWNER);

        let (market_signer, market_cap) = account::create_resource_account(sender, seed);

        move_to(sender, SignerCap { cap: market_cap });
        move_to(&market_signer, MarketData {fee, fund_address });
        move_to(&market_signer, ListData {
            listed_items:table::new<TokenId, ListedItem>(),
            list_events: account::new_event_handle<ListEvent>(&market_signer),
            buy_events: account::new_event_handle<BuyEvent>(&market_signer),
            delist_events: account::new_event_handle<DelistEvent>(&market_signer),
            change_price_events: account::new_event_handle<ChangePriceEvent>(&market_signer)
        });

        move_to(&market_signer, OfferData {
            offer_items: table::new<TokenId,OfferItem>(),
            offer_events: account::new_event_handle(&market_signer),
            accept_offer_events: account::new_event_handle(&market_signer),
            cancel_offer_events: account::new_event_handle(&market_signer)
        })
    }

    fun list_token(sender: &signer, token_id: TokenId, price: u64) acquires ListData, SignerCap {
        let sender_addr = signer::address_of(sender);
        let market_cap = &borrow_global<SignerCap>(@kepler).cap;
        let market_signer = &account::create_signer_with_capability(market_cap);
        let market_signer_address = signer::address_of(market_signer);

        let token = token::withdraw_token(sender, token_id, 1);
        let listed_items_data = borrow_global_mut<ListData>(market_signer_address);
        let listed_items = &mut listed_items_data.listed_items;

        let royalty = token::get_royalty(token_id);
        let royalty_payee = token::get_royalty_payee(&royalty);
        let royalty_numerator = token::get_royalty_numerator(&royalty);
        let royalty_denominator = token::get_royalty_denominator(&royalty);
        
        let listing_id = guid::creation_num(&account::create_guid(market_signer));

        event::emit_event<ListEvent>( &mut listed_items_data.list_events, ListEvent {
            id: token_id,
            amount: price,
            seller_address: sender_addr,
            timestamp: timestamp::now_seconds(),
            listing_id,
            royalty_payee,
            royalty_numerator,
            royalty_denominator
        });

        table::add(listed_items, token_id, ListedItem {
            amount: price,
            listing_id,
            timestamp: timestamp::now_seconds(),
            locked_token: option::some(token),
            seller_address: sender_addr
        })
    }

    // entry batch list script by token owners
    public entry fun batch_list_script(
        sender: &signer,
        creators: vector<address>,
        collection_names: vector<String>,
        token_names: vector<String>,
        property_versions: vector<u64>,
        prices: vector<u64>
    ) acquires ListData, SignerCap {

        let length_creators = vector::length(&creators);
        let length_collections = vector::length(&collection_names);
        let length_token_names = vector::length(&token_names);
        let length_prices = vector::length(&prices);
        let length_properties = vector::length(&property_versions);

        assert!(length_collections == length_creators
            && length_creators == length_token_names
            && length_token_names == length_prices
            && length_prices == length_properties, ERROR_NOT_ENOUGH_LENGTH);

        let i = length_properties;

        while (i > 0) {
            let creator = vector::pop_back(&mut creators);
            let token_name = vector::pop_back(&mut token_names);
            let collection_name = vector::pop_back(&mut collection_names);
            let price = vector::pop_back(&mut prices);
            let property_version = vector::pop_back(&mut property_versions);

            let token_id = token::create_token_id_raw(creator, collection_name, token_name, property_version);

            list_token(sender, token_id, price);

            i = i - 1;
        }
    }

    // delist token
    fun delist_token(sender: &signer, token_id: TokenId) acquires ListData, SignerCap {
        let sender_addr = signer::address_of(sender);
        let market_cap = &borrow_global<SignerCap>(@kepler).cap;
        let market_signer = &account::create_signer_with_capability(market_cap);
        let market_signer_address = signer::address_of(market_signer);

        let listed_items_data = borrow_global_mut<ListData>(market_signer_address);
        let listed_items = &mut listed_items_data.listed_items;
        let listed_item = table::borrow_mut(listed_items, token_id);

        event::emit_event<DelistEvent>( &mut listed_items_data.delist_events, DelistEvent {
            id: token_id,
            amount: listed_item.amount,
            listing_id: listed_item.listing_id,
            timestamp: timestamp::now_seconds(),
            seller_address: sender_addr
        });

        let token = option::extract(&mut listed_item.locked_token);
        token::deposit_token(sender, token);

        let ListedItem {amount: _, timestamp: _, locked_token, seller_address: _, listing_id: _}
            = table::remove(listed_items, token_id);
        option::destroy_none(locked_token);
    }

    public entry fun batch_delist_script(
        sender: &signer,
        creators: vector<address>,
        collection_names: vector<String>,
        token_names: vector<String>,
        property_versions: vector<u64>
    ) acquires ListData, SignerCap {

        let length_creators = vector::length(&creators);
        let length_collections = vector::length(&collection_names);
        let length_token_names = vector::length(&token_names);
        let length_properties = vector::length(&property_versions);

        assert!(length_collections == length_creators
            && length_creators == length_token_names
            && length_token_names == length_properties, ERROR_NOT_ENOUGH_LENGTH);

        let i = length_token_names;

        while (i > 0) {
            let creator = vector::pop_back(&mut creators);
            let collection_name = vector::pop_back(&mut collection_names);
            let token_name = vector::pop_back(&mut token_names);
            let property_version = vector::pop_back(&mut property_versions);
            let token_id = token::create_token_id_raw(creator, collection_name, token_name, property_version);
            delist_token(sender, token_id);
            i = i - 1;
        }
    }

    // part of the fixed price sale flow
    fun buy_token<CoinType>( sender: &signer, token_id: TokenId) acquires ListData, SignerCap, MarketData {
        let sender_addr = signer::address_of(sender);

        let market_cap = &borrow_global<SignerCap>(@kepler).cap;
        let market_signer = &account::create_signer_with_capability(market_cap);
        let market_signer_address = signer::address_of(market_signer);
        let market_data = borrow_global_mut<MarketData>(market_signer_address);

        let listed_items_data = borrow_global_mut<ListData>(market_signer_address);
        let listed_items = &mut listed_items_data.listed_items;
        let listed_item = table::borrow_mut(listed_items, token_id);
        let seller = listed_item.seller_address;

        assert!(sender_addr != seller, ERROR_INVALID_BUYER);

        let royalty = token::get_royalty(token_id);
        let royalty_payee = token::get_royalty_payee(&royalty);
        let royalty_numerator = token::get_royalty_numerator(&royalty);
        let royalty_denominator = token::get_royalty_denominator(&royalty);

        let fee_royalty: u64 = 0;
        if (royalty_denominator > 0){
            fee_royalty = royalty_numerator * listed_item.amount / royalty_denominator;
        };

        let fee_listing = listed_item.amount * market_data.fee / 10000;
        let sub_amount = listed_item.amount - fee_listing - fee_royalty;

        if (fee_royalty > 0) {
            coin::transfer<CoinType>(sender, royalty_payee, fee_royalty);
        };

        if (fee_listing > 0) {
            coin::transfer<CoinType>(sender, market_data.fund_address, fee_listing);
        };

        coin::transfer<CoinType>(sender, seller, sub_amount);

        let token = option::extract(&mut listed_item.locked_token);
        token::deposit_token(sender, token);

        event::emit_event<BuyEvent>(&mut listed_items_data.buy_events,
            BuyEvent {
                id: token_id,
                listing_id: listed_item.listing_id,
                seller_address: listed_item.seller_address,
                timestamp: timestamp::now_seconds(),
                buyer_address: sender_addr
            },
        );

        let ListedItem {amount: _, timestamp: _, locked_token, seller_address: _, listing_id: _} = table::remove(listed_items, token_id);
        option::destroy_none(locked_token);
    }

    // batch buy script
	public entry fun batch_buy_script(
        sender: &signer,
        creators: vector<address>,
        collection_names: vector<String>,
        token_names: vector<String>,
        property_versions: vector<u64>
    ) acquires ListData, SignerCap, MarketData {
        let length_creators = vector::length(&creators);
        let length_collections = vector::length(&collection_names);
        let length_token_names = vector::length(&token_names);
        let length_properties = vector::length(&property_versions);

        assert!(length_collections == length_creators
                && length_creators == length_token_names
                && length_token_names == length_properties, ERROR_NOT_ENOUGH_LENGTH);

        let i = length_token_names;

        while (i > 0){
            let creator = vector::pop_back(&mut creators);
            let collection_name = vector::pop_back(&mut collection_names);
            let token_name = vector::pop_back(&mut token_names);
            let property_version = vector::pop_back(&mut property_versions);
            let token_id = token::create_token_id_raw(creator, collection_name, token_name, property_version);
            buy_token<AptosCoin>(sender, token_id);
            i = i - 1;
        }
	}

    // offer mode
    // make offer by listing token (by buyer)
    public entry fun make_offer_script(
        sender: &signer,
        creator: address,
        collection_name: String,
        token_name: String,
        property_version: u64,
        //price
        offer_amount: u64,
        duration: u64
    ) acquires SignerCap, OfferData, CoinEscrowOffer {
        let token_id = token::create_token_id_raw(creator, collection_name, token_name, property_version);
        make_offer<AptosCoin>(sender, token_id, offer_amount, duration)
    }

    // make offer for listing token
    fun make_offer<CoinType>(
        sender: &signer,
        token_id: TokenId,
        offer_amount: u64,
        duration: u64
    ) acquires SignerCap, OfferData, CoinEscrowOffer {
        //enable direct transfer
        token::opt_in_direct_transfer(sender,true);


        let sender_addr = signer::address_of(sender);
        let market_cap = &borrow_global<SignerCap>(@kepler).cap;
        let market_signer = &account::create_signer_with_capability(market_cap);
        let market_signer_address = signer::address_of(market_signer);

        let offer_data = borrow_global_mut<OfferData>(market_signer_address);
        let offer_items = &mut offer_data.offer_items;
        let is_contain = table::contains(offer_items, token_id);

        let royalty = token::get_royalty(token_id);
        let royalty_payee = token::get_royalty_payee(&royalty);
        let royalty_numerator = token::get_royalty_numerator(&royalty);
        let royalty_denominator = token::get_royalty_denominator(&royalty);

        if(!exists<CoinEscrowOffer<CoinType>>(sender_addr)){
            move_to(sender, CoinEscrowOffer { locked_coins: table::new<TokenId, Coin<CoinType>>()})
        };

        // unique offer id
        let offer_id = guid::creation_num(&account::create_guid(market_signer));
        let started_at = timestamp::now_seconds();

        if (!is_contain){
            let offerer = Offerer {
                offer_address: sender_addr,
                timestamp: timestamp::now_seconds(),
                amount: offer_amount,
                offer_id,
                started_at,
                duration
            };

            let locked_coins = &mut borrow_global_mut<CoinEscrowOffer<CoinType>>(sender_addr).locked_coins;
            let coins = coin::withdraw<CoinType>(sender, offer_amount);
            table::add(locked_coins, token_id, coins);

            let offerers = vector::empty<Offerer>();

            vector::push_back(&mut offerers, offerer);
            table::add(offer_items, token_id, OfferItem {
                offerers,
                token:option::none<TokenId>(),
                claimable_token_address: @0x0,
                claimable_offer_id: 0,
                accept_address: @0x0
            });

        } else {
            //1. check sender has been offered
            let already_offered = false;
            let index = 0;
            let offer_item = table::borrow_mut(offer_items, token_id);
            let offerers = &mut offer_item.offerers;
            let i = vector::length(offerers);

            while (i > 0){
                let offerer = vector::borrow(offerers, i - 1);
                if (offerer.offer_address == sender_addr) {
                    already_offered = true;
                    index = i - 1;
                    break
                };

                i = i - 1;
            };
            if (already_offered) {
                let locked_coins = &mut borrow_global_mut<CoinEscrowOffer<CoinType>>(sender_addr).locked_coins;
                let coins_refund = table::remove(locked_coins, token_id);
                coin::deposit<CoinType>(sender_addr, coins_refund);
                // locked new amount to offer
                let coins = coin::withdraw<CoinType>(sender, offer_amount);
                table::add(locked_coins, token_id, coins);

                // update offer of sender
                let _offerer = vector::borrow_mut(offerers, index);

                // update offer_id
                offer_id = _offerer.offer_id;

                _offerer.amount = offer_amount;
                _offerer.started_at = started_at;
                _offerer.duration = duration;

            } else {
                //2. locked_coins offered
                let locked_coins = &mut borrow_global_mut<CoinEscrowOffer<CoinType>>(sender_addr).locked_coins;
                let coins = coin::withdraw<CoinType>(sender, offer_amount);
                table::add(locked_coins, token_id, coins);

                //3. add to offerers
                let offerer = Offerer {
                    offer_address: sender_addr,
                    timestamp: timestamp::now_seconds(),
                    amount: offer_amount,
                    offer_id,
                    started_at,
                    duration
                };

                vector::push_back(offerers, offerer);
            }
        };

        event::emit_event(&mut offer_data.offer_events, OfferEvent {
            id: token_id,
            offerer: sender_addr,
            amount: offer_amount,
            timestamp: timestamp::now_seconds(),
            offer_id,
            started_at,
            duration,
            royalty_payee,
            royalty_numerator,
            royalty_denominator
        })
    }

    //delist token and  accept offer by token owner.
    public entry fun delist_and_accept_offer_script(
        sender: &signer,
        creator: address,
        collection_name: String,
        token_name: String,
        property_version: u64,
        offerer: address,
    ) acquires SignerCap, MarketData, OfferData, CoinEscrowOffer,ListData  {
        let token_id = token::create_token_id_raw(creator, collection_name, token_name, property_version);
        delist_token(sender,token_id);
        accept_offer<AptosCoin>(sender, token_id, offerer)
    }

    // accept offer by token owner.
    public entry fun accept_offer_script(
        sender: &signer,
        creator: address,
        collection_name: String,
        token_name: String,
        property_version: u64,
        offerer: address,
    ) acquires SignerCap, MarketData, OfferData, CoinEscrowOffer  {
        let token_id = token::create_token_id_raw(creator, collection_name, token_name, property_version);
        accept_offer<AptosCoin>(sender, token_id, offerer)
    }

    fun accept_offer<CoinType>(
        sender: &signer, token_id: TokenId, offerer: address
    ) acquires SignerCap, MarketData, OfferData, CoinEscrowOffer {
        let sender_addr = signer::address_of(sender);

        let market_cap = &borrow_global<SignerCap>(@kepler).cap;
        let market_signer = &account::create_signer_with_capability(market_cap);
        let market_signer_address = signer::address_of(market_signer);

        let market_data = borrow_global_mut<MarketData>(market_signer_address);
        let offer_data = borrow_global_mut<OfferData>(market_signer_address);

        assert!(exists<CoinEscrowOffer<CoinType>>(offerer),ERROR_COIN_ESCROW_NOT_FOUND);
        let locked_coins = &mut borrow_global_mut<CoinEscrowOffer<CoinType>>(offerer).locked_coins;

        //
        let offer_items = &mut offer_data.offer_items;
        assert!(table::contains(offer_items, token_id), ERROR_INVALID_TOKEN_ID);

        let offer_item = table::borrow_mut(offer_items, token_id);
        let offerers = &mut offer_item.offerers;
        //
        let royalty = token::get_royalty(token_id);
        let royalty_payee = token::get_royalty_payee(&royalty);
        let royalty_numerator = token::get_royalty_numerator(&royalty);
        let royalty_denominator = token::get_royalty_denominator(&royalty);

        // check offerer
        let offer_id = search_offer_id(offerers,offerer);
        // assert!(false,2000);
        assert!(table::contains(locked_coins, token_id), ERROR_ALREADY_CLAIMED);
        
        let coins = table::remove(locked_coins, token_id);
        let amount = coin::value(&coins);

        let fee = market_data.fee * amount / 10000;
        if (fee > 0) {
            coin::deposit<CoinType>(market_data.fund_address, coin::extract(&mut coins, fee));
        };

        if(royalty_numerator > 0 && royalty_denominator > 0){
            let royalty_fee = amount * royalty_numerator / royalty_denominator;
            coin::deposit<CoinType>(royalty_payee, coin::extract(&mut coins, royalty_fee));
        };

        coin::deposit<CoinType>(sender_addr, coins);

        // update offer_item
        offer_item.claimable_token_address = offerer;
        offer_item.claimable_offer_id = offer_id;
        option::destroy_none(offer_item.token);
        offer_item.token = some(token_id);
        offer_item.accept_address = sender_addr;

        //transfer token to offerer
        token::transfer(sender,token_id,offerer,1);

        event::emit_event(&mut offer_data.accept_offer_events, AcceptOfferEvent {
            id: token_id,
            timestamp: timestamp::now_seconds(),
            offerer,
            offer_id,
            amount,
            owner_token: sender_addr
        })
    }

    fun search_offer_id(offerers: &vector<Offerer>, offerer:address): u64 {
        let i = vector::length(offerers);
        while (i > 0){
            let item = vector::borrow(offerers, i - 1);
            if(item.duration + item.started_at >= timestamp::now_seconds() && item.offer_address == offerer){
                return item.offer_id
            };
            i = i - 1;
        };

        abort ERROR_EXPIRED_TIME_ACCEPT
    }

    // cancel offer by buyer
    public entry fun cancel_offer_script(
        sender: &signer, creator: address, collection_name: String, token_name: String, property_version: u64
    ) acquires SignerCap, OfferData, CoinEscrowOffer {
        let token_id = token::create_token_id_raw(creator, collection_name, token_name, property_version);
        cancel_offer<AptosCoin>(sender, token_id)
    }

    fun cancel_offer<CoinType>( sender: &signer, token_id: TokenId) acquires SignerCap, OfferData, CoinEscrowOffer {
        let sender_addr = signer::address_of(sender);

        let market_cap = &borrow_global<SignerCap>(@kepler).cap;
        let market_signer = &account::create_signer_with_capability(market_cap);
        let market_signer_address = signer::address_of(market_signer);
        let offer_data = borrow_global_mut<OfferData>(market_signer_address);

        let offer_items = &mut offer_data.offer_items;
        assert!(table::contains(offer_items, token_id), ERROR_INVALID_TOKEN_ID);

        let offer_item = table::borrow_mut(offer_items, token_id);
        let offerers = &mut offer_item.offerers;

        // remove offer from offerers
        let current_offer_id: u64 = 0;

        let i = vector::length(offerers);
        while (i > 0) {
            let _offerer = vector::borrow_mut(offerers,i - 1);
            if (_offerer.offer_address == sender_addr){
                current_offer_id = _offerer.offer_id;
                vector::remove(offerers, i - 1);
                break
            };

            i = i -1;
        };

        let locked_coins = &mut borrow_global_mut<CoinEscrowOffer<CoinType>>(sender_addr).locked_coins;
        let coins = table::remove(locked_coins, token_id);
        coin::deposit(sender_addr, coins);

        event::emit_event(&mut offer_data.cancel_offer_events, CancelOfferEvent {
            id: token_id,
            offer_id: current_offer_id,
            timestamp: timestamp::now_seconds(),
            offerer: sender_addr
        })
    }

    
    public entry fun change_token_price_script(
        sender: &signer,
        creator: address,
        collection_name: String,
        token_name: String,
        property_vertion: u64,
        new_price: u64,
    ) acquires ListData, SignerCap {
        let token_id = token::create_token_id_raw(creator, collection_name, token_name, property_vertion);
        change_token_price(sender, token_id, new_price);
    }

    // change token price
    fun change_token_price(
        sender: &signer, token_id: TokenId, new_price: u64,
    ) acquires ListData, SignerCap {
        let sender_addr = signer::address_of(sender);
        let market_cap = &borrow_global<SignerCap>(@kepler).cap;
        let market_signer = &account::create_signer_with_capability(market_cap);
        let market_signer_address = signer::address_of(market_signer);

        let listed_items_data = borrow_global_mut<ListData>(market_signer_address);
        let listed_items = &mut listed_items_data.listed_items;

        assert!(table::contains(listed_items, token_id), ERROR_ALREADY_CLAIMED);

        let listed_item = table::borrow_mut(listed_items, token_id);

        listed_item.amount = new_price;

        event::emit_event(&mut listed_items_data.change_price_events, ChangePriceEvent {
            id: token_id,
            listing_id: listed_item.listing_id,
            amount: new_price,
            timestamp: timestamp::now_seconds(),
            seller_address: sender_addr
        })
    }

}
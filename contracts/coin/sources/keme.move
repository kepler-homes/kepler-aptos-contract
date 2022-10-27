module kepler::KEME {
    use aptos_framework::managed_coin;
    struct Coin {}

    fun init_module(sender: &signer) {
        managed_coin::initialize<Coin>( sender, b"KEME Token", b"KEME", 6, false);
    }
}
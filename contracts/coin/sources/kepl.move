module kepler::KEPL {
    use aptos_framework::managed_coin;
    struct Coin {}

    fun init_module(sender: &signer) {
        managed_coin::initialize<Coin>( sender, b"Kepler Token", b"KEPL", 6, false);
    }
}

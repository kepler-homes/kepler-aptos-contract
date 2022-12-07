module coin::KEPL {
    use aptos_framework::managed_coin;
    struct T {}

    fun init_module(sender: &signer) {
        managed_coin::initialize<T>( sender, b"Kepler Token", b"KEPL", 8, false);
    }
}

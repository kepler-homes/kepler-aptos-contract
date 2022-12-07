module coin::VeKEPL {
    use aptos_framework::managed_coin;

    struct T {}

    fun init_module(sender: &signer) {
        managed_coin::initialize<T>( sender, b"veKEPL Token", b"veKEPL", 8, false);
    }
}

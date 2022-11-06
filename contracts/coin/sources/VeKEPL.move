module kepler::VeKEPL {
    use aptos_framework::managed_coin;
    
    struct T {}

    fun init_module(sender: &signer) {
        managed_coin::initialize<T>( sender, b"veKEPL", b"veKEPL", 6, false);
    }
}

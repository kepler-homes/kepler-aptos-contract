module coin::KEME {
    use aptos_framework::managed_coin;
    struct T {}

    fun init_module(sender: &signer) {
        managed_coin::initialize<T>( sender, b"KEME Token", b"KEME", 8, false);
    }
}
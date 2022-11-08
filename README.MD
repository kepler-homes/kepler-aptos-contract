# KEPLER-APTOS-CONTRACTS

```shell
aptos move compile --named-addresses kepler=default
aptos move publish --assume-yes --named-addresses kepler=default
aptos move run --assume-yes --function-id 'default::message::set_message' --args 'string:hello, blockchain'
```

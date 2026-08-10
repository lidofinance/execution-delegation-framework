# Owner: nominate (or renominate) the delegate; effective after the contract's cooldown (anvil)
nominate-delegate contract new_delegate *args:
    cast send {{contract}} "nominateDelegate(address)" {{new_delegate}} --rpc-url {{anvil_rpc_url}} {{args}}

# Owner: nominate (or renominate) the delegate; effective after the contract's cooldown (live)
[confirm("You are about to broadcast a transaction to the network. Are you sure?")]
nominate-delegate-live contract new_delegate *args:
    cast send {{contract}} "nominateDelegate(address)" {{new_delegate}} --rpc-url ${RPC_URL} {{args}}

# Owner: immediately remove the current and pending delegate (anvil)
revoke-delegate contract *args:
    cast send {{contract}} "revokeDelegate()" --rpc-url {{anvil_rpc_url}} {{args}}

# Owner: immediately remove the current and pending delegate (live)
[confirm("You are about to broadcast a transaction to the network. Are you sure?")]
revoke-delegate-live contract *args:
    cast send {{contract}} "revokeDelegate()" --rpc-url ${RPC_URL} {{args}}

# Owner: irreversibly terminate the contract, e.g. if the owner key is suspected compromised (anvil)
terminate contract *args:
    cast send {{contract}} "terminate()" --rpc-url {{anvil_rpc_url}} {{args}}

# Owner: irreversibly terminate the contract, e.g. if the owner key is suspected compromised (live)
[confirm("This is IRREVERSIBLE: it permanently disables execute() and delegate renomination. Are you sure?")]
terminate-live contract *args:
    cast send {{contract}} "terminate()" --rpc-url ${RPC_URL} {{args}}

# Views: pass --rpc-url yourself (e.g. --rpc-url {{anvil_rpc_url}} or --rpc-url $RPC_URL)
get-owner contract *args:
    cast call {{contract}} "owner()(address)" {{args}}

get-delegate contract *args:
    cast call {{contract}} "getDelegate()(address)" {{args}}

get-pending-delegate contract *args:
    cast call {{contract}} "getPendingDelegate()(address,uint256)" {{args}}

get-cooldown contract *args:
    cast call {{contract}} "getCooldown()(uint256)" {{args}}

is-terminated contract *args:
    cast call {{contract}} "isTerminated()(bool)" {{args}}

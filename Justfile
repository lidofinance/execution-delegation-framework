set dotenv-load

# Restrict Foundry parallelism by default; override from the caller when needed.
export FOUNDRY_THREADS := env("FOUNDRY_THREADS", "4")

chain := env_var_or_default("CHAIN", "mainnet")
chain_script_suffix := if chain == "mainnet" {
    "Mainnet"
} else if chain == "hoodi" {
    "Hoodi"
} else {
    error("Unsupported chain " + chain + ". Supported: mainnet, hoodi")
}
anvil_host := env_var_or_default("ANVIL_IP_ADDR", "127.0.0.1")
anvil_port := env_var_or_default("ANVIL_PORT", "8545")
anvil_rpc_url := "http://" + anvil_host + ":" + anvil_port
disable_code_size_limit := if env("DISABLE_CODE_SIZE_LIMIT", "") != "" { "--disable-code-size-limit" } else { "" }

deploy_script_name := "Deploy" + chain_script_suffix
deploy_config_path := "artifacts" / chain / "deploy-" + chain + ".json"
deploy_script_path := "script" / deploy_script_name + ".s.sol:" + deploy_script_name

artifacts_latest_dir := "./artifacts/latest/"
artifacts_local_dir := "./artifacts/local/"
latest_transactions_path := artifacts_latest_dir + "transactions.json"
local_transactions_path := artifacts_local_dir + "transactions.json"
latest_deploy_config_path := artifacts_latest_dir + "deploy-" + chain + ".json"
local_deploy_config_path := artifacts_local_dir + "deploy-" + chain + ".json"

# Shared deployment helpers
_deploy-generic deploy_script_path rpc_url *args:
    FOUNDRY_PROFILE=deploy \
        forge script {{deploy_script_path}} --sig="run(string)" --rpc-url {{rpc_url}} --broadcast --slow {{args}} -- `git rev-parse HEAD`

[confirm("You are about to broadcast deployment transactions to the network. Are you sure?")]
_deploy-live-generic deploy_script_path *args:
    just _deploy-live-generic-no-confirm {{deploy_script_path}} --broadcast --verify {{args}}

_deploy-live-generic-no-confirm deploy_script_path *args:
    forge script {{deploy_script_path}} --sig="run(string)" --force --rpc-url ${RPC_URL} {{args}} -- `git rev-parse HEAD`

_deploy-live-generic-dry deploy_script_path *args:
    FOUNDRY_PROFILE=deploy just _deploy-live-generic-no-confirm {{deploy_script_path}} {{args}}

_verify-live-generic deploy_script_path *args:
    forge script {{deploy_script_path}} --sig="run(string)" --rpc-url ${RPC_URL} --broadcast --resume --verify {{args}} -- `git rev-parse HEAD`

# Shared artifact helpers
_copy-broadcast-json script_name rpc_url dry_prefix json_name dest_path:
    just _copy-file \
        ./broadcast/{{script_name}}.s.sol/$(cast chain-id --rpc-url "{{rpc_url}}"){{dry_prefix}}/{{json_name}} \
        {{dest_path}}

_finalize-broadcast-artifacts script_name rpc_url dry_prefix json_name deploy_config_path:
    just _copy-broadcast-json "{{script_name}}" "{{rpc_url}}" "{{dry_prefix}}" "{{json_name}}" "$(dirname "{{deploy_config_path}}")/transactions.json"

_copy-file src_path dest_path:
    mkdir -p "$(dirname "{{dest_path}}")"
    cp "{{src_path}}" "{{dest_path}}"

_warn message:
    @tput setaf 3 && printf "[WARNING]" && tput sgr0 && echo " {{message}}"

_info message:
    @tput setaf 6 && printf "[INFO]" && tput sgr0 && echo " {{message}}"

# Recipe modules
import? ".local.just"

# Default and top-level workflows
default: clean deps build test-unit

build *args:
    forge build --skip test --skip script {{args}}

clean:
    forge clean
    rm -rf cache broadcast out node_modules

deps:
    yarn workspaces focus --all --production

deps-dev:
    yarn workspaces focus --all && npx husky install

lint-solhint:
    yarn lint:solhint

lint-foundry *args:
    forge lint {{args}}

lint-fix:
    yarn lint:fix

lint:
    just lint-foundry
    yarn lint:check

# Run all unit tests
test-unit *args:
    env -u FOUNDRY_THREADS forge test --skip script --match-path 'test/unit/**' -vvv {{args}}

coverage *args:
    FOUNDRY_PROFILE=coverage forge coverage --no-match-coverage '(test|script)' --no-match-path 'test/fork/*' {{args}}

# Run coverage and save the report in LCOV file.
coverage-lcov *args:
    FOUNDRY_PROFILE=coverage forge coverage --no-match-coverage '(test|script)' --no-match-path 'test/fork/*' --report lcov {{args}}

# Deployment

# Deploy to local anvil instance
deploy *args:
    mkdir -p {{artifacts_local_dir}}
    ARTIFACTS_DIR={{artifacts_local_dir}} \
        just _deploy-generic {{deploy_script_path}} {{anvil_rpc_url}} {{args}}
    just _finalize-broadcast-artifacts {{deploy_script_name}} {{anvil_rpc_url}} "" "run-latest.json" {{local_deploy_config_path}}

# Deploy to live network (mainnet or hoodi)
deploy-live *args:
    just _warn "The current `tput bold`chain={{chain}}`tput sgr0` with the following rpc url: $RPC_URL"
    mkdir -p {{artifacts_latest_dir}}
    ARTIFACTS_DIR={{artifacts_latest_dir}} \
        just _deploy-live-generic {{deploy_script_path}} {{args}}
    just _finalize-broadcast-artifacts {{deploy_script_name}} $RPC_URL "" "run-latest.json" {{latest_deploy_config_path}}

# Dry-run deployment to live network (mainnet or hoodi)
deploy-live-dry *args:
    just _warn "The current `tput bold`chain={{chain}}`tput sgr0` with the following rpc url: $RPC_URL"
    mkdir -p {{artifacts_local_dir}}
    ARTIFACTS_DIR={{artifacts_local_dir}} \
        just _deploy-live-generic-dry {{deploy_script_path}} {{args}}
    just _finalize-broadcast-artifacts {{deploy_script_name}} $RPC_URL "/dry-run" "run-latest.json" {{local_deploy_config_path}}

# Verify deployment on live network (mainnet or hoodi)
verify-live *args:
    just _warn "Pass --chain=your_chain manually when running deployments"
    just _verify-live-generic {{deploy_script_path}} {{args}}

# DelegationContract management (via cast)
# Requires: jq

# Deploy a new DelegationContract via the factory recorded in the local deploy artifact (anvil)
deploy-delegate owner delegate cooldown *args:
    #!/usr/bin/env bash
    set -euo pipefail
    factory=$(jq -r ".DelegationFactory" "{{local_deploy_config_path}}")
    receipt=$(cast send "$factory" "deploy(address,address,uint256)" {{owner}} {{delegate}} {{cooldown}} --rpc-url {{anvil_rpc_url}} --json {{args}})
    topic=$(echo "$receipt" | jq -r '.logs[0].topics[1]')
    just _info "Deployed DelegationContract at 0x${topic: -40}"

# Deploy a new DelegationContract via the factory recorded in the live deploy artifact (mainnet or hoodi)
[confirm("You are about to broadcast a transaction to the network. Are you sure?")]
deploy-delegate-live owner delegate cooldown *args:
    #!/usr/bin/env bash
    set -euo pipefail
    factory=$(jq -r ".DelegationFactory" "{{latest_deploy_config_path}}")
    receipt=$(cast send "$factory" "deploy(address,address,uint256)" {{owner}} {{delegate}} {{cooldown}} --rpc-url ${RPC_URL} --json {{args}})
    topic=$(echo "$receipt" | jq -r '.logs[0].topics[1]')
    just _info "Deployed DelegationContract at 0x${topic: -40}"

# Verify a deployed DelegationContract on Etherscan (live)
verify-delegate-live contract owner delegate cooldown *args:
    forge verify-contract {{contract}} \
        src/DelegationContract.sol:DelegationContract \
        --chain ${CHAIN} \
        --etherscan-api-key ${ETHERSCAN_API_KEY} \
        --compiler-version 0.8.35 \
        --constructor-args $(cast abi-encode "constructor(address,address,uint256)" {{owner}} {{delegate}} {{cooldown}}) \
        {{args}}

# Owner: assign (or reassign) the delegate; effective after the contract's cooldown (anvil)
assign-delegate contract new_delegate *args:
    cast send {{contract}} "assignDelegate(address)" {{new_delegate}} --rpc-url {{anvil_rpc_url}} {{args}}

# Owner: assign (or reassign) the delegate; effective after the contract's cooldown (live)
[confirm("You are about to broadcast a transaction to the network. Are you sure?")]
assign-delegate-live contract new_delegate *args:
    cast send {{contract}} "assignDelegate(address)" {{new_delegate}} --rpc-url ${RPC_URL} {{args}}

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
[confirm("This is IRREVERSIBLE: it permanently disables execute() and delegate reassignment. Are you sure?")]
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


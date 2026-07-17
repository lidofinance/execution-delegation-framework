# Development Guide

This guide covers repo-maintainer tasks: deploying the `DelegationFactory` itself, and a full reference of the `just` commands this repo provides. If you just want to deploy your own `DelegationContract` through an already-deployed factory, see the [Usage Guide](usage.md) instead.

## Prerequisites

- [Foundry](https://getfoundry.sh/) (`forge`/`cast`) and [`just`](https://github.com/casey/just) installed
- Node.js (see `.nvmrc`) and [Yarn](https://yarnpkg.com/) (via Corepack)
- `jq` on your `PATH` — required by the `deploy-delegate`/`deploy-delegate-live` commands, which read the factory address from the deploy artifact JSON

## Setup

```bash
just deps        # Install dependencies
just deps-dev    # Install development dependencies (also sets up git hooks)
```

## Configure Environment

Copy `.env.example` to `.env` and fill in the values:

```bash
cp .env.example .env
```

| Variable            | Description                                                               |
|---------------------|---------------------------------------------------------------------------|
| `RPC_URL`           | RPC endpoint used by all `-live` commands                                 |
| `ETHERSCAN_API_KEY` | Used by `deploy-live`/`verify-live` to verify the deployed source         |
| `CHAIN`             | `mainnet`, `hoodi`, or `local-devnet` — selects deploy artifact paths     |
| `ARTIFACTS_DIR`     | Where deployment artifacts are written (defaults to `./artifacts/local/`) |

Create a signing account for deployment:

```bash
cast wallet import --interactive Deployer
```

## Deploying the DelegationFactory

The factory is a singleton with no constructor arguments, so it only needs to be deployed once per network.

```bash
# Deploy to a local anvil instance
# `anvil --chain-id 560048` in a separate terminal
just deploy --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --unlocked

# Deploy to a local devnet with an explicit expected chain id
# `anvil --chain-id 31337` in a separate terminal
just deploy-local-devnet 31337 --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --unlocked

# Dry-run against a live network (mainnet or hoodi) without broadcasting
CHAIN=hoodi just deploy-live-dry --account Deployer

# Deploy to a live network and verify on Etherscan
CHAIN=hoodi just deploy-live --account Deployer

# Verify an already-deployed factory separately (e.g. if verification failed during deploy)
CHAIN=hoodi just verify-live --account Deployer
```

Each deploy writes the factory address to a JSON artifact:

- `deploy` (anvil) → `artifacts/local/deploy-<chain>.json`
- `deploy-local-devnet <chain-id>` → `artifacts/local/deploy-local-devnet.json`
- `deploy-live`/`deploy-live-dry` → `artifacts/latest/deploy-<chain>.json` (or `artifacts/local/...` for the dry run)

`deploy-local-devnet` passes `<chain-id>` to the Solidity deploy script and reverts before broadcasting when it does not match the RPC network's `block.chainid`.

The `deploy-delegate`/`deploy-delegate-live` commands (see below) read the factory address straight out of these artifacts, so no manual address copying is needed once the factory is deployed.
Use `CHAIN=local-devnet just deploy-delegate ...` to select the local-devnet factory artifact.

To commit a live deployment permanently, copy the artifacts from `artifacts/latest/` to the chain-specific directory and commit them:

```bash
mkdir -p artifacts/hoodi
cp artifacts/latest/deploy-hoodi.json artifacts/hoodi/
cp artifacts/latest/transactions.json artifacts/hoodi/
git add artifacts/hoodi/
git commit -m "chore: add hoodi deployment artifacts"
```

`deploy-live` and `deploy-delegate-live`/`assign-delegate-live`/`revoke-delegate-live`/`terminate-live` all prompt for confirmation before broadcasting, since these are real, irreversible transactions.

## CLI Command Reference

### Build, test, lint

| Command              | Description                                  |
|----------------------|----------------------------------------------|
| `just build`         | Compile Solidity contracts                   |
| `just test-unit`     | Run unit tests                               |
| `just coverage`      | Run coverage                                 |
| `just coverage-lcov` | Run coverage and write an LCOV report        |
| `just lint`          | Run `forge lint` + Solhint + Prettier checks |
| `just lint-fix`      | Auto-fix lint/formatting issues              |
| `just clean`         | Remove build/cache/deploy artifacts          |

### Factory deployment

| Command                                   | Description                                                                                |
|-------------------------------------------|--------------------------------------------------------------------------------------------|
| `just deploy`                             | Deploy `DelegationFactory` to a local anvil instance                                       |
| `just deploy-local-devnet <chain-id>`     | Deploy to a local devnet and validate its chain ID against the explicit parameter          |
| `just deploy-live`                        | Deploy `DelegationFactory` to a live network, with confirmation and Etherscan verification |
| `just deploy-live-dry`                    | Simulate a live deployment without broadcasting                                            |
| `just verify-live`                        | Verify an already-deployed factory on Etherscan                                            |

### DelegationContract deployment and management (via `cast`)

Owner-only commands broadcast a real transaction and prompt for confirmation on the `-live` variant; view commands are read-only and free.

| Command                                                   | Description                                               | Who can call |
|-----------------------------------------------------------|-----------------------------------------------------------|--------------|
| `just deploy-delegate <owner> <delegate> <cooldown>`      | Deploy a `DelegationContract` via the factory (anvil)     | Anyone       |
| `just deploy-delegate-live <owner> <delegate> <cooldown>` | Same, on a live network                                   | Anyone       |
| `just assign-delegate <contract> <newDelegate>`           | Schedule a new delegate, effective after cooldown (anvil) | Owner only   |
| `just assign-delegate-live <contract> <newDelegate>`      | Same, on a live network                                   | Owner only   |
| `just revoke-delegate <contract>`                         | Remove delegate access immediately (anvil)                | Owner only   |
| `just revoke-delegate-live <contract>`                    | Same, on a live network                                   | Owner only   |
| `just terminate <contract>`                               | Irreversibly disable the contract (anvil)                 | Owner only   |
| `just terminate-live <contract>`                          | Same, on a live network                                   | Owner only   |
| `just get-owner <contract> --rpc-url <url>`               | View the owner address                                    | Anyone       |
| `just get-delegate <contract> --rpc-url <url>`            | View the currently effective delegate                     | Anyone       |
| `just get-pending-delegate <contract> --rpc-url <url>`    | View the scheduled delegate and its activation time       | Anyone       |
| `just get-cooldown <contract> --rpc-url <url>`            | View the reassignment cooldown, in seconds                | Anyone       |
| `just is-terminated <contract> --rpc-url <url>`           | View whether the contract has been terminated             | Anyone       |

Local `anvil` commands accept a signer via `--private-key <key>` or `--unlocked --from <address>` (anvil's default dev accounts are pre-funded and unlocked); live commands typically use `--account <name>` with a key imported via `cast wallet import`.

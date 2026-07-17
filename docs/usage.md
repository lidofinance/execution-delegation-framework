# Usage Guide

This guide walks through deploying your own `DelegationContract` via the already-deployed `DelegationFactory`, and managing that contract afterwards, using the `just` CLI. See the [Deployed Instances](../README.md#deployed-instances) table for the factory address on each network. To deploy the factory itself, see the [Development Guide](development.md) instead.

## Prerequisites

- [Foundry](https://getfoundry.sh/) (`forge`/`cast`) and [`just`](https://github.com/casey/just) installed
- `jq` on your `PATH` — required by the `deploy-delegate`/`deploy-delegate-live` commands, which read the factory address from the deploy artifact JSON

## 1. Configure Environment

Copy `.env.example` to `.env` and fill in the values:

```bash
cp .env.example .env
```

Create an account for deployment:

```bash
cast wallet import --interactive Owner
```

## 2. Deploy DelegationContract

Look up the `DelegationFactory` address for your network from the [Deployed Instances](../README.md#deployed-instances) table, then deploy your own `DelegationContract` through it:

```bash
just deploy-delegate-live <owner> <delegate> <cooldown> --account Owner
```

`deploy-delegate-live` reads the factory address from the local deploy artifact (`artifacts/latest/deploy-<chain>.json`), written when the factory itself was deployed.

## 3. Manage Delegation

Via `just` (owner-only commands need `--account Owner`; view commands need no signer):

| Command                                                   | Description                                           | Who can call |
|-----------------------------------------------------------|-------------------------------------------------------|--------------|
| `just assign-delegate-live <contract> <newDelegate>`      | Schedule a new delegate, effective after the cooldown | Owner only   |
| `just revoke-delegate-live <contract>`                    | Remove delegate access immediately                    | Owner only   |
| `just terminate-live <contract>`                          | Irreversibly disable the contract (owner compromise)  | Owner only   |
| `just get-owner <contract> --rpc-url $RPC_URL`            | View the owner address                                | Anyone       |
| `just get-delegate <contract> --rpc-url $RPC_URL`         | View the currently effective delegate                 | Anyone       |
| `just get-pending-delegate <contract> --rpc-url $RPC_URL` | View the scheduled delegate and its activation time   | Anyone       |
| `just get-cooldown <contract> --rpc-url $RPC_URL`         | View the reassignment cooldown, in seconds            | Anyone       |
| `just is-terminated <contract> --rpc-url $RPC_URL`        | View whether the contract has been terminated         | Anyone       |

Local `anvil` testing uses the same commands without the `-live` suffix (`assign-delegate`, `revoke-delegate`, `terminate`, `deploy-delegate`), defaulting to the local anvil RPC URL instead of `$RPC_URL`.

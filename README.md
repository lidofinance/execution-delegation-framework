# <img src="docs/_logo.svg" height="70px" align="center" alt="Lido Logo"/> Execution Delegation Framework

Fast and safe execution delegation framework for permissioned entities.

## Overview

Permissioned protocol operators (oracles, guardians, keepers, and similar off-chain bots) typically hold on-chain permissions directly on a **hot private key** stored on the machine running their bot. A compromise, personnel change, or even routine rotation then requires going through the protocol's full permission-update process (e.g. a governance vote), which can take days — leaving the protocol exposed in the meantime.

The **Execution Delegation Framework (EDF)** removes hot keys from that critical path: the protocol grants permissions to a per-entity **Delegation Contract** (deployed from a factory) instead of to the hot key directly. The organization operating the bot controls that contract and can rotate, revoke, or — in an emergency — permanently disable its hot key instantly, with no governance vote required.

This repository implements the EDF as specified in [LIP-37](https://github.com/lidofinance/lido-improvement-proposals/blob/master/LIPS/lip-37.md).

## Key Principles

1. **Hot keys no longer hold protocol power directly**
   - Hot keys only act as _delegates_
   - All authority is mediated by the on-chain delegation contract
2. **Owner controls delegation**
   - Each delegation contract has an Owner, fixed at deployment
   - Owner can assign or revoke the delegate; reassignment is cooldown-gated, revocation is immediate
   - Owner can irreversibly `terminate()` the contract if the owner itself is suspected compromised
3. **Protocol trusts Delegation contracts**
   - Delegation contracts can have only one owner and one active delegate
   - The owner can never `execute()` or sign on the contract's behalf
   - Core contracts can validate signed messages in the delegation contracts via ERC-1271
4. **Factory-based deployment**
   - A factory contract deploys a standardized delegation contract
   - Delegation Layer should be used for any permissioned bot

## Deployed Instances

| Network | DelegationFactory Address |
| ------- | ------------------------- |
| Mainnet | _Not yet deployed_        |
| Hoodi   | _Not yet deployed_        |

## Documentation

- [Architecture](docs/architecture.md) — the `DelegationFactory`/`DelegationContract` design and how delegation, rotation, and termination work
- [Usage Guide](docs/usage.md) — deploying the `DelegationFactory`, deploying a `DelegationContract` through it, and managing delegation (assign/revoke/terminate/views) via the `just` CLI or manually through Etherscan
- [Development Guide](docs/development.md) — deploying/verifying the `DelegationFactory` itself and a full reference of every `just` command in this repo

# License

2026 Lido <info@lido.fi>

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, version 3 of the License, or any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the [GNU General Public License](LICENSE)
along with this program. If not, see <https://www.gnu.org/licenses/>.

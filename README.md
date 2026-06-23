# <img src="docs/logo.svg" height="70px" align="center" alt="Lido Logo"/> Delegation Execution Authority

Fast and safe hot-key rotation for Lido Oracles and other permissioned operators.

## Context

At present, **Oracle Holders** and **Council Holders** in the Lido protocol rely on **hot private keys** stored directly inside their off-chain bots/daemons.

- **Oracles** use hot keys to sign and submit on-chain transactions - reports for protocol.
- **Councils** use hot keys to sign pause and unvet transactions or sign deposit messages consumed by depositor bot.

These hot keys:

- Are accessible to multiple people and systems
- Hold meaningful protocol permissions
- In some cases are very old

Key management issues:

- **Security risk**: if a hot key is compromised, an attacker can act with the permissions of an Oracle or Council Holder.
- **Operational risk**: hot-key rotation requires on-chain governance voting, which takes ~10 days.
- **Personnel risk**: when responsibility changes, there is no guarantee that the previous maintainer has not retained a copy of the hot key.

As a result, the protocol is exposed during the entire governance delay window, and rapid response to incidents is not possible.

## Solution

Introduce a **Delegation Layer** for permissioned entities.

Instead of governance granting protocol permissions directly to a hot EOA key, governance grants permissions to a **per-entity Delegation Contract** (deployed from a factory). The organization operating the bot controls that contract (via cold key or multisig) and can **rotate** hot keys instantly.

This model assumes that each permissioned entity (oracle/council operator) is a real-world organization and that ownership/authority over Admin keys is verified via the protocol's existing social/governance processes (e.g., forum announcements, established channels).

## Key Principles

1. **Hot keys no longer hold protocol power directly**
    - Hot keys only act as *delegatees*
    - All authority is mediated by the on-chain delegation contract
2. **Admin controls delegation**
    - Each delegation contract has an Admin
    - Admin is a cold key or multisig
    - Admin can assign or revoke hot keys instantly
3. **Protocol trusts Delegation contracts**
    - Delegation contracts can have only one admin and one delegatee
    - Core contracts can validate signed messages in the delegation contracts
4. **Factory-based deployment**
    - A factory contract deploys a standardized delegation contract
    - Delegation Layer should be used for any permissioned bot

## Architecture

The system consists of two contracts:

### DelegationFactory

A factory contract that deploys new `DelegationContract` instances. Each permissioned entity gets its own delegation contract.

### DelegationContract

A per-entity contract that:

- Has an **Admin** (cold key/multisig) who controls the contract
- Has a **Delegatee** (hot key) who can execute transactions through the contract
- Implements **EIP-1271** for signature validation
- Provides an `execute()` function for the delegatee to call external contracts

## How It Works

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              SETUP (one-time)                               │
├─────────────────────────────────────────────────────────────────────────────┤
│  1. Admin deploys DelegationContract via DelegationFactory                  │
│  2. Governance grants protocol permissions to DelegationContract address    │
│  3. Admin assigns hot key as delegatee                                      │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                            NORMAL OPERATION                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   Hot Key (Delegatee)                                                       │
│         │                                                                   │
│         │ execute(target, calldata)                                         │
│         ▼                                                                   │
│   ┌─────────────────────┐                                                   │
│   │ DelegationContract  │                                                   │
│   │   (has permissions) │                                                   │
│   └──────────┬──────────┘                                                   │
│              │                                                              │
│              │ call (msg.sender = DelegationContract)                       │
│              ▼                                                              │
│   ┌─────────────────────┐                                                   │
│   │   Target Contract   │                                                   │
│   │ (e.g. HashConsensus)│                                                   │
│   └─────────────────────┘                                                   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                            KEY ROTATION                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│  Admin calls assignDelegate(newHotKey) or revokeDelegate()                  │
│  No governance vote required - instant rotation                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Usage

### 1. Configure Environment

Copy `.env.example` to `.env` and fill in the values:

```bash
cp .env.example .env
```

Create account for deploy

```bash
cast wallet import --interactive Deployer
```

### 2. Deploy DelegationFactory

```bash
just deploy-live ----account Deployer
```

### 3. Deploy DelegationContract

Once the factory is deployed, anyone can deploy their own DelegationContract:

1. Go to the DelegationFactory on Etherscan
2. Navigate to **Contract** → **Write Contract**
3. Connect your wallet (this will be the Admin)
4. Call `deployDelegation(admin, delegatee)`:
   - `admin`: Address of the cold key/multisig that will control this delegation
   - `delegatee`: Address of the hot key (or `0x0` to assign later)
5. Confirm the transaction

### 4. Manage Delegation

On Etherscan, go to your DelegationContract → **Write Contract**:

| Function | Description | Who can call |
|----------|-------------|--------------|
| `assignDelegate(address)` | Set or rotate the hot key | Admin only |
| `revokeDelegate()` | Remove delegatee access | Admin only |
| `changeAdmin(address)` | Transfer admin role | Admin only |
| `execute(bytes)` | Execute call through contract | Delegatee only |

### 5. Request Protocol Permissions

After deploying your DelegationContract:

1. Submit a request to Lido governance to grant permissions to your DelegationContract address
2. Once approved, your delegatee can execute permitted operations through the contract

## Development

### Setup

```bash
just deps        # Install dependencies
just deps-dev    # Install development dependencies
```

### Build & Test

```bash
just build        # Compile Solidity contracts
just test-unit    # Run tests
```

### Linting & Formatting

```bash
just lint        # Run linter
just lint-fix    # Run linter and fix formatting issues
```

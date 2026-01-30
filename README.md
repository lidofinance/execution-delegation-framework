# <img src="docs/logo.svg" height="70px" align="center" alt="Lido Logo"/> Delegation Execution Authority

Fast and safe hot-key rotation for Lido Oracles and other permissioned operators.

## Context

At present, **Oracle Holders** and **Council Holders** in the Lido protocol rely on **hot private keys** stored directly inside their off-chain bots/daemons

- **Oracles** use hot keys to sign and submit on-chain transactions - reports for protocol.
- **Councils** use hot keys to sign pause and unvet transactions or sing deposit messages consumed by depositor bot.

These hot keys:

- Are accessable to multiple people and systems
- Hold meaningfull protocol permissions
- In some cases are very old

Key mamagement issues:

- **Security risk**: if a hot key is compromised, an attacker can act with the permissions of an Oracle or Council Holder.
- **Operational risk**: hot-key rotation requires on-chain governance voting, which takes ~10 days.
- **Personnel risk**: when responsibility changes, there is no guarantee that the previous maintainer has not retained a copy of the hot key.

As a result, the protocol is exposed during the entire governance delay window, and rapid response to incidents is not possible.

## Solution

Introduce a **Delegation Layer** for permissioned entities.

Instead of governance granting protocol permissions directly to a hot EOA key, governance grants permissions to a **per-entity Delegation Contract** (deployed from a factory). The organization operating the bot controls that contract (via cold key or multisig) and can **rotate** hot keys instantly.

This model assumes that each permissioned entity (oracle/council operator) is a real-world organization and that ownership/authority over Admin keys is verified via the protocol’s existing social/governance processes (e.g., forum announcements, established channels).

## **Key principles**

1. **Hot keys no longer hold protocol power directly.**
    - Hot keys only act as *delegatees*
    - All authority is mediated by the on-chain delegation contract
2. Admin controls delegation
    - Each delegation contract has an Admin
    - Admin is a cold key or multisig
    - Admin can assign or revoke hot keys instantly
3. Protocol trusts Delegation contracts
    - Delegation contracts could have only one owner and one delegatee.
    - Core contracts can validate signed messages in the delegation contacts.
4. Factory based deployment
    - A factory contract deploys standardized delegation contract
    - Delegation Layer should be used for any permissioned bot

License
- MIT (adjust as appropriate)

# Architecture

The system consists of two contracts:

## DelegationFactory

A factory contract that deploys new `DelegationContract` instances.

## DelegationContract

A per-entity, non-upgradeable contract that:

- Has an **Owner**, fixed for the contract's lifetime, who assigns/revokes the delegate and can `terminate()` the contract
- Has an active **Delegate** who can execute transactions through the contract
- Reassigning the delegate is gated by a constructor-immutable **cooldown**: the previous delegate stays effective until the new one activates, so rotation is seamless; revocation is immediate
- Implements **ERC-1271** for signature validation (pull integration), **ERC-165** interface detection, and **ERC-5313** for the `owner()` view
- Provides an `execute()` function for the delegate to call external contracts (push integration), forwarding `msg.value`.

## How It Works

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              SETUP (one-time)                               │
├─────────────────────────────────────────────────────────────────────────────┤
│  1. Owner deploys DelegationContract via DelegationFactory                  │
│  2. DelegationContract receives protocol permissions                        │
│  3. Owner assigns the delegate (or sets it in the same deployment)          │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                            NORMAL OPERATION                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Push integration (execute):                                                │
│                                                                             │
│   Delegate                                                                  │
│         │                                                                   │
│         │ execute(target, data)                                             │
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
│   │ (e.g. Core Protocol)│                                                   │
│   └─────────────────────┘                                                   │
│                                                                             │
│─────────────────────────────────────────────────────────────────────────────│
│                                                                             │
│  Pull integration (ERC-1271):                                               │
│                                                                             │
│   ┌─────────────────────┐                                                   │
│   │   Target Contract   │                                                   │
│   │ (e.g. Core Protocol)│                                                   │
│   └──────────┬──────────┘                                                   │
│              │                                                              │
│              │ isValidSignature(hash, signature)                            │
│              ▼                                                              │
│   ┌─────────────────────┐                                                   │
│   │ DelegationContract  │                                                   │
│   │   (has permissions) │                                                   │
│   └──────────┬──────────┘                                                   │
│              │                                                              │
│              │ verify signature from delegate                               │
│              ▼                                                              │
│        returns ERC1271_MAGIC_VALUE                                          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                            KEY ROTATION                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│  Owner calls assignDelegate(newDelegate): old delegate stays effective until│
│  the cooldown elapses, then the new delegate takes over seamlessly.         │
│  Owner calls revokeDelegate() to drop a compromised delegate immediately.   │
│  No governance vote required for either action.                             │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                          EMERGENCY TERMINATION                              │
├─────────────────────────────────────────────────────────────────────────────┤
│  If the Owner key itself is suspected compromised, the Owner calls          │
│  terminate(): execute() and delegate reassignment are disabled forever.     │
│  A fresh DelegationContract must then be deployed and the role reassigned.  │
└─────────────────────────────────────────────────────────────────────────────┘
```

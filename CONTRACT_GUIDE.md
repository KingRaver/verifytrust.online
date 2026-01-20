# VerifyTrust Contract Guide

This document describes the **optional Cronos smart contract layer** for VerifyTrust.
The contract is designed to complement x402 payments by providing **on-chain access receipts and enforcement**, while keeping settlement logic off-chain via the Cronos x402 Facilitator.

> **Important:**
> VerifyTrust does *not* require a smart contract to function.
> The contract exists to enable **trust minimization, composability, and protocol-level guarantees**.

---

## Why a Contract Exists

VerifyTrust already settles payments using x402. However, without a contract:

* Access decisions are enforced by the backend
* Payment proofs are interpreted off-chain
* Access rights are not composable across applications

The VerifyTrust contract introduces an **on-chain source of truth** for paid access.

---

## Design Principles

The contract is intentionally:

* **Minimal** — no token custody, no pricing logic
* **Non-upgradeable** — reduces governance and security risk
* **Composable** — readable by any app or indexer
* **Chain-agnostic by pattern** — Cronos today, extensible later

---

## What the Contract Does

The VerifyTrust contract:

* Records successful paid access
* Emits canonical, indexable events
* Optionally tracks time-based access windows
* Enables on-chain access checks

The contract **does not**:

* Collect payments
* Verify signatures
* Replace the x402 facilitator

---

## High-Level Architecture

```text
User Wallet
  └─ x402 Payment (EIP-3009)
       ↓
Cronos x402 Facilitator
  └─ Settlement (ERC-20 transfer)
       ↓
VerifyTrust Backend
  └─ Contract call: recordAccess(...)
       ↓
VerifyTrust Contract
  └─ Emits AccessGranted event
```

---

## Core Contract Responsibilities

### 1. Record Access Grants

Each successful payment results in an on-chain record:

* Who paid
* What resource was accessed
* How long access lasts (optional)

```solidity
mapping(address => mapping(bytes32 => uint256)) public accessExpiry;
```

---

### 2. Emit Canonical Events

Events serve as the primary integration surface:

```solidity
event AccessGranted(
  address indexed buyer,
  bytes32 indexed resourceId,
  uint256 amount,
  uint256 expiresAt,
  bytes32 paymentHash
);
```

These events can be indexed by:

* Frontends
* APIs
* Subgraphs
* Analytics pipelines

---

### 3. Enforce Optional Access Checks

The contract exposes a simple view method:

```solidity
function hasAccess(
  address user,
  bytes32 resourceId
) external view returns (bool);
```

This allows:

* On-chain gating
* Off-chain verification
* Cross-app interoperability

---

## What the Contract Intentionally Avoids

| Feature                | Reason                         |
| ---------------------- | ------------------------------ |
| Token custody          | x402 already settles payments  |
| Price discovery        | Kept off-chain for flexibility |
| Upgradeability         | Reduces attack surface         |
| Signature verification | Handled by the facilitator     |
| User identity          | Wallet address is sufficient   |

---

## Contract Interface (Minimal Example)

```solidity
interface IVerifyTrustAccess {
  function recordAccess(
    address buyer,
    bytes32 resourceId,
    uint256 amount,
    uint256 duration
  ) external;

  function hasAccess(
    address buyer,
    bytes32 resourceId
  ) external view returns (bool);
}
```

---

## Backend Integration

After successful settlement:

1. Backend receives `txHash` from facilitator
2. Backend calls `recordAccess(...)`
3. Contract emits `AccessGranted`
4. Resource becomes accessible

The backend acts as a **relay**, not a trust anchor.

---

## Resource Identification

Resources are identified using deterministic IDs:

```ts
const resourceId = keccak256(
  toUtf8Bytes("verifytrust:premium-data:v1")
);
```

This ensures:

* Collision resistance
* Namespace safety
* Cross-app consistency

---

## Access Models Supported

The contract can support:

* **One-time access**
* **Time-based access**
* **Subscription-style access**
* **Usage-metered access** (optional extension)

Example:

```solidity
accessExpiry[user][resourceId] = block.timestamp + duration;
```

---

## Security Considerations

* Only a trusted backend (or future DAO) may call `recordAccess`
* All state transitions are deterministic and auditable
* No external calls → no reentrancy risk
* No token transfers → minimal economic attack surface

---

## Deployment Notes

* Deploy once per network (Cronos mainnet)
* No upgrades required
* Gas usage is minimal (storage + event emission)
* ABI should be published for third-party integrations

---

## When to Use the Contract

Use the contract if you want to:

* Eliminate backend trust assumptions
* Enable cross-application access verification
* Build a protocol, not just an app
* Support subscriptions or time-based access

Skip the contract if you only need:

* One-off payments
* Server-enforced access
* Fast iteration for demos

---

## Future Extensions (Optional)

* ZK-based access proofs
* DAO-controlled access rules
* Multi-resource bundles
* Cross-chain receipt mirroring

---

## Summary

The VerifyTrust contract is **not required**, but it is **transformative**.

It turns:

* Payments → access rights
* Access rights → on-chain truth
* A product → a protocol

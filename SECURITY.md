# Security Policy

VerifyTrust takes security seriously.
This document outlines our **security practices**, **threat model assumptions**, and **responsible disclosure process**.

---

## Scope

This security policy applies to all VerifyTrust components, including:

* Web application (`verifytrust.online`)
* Backend APIs and infrastructure
* x402 payment integration
* Smart contracts maintained by VerifyTrust
* Public repositories and documentation

---

## Security Model Overview

VerifyTrust is designed around the following principles:

* **Wallet-based authentication**
  Users authenticate via cryptographic wallet signatures—no passwords or accounts are stored.

* **On-chain settlement**
  Payments settle on Cronos mainnet via the x402 protocol and Cronos x402 Facilitator.

* **Minimal trust surface**
  Backend systems act as relayers and verifiers, not custodians of funds.

* **Explicit verification boundaries**
  All critical state transitions are either on-chain or validated against on-chain proofs.

---

## Threat Model Assumptions

VerifyTrust assumes:

* The underlying blockchain (Cronos) provides consensus safety.
* User wallets correctly implement signing standards (EIP-712, EIP-3009).
* The Cronos x402 Facilitator performs correct payment verification and settlement.

VerifyTrust **does not assume**:

* Trusted clients
* Trusted networks
* Persistent user identity beyond wallet ownership

---

## Key Security Considerations

### 1. Wallet & Signature Safety

* VerifyTrust never requests private keys.
* All signatures occur inside user-controlled wallets.
* EIP-712 typed data is used to prevent signature replay across domains.

---

### 2. Payment Integrity (x402)

* All paid requests must include a valid `X-PAYMENT` header.
* Seller APIs validate:

  * Network
  * Asset
  * Recipient address
  * Amount bounds
* Payments are verified and settled via the Cronos x402 Facilitator.

---

### 3. Replay & Double-Spend Prevention

* x402 authorizations include validity constraints.
* Backend logic rejects duplicate or malformed settlement proofs.
* Optional smart contract layer enforces one-time recording via `paymentHash`.

---

### 4. Smart Contract Security

VerifyTrust smart contracts:

* Do not custody tokens
* Do not perform external calls
* Are designed to be minimal and non-upgradeable
* Emit canonical events for auditability

Contracts should be:

* Reviewed internally before deployment
* Audited before production use
* Deployed with verified source code

---

### 5. Backend Security

* All server-side validation is enforced independently of client logic.
* Inputs are sanitized and validated before processing.
* Facilitator responses are logged for audit and forensic analysis.
* Secrets and keys are stored using environment-level protections.

---

### 6. Frontend Security

* Wallet connections are explicitly user-initiated.
* No sensitive data is stored in local storage.
* Cross-site scripting (XSS) and injection risks are mitigated via framework defaults.

---

## Responsible Disclosure

We welcome responsible disclosure of security vulnerabilities.

If you believe you have found a security issue, **do not disclose it publicly**.
Instead, report it directly to us.

### How to Report

* **Email:** [security@verifytrust.online](mailto:security@verifytrust.online)
* **Subject:** `Security Vulnerability Report`

Please include:

* A detailed description of the issue
* Steps to reproduce
* Potential impact
* Any proof-of-concept code (if available)

---

## Response Process

Upon receiving a report, we aim to:

1. Acknowledge receipt within **72 hours**
2. Investigate and validate the issue
3. Develop and deploy a fix
4. Notify the reporter once resolved

We may request additional details during investigation.

---

## Bug Bounties

At this time, VerifyTrust does **not** operate a public bug bounty program.

Researchers who responsibly disclose critical vulnerabilities may be:

* Acknowledged publicly (with permission)
* Considered for future bounty or partnership programs

---

## Security Updates

Security-related updates and advisories will be communicated through:

* Repository releases
* Official documentation updates
* Direct communication with affected partners

---

## Disclaimer

No system is completely secure.
VerifyTrust provides its software and services **“as is”**, without warranty, and users are responsible for understanding the risks associated with blockchain-based systems.

---

## Contact

For security-related concerns only:

**Email:** [security@verifytrust.online](mailto:security@verifytrust.online)
**Website:** [https://www.verifytrust.online](https://www.verifytrust.online)

---

Thank you for helping keep VerifyTrust and its users secure.

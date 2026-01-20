# VerifyTrust Developer Guide

This guide explains how to **run, configure, and extend VerifyTrust** as a developer.
It is intended for contributors, hackathon reviewers, and teams integrating VerifyTrust-style x402 payments into their own applications.

VerifyTrust is a **wallet-first access and payments gateway** for the **Cronos EVM**, powered by the **x402 payment protocol**.

---

## Contents

* Architecture overview
* Local development setup
* Environment configuration
* Core flows (wallet → payment → access)
* Key modules and responsibilities
* Extending VerifyTrust
* Security considerations
* Common pitfalls

---

## Architecture Overview

VerifyTrust consists of three primary layers:

1. **Client (Next.js UI)**
   Handles wallet connection, payment construction, and user flow.

2. **Seller API (Next.js API routes)**
   Publishes payment requirements and settles x402 payments.

3. **x402 Integration Layer**
   Encapsulates Cronos- and x402-specific logic.

```text
Client (Browser)
  └─ Wallet (MetaMask / WalletConnect)
       ↓
VerifyTrust UI
  └─ x402 Envelope Builder
       ↓
Seller API
  └─ Cronos x402 Facilitator
       ↓
Cronos Mainnet
```

---

## Local Development Setup

### Prerequisites

* Node.js (v18+ recommended)
* npm or yarn
* A Cronos-compatible wallet with:

  * CRO for gas
  * A supported stablecoin (e.g. USDC / USDX)

---

### Installation

```bash
git clone <your-repo-url> verifytrust
cd verifytrust
npm install
```

---

### Environment Configuration

Create a `.env.local` file in the project root:

```env
# Cronos RPC
CRONOS_RPC_URL=https://evm.cronos.org/

# Cronos x402 Facilitator
CRONOS_X402_FACILITATOR=https://facilitator.cronoslabs.org/v2/x402

# Seller wallet address
CRONOS_SELLER_ADDRESS=0xYourSellerAddress

# Stablecoin contract address
CRONOS_USD_TOKEN=0xYourStablecoinAddress
```

> These values are exposed to the app via `next.config.js`.

---

### Running the App

```bash
npm run dev
```

Open:
`http://localhost:3000`

---

## Core Application Flow

### 1. Wallet Connection

**Entry point:** `pages/index.tsx`

* Uses `ethers` `BrowserProvider`.
* Supports MetaMask and WalletConnect.
* On success, redirects to:

```
/pay?address=<walletAddress>
```

The wallet address acts as lightweight session context.

---

### 2. Fetching Payment Requirements

**Endpoint:** `/api/payment-requirements`

* Returns seller-defined pricing and payment metadata.
* Uses the x402 “exact” scheme.
* Always includes:

  * Network
  * Token
  * Amount
  * Recipient address

This endpoint is intentionally simple and deterministic.

---

### 3. Building the x402 Payment

**Location:** `pages/pay.tsx`

When the user clicks **Pay**:

1. The UI retrieves a signer from the connected wallet.
2. `buildExactPaymentHeader(...)` is called.
3. The function:

   * Constructs EIP-712 typed data
   * Signs an EIP-3009 `TransferWithAuthorization`
   * Encodes the result as a base64 x402 envelope

The result is sent as an `X-PAYMENT` header.

---

### 4. Payment Verification & Settlement

**Endpoint:** `/api/settle-payment`

* Extracts the `X-PAYMENT` header.
* Calls the Cronos x402 Facilitator:

  * `POST /verify`
  * `POST /settle`
* Returns:

  * `ok` status
  * `txHash`
  * Raw facilitator response (for debugging)

Once settlement succeeds, the resource can be unlocked.

---

## Key Modules

### `lib/x402Cronos.ts`

**Purpose:**
Encapsulates all Cronos- and x402-specific logic.

**Responsibilities:**

* Define “exact” payment requirements
* Build EIP-3009 authorizations
* Construct x402 envelopes
* Call facilitator endpoints

This module is the primary extension point for:

* New chains
* New tokens
* Alternate x402 schemes

---

### API Routes

| File                      | Responsibility                      |
| ------------------------- | ----------------------------------- |
| `payment-requirements.ts` | Seller price definition             |
| `settle-payment.ts`       | Payment verification and settlement |

These routes are intentionally thin and composable.

---

## Extending VerifyTrust

### Adding a New Paid Resource

1. Create a new API route (e.g. `/api/premium-data`).
2. On request:

   * Check for `X-PAYMENT`
   * If missing, return `402` with `paymentRequirements`
3. On successful settlement:

   * Return the protected content

This pattern works for APIs, files, or UI routes.

---

### Supporting a Different Token

To support another ERC-20 stablecoin:

1. Update:

   * Token address
   * Decimals
   * EIP-712 domain values
2. Ensure the token supports EIP-3009 or equivalent authorization.

---

### Adding Testnet Support

* Introduce environment-specific configs:

  * RPC
  * Facilitator
  * Token addresses
* Add a `network` switch in `paymentRequirements`.

---

## Security Considerations

* Always validate:

  * `network`
  * `payTo`
  * `asset`
* Enforce strict amount checks.
* Reject malformed or missing `X-PAYMENT` headers.
* Log facilitator responses for audits.
* Consider replay protection and authorization expiry.

---

## Common Pitfalls

* **Incorrect token decimals**
  Leads to under- or over-payment.

* **Mismatched EIP-712 domain data**
  Causes signature verification failures.

* **Assuming wallet state persists**
  Always re-check signer and chain ID.

* **Skipping server-side validation**
  Never trust client-provided payment metadata.

---

## Development Philosophy

VerifyTrust follows a few guiding principles:

* **Payments are authentication**
  Access is granted because payment is provable.

* **Minimize state**
  Prefer on-chain proof over server-side sessions.

* **Composable by default**
  Every component should be reusable in other x402 integrations.

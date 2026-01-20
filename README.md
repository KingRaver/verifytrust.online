# VerifyTrust

**VerifyTrust** is a wallet-first access and payments gateway built for the **Cronos EVM** and the **x402 payment protocol**.
It enables users to unlock protected resources by completing an on-chain stablecoin payment—without creating traditional accounts, passwords, or emails.

VerifyTrust is designed as a reference implementation of **buyer-side x402 flows on Cronos**, with a minimal seller backend that integrates directly with the **Cronos x402 Facilitator**.

---

## Key Capabilities

* **Wallet-based authentication** using MetaMask or WalletConnect
* **Cronos-native configuration**

  * Chain ID: `25`
  * RPC: `https://evm.cronos.org/`
* **Step-by-step access flow**

  1. Connect wallet
  2. Complete x402 payment
  3. Unlock gated resource
* **Buyer-side x402 “exact” scheme scaffold**

  * Uses EIP-3009 `TransferWithAuthorization`
* **Minimal seller API**

  * Verifies and settles payments via the Cronos x402 Facilitator over HTTPS

---

## System Architecture

### Frontend (Next.js)

| File                 | Description                                                                                                                          |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `pages/index.tsx`    | Landing page. Prompts the user to connect a wallet via MetaMask or WalletConnect and redirects to `/pay` after connection.           |
| `pages/pay.tsx`      | Payment page. Fetches payment requirements, builds an x402 payment header using the connected wallet, and submits it for settlement. |
| `styles/globals.css` | Global styles for the VerifyTrust card UI and animated background.                                                                   |

---

### Backend (Next.js API Routes)

| Endpoint                    | Description                                                                                                                        |
| --------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `/api/payment-requirements` | Returns a JSON object describing the required payment (amount, asset, destination). Acts as the seller “price sheet.”              |
| `/api/settle-payment`       | Accepts an `X-PAYMENT` header, forwards it to the Cronos x402 Facilitator for verification and settlement, and returns the result. |

---

### Shared Library

**`lib/x402Cronos.ts`** provides helpers to:

* Define Cronos-specific “exact” x402 payment requirements
* Construct an x402 envelope
* Sign an EIP-3009 `TransferWithAuthorization` using the user’s wallet
* Verify and settle payments via the Cronos x402 Facilitator

---

## Cronos & x402 Overview

**Cronos** is an EVM-compatible blockchain (chain ID `25`) with a public JSON-RPC endpoint at `https://evm.cronos.org/`.
It supports CRO for gas fees and multiple stablecoins (e.g., USDC, USDX) for dollar-denominated payments.

**x402** is an HTTP-native payment protocol built around the `402 Payment Required` status code.

### Typical x402 Flow

1. Buyer requests a protected resource.
2. Seller responds with `402 Payment Required` and a `paymentRequirements` object.
3. Buyer constructs and signs a payment authorization (e.g., EIP-3009).
4. Buyer retries the request with an `X-PAYMENT` header.
5. Seller verifies and settles the payment, then returns the requested content.

VerifyTrust implements:

* A **buyer UI** that handles wallet connection and x402 payment signing
* A **minimal seller interface** tailored for the Cronos x402 Facilitator

This makes it suitable as a **PayTech Hackathon submission** and as a reusable reference architecture.

---

## Getting Started

### Prerequisites

* Node.js and npm
* A Cronos mainnet wallet with:

  * CRO for gas
  * A supported stablecoin (e.g., USDC or USDX)
* A seller wallet address on Cronos to receive payments

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
# Cronos mainnet RPC
CRONOS_RPC_URL=https://evm.cronos.org/

# Cronos x402 facilitator base URL
CRONOS_X402_FACILITATOR=https://facilitator.cronoslabs.org/v2/x402

# Seller wallet on Cronos
CRONOS_SELLER_ADDRESS=0xYourCronosSellerAddressHere

# Stablecoin contract address on Cronos (USDC / USDX)
CRONOS_USD_TOKEN=0xYourCronosStableTokenAddressHere
```

These values align with Cronos’ recommended public RPC and facilitator endpoints.

> **Note:** `next.config.js` exposes these values to the application at build time.

---

### Running Locally

```bash
npm run dev
# Open http://localhost:3000
```

#### End-to-End Flow

1. Open `/` and connect a wallet configured for Cronos.
2. You are redirected to `/pay`.
3. `/pay` fetches payment requirements from `/api/payment-requirements`.
4. Click **“Pay with Cronos”** to sign and submit an x402 payment.
5. On success, `/api/settle-payment` returns settlement details (including `txHash`).
6. The UI unlocks gated content.

---

## Code Walkthrough

### Wallet Connection (`pages/index.tsx`)

* Uses `ethers` `BrowserProvider` to access MetaMask or WalletConnect.
* Displays a shortened wallet address after connection.
* Redirects to `/pay?address=<walletAddress>` to avoid re-prompting.

---

### Payment Flow (`pages/pay.tsx`)

* Fetches `paymentRequirements` on mount.
* On **“Pay with Cronos”**:

  * Retrieves the wallet signer.
  * Calls `buildExactPaymentHeader({ signer, from, requirements })`, which:

    * Converts human-readable amounts to token units.
    * Constructs EIP-712 typed data for `TransferWithAuthorization`.
    * Signs and encodes the authorization as a base64 x402 envelope.
  * Sends the envelope as an `X-PAYMENT` header to `/api/settle-payment`.

---

### Seller Configuration (`/api/payment-requirements`)

Returns a response such as:

```ts
{
  network: "cronos",
  scheme: "exact",
  payTo: process.env.CRONOS_SELLER_ADDRESS,
  asset: process.env.CRONOS_USD_TOKEN,
  amount: "1.00",
  currency: "USDC",
  description: "VerifyTrust wallet verification access"
}
```

This matches the Cronos “exact” payment scheme and includes the `network` field required by the facilitator.

---

### Payment Settlement (`/api/settle-payment`)

* Expects an `X-PAYMENT` header containing a base64-encoded x402 envelope.
* Calls the Cronos x402 Facilitator:

  1. `/verify` to validate the payment
  2. `/settle` to execute settlement
* Returns:

  * `ok` status
  * `txHash`
  * Raw facilitator responses

---

## Development Notes & TODOs

### Token Integration

* The EIP-3009 typed-data configuration in `lib/x402Cronos.ts` is scaffolding.
* Update:

  * Token name
  * Version
  * Decimals
  * Domain separator
    to match the deployed stablecoin contract.

---

### Security Considerations

* Validate `network`, `payTo`, and `asset` server-side before settlement.
* Enforce strict amount checks to prevent over-payment or malicious headers.
* Consider replay-protection and nonce handling for production use.

---

### Production Deployment

* Deploy the Next.js app to Vercel or a similar platform.
* Use the same environment variables in production.
* Optionally extract seller logic into a standalone backend (Node, FastAPI, etc.) while preserving the x402 interface.

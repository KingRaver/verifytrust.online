# VerifyTrust

VerifyTrust is a wallet‑first access and payments gateway built for the Cronos EVM and the x402 payment protocol. It lets users connect a wallet, complete a stablecoin payment on Cronos, and unlock protected resources without traditional accounts, passwords, or emails.

## Features

- Wallet‑based login with MetaMask or WalletConnect.
- Cronos‑native configuration (chainId 25, `https://evm.cronos.org/` RPC).
- Step‑by‑step flow: connect wallet → pay via x402 → access protected resource.
- Buyer‑side x402 “exact” scheme scaffold using EIP‑3009 authorizations.
- Simple seller API endpoints that talk to the Cronos x402 Facilitator over HTTPS.

***

## Architecture

### Frontend (Next.js)

- `pages/index.tsx`  
  Landing screen; prompts user to connect a wallet via MetaMask or WalletConnect. On successful connection it redirects to `/pay?address=<walletAddress>`.

- `pages/pay.tsx`  
  Payment step. Fetches `paymentRequirements` from the backend, builds an x402 payment header using the connected wallet, and posts it to `/api/settle-payment`.

- `styles/globals.css`  
  Global styling for the VerifyTrust card UI and animated background.

### Backend (Next.js API routes)

- `pages/api/payment-requirements.ts`  
  Returns a JSON `paymentRequirements` object describing how much to pay, which stablecoin to use, and which Cronos address receives funds. This is the seller’s “price sheet”.

- `pages/api/settle-payment.ts`  
  Accepts an `X-PAYMENT` header from the client, forwards it to the Cronos x402 Facilitator `/verify` and `/settle` endpoints, and returns a success response if payment is settled.

### Shared library

- `lib/x402Cronos.ts`  
  Helper functions to:
  - Describe Cronos “exact” payment requirements.
  - Construct the x402 envelope and sign an EIP‑3009 `TransferWithAuthorization` using the user’s wallet.
  - Call the Cronos x402 Facilitator to verify and settle the payment.

***

## Cronos & x402 Background

Cronos is an EVM‑compatible chain (chainId `25`) with a JSON‑RPC endpoint at `https://evm.cronos.org/`, making it straightforward to integrate via ethers.js and MetaMask.  The native token is CRO, while stablecoins such as USDX or USDC are used for dollar‑denominated payments.

x402 is an HTTP‑native payment protocol based on status code 402. A typical flow is:

1. Buyer requests a resource (e.g. `/api/premium-data`).
2. Seller responds with `402 Payment Required` and a `paymentRequirements` object describing amount, token, network, and destination address.
3. Buyer constructs and signs an authorization (e.g. EIP‑3009 on an EVM chain) and encodes it as an `X-PAYMENT` header.
4. Buyer retries the request with `X-PAYMENT`.
5. Seller verifies and settles via a facilitator (Cronos x402 Facilitator), then returns the requested content.

VerifyTrust implements the buyer UI and a minimal seller interface tailored for the Cronos x402 Facilitator so it qualifies for the Cronos x402 PayTech Hackathon.

***

## Getting Started

### Prerequisites

- Node.js and npm installed.
- A Cronos mainnet wallet with some CRO for gas and a supported stablecoin (e.g. USDX/USDC).
- A seller address on Cronos where payments will be received.

### Installation

```bash
git clone <your-repo-url> verifytrust
cd verifytrust
npm install
```

### Environment configuration

Create `.env.local` in the project root:

```env
# Cronos mainnet RPC
CRONOS_RPC_URL=https://evm.cronos.org/

# Cronos x402 facilitator base URL
CRONOS_X402_FACILITATOR=https://facilitator.cronoslabs.org/v2/x402

# Your seller wallet on Cronos (where funds go)
CRONOS_SELLER_ADDRESS=0xYourCronosSellerAddressHere

# Stable token contract on Cronos (e.g. USDX or USDC)
CRONOS_USD_TOKEN=0xYourCronosStableTokenAddressHere
```

These values align with Cronos’ recommended public RPC and facilitator endpoint.

The `next.config.js` file exposes these values to the app at build time.

### Running the app locally

```bash
npm run dev
# open http://localhost:3000
```

Flow:

1. Open `/` and connect your wallet on Cronos.
2. You are redirected to `/pay`.
3. `/pay` fetches `paymentRequirements` from `/api/payment-requirements`.
4. Click “Pay with Cronos” to sign and submit an x402 payment header.
5. On success, `/api/settle-payment` responds with payment details (including `txHash` from the facilitator), and the UI can then unlock gated content.

***

## Code Walkthrough

### Wallet connect (`pages/index.tsx`)

- Uses `ethers` `BrowserProvider` to get a signer from MetaMask or WalletConnect.
- Displays a short address summary after connection.
- Navigates to `/pay?address=<walletAddress>` to avoid re‑prompting for wallet details.

### Payment UI (`pages/pay.tsx`)

- On mount, calls `/api/payment-requirements` to discover what needs to be paid.
- When the user clicks “Pay with Cronos”:
  - Gets the signer from the injected provider.
  - Calls `buildExactPaymentHeader({ signer, from, requirements })`, which:
    - Derives a token amount from the human value.
    - Constructs EIP‑712 typed data for `TransferWithAuthorization` on Cronos.
    - Signs it and returns a base64‑encoded x402 envelope suitable for `X-PAYMENT`.
  - Sends `X-PAYMENT` to `/api/settle-payment`.

### Seller configuration (`pages/api/payment-requirements.ts`)

- Returns an object like:

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

This matches the “exact” payment scheme and includes the `network` field used by the Cronos facilitator to distinguish mainnet from testnet.

### Settlement handler (`pages/api/settle-payment.ts`)

- Expects an `X-PAYMENT` header carrying a base64‑encoded x402 envelope.
- Calls `settleWithCronosFacilitator(x402Header)` from `lib/x402Cronos.ts`, which:
  - POSTs to `https://facilitator.cronoslabs.org/v2/x402/verify` with the payment header and requirements.
  - If valid, POSTs to `.../settle`.
  - Returns `ok`, `txHash`, and raw facilitator responses on success.

***

## Development Notes & TODOs

- **Token details:**  
  The EIP‑3009 representation and `value` calculation in `lib/x402Cronos.ts` are scaffolding. They must be updated to match the actual stablecoin contract on Cronos, including name, version, and decimals.

- **Security considerations:**  
  - Validate `network`, `payTo`, and `asset` on the server before forwarding to the facilitator.
  - Sanity‑check payment amounts to avoid over‑payments or phishing headers.

- **Production deployment:**  
  - Host the Next.js app on a platform like Vercel, using the same `.env` keys.
  - Optionally move seller logic to a dedicated backend (FastAPI, Node, etc.) while keeping the same x402 interface.

***

## Resources

- Cronos docs: `https://docs.cronos.org`
- Cronos x402 Facilitator docs: `https://docs.cronos.org/cronos-x402-facilitator`
- x402 protocol overview: `https://www.x402.org`
- Quickstart for x402 buyers: `https://docs.cronos.org/cronos-x402-facilitator/quick-start-for-buyers`
- Quickstart for x402 sellers (pattern shared across chains): `https://docs.cdp.coinbase.com/x402/docs/welcome`

This README should give collaborators, hackathon judges, and future you enough context to understand how VerifyTrust works end‑to‑end and how it integrates Cronos and x402.


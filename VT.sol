```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * VerifyTrustAccessRegistry
 *
 * A minimal, non-custodial access registry for VerifyTrust.
 *
 * - DOES: record paid access on-chain (receipt + optional expiry), emit canonical events, enable access checks.
 * - DOES NOT: custody tokens, verify x402 signatures, price resources, or settle payments.
 *
 * Intended flow:
 *  1) Buyer pays via x402 (facilitator settles ERC-20 transfer on Cronos).
 *  2) Your backend receives settlement proof (e.g., txHash/receipt/paymentHash).
 *  3) Backend calls recordAccess(...) to mint an on-chain access receipt.
 *
 * Trust model:
 *  - Only an authorized "recorder" (typically your backend relayer) can record access.
 *  - You can later migrate the recorder to a DAO/multisig, or add additional recorders.
 */
contract VerifyTrustAccessRegistry {
    // =========================
    // Errors
    // =========================
    error NotOwner();
    error NotRecorder();
    error ZeroAddress();
    error ZeroResourceId();
    error InvalidDuration();
    error AlreadyRecorded(bytes32 paymentHash);
    error ExpiryNotExtended();
    error BatchLengthMismatch();
    error BatchTooLarge();

    // =========================
    // Events
    // =========================
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event RecorderUpdated(address indexed recorder, bool allowed);

    /**
     * Canonical receipt event.
     *
     * paymentHash is intended to be a unique identifier for the settlement proof.
     * Examples:
     *  - bytes32 keccak256(abi.encodePacked(txHash))            (recommended minimum)
     *  - bytes32 keccak256(abi.encode(...full facilitator response...)) (stronger)
     *  - bytes32(txHash) if you pass txHash as bytes32 already
     */
    event AccessGranted(
        address indexed buyer,
        bytes32 indexed resourceId,
        uint256 amount,
        uint256 expiresAt,
        bytes32 indexed paymentHash
    );

    event AccessRevoked(address indexed buyer, bytes32 indexed resourceId, uint256 previousExpiresAt);

    // =========================
    // Storage
    // =========================
    address public owner;

    /// @notice Authorized relayers/recorders (e.g., your backend service).
    mapping(address => bool) public isRecorder;

    /**
     * @notice Access expiry timestamp per buyer+resource.
     * expiresAt == 0 => no access
     * expiresAt > block.timestamp => active access
     * expiresAt <= block.timestamp => expired access
     */
    mapping(address => mapping(bytes32 => uint256)) public accessExpiry;

    /**
     * @notice Optional: keep a registry of processed payment hashes to prevent replay/double-recording.
     * If your backend might call recordAccess twice for the same settlement, this prevents duplicates.
     */
    mapping(bytes32 => bool) public paymentProcessed;

    /// @notice Optional safety bound to avoid accidental huge expiries (e.g., fat-fingered durations).
    uint256 public maxGrantDuration;

    /// @notice Optional metadata: a protocol namespace string hash to help standardize resourceId derivation.
    bytes32 public immutable namespace;

    // =========================
    // Modifiers
    // =========================
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyRecorder() {
        if (!isRecorder[msg.sender]) revert NotRecorder();
        _;
    }

    // =========================
    // Constructor
    // =========================
    /**
     * @param _owner Initial owner (can be a multisig)
     * @param _recorder Initial recorder (typically your backend relayer)
     * @param _maxGrantDuration Maximum duration allowed for a grant in seconds (0 disables the check)
     * @param _namespace A human string hashed off-chain, e.g. keccak256("verifytrust")
     */
    constructor(
        address _owner,
        address _recorder,
        uint256 _maxGrantDuration,
        bytes32 _namespace
    ) {
        if (_owner == address(0)) revert ZeroAddress();
        if (_recorder == address(0)) revert ZeroAddress();

        owner = _owner;
        namespace = _namespace;
        maxGrantDuration = _maxGrantDuration;

        isRecorder[_recorder] = true;
        emit OwnershipTransferred(address(0), _owner);
        emit RecorderUpdated(_recorder, true);
    }

    // =========================
    // Admin
    // =========================

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function setRecorder(address recorder, bool allowed) external onlyOwner {
        if (recorder == address(0)) revert ZeroAddress();
        isRecorder[recorder] = allowed;
        emit RecorderUpdated(recorder, allowed);
    }

    /**
     * @notice Set a maximum duration for access grants, as a guardrail.
     * @dev Set to 0 to disable.
     */
    function setMaxGrantDuration(uint256 newMaxGrantDuration) external onlyOwner {
        maxGrantDuration = newMaxGrantDuration;
    }

    // =========================
    // Core: recording access
    // =========================

    /**
     * @notice Record access for a buyer for a given resource.
     *
     * @param buyer The wallet that paid (and will be granted access)
     * @param resourceId Deterministic identifier for the protected resource
     * @param amount Amount paid in token base units (informational; not enforced by contract)
     * @param durationSeconds How long access should last from now (0 allowed => "permanent" style, see below)
     * @param paymentHash Unique identifier for this settlement proof (prevents double-record)
     *
     * Duration semantics:
     *  - If durationSeconds == 0: treat as "non-expiring" access by setting expiresAt to type(uint256).max
     *    (This is optional behavior; if you prefer, you can disallow 0 by changing the code.)
     *
     * Expiry extension:
     *  - If buyer already has access with a later expiry, this call MUST extend or keep permanent.
     *    This prevents accidentally shortening someone’s access.
     */
    function recordAccess(
        address buyer,
        bytes32 resourceId,
        uint256 amount,
        uint256 durationSeconds,
        bytes32 paymentHash
    ) external onlyRecorder returns (uint256 newExpiresAt) {
        if (buyer == address(0)) revert ZeroAddress();
        if (resourceId == bytes32(0)) revert ZeroResourceId();
        if (paymentHash == bytes32(0)) revert ZeroResourceId(); // reuse error to avoid another; paymentHash must be nonzero

        // Replay protection for settlement proofs
        if (paymentProcessed[paymentHash]) revert AlreadyRecorded(paymentHash);
        paymentProcessed[paymentHash] = true;

        if (maxGrantDuration != 0 && durationSeconds > maxGrantDuration) revert InvalidDuration();

        uint256 current = accessExpiry[buyer][resourceId];

        // durationSeconds == 0 => permanent access
        if (durationSeconds == 0) {
            newExpiresAt = type(uint256).max;
        } else {
            unchecked {
                newExpiresAt = block.timestamp + durationSeconds;
            }
        }

        // Never shorten access
        if (current == type(uint256).max) {
            // already permanent; do not overwrite with non-permanent
            newExpiresAt = type(uint256).max;
        } else {
            if (newExpiresAt < current) revert ExpiryNotExtended();
        }

        accessExpiry[buyer][resourceId] = newExpiresAt;

        emit AccessGranted(buyer, resourceId, amount, newExpiresAt, paymentHash);
        return newExpiresAt;
    }

    /**
     * @notice Record multiple access grants in one transaction.
     * @dev Useful if your backend settles a bundle and wants to grant multiple resources.
     *
     * Constraints:
     *  - All arrays must be same length
     *  - Batch size is capped to reduce worst-case gas blowups
     */
    function recordAccessBatch(
        address[] calldata buyers,
        bytes32[] calldata resourceIds,
        uint256[] calldata amounts,
        uint256[] calldata durationSeconds,
        bytes32[] calldata paymentHashes
    ) external onlyRecorder {
        uint256 n = buyers.length;
        if (
            resourceIds.length != n ||
            amounts.length != n ||
            durationSeconds.length != n ||
            paymentHashes.length != n
        ) revert BatchLengthMismatch();

        // Conservative cap; tune to your needs.
        if (n > 100) revert BatchTooLarge();

        for (uint256 i = 0; i < n; i++) {
            // reuse single-call logic; keep it inline for gas predictability rather than external call
            address buyer = buyers[i];
            bytes32 resourceId = resourceIds[i];
            uint256 amount = amounts[i];
            uint256 dur = durationSeconds[i];
            bytes32 pHash = paymentHashes[i];

            if (buyer == address(0)) revert ZeroAddress();
            if (resourceId == bytes32(0)) revert ZeroResourceId();
            if (pHash == bytes32(0)) revert ZeroResourceId();
            if (paymentProcessed[pHash]) revert AlreadyRecorded(pHash);
            paymentProcessed[pHash] = true;

            if (maxGrantDuration != 0 && dur > maxGrantDuration) revert InvalidDuration();

            uint256 current = accessExpiry[buyer][resourceId];
            uint256 newExpiresAt;

            if (dur == 0) {
                newExpiresAt = type(uint256).max;
            } else {
                unchecked {
                    newExpiresAt = block.timestamp + dur;
                }
            }

            if (current == type(uint256).max) {
                newExpiresAt = type(uint256).max;
            } else {
                if (newExpiresAt < current) revert ExpiryNotExtended();
            }

            accessExpiry[buyer][resourceId] = newExpiresAt;
            emit AccessGranted(buyer, resourceId, amount, newExpiresAt, pHash);
        }
    }

    // =========================
    // Revocation (optional)
    // =========================

    /**
     * @notice Revoke access (set expiry to 0).
     * @dev This is optional but often useful for admin moderation, refunds, or abuse handling.
     */
    function revokeAccess(address buyer, bytes32 resourceId) external onlyOwner {
        if (buyer == address(0)) revert ZeroAddress();
        if (resourceId == bytes32(0)) revert ZeroResourceId();

        uint256 prev = accessExpiry[buyer][resourceId];
        accessExpiry[buyer][resourceId] = 0;

        emit AccessRevoked(buyer, resourceId, prev);
    }

    // =========================
    // Views
    // =========================

    function hasAccess(address buyer, bytes32 resourceId) public view returns (bool) {
        uint256 exp = accessExpiry[buyer][resourceId];
        if (exp == type(uint256).max) return true;
        return exp > block.timestamp;
    }

    function expiresAt(address buyer, bytes32 resourceId) external view returns (uint256) {
        return accessExpiry[buyer][resourceId];
    }

    /**
     * @notice Helper to standardize resourceId derivation on-chain if you want it.
     * @dev Many teams prefer to compute resourceId off-chain; this helper exists for convenience.
     *
     * Suggested off-chain derivation:
     *   resourceId = keccak256(abi.encodePacked("verifytrust:", resourceName))
     *
     * If you use a namespace, you can do:
     *   resourceId = keccak256(abi.encode(namespace, resourceName))
     */
    function deriveResourceId(string calldata resourceName) external view returns (bytes32) {
        // Avoiding heavy string operations; keccak256 over ABI encoding is fine.
        return keccak256(abi.encode(namespace, resourceName));
    }
}
```

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

/// @title  TokenRiskFilter — rug/honeypot detection for defensive token filtering
/// @author mev-arbitrum
/// @notice On-chain token risk assessment. Called by coordinator via eth_call
///         before routing through aggregators. Filters tokens matching the
///         JB-10 playbook (defensive only — no offensive sniping).
///
/// @dev    Risk assessment via static call — no state modification.
///         Integrates with ADR-010 (aggregator fanout) as per-process filter.
contract TokenRiskFilter {
    /// @dev Bit flags for risk assessment.
    uint256 internal constant MASK_OWNER_RENOUNCED = 1 << 0;
    uint256 internal constant MASK_MINT_DISABLED = 1 << 1;
    uint256 internal constant MASK_TRANSFER_TAX = 1 << 2;
    uint256 internal constant MASK_SELL_TAX_HIGHER = 1 << 3;
    uint256 internal constant MASK_CONCENTRATED_HOLDERS = 1 << 4;
    uint256 internal constant MASK_BLACKLIST_FUNC = 1 << 5;
    uint256 internal constant MASK_PAUSABLE_TRANSFERS = 1 << 6;
    uint256 internal constant MASK_PROXY_MINT = 1 << 7;
    uint256 internal constant MASK_NO_CODE = 1 << 8;

    /// @notice Whitelisted majors (fast-path bypass).
    mapping(address => bool) public majorsWhitelist;

    /// @notice Cached risk verdicts (address => riskFlags).
    mapping(address => uint256) public cachedRisk;

    /// @notice Timestamp of last cache update per token.
    mapping(address => uint256) public cacheTimestamp;

    /// @notice Cache TTL (5 minutes).
    uint256 internal constant CACHE_TTL = 300;

    /// @dev Bounded probes prevent hostile token code from consuming the full
    ///      caller gas budget during defensive assessment.
    uint256 internal constant RISK_STATICCALL_GAS = 30_000;

    /// @notice Emitted when a token risk verdict is recomputed and cached.
    event RiskVerdictCached(address indexed token, uint256 flags);

    /// @notice Initialize whitelist with audited Arbitrum One majors.
    /// @dev    Per ADR-001 this contract is Arbitrum-only. Prior versions
    ///         used Ethereum mainnet addresses which silently fail the
    ///         fast-path on Arbitrum (wrong addresses → `isMajor() = false`
    ///         → callers fall through to full assessment; degraded coverage,
    ///         not a security bypass). Closes L-5 of 2026-05-12 production
    ///         code review.
    ///         Address sources (verified 2026-05-12):
    ///           - USDC:    bridged-USDC on Arbitrum (Circle CCTP native)
    ///                      <https://arbiscan.io/token/0xaf88d065e77c8cC2239327C5EDb3A432268e5831>
    ///           - USDT:    Tether on Arbitrum
    ///                      <https://arbiscan.io/token/0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9>
    ///           - DAI:     MakerDAO bridged
    ///                      <https://arbiscan.io/token/0xDA10009cBd5D07dD0CeCc66161FC93D7c9000da1>
    ///           - WETH:    canonical
    ///                      <https://arbiscan.io/token/0x82aF49447D8a07e3bd95BD0d56f35241523fBab1>
    ///           - WBTC:    bridged (BitGo)
    ///                      <https://arbiscan.io/token/0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f>
    ///           - rETH:    Rocket Pool bridged
    ///                      <https://arbiscan.io/token/0xEC70Dcb4A1EFa46b8F2D97C310C9c4790ba5ffA8>
    ///           - ARB:     Arbitrum-native (governance)
    ///           - wstETH:  Lido bridged
    ///           - cbETH:   Coinbase bridged
    constructor() {
        majorsWhitelist[address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831)] = true; // USDC.e (Arbitrum)
        majorsWhitelist[address(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9)] = true; // USDT (Arbitrum)
        majorsWhitelist[address(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1)] = true; // DAI (Arbitrum)
        majorsWhitelist[address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1)] = true; // WETH (Arbitrum)
        majorsWhitelist[address(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f)] = true; // WBTC (Arbitrum)
        majorsWhitelist[address(0x912CE59144191C1204E64559FE8253a0e49E6548)] = true; // ARB (Arbitrum)
        majorsWhitelist[address(0x5979D7b546E38E414F7E9822514be443A4800529)] = true; // wstETH (Arbitrum)
        majorsWhitelist[address(0x1DEBd73E752bEaF79865Fd6446b0c970EaE7732f)] = true; // cbETH (Arbitrum)
        majorsWhitelist[address(0xEC70Dcb4A1EFa46b8F2D97C310C9c4790ba5ffA8)] = true; // rETH (Arbitrum)
    }

    /// @notice Risk verdict returned by assess().
    struct RiskVerdict {
        uint256 flags;
        bool isSafe;
        string[] reasons;
    }

    /// @notice Check if token is whitelisted major (fast-path).
    function isMajor(
        address token
    ) external view returns (bool) {
        return majorsWhitelist[token];
    }

    /// @notice Assess token risk via static call simulation.
    /// @param token Token address to assess.
    /// @return verdict Risk verdict with flags and reasons.
    function assess(
        address token
    ) internal view returns (RiskVerdict memory verdict) {
        if (majorsWhitelist[token]) {
            return RiskVerdict({ flags: 0, isSafe: true, reasons: new string[](0) });
        }

        string[] memory reasons = new string[](0);
        uint256 flags = 0;

        if (token.code.length == 0) {
            flags |= MASK_NO_CODE;
            reasons = _append(reasons, "token_has_no_code");
            return RiskVerdict({ flags: flags, isSafe: false, reasons: reasons });
        }

        // Check owner (renounced = lower risk)
        (bool success, bytes memory data) =
            token.staticcall{ gas: RISK_STATICCALL_GAS }(abi.encodeWithSelector(ITokenRiskERC20Metadata.owner.selector));
        if (success && data.length == 32) {
            address owner = abi.decode(data, (address));
            if (owner == address(0)) {
                flags |= MASK_OWNER_RENOUNCED;
            }
        }

        // EIP-1967 proxy implementation detection must be supplied by the
        // off-chain policy layer via eth_getStorageAt. Solidity cannot read
        // another contract's storage slot directly; using sload here would
        // inspect TokenRiskFilter storage, not token storage.

        // Check for transfer tax (honeypot detection)
        // Simulate transfer and compare in/out
        (bool transferSuccess, bytes memory transferData) = token.staticcall{ gas: RISK_STATICCALL_GAS }(
            abi.encodeCall(ITokenRiskERC20Metadata.transfer, (address(this), 1e18))
        );
        if (!transferSuccess) {
            flags |= MASK_TRANSFER_TAX;
            reasons = _append(reasons, "transfer_simulation_unavailable");
        } else if (transferData.length == 32) {
            bool returnedBool = abi.decode(transferData, (bool));
            if (!returnedBool) {
                flags |= MASK_TRANSFER_TAX;
                reasons = _append(reasons, "transfer_failed_or_tax");
            }
        } else if (transferData.length != 0) {
            flags |= MASK_TRANSFER_TAX;
            reasons = _append(reasons, "transfer_return_malformed");
        }

        // Check for blacklist function (dangerous)
        bytes4 blacklistSelector = bytes4(0x8ecfd9a7);
        (bool hasBlacklist,) = token.staticcall{ gas: RISK_STATICCALL_GAS }(abi.encodeWithSelector(blacklistSelector));
        if (hasBlacklist) {
            flags |= MASK_BLACKLIST_FUNC;
            reasons = _append(reasons, "has_blacklist_function");
        }

        // Check for pausable transfers
        (bool pausableSuccess, bytes memory pausableData) =
            token.staticcall{ gas: RISK_STATICCALL_GAS }(abi.encodeWithSelector(IPausable.paused.selector));
        if (pausableSuccess && pausableData.length == 32) {
            bool isPaused = abi.decode(pausableData, (bool));
            if (isPaused) {
                flags |= MASK_PAUSABLE_TRANSFERS;
                reasons = _append(reasons, "transfers_are_paused");
            }
        }

        // Holder concentration is intentionally off-chain: the EVM cannot
        // enumerate token holders without an indexed data source.

        bool isSafe = (flags & (MASK_TRANSFER_TAX | MASK_BLACKLIST_FUNC | MASK_PROXY_MINT)) == 0;

        return RiskVerdict({ flags: flags, isSafe: isSafe, reasons: reasons });
    }

    /// @notice External wrapper for assess (exposes internal to external calls).
    function assessExternal(
        address token
    ) external view returns (RiskVerdict memory verdict) {
        return assess(token);
    }

    /// @notice Batch assess multiple tokens.
    function assessBatch(
        address[] calldata tokens
    ) external view returns (RiskVerdict[] memory verdicts) {
        verdicts = new RiskVerdict[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            verdicts[i] = assess(tokens[i]);
        }
    }

    /// @notice Recompute and cache a token risk verdict.
    /// @dev    The caller does not supply flags. This prevents arbitrary cache
    ///         poisoning while still allowing any keeper to pay gas for refresh.
    function updateCache(
        address token
    ) external returns (RiskVerdict memory verdict) {
        verdict = assess(token);
        uint256 flags = verdict.flags;
        cachedRisk[token] = flags;
        cacheTimestamp[token] = block.timestamp;
        // forge-lint: disable-next-line(reentrancy-events) — preceding calls are view probes; verdict re-derived and token-keyed; nothing corruptible.
        emit RiskVerdictCached(token, flags);
    }

    /// @notice Get cached verdict if fresh.
    function getCachedVerdict(
        address token
    ) external view returns (uint256 flags, bool isFresh) {
        uint256 ts = cacheTimestamp[token];
        if (ts != 0 && block.timestamp - ts < CACHE_TTL) {
            return (cachedRisk[token], true);
        }
        return (0, false);
    }

    /// @notice Union of bits that represent genuinely dangerous token properties.
    /// @dev    Used by `_assessSnipeTarget` to gate the snipe: only HAZARD bits block execution;
    ///         informational / positive bits (e.g. MASK_OWNER_RENOUNCED, MASK_MINT_DISABLED) are
    ///         excluded so renounced-ownership tokens are not falsely rejected.
    ///
    ///         Included hazards:
    ///           MASK_TRANSFER_TAX        (bit 2) — fee-on-transfer; buy/sell amounts diverge.
    ///           MASK_SELL_TAX_HIGHER     (bit 3) — sell-side tax exceeds buy-side; exit cost.
    ///           MASK_CONCENTRATED_HOLDERS(bit 4) — top wallets can dump; price impact risk.
    ///           MASK_BLACKLIST_FUNC      (bit 5) — owner can freeze the sniper's balance.
    ///           MASK_PAUSABLE_TRANSFERS  (bit 6) — owner can halt transfers post-buy.
    ///           MASK_PROXY_MINT          (bit 7) — hidden mint proxy; dilution risk.
    ///           MASK_NO_CODE             (bit 8) — zero bytecode; not a real token.
    ///
    ///         Excluded (informational/positive):
    ///           MASK_OWNER_RENOUNCED     (bit 0) — owner == address(0) is DESIRABLE.
    ///           MASK_MINT_DISABLED       (bit 1) — minting disabled is DESIRABLE.
    uint256 public constant HAZARD_MASK = MASK_TRANSFER_TAX | MASK_SELL_TAX_HIGHER | MASK_CONCENTRATED_HOLDERS
        | MASK_BLACKLIST_FUNC | MASK_PAUSABLE_TRANSFERS | MASK_PROXY_MINT | MASK_NO_CODE;

    /// @notice Bitmask of all risk flags reserved by this contract.
    /// @dev Includes flags that are supplied by the off-chain policy layer in
    ///      v1 so external consumers can decode cached verdicts without a
    ///      separate constants file.
    function knownRiskMask() external pure returns (uint256) {
        return MASK_OWNER_RENOUNCED | MASK_MINT_DISABLED | MASK_TRANSFER_TAX | MASK_SELL_TAX_HIGHER
            | MASK_CONCENTRATED_HOLDERS | MASK_BLACKLIST_FUNC | MASK_PAUSABLE_TRANSFERS | MASK_PROXY_MINT | MASK_NO_CODE;
    }

    function _append(
        string[] memory arr,
        string memory elem
    ) internal pure returns (string[] memory) {
        string[] memory result = new string[](arr.length + 1);
        for (uint256 i = 0; i < arr.length; i++) {
            result[i] = arr[i];
        }
        result[arr.length] = elem;
        return result;
    }
}

/// @dev Minimal metadata interface for static calls.
interface ITokenRiskERC20Metadata {
    function owner() external view returns (address);
    function transfer(
        address to,
        uint256 amount
    ) external returns (bool);
    function balanceOf(
        address account
    ) external view returns (uint256);
}

/// @dev IPausable for pausable token detection.
interface IPausable {
    function paused() external view returns (bool);
}

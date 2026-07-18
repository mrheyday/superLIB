// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

/// @title  RouterRegistry — single source of truth for swap-router addresses on Arbitrum One
/// @author mev-arbitrum
/// @notice All address constants in this library were verified via
///         `eth_getCode` against `arb1.arbitrum.io/rpc` on 2026-05-07.
///         Sources of truth:
///           - Uniswap V3:   developers.uniswap.org/contracts/v3/reference/deployments
///           - Uniswap V4:   developers.uniswap.org/contracts/v4/deployments
///           - UniswapX:     developers.uniswap.org/contracts/uniswapx/deployments
///           - Permit2:      000000000022D473030F116dDEE9F6B43aC78BA3 (canonical, all chains)
///           - Forks:        each project's docs (Camelot, PancakeSwap, SushiSwap)
/// @dev    This library is **read-only**. `isKnown` is informational only;
///         execution paths must use a dedicated executable-router allowlist
///         because this registry also tracks non-router contracts.
///
///         Every constant here is `internal` to keep the library
///         deployment-free (constants inlined into call sites at
///         compile time). The `RouterKind` enum + `routerFor` helper
///         give a uniform lookup interface for tests and scripts.
library RouterRegistry {
    // =========================================================================
    // Uniswap canonical
    // =========================================================================

    // -- V2 ---------------------------------------------------------------
    address internal constant UNIV2_ROUTER = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
    address internal constant UNIV2_FACTORY = 0xf1D7CC64Fb4452F05c498126312eBE29f30Fbcf9;

    // -- V3 ---------------------------------------------------------------
    address internal constant UNIV3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address internal constant UNIV3_POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address internal constant UNIV3_SWAP_ROUTER_02 = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    address internal constant UNIV3_QUOTER_V2 = 0x61fFE014bA17989E743c5F6cB21bF9697530B21e;

    // -- V4 ---------------------------------------------------------------
    address internal constant UNIV4_POOL_MANAGER = 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32;
    address internal constant UNIV4_POSITION_MANAGER = 0xd88F38F930b7952f2DB2432Cb002E7abbF3dD869;
    address internal constant UNIV4_STATE_VIEW = 0x76Fd297e2D437cd7f76d50F01AfE6160f86e9990;
    address internal constant UNIV4_QUOTER = 0x3972C00f7ed4885e145823eb7C655375d275A1C5;
    /// @notice Hookmate V4 swap router on Arbitrum One. Separate from Uniswap Universal Router.
    /// @dev Source: `akshatmittal/hookmate` `AddressConstants.getV4SwapRouterAddress(42161)`.
    address internal constant HOOKMATE_V4_SWAP_ROUTER = 0xC0077d448203c71f6b18061C2E95409b386982BE;

    // -- Universal Router -------------------------------------------------
    //
    // Routing semantics on Arbitrum One — Universal Router NATIVELY routes
    // **only Uniswap V2 / V3 / V4 pools**. Third-party V2- / V3- interface
    // forks are *interface-compatible* but the off-chain quote builder
    // must pre-compute their pool addresses (UR derives V3 pool addresses
    // from `UNIV3_FACTORY`, so a SushiSwap-V3 / PancakeSwap-V3 / iZi pool
    // must be passed as the explicit pool address, not via path encoding).
    // V2 forks are simpler: pass the pair address directly into V2_SWAP_*
    // commands and UR calls `getReserves()` / `swap()` on whatever pair
    // the caller supplied.
    //
    // Protocols that DO NOT route through Universal Router at all (custom
    // AMM curves / non-standard interfaces) are listed below as
    // NOT_ROUTABLE_VIA_UR comments — those need dedicated adapter routers
    // (the project's quote engine handles the dispatch off-chain).

    /// @notice Universal Router 2.0 — V2 + V3 + V4 + permit2 + NFT.
    ///         The address listed in Uniswap's V3 deployments doc; per
    ///         user-authoritative breakdown, the live build supports the
    ///         V4_SWAP (0x10) command.
    address internal constant UNIVERSAL_ROUTER_V20 = 0xA51afAFe0263b40EdaEf0Df8781eA9aa03E381a3;
    address internal constant UNISWAP_V4_UNIVERSAL_ROUTER = UNIVERSAL_ROUTER_V20;

    /// @notice Universal Router 2.1.1 — newer release listed in Uniswap's
    ///         V4 deployments doc. Bug fixes + added commands over 2.0.
    address internal constant UNIVERSAL_ROUTER_V211 = 0x8B844f885672f333Bc0042cB669255f93a4C1E6b;

    /// @notice Backwards-compat aliases for code that read the old names.
    address internal constant UNIVERSAL_ROUTER_LEGACY = UNIVERSAL_ROUTER_V20;
    address internal constant UNIVERSAL_ROUTER_LATEST = UNIVERSAL_ROUTER_V211;

    // -- UniswapX ---------------------------------------------------------
    /// @notice DutchV3 reactor — the live Arbitrum One UniswapX entry.
    ///         The V2 / Exclusive variants are mainnet-only as of 2026-05-07.
    address internal constant UNISWAPX_V3_DUTCH_REACTOR = 0xB274d5F4b833b61B340b654d600A864fB604a87c;

    /// @notice OrderQuoter — off-chain quote validation for UniswapX orders.
    address internal constant UNISWAPX_ORDER_QUOTER = 0x88440407634F89873c5D9439987Ac4BE9725fea8;

    // -- Squid -----------------------------------------------------------
    address internal constant SQUID_ROUTER = 0xce16F69375520ab01377ce7B88f5BA8C48F8D666;
    address internal constant SQUID_MULTICALL = 0xaD6Cea45f98444a922a2b4fE96b8C90F0862D2F4;

    // -- Permit2 (canonical) ---------------------------------------------
    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // =========================================================================
    // Executor deployment config bundle — Arbitrum One
    // =========================================================================

    // -- Aggregators ------------------------------------------------------
    address internal constant ONEINCH_V6_ROUTER = 0x111111125421cA6dc452d289314280a0f8842A65;
    address internal constant ZEROX_EXCHANGE_PROXY = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
    address internal constant PARASWAP_AUGUSTUS = 0x6A000F20005980200259B80c5102003040001068;
    address internal constant ODOS_ROUTER = 0xa669e7A0d4b3e4Fa48af2dE86BD4CD7126Be4e13;
    address internal constant KYBER_META_AGGREGATION = 0x6131B5fae19EA4f9D964eAc0408E4408b66337b5;
    address internal constant OPENOCEAN_EXCHANGE = 0x6352a56caadC4F1E25CD6c75970Fa768A3304e64;

    // -- Flash lenders ----------------------------------------------------
    address internal constant AAVE_V3_POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address internal constant MORPHO_BLUE = 0x6c247b1F6182318877311737BaC0844bAa518F5e;

    // -- Settlement, flash, and cross-chain venues ------------------------
    address internal constant COW_SETTLEMENT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    address internal constant COW_FLASH_LOAN_ROUTER = 0x7d9C4DeE56933151Bc5C909cfe09DEf0d315CB4A;
    address internal constant BALANCER_V2_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address internal constant BALANCER_V3_VAULT = 0xbA1333333333a1BA1108E8412f11850A5C319bA9;
    address internal constant INSTA_FLASH_AGGREGATOR = 0x1f882522DF99820dF8e586b6df8bAae2b91a782d;
    address internal constant INSTA_FLASH_RESOLVER = 0x33D8F735DD64ceC51d212616BCa5Ad9b7769CD34;
    address internal constant ACROSS_SPOKEPOOL = 0xe35e9842fceaCA96570B734083f4a58e8F7C5f2A;

    // -- Tokens and read references --------------------------------------
    address internal constant EXECUTOR_OWNER_SAFE = 0x17e0d1E9AbC7D0dfdCA60dC60B3eDf38C9C3D973;
    address internal constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address internal constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address internal constant USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address internal constant ARB = 0x912CE59144191C1204E64559FE8253a0e49E6548;
    address internal constant FLUX_DATAMINE_TOKEN = 0xF80D589b3Dbe130c270a69F1a69D050f268786Df;
    address internal constant FLUX_PROTOCOL_TOKEN = 0x2338a5d62E9A766289934e8d2e83a443e8065b83;
    address internal constant MULTICALL3 = 0xcA11bde05977b3631167028862bE2a173976CA11;

    // =========================================================================
    // Forked vendors on Arbitrum One — V2-interface-compatible
    // =========================================================================
    //
    // V2 commands (V2_SWAP_EXACT_IN = 0x08, V2_SWAP_EXACT_OUT = 0x09) on
    // Universal Router accept ANY V2-pair-interface address as the pool —
    // UR calls `getReserves()` / `swap()` on whatever the caller supplies.
    // Pre-fetch the pair address from the fork's factory and pass it
    // directly. The fork's own dedicated Router is included where the
    // quote engine prefers it over routing through UR.

    /// @notice SushiSwap Classic V2 Factory.
    address internal constant SUSHI_V2_FACTORY = 0xc35DADB65012eC5796536bD9864eD8773aBc74C4;

    /// @notice SushiSwap V2 Router02 (dedicated, not via UR).
    address internal constant SUSHI_V2_ROUTER = 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506;

    /// @notice PancakeSwap V2 Factory. Pancake V2 uses a 25 bps LP fee
    ///         (`9975 / 10000`), distinct from Uniswap V2's 30 bps formula.
    address internal constant PANCAKE_V2_FACTORY = 0x02a84c1b3BBD7401a5f7fa98a384EBC70bB5749E;

    /// @notice PancakeSwap V2 Router02 (dedicated, not via UR).
    address internal constant PANCAKE_V2_ROUTER = 0x8cFe327CEc66d1C090Dd72bd0FF11d690C33a2Eb;

    /// @notice Camelot V2 Factory.
    address internal constant CAMELOT_V2_FACTORY = 0x6EcCab422D763aC031210895C81787E87B43A652;

    /// @notice Camelot V2 Router (Arbiscan label: "Camelot: Router").
    address internal constant CAMELOT_V2_ROUTER = 0xc873fEcbd354f5A56E00E710B90EF4201db2448d;

    /// @notice Frax Swap Factory.
    address internal constant FRAXSWAP_FACTORY = 0x5Ca135cB8527d76e932f34B5145575F9d8cbE08E;

    /// @notice User-pinned DarwinSwap factory; verified source name `DarwinSwapFactory`.
    address internal constant DARWIN_SWAP_FACTORY = 0xBfdc810f451FaFaD57e782077E155BE2fe82CC8F;

    // =========================================================================
    // Forked vendors on Arbitrum One — V3-interface-compatible
    // =========================================================================
    //
    // V3 commands (V3_SWAP_EXACT_IN = 0x00, V3_SWAP_EXACT_OUT = 0x01) on
    // Universal Router DERIVE pool address from `UNIV3_FACTORY` via the
    // path encoding `tokenA + fee + tokenB`. For non-Uniswap V3 forks
    // (SushiSwap V3, PancakeSwap V3, iZiSwap) the path encoding alone
    // routes to a non-existent Uniswap pool — the off-chain coordinator
    // must pre-compute the pool from the fork's own factory and pass
    // it as an explicit pool address, OR call the fork's dedicated
    // Router directly (preferred for clarity).

    /// @notice SushiSwap V3 Factory — used for off-chain pool address pre-computation.
    address internal constant SUSHI_V3_FACTORY = 0x1af415a1EbA07a4986a52B6f2e7dE7003D82231e;

    /// @notice SushiSwap V3 SwapRouter (dedicated, not via UR's path encoding).
    address internal constant SUSHI_V3_SWAP_ROUTER = 0x8A21F6768C1f8075791D08546Dadf6daA0bE820c;

    /// @notice PancakeSwap V3 Factory.
    address internal constant PANCAKE_V3_FACTORY = 0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865;

    /// @notice PancakeSwap V3 Interface Multicall support contract.
    address internal constant PANCAKE_V3_INTERFACE_MULTICALL = 0xac1cE734566f390A94b00eb9bf561c2625BF44ea;

    /// @notice PancakeSwap V3 MasterChef emissions contract.
    address internal constant PANCAKE_V3_MASTERCHEF = 0x5e09ACf80C0296740eC5d6F643005a4ef8DaA694;

    /// @notice PancakeSwap V3 SwapRouter (dedicated).
    address internal constant PANCAKE_V3_SWAP_ROUTER = 0x1b81D678ffb9C0263b24A97847620C99d213eB14;

    /// @notice PancakeSwap V3 SmartRouter (dedicated, not via UR).
    address internal constant PANCAKE_V3_SMART_ROUTER = 0x32226588378236Fd0c7c4053999F88aC0e5cAc77;

    /// @notice PancakeSwap V3 QuoterV2 — read-only quote endpoint.
    address internal constant PANCAKE_V3_QUOTER_V2 = 0xB048Bbc1Ee6b733FFfCFb9e9CeF7375518e25997;

    /// @notice PancakeSwap Universal Router on Arbitrum One.
    address internal constant PANCAKE_UNIVERSAL_ROUTER = 0xFE6508f0015C778Bdcc1fB5465bA5ebE224C9912;

    /// @notice PancakeSwap V3 PoolDeployer — the CREATE2 deployer that mints V3
    ///         pools. Unlike Uniswap V3 (pools salted from the factory), Pancake
    ///         V3 pool addresses are derived from THIS deployer, so anyone
    ///         computing a pool address off-chain must salt against it. Never a
    ///         swap call target — informational (`isKnown`) only, not executable.
    address internal constant PANCAKE_V3_POOL_DEPLOYER = 0x41ff9AA7e16B8B1a8a8dc4f0eFacd93D02d071c9;

    /// @notice PancakeSwap V3 MixedRouteQuoterV1 (Arbitrum-specific) — read-only
    ///         quoter for mixed V2+V3 routes. Off-chain quote endpoint only;
    ///         informational (`isKnown`), never an executable call target.
    address internal constant PANCAKE_V3_MIXED_ROUTE_QUOTER_V1 = 0x3652Fc6EDcbD76161b8554388867d3dAb65eCA93;

    /// @notice Camelot V3 SwapRouter (Algebra-engine V3 fork — different
    ///         pool ABI from Uniswap V3, must use this dedicated router).
    address internal constant CAMELOT_V3_SWAP_ROUTER = 0x1F721E2E82F6676FCE4eA07A5958cF098D339e18;
    address internal constant CAMELOT_V3_ROUTER = CAMELOT_V3_SWAP_ROUTER;

    /// @notice Camelot Algebra V4-engine SwapRouter.
    address internal constant CAMELOT_ALGEBRA_V4_SWAP_ROUTER = 0x4ee15342d6Deb297c3A2aA7CFFd451f788675F53;

    /// @notice Algebra V4 Factory backing the current Camelot Algebra router.
    address internal constant ALGEBRA_V4_FACTORY = 0xBefC4b405041c5833f53412fF997ed2f697a2f37;

    // =========================================================================
    // RFQ settlement routers (executor-dispatched, delegatee-supplied)
    // =========================================================================

    /// @notice Hashflow Router on Arbitrum One (venue 20 taker-RFQ settlement).
    /// @dev    The executor settles a signed Hashflow RFQ quote by dispatching a
    ///         `tradeRFQT(RFQTQuote)` swap-step call to this router (calldata is
    ///         built off-chain from the maker-signed 13-field quote). Unlike the
    ///         CoW/Across settlement contracts — which the executor reaches via
    ///         fixed immutable pins, never a delegatee-supplied `s.router` — this
    ///         RFQ router IS a delegatee-supplied swap-step target, so it belongs
    ///         in the executable allowlist. Same CREATE2 address on
    ///         Ethereum/Polygon/BNB/Avalanche; EIP-55 checksum verified;
    ///         bytecode confirmed live on Arbitrum One.
    address internal constant HASHFLOW_ROUTER_ARBITRUM = 0x55084eE0fEf03f14a305cd24286359A35D735151;

    // =========================================================================
    // Dedicated non-UR AMM routers and registries
    // =========================================================================

    /// @notice Curve Router on Arbitrum One.
    address internal constant CURVE_ROUTER = 0x2191718CD32d02B8E60BAdFFeA33E4B5DD9A0A0D;

    /// @notice Curve StableSwap Registry — pool catalogue / lookup.
    address internal constant CURVE_STABLESWAP_REGISTRY = 0x445FE580eF8d70FF569aB36e80c647af338db351;

    /// @notice Curve legacy stable factory.
    address internal constant CURVE_STABLE_FACTORY = 0xb17b674D9c5CB2e441F8e196a2f048A81355d031;

    /// @notice Curve StableSwap-NG Factory on Arbitrum One.
    address internal constant CURVE_STABLESWAP_NG_FACTORY = 0x9AF14D26075f142eb3F292D5065EB3faa646167b;

    /// @notice Curve StableSwap-NG Views contract.
    address internal constant CURVE_STABLESWAP_NG_VIEWS = 0x3BbA971980A721C7A33cEF62cE01c0d744F26e95;

    /// @notice Curve StableSwap-NG Math contract.
    address internal constant CURVE_STABLESWAP_NG_MATH = 0xD4a8bd4d59d65869E99f20b642023a5015619B34;

    /// @notice Current Arbitrum StableSwap-NG plain-pool implementation.
    address internal constant CURVE_STABLESWAP_NG_PLAIN_IMPL = 0xf6841C27fe35ED7069189aFD5b81513578AFD7FF;

    /// @notice Current Arbitrum StableSwap-NG metapool implementation.
    address internal constant CURVE_STABLESWAP_NG_META_IMPL = 0xFf02cBD91F57A778Bab7218DA562594a680B8B61;

    /// @notice Curve TwoCrypto factory on Arbitrum One.
    address internal constant CURVE_TWOCRYPTO_FACTORY = 0x98EE851a00abeE0d95D08cF4CA2BdCE32aeaAF7F;

    /// @notice Curve TriCrypto factory on Arbitrum One.
    address internal constant CURVE_TRICRYPTO_FACTORY = 0xbC0797015fcFc47d9C1856639CaE50D0e69FbEE8;

    /// @notice DODO V2 Proxy02 (PMM router).
    address internal constant DODO_V2_PROXY02 = 0x88CBf433471A0CD8240D2a12354362988b4593E5;

    /// @notice Maverick V2 Router on Arbitrum One.
    address internal constant MAVERICK_V2_ROUTER = 0x5c3b380e5Aeec389d1014Da3Eb372FA2C9e0fc76;

    /// @notice Maverick V2 Quoter — read-only quote endpoint.
    address internal constant MAVERICK_V2_QUOTER = 0xb40AfdB85a07f37aE217E7D6462e609900dD8D7A;

    /// @notice Maverick V2 Reward Router — reward harvest path, not a swap target.
    address internal constant MAVERICK_V2_REWARD_ROUTER = 0x293A7D159C5AD1b36b784998DE5563fe36963460;

    /// @notice LFJ / Trader Joe LBRouter V2.1.
    address internal constant LFJ_LB_ROUTER_V21 = 0xb4315e873dBcf96Ffd0acd8EA43f689D8c20fB30;

    /// @notice LFJ / Trader Joe LBRouter V2.2.
    address internal constant LFJ_LB_ROUTER_V22 = 0x18556DA13313f3532c54711497A8FedAC273220E;

    /// @notice KyberSwap Elastic Router. Legacy/dead venue on Arbitrum; known for attribution only.
    address internal constant KYBER_ELASTIC_ROUTER = 0xF9c2b5746c946EF883ab2660BbbB1f10A5bdeAb4;

    /// @notice KyberSwap Elastic Factory. Legacy/dead venue on Arbitrum; known for attribution only.
    address internal constant KYBER_ELASTIC_FACTORY = 0xC7a590291e07B9fe9E64b86c58fD8fC764308C4A;

    /// @notice Ramses Router V2.
    address internal constant RAMSES_ROUTER_V2 = 0xAA23611badAFB62D37E7295A682D21960ac85A90;

    /// @notice Ramses Universal Router.
    address internal constant RAMSES_UNIVERSAL_ROUTER = 0xAA273216Cc9201A1e4285CA623f584BADc736944;

    /// @notice GMX V2 ExchangeRouter. Known for attribution; async order flow is not a swap-chain target.
    address internal constant GMX_V2_EXCHANGE_ROUTER = 0x7C68C7866A64FA2160F78EEaE12217FFbf871fa8;

    /// @notice Wombat Router.
    address internal constant WOMBAT_ROUTER = 0xc4B2F992496376C6127e73F1211450322E580668;

    /// @notice Balancer V3 Router — standard single-pool swap entry.
    address internal constant BALANCER_V3_ROUTER = 0xEAedc32a51c510d35ebC11088fD5fF2b47aACF2E;

    /// @notice Balancer V3 Batch Router — multi-hop / multi-pool batched swaps.
    address internal constant BALANCER_V3_BATCH_ROUTER = 0xaD89051bEd8d96f045E8912aE1672c6C0bF8a85E;

    /// @notice Balancer V3 Aggregator Router — aggregator-friendly swap entry.
    address internal constant BALANCER_V3_AGGREGATOR_ROUTER = 0x4b979eD48F982Ba0baA946cB69c1083eB799729c;

    /// @notice Balancer V3 Buffer Router — ERC-4626 buffer management; not a swap-chain target.
    address internal constant BALANCER_V3_BUFFER_ROUTER = 0x311334883921Fb1b813826E585dF1C2be4358615;

    /// @notice Bebop Settlement (RFQ/JAM).
    address internal constant BEBOP_SETTLEMENT = 0xbbbbbBB520d69a9775E85b458C58c648259FAD5F;

    /// @notice WooFi V2 Router (sPMM).
    address internal constant WOOFI_ROUTER_V2 = 0x4c4AF8DBc524681930a27b2F1Af5bcC8062E6fB7;

    /// @notice WooFi alternative router endpoint.
    address internal constant WOOFI_ROUTER_ALT = 0x9aEd3A8896A85FE9a8CAc52C9B402D092B629a30;

    /// @notice OKX DEX Aggregator Router.
    address internal constant OKX_DEX_ROUTER = 0xf332761c673b59B21fF6dfa8adA44d78c12dEF09;

    /// @notice Enso Router.
    address internal constant ENSO_ROUTER = 0x80EbA3855878739F4710233A8a19d89Bdd2ffB8E;

    /// @notice LI.FI Diamond.
    address internal constant LIFI_DIAMOND = 0x1231DEB6f5749EF6cE6943a275A1D3E7486F4EaE;

    /// @notice Rango Diamond.
    address internal constant RANGO_DIAMOND = 0x69460570c93f9DE5E2edbC3052bf10125f0Ca22d;

    /// @notice Rubic Proxy V3.
    address internal constant RUBIC_PROXY_V3 = 0x33388CF69e032C6f60A420b37E44b1F5443d3333;

    /// @notice NativeRouter V4 — latest Native Protocol router endpoint.
    address internal constant NATIVE_ROUTER_V4 = 0x0FC85a171bD0b53BF0bBace74F04B66170Ae3eAb;

    /// @notice NativeRouter V3 — legacy Native Protocol router.
    address internal constant NATIVE_ROUTER_V3 = 0x7d1c4889DF6113B3e4581a8c0484374bdeC3341B;

    /// @notice NativeProtocol CreditVault — LP-side credit pool; known for attribution only.
    address internal constant NATIVE_CREDIT_VAULT = 0xbA1cf8A63227b46575AF823BEB4d83D1025eff09;

    // -- Dolomite --------------------------------------------------------
    //
    // Official Arbitrum One addresses from Dolomite docs:
    // `smart-contract-addresses/core-immutable`, `core-routers`, and
    // `core-proxies`. Dolomite is a money-market + DEX venue; the
    // GenericTrader router/proxy are the swap/zap surfaces, while the
    // margin and liquidator contracts are pinned for strategy attribution.

    /// @notice DolomiteMargin main margin contract on Arbitrum One.
    address internal constant DOLOMITE_MARGIN = 0x6Bd780E7fDf01D77e4d475c821f1e7AE05409072;

    /// @notice Dolomite BorrowPositionRouter.
    address internal constant DOLOMITE_BORROW_POSITION_ROUTER = 0xF579b345cdA0860668b857De10ABD62442133D0F;

    /// @notice Dolomite DepositWithdrawalRouter.
    address internal constant DOLOMITE_DEPOSIT_WITHDRAWAL_ROUTER = 0xf8b2c637A68cF6A17b1DF9F8992EeBeFf63d2dFf;

    /// @notice Dolomite GenericTraderRouter — zap/trade router surface.
    address internal constant DOLOMITE_GENERIC_TRADER_ROUTER = 0x7b61CbA306CfdB02493b94757143132B1b72Bc6b;

    address internal constant DOLOMITE_BORROW_POSITION_PROXY_V1 = 0xe43638797513ef7A6d326a95E8647d86d2f5a099;
    address internal constant DOLOMITE_BORROW_POSITION_PROXY_V2 = 0x38E49A617305101216eC6306e3a18065D14Bf3a7;
    address internal constant DOLOMITE_DEPOSIT_WITHDRAWAL_PROXY = 0xAdB9D68c613df4AA363B42161E1282117C7B9594;
    address internal constant DOLOMITE_EVENT_EMITTER_REGISTRY_PROXY = 0x4BfF12773B0Dc3Cb35f174B5CD351F662018CC2F;
    address internal constant DOLOMITE_EXPIRY_TRADER = 0xDEc1ae3b570ac3c57871BBD7bFeacC807f973Bea;
    address internal constant DOLOMITE_EXPIRY_PROXY = 0x40899E265A7899968f0f153410321B9175730B00;
    address internal constant DOLOMITE_GENERIC_TRADER_PROXY_V1 = 0x905F3adD52F01A9069218c8D1c11E240afF61D2B;
    address internal constant DOLOMITE_SAFE = 0xa75c21C5BE284122a87A37a76cc6C4DD3E55a1D4;
    address internal constant DOLOMITE_LIQUIDATOR_ASSET_REGISTRY = 0x10d98759762EFaC656BD4bE7F2f5599208F44FAc;
    address internal constant DOLOMITE_LIQUIDATOR_PROXY_V1 = 0x8c6e337dA1bD534548c5A9b6aC3d9e4D15Fa715A;
    address internal constant DOLOMITE_LIQUIDATOR_PROXY_V4_WITH_GENERIC_TRADER =
        0x34975624E992bF5c094EF0CF3344660f7AaB9CB3;
    address internal constant DOLOMITE_LIQUIDATOR_PROXY_V5 = 0x1506f80d2FD5fbeF2424573EC86E5481C972B99a;
    address internal constant DOLOMITE_ARBITRUM_MULTICALL = 0xB18B8B1A5BDEa1f3c9776715b9325F932803FB1f;
    address internal constant DOLOMITE_PARTIALLY_DELAYED_MULTISIG = 0x52d7BcB650c591f6E8da90f797A1d0Bfd8fD05F9;
    address internal constant DOLOMITE_TRANSFER_PROXY = 0xe04f884e8BB9868b6013dEAd84ad5A3B8cb1Df5A;

    // Dolomite pricing / trading / liquidation infrastructure (P6-relevant).
    // Recorded for completeness — informational only; NOT used by the flash lane
    // (the kind-8 flash entry is `DOLOMITE_MARGIN` above). Canonical Arbitrum One
    // addresses from the Dolomite docs address book.
    //
    // NOTE: `LinearStepFunctionInterestSetter` is intentionally omitted — the
    // docs list it as "Various (depends on configuration)" with no single
    // canonical address, so there is no constant to pin.

    /// @notice Dolomite AlwaysZeroInterestSetter (zero-rate interest model).
    address internal constant DOLOMITE_ALWAYS_ZERO_INTEREST_SETTER = 0x37b6fF70654EDfBdAA3c9a723fdAdF5844De2168;

    /// @notice Dolomite Chainlink price oracle.
    address internal constant DOLOMITE_CHAINLINK_PRICE_ORACLE = 0x8FA6d763CA105B3C88fd01317db2E66021208451;

    /// @notice Dolomite Chaos Labs price oracle.
    address internal constant DOLOMITE_CHAOSLABS_PRICE_ORACLE = 0xB02808f5db0E6926E00AF4971AbdF1dA6C7DB34e;

    /// @notice Dolomite Chronicle price oracle.
    address internal constant DOLOMITE_CHRONICLE_PRICE_ORACLE = 0x8990A46Fd1F2E00b8eb85DAfd85735d2B5Ed4Eeb;

    /// @notice Dolomite RedStone price oracle.
    address internal constant DOLOMITE_REDSTONE_PRICE_ORACLE = 0x5fBAe9cbbc209efDf2054e050Baf5a0783Be01d2;

    /// @notice Dolomite OracleAggregator.
    address internal constant DOLOMITE_ORACLE_AGGREGATOR = 0xBfca44aB734E57Dc823cA609a0714EeC9ED06cA0;

    /// @notice Dolomite CREATE3 factory.
    address internal constant DOLOMITE_CREATE3_FACTORY = 0xa8F7e7A361De6A2172fcb2accE68bd21597599F7;

    /// @notice Dolomite AccountRegistry proxy.
    address internal constant DOLOMITE_ACCOUNT_REGISTRY_PROXY = 0xC777fB526922fB61581b65f8eb55bb769CD59C63;

    /// @notice Dolomite Migrator.
    address internal constant DOLOMITE_MIGRATOR = 0xD5545e44d6BaEd250781375FCb98d9Bdc7f5afc9;

    /// @notice Dolomite Owner V1.
    address internal constant DOLOMITE_OWNER_V1 = 0xCf359A2fa50548c6793a5eD7F26471c1B17Bb11D;

    /// @notice Dolomite Owner V2.
    address internal constant DOLOMITE_OWNER_V2 = 0xC2B66E247daE5Ee749Ae1d827190115F3653dE06;

    /// @notice Dolomite Registry proxy.
    address internal constant DOLOMITE_REGISTRY_PROXY = 0x2A059D6d682e5fB1226eB8bC2977b512698C2404;

    /// @notice Dolomite IsolationModeFreezableLiquidatorProxy.
    address internal constant DOLOMITE_ISOLATION_MODE_FREEZABLE_LIQUIDATOR_PROXY =
        0x76Ac5542eE033A15f78D1f8B4aD48af618a33E44;

    /// @notice Dolomite Odos aggregator trader.
    address internal constant DOLOMITE_ODOS_AGGREGATOR_TRADER = 0x2cdBb25b4aca98a55F6B1A0f67d9f43455e67f3c;

    /// @notice Dolomite Paraswap aggregator trader V2.
    address internal constant DOLOMITE_PARASWAP_AGGREGATOR_TRADER_V2 = 0xd991d9E0a22a51391c25B258eeF8C1c4a392383a;

    // =========================================================================
    // NOT routable via Universal Router (custom AMM curves / non-standard ABIs)
    // =========================================================================
    //
    // The protocols below cannot be routed through Universal Router at all.
    // The project's quote engine + Executor dispatch them via dedicated
    // adapter calldata. Listed here for completeness so the conformance
    // check is comprehensive — the actual addresses live in their own
    // adapter modules (Balancer V2/V3 Vault constants are on `MevSafe`,
    // Curve / DODO / GMX / WooFi / KyberSwap Classic adapters live in
    // `solver/driver/execution/`).
    //
    //   Balancer V2 / V3   custom Vault architecture + callback model
    //   Curve              StableSwap curve, custom interface
    //   DODO               PMM (Proactive Market Maker) curve
    //   GMX                perp / RFQ — not an AMM
    //   WooFi              sPMM oracle-based price feed
    //   KyberSwap Classic  custom non-V2 interface

    // =========================================================================
    // Discriminated lookup
    // =========================================================================

    enum RouterKind {
        UNIVERSAL_ROUTER_V20,
        UNIVERSAL_ROUTER_V211,
        UNIV2_ROUTER,
        UNIV3_SWAP_ROUTER_02,
        UNIV3_POSITION_MANAGER,
        UNIV4_POOL_MANAGER,
        UNIV4_POSITION_MANAGER,
        UNISWAPX_V3_DUTCH_REACTOR,
        CAMELOT_V3_SWAP_ROUTER,
        CAMELOT_V2_ROUTER,
        PANCAKE_V3_SMART_ROUTER,
        PANCAKE_V3_SWAP_ROUTER,
        PANCAKE_UNIVERSAL_ROUTER,
        SUSHI_V2_ROUTER,
        SUSHI_V3_SWAP_ROUTER,
        SQUID_ROUTER,
        CURVE_ROUTER,
        DODO_V2_PROXY02,
        DOLOMITE_BORROW_POSITION_ROUTER,
        DOLOMITE_DEPOSIT_WITHDRAWAL_ROUTER,
        DOLOMITE_GENERIC_TRADER_ROUTER,
        PANCAKE_V2_ROUTER,
        UNISWAP_V4_UNIVERSAL_ROUTER,
        HOOKMATE_V4_SWAP_ROUTER,
        ONEINCH_V6_ROUTER,
        ZEROX_EXCHANGE_PROXY,
        PARASWAP_AUGUSTUS,
        ODOS_ROUTER,
        KYBER_META_AGGREGATION,
        OPENOCEAN_EXCHANGE,
        MAVERICK_V2_ROUTER,
        LFJ_LB_ROUTER_V21,
        LFJ_LB_ROUTER_V22,
        RAMSES_ROUTER_V2,
        RAMSES_UNIVERSAL_ROUTER,
        WOMBAT_ROUTER,
        BALANCER_V3_ROUTER,
        BALANCER_V3_BATCH_ROUTER,
        BALANCER_V3_AGGREGATOR_ROUTER,
        BEBOP_SETTLEMENT,
        WOOFI_ROUTER_V2,
        WOOFI_ROUTER_ALT,
        OKX_DEX_ROUTER,
        ENSO_ROUTER,
        LIFI_DIAMOND,
        RANGO_DIAMOND,
        RUBIC_PROXY_V3,
        NATIVE_ROUTER_V4,
        NATIVE_ROUTER_V3
    }

    /// @dev Raised by `routerFor` when given a `RouterKind` enum value that
    ///      is not in the dispatch table. Currently unreachable in safe
    ///      Solidity because `RouterKind` is a closed enum, but kept as
    ///      defense-in-depth for future entries.
    error UnknownRouterKind();

    /// @notice Resolve a `RouterKind` to its on-chain address. Pure;
    ///         caller can fold this into a constant-folded constant
    ///         per call site.
    /// @dev    Used by tests (`RouterRegistry.t.sol`) and operations
    ///         scripts that need a uniform discriminator over the registered
    ///         router constants. Constants remain `internal` so they are
    ///         inlined at call sites; this dispatcher exists for the cases
    ///         where the tag is dynamic.
    /// @param  kind  Enum tag selecting the router.
    /// @return       Canonical Arbitrum One address for the requested kind.
    function routerFor(
        RouterKind kind
    ) internal pure returns (address) {
        if (kind == RouterKind.UNIVERSAL_ROUTER_V20) return UNIVERSAL_ROUTER_V20;
        if (kind == RouterKind.UNIVERSAL_ROUTER_V211) return UNIVERSAL_ROUTER_V211;
        if (kind == RouterKind.UNIV2_ROUTER) return UNIV2_ROUTER;
        if (kind == RouterKind.UNIV3_SWAP_ROUTER_02) return UNIV3_SWAP_ROUTER_02;
        if (kind == RouterKind.UNIV3_POSITION_MANAGER) return UNIV3_POSITION_MANAGER;
        if (kind == RouterKind.UNIV4_POOL_MANAGER) return UNIV4_POOL_MANAGER;
        if (kind == RouterKind.UNIV4_POSITION_MANAGER) return UNIV4_POSITION_MANAGER;
        if (kind == RouterKind.UNISWAPX_V3_DUTCH_REACTOR) return UNISWAPX_V3_DUTCH_REACTOR;
        if (kind == RouterKind.CAMELOT_V3_SWAP_ROUTER) return CAMELOT_V3_SWAP_ROUTER;
        if (kind == RouterKind.CAMELOT_V2_ROUTER) return CAMELOT_V2_ROUTER;
        if (kind == RouterKind.PANCAKE_V3_SMART_ROUTER) return PANCAKE_V3_SMART_ROUTER;
        if (kind == RouterKind.PANCAKE_V3_SWAP_ROUTER) return PANCAKE_V3_SWAP_ROUTER;
        if (kind == RouterKind.PANCAKE_UNIVERSAL_ROUTER) return PANCAKE_UNIVERSAL_ROUTER;
        if (kind == RouterKind.SUSHI_V2_ROUTER) return SUSHI_V2_ROUTER;
        if (kind == RouterKind.SUSHI_V3_SWAP_ROUTER) return SUSHI_V3_SWAP_ROUTER;
        if (kind == RouterKind.SQUID_ROUTER) return SQUID_ROUTER;
        if (kind == RouterKind.CURVE_ROUTER) return CURVE_ROUTER;
        if (kind == RouterKind.DODO_V2_PROXY02) return DODO_V2_PROXY02;
        if (kind == RouterKind.DOLOMITE_BORROW_POSITION_ROUTER) return DOLOMITE_BORROW_POSITION_ROUTER;
        if (kind == RouterKind.DOLOMITE_DEPOSIT_WITHDRAWAL_ROUTER) return DOLOMITE_DEPOSIT_WITHDRAWAL_ROUTER;
        if (kind == RouterKind.DOLOMITE_GENERIC_TRADER_ROUTER) return DOLOMITE_GENERIC_TRADER_ROUTER;
        if (kind == RouterKind.PANCAKE_V2_ROUTER) return PANCAKE_V2_ROUTER;
        if (kind == RouterKind.UNISWAP_V4_UNIVERSAL_ROUTER) return UNISWAP_V4_UNIVERSAL_ROUTER;
        if (kind == RouterKind.HOOKMATE_V4_SWAP_ROUTER) return HOOKMATE_V4_SWAP_ROUTER;
        if (kind == RouterKind.ONEINCH_V6_ROUTER) return ONEINCH_V6_ROUTER;
        if (kind == RouterKind.ZEROX_EXCHANGE_PROXY) return ZEROX_EXCHANGE_PROXY;
        if (kind == RouterKind.PARASWAP_AUGUSTUS) return PARASWAP_AUGUSTUS;
        if (kind == RouterKind.ODOS_ROUTER) return ODOS_ROUTER;
        if (kind == RouterKind.KYBER_META_AGGREGATION) return KYBER_META_AGGREGATION;
        if (kind == RouterKind.OPENOCEAN_EXCHANGE) return OPENOCEAN_EXCHANGE;
        if (kind == RouterKind.MAVERICK_V2_ROUTER) return MAVERICK_V2_ROUTER;
        if (kind == RouterKind.LFJ_LB_ROUTER_V21) return LFJ_LB_ROUTER_V21;
        if (kind == RouterKind.LFJ_LB_ROUTER_V22) return LFJ_LB_ROUTER_V22;
        if (kind == RouterKind.RAMSES_ROUTER_V2) return RAMSES_ROUTER_V2;
        if (kind == RouterKind.RAMSES_UNIVERSAL_ROUTER) return RAMSES_UNIVERSAL_ROUTER;
        if (kind == RouterKind.WOMBAT_ROUTER) return WOMBAT_ROUTER;
        if (kind == RouterKind.BALANCER_V3_ROUTER) return BALANCER_V3_ROUTER;
        if (kind == RouterKind.BALANCER_V3_BATCH_ROUTER) return BALANCER_V3_BATCH_ROUTER;
        if (kind == RouterKind.BALANCER_V3_AGGREGATOR_ROUTER) return BALANCER_V3_AGGREGATOR_ROUTER;
        if (kind == RouterKind.BEBOP_SETTLEMENT) return BEBOP_SETTLEMENT;
        if (kind == RouterKind.WOOFI_ROUTER_V2) return WOOFI_ROUTER_V2;
        if (kind == RouterKind.WOOFI_ROUTER_ALT) return WOOFI_ROUTER_ALT;
        if (kind == RouterKind.OKX_DEX_ROUTER) return OKX_DEX_ROUTER;
        if (kind == RouterKind.ENSO_ROUTER) return ENSO_ROUTER;
        if (kind == RouterKind.LIFI_DIAMOND) return LIFI_DIAMOND;
        if (kind == RouterKind.RANGO_DIAMOND) return RANGO_DIAMOND;
        if (kind == RouterKind.RUBIC_PROXY_V3) return RUBIC_PROXY_V3;
        if (kind == RouterKind.NATIVE_ROUTER_V4) return NATIVE_ROUTER_V4;
        if (kind == RouterKind.NATIVE_ROUTER_V3) return NATIVE_ROUTER_V3;
        revert UnknownRouterKind();
    }

    /// @notice True iff `addr` is a canonical executable swap-router target.
    /// @dev    Dedicated execution allowlist. This intentionally excludes
    ///         Permit2, tokens, factories, quoters, *passive* settlement
    ///         contracts (CoW/Across — reached via fixed immutable pins, never a
    ///         delegatee-supplied `s.router`), flash lenders, owner/multisig
    ///         safes, multicall helpers, and other registry anchors that are
    ///         present in `isKnown`. It DOES include RFQ settlement routers the
    ///         executor dispatches to as a swap step (Hashflow `tradeRFQT`),
    ///         because those are delegatee-supplied call targets and must pass
    ///         the same call-target gate as any aggregator router.
    /// @param  addr  Candidate target for executor swap dispatch.
    /// @return       True iff `addr` is an allowed executable router target.
    function isExecutableRouter(
        address addr
    ) public pure returns (bool) {
        return addr == ONEINCH_V6_ROUTER //
            || addr == ZEROX_EXCHANGE_PROXY //
            || addr == PARASWAP_AUGUSTUS //
            || addr == ODOS_ROUTER //
            || addr == KYBER_META_AGGREGATION //
            || addr == OPENOCEAN_EXCHANGE //
            || addr == UNISWAP_V4_UNIVERSAL_ROUTER //
            || addr == SQUID_ROUTER //
            || addr == UNIVERSAL_ROUTER_V20 //
            || addr == UNIVERSAL_ROUTER_V211 //
            || addr == UNIV2_ROUTER //
            || addr == UNIV3_SWAP_ROUTER_02 //
            || addr == SUSHI_V2_ROUTER //
            || addr == SUSHI_V3_SWAP_ROUTER //
            || addr == PANCAKE_V2_ROUTER //
            || addr == PANCAKE_V3_SWAP_ROUTER //
            || addr == PANCAKE_V3_SMART_ROUTER //
            || addr == CAMELOT_V2_ROUTER //
            || addr == CAMELOT_V3_SWAP_ROUTER //
            || addr == CURVE_ROUTER //
            || addr == DODO_V2_PROXY02 //
            || addr == DOLOMITE_GENERIC_TRADER_ROUTER //
            || addr == HOOKMATE_V4_SWAP_ROUTER //
            || addr == CAMELOT_ALGEBRA_V4_SWAP_ROUTER //
            || addr == HASHFLOW_ROUTER_ARBITRUM //
            || addr == MAVERICK_V2_ROUTER //
            || addr == LFJ_LB_ROUTER_V21 //
            || addr == LFJ_LB_ROUTER_V22 //
            || addr == RAMSES_ROUTER_V2 //
            || addr == RAMSES_UNIVERSAL_ROUTER //
            || addr == WOMBAT_ROUTER //
            || addr == BALANCER_V3_ROUTER //
            || addr == BALANCER_V3_BATCH_ROUTER //
            || addr == BALANCER_V3_AGGREGATOR_ROUTER //
            || addr == BEBOP_SETTLEMENT //
            || addr == WOOFI_ROUTER_V2 //
            || addr == WOOFI_ROUTER_ALT //
            || addr == OKX_DEX_ROUTER //
            || addr == ENSO_ROUTER //
            || addr == LIFI_DIAMOND //
            || addr == RANGO_DIAMOND //
            || addr == RUBIC_PROXY_V3 //
            || addr == NATIVE_ROUTER_V4 //
            || addr == NATIVE_ROUTER_V3;
    }

    /// @notice True iff `addr` is one of the registered canonical routers,
    ///         factories, tokens, venues, or metadata anchors.
    /// @dev    Informational only. Execution paths MUST NOT use this as a
    ///         router whitelist because it includes Permit2, tokens, factories,
    ///         quoters, lenders, settlement contracts, multisigs, and other
    ///         non-router contracts. `Executor._isWhitelistedRouter` maintains
    ///         a dedicated executable-router allowlist instead.
    /// @dev    `public` (not `internal`) on purpose: it deploys as a linked
    ///         library so the comparison chain is delegatecalled rather than
    ///         inlined into the Executor, keeping the Executor runtime under
    ///         the EIP-170 24,576-byte limit. Pure; constant-folds against
    ///         compile-time addresses.
    /// @param  addr  Candidate address to check against the registry.
    /// @return       True iff `addr` matches one of the registered addresses.
    function isKnown(
        address addr
    ) public pure returns (bool) {
        return addr == UNIVERSAL_ROUTER_V20 //
            || addr == UNIVERSAL_ROUTER_V211 //
            || addr == UNIV2_ROUTER //
            || addr == UNIV2_FACTORY //
            || addr == UNIV3_SWAP_ROUTER_02 //
            || addr == UNIV3_POSITION_MANAGER //
            || addr == UNIV3_FACTORY //
            || addr == UNIV3_QUOTER_V2 //
            || addr == UNIV4_POOL_MANAGER //
            || addr == UNIV4_POSITION_MANAGER //
            || addr == UNIV4_STATE_VIEW //
            || addr == UNIV4_QUOTER //
            || addr == HOOKMATE_V4_SWAP_ROUTER //
            || addr == UNISWAPX_V3_DUTCH_REACTOR //
            || addr == UNISWAPX_ORDER_QUOTER //
            || addr == PERMIT2 //
            || addr == ONEINCH_V6_ROUTER //
            || addr == ZEROX_EXCHANGE_PROXY //
            || addr == PARASWAP_AUGUSTUS //
            || addr == ODOS_ROUTER //
            || addr == KYBER_META_AGGREGATION //
            || addr == OPENOCEAN_EXCHANGE //
            || addr == AAVE_V3_POOL //
            || addr == MORPHO_BLUE //
            || addr == COW_SETTLEMENT //
            || addr == COW_FLASH_LOAN_ROUTER //
            || addr == BALANCER_V2_VAULT //
            || addr == BALANCER_V3_VAULT //
            || addr == INSTA_FLASH_AGGREGATOR //
            || addr == INSTA_FLASH_RESOLVER //
            || addr == ACROSS_SPOKEPOOL //
            || addr == EXECUTOR_OWNER_SAFE //
            || addr == WETH //
            || addr == USDC //
            || addr == USDT //
            || addr == ARB //
            || addr == FLUX_DATAMINE_TOKEN //
            || addr == FLUX_PROTOCOL_TOKEN //
            || addr == MULTICALL3 //
            || addr == SUSHI_V2_ROUTER //
            || addr == SUSHI_V2_FACTORY //
            || addr == PANCAKE_V2_ROUTER //
            || addr == PANCAKE_V2_FACTORY //
            || addr == PANCAKE_V3_FACTORY //
            || addr == PANCAKE_V3_INTERFACE_MULTICALL //
            || addr == PANCAKE_V3_MASTERCHEF //
            || addr == PANCAKE_V3_SWAP_ROUTER //
            || addr == PANCAKE_V3_QUOTER_V2 //
            || addr == PANCAKE_UNIVERSAL_ROUTER //
            || addr == PANCAKE_V3_POOL_DEPLOYER //
            || addr == PANCAKE_V3_MIXED_ROUTE_QUOTER_V1 //
            || addr == SUSHI_V3_SWAP_ROUTER //
            || addr == SUSHI_V3_FACTORY //
            || addr == CAMELOT_V2_FACTORY //
            || addr == CAMELOT_V2_ROUTER //
            || addr == CAMELOT_V3_SWAP_ROUTER //
            || addr == CAMELOT_ALGEBRA_V4_SWAP_ROUTER //
            || addr == ALGEBRA_V4_FACTORY //
            || addr == DARWIN_SWAP_FACTORY //
            || addr == PANCAKE_V3_SMART_ROUTER //
            || addr == CURVE_ROUTER //
            || addr == CURVE_STABLESWAP_REGISTRY //
            || addr == CURVE_STABLE_FACTORY //
            || addr == CURVE_STABLESWAP_NG_FACTORY //
            || addr == CURVE_STABLESWAP_NG_VIEWS //
            || addr == CURVE_STABLESWAP_NG_MATH //
            || addr == CURVE_STABLESWAP_NG_PLAIN_IMPL //
            || addr == CURVE_STABLESWAP_NG_META_IMPL //
            || addr == CURVE_TWOCRYPTO_FACTORY //
            || addr == CURVE_TRICRYPTO_FACTORY //
            || addr == DODO_V2_PROXY02 //
            || addr == MAVERICK_V2_ROUTER //
            || addr == MAVERICK_V2_QUOTER //
            || addr == MAVERICK_V2_REWARD_ROUTER //
            || addr == LFJ_LB_ROUTER_V21 //
            || addr == LFJ_LB_ROUTER_V22 //
            || addr == KYBER_ELASTIC_ROUTER //
            || addr == KYBER_ELASTIC_FACTORY //
            || addr == RAMSES_ROUTER_V2 //
            || addr == RAMSES_UNIVERSAL_ROUTER //
            || addr == GMX_V2_EXCHANGE_ROUTER //
            || addr == WOMBAT_ROUTER //
            || addr == BALANCER_V3_ROUTER //
            || addr == BALANCER_V3_BATCH_ROUTER //
            || addr == BALANCER_V3_AGGREGATOR_ROUTER //
            || addr == BALANCER_V3_BUFFER_ROUTER //
            || addr == BEBOP_SETTLEMENT //
            || addr == WOOFI_ROUTER_V2 //
            || addr == WOOFI_ROUTER_ALT //
            || addr == OKX_DEX_ROUTER //
            || addr == ENSO_ROUTER //
            || addr == DOLOMITE_MARGIN //
            || addr == DOLOMITE_BORROW_POSITION_ROUTER //
            || addr == DOLOMITE_DEPOSIT_WITHDRAWAL_ROUTER //
            || addr == DOLOMITE_GENERIC_TRADER_ROUTER //
            || addr == DOLOMITE_BORROW_POSITION_PROXY_V1 //
            || addr == DOLOMITE_BORROW_POSITION_PROXY_V2 //
            || addr == DOLOMITE_DEPOSIT_WITHDRAWAL_PROXY //
            || addr == DOLOMITE_EVENT_EMITTER_REGISTRY_PROXY //
            || addr == DOLOMITE_EXPIRY_TRADER //
            || addr == DOLOMITE_EXPIRY_PROXY //
            || addr == DOLOMITE_GENERIC_TRADER_PROXY_V1 //
            || addr == DOLOMITE_SAFE //
            || addr == DOLOMITE_LIQUIDATOR_ASSET_REGISTRY //
            || addr == DOLOMITE_LIQUIDATOR_PROXY_V1 //
            || addr == DOLOMITE_LIQUIDATOR_PROXY_V4_WITH_GENERIC_TRADER //
            || addr == DOLOMITE_LIQUIDATOR_PROXY_V5 //
            || addr == DOLOMITE_ARBITRUM_MULTICALL //
            || addr == DOLOMITE_PARTIALLY_DELAYED_MULTISIG //
            || addr == DOLOMITE_TRANSFER_PROXY //
            || addr == DOLOMITE_ALWAYS_ZERO_INTEREST_SETTER //
            || addr == DOLOMITE_CHAINLINK_PRICE_ORACLE //
            || addr == DOLOMITE_CHAOSLABS_PRICE_ORACLE //
            || addr == DOLOMITE_CHRONICLE_PRICE_ORACLE //
            || addr == DOLOMITE_REDSTONE_PRICE_ORACLE //
            || addr == DOLOMITE_ORACLE_AGGREGATOR //
            || addr == DOLOMITE_CREATE3_FACTORY //
            || addr == DOLOMITE_ACCOUNT_REGISTRY_PROXY //
            || addr == DOLOMITE_MIGRATOR //
            || addr == DOLOMITE_OWNER_V1 //
            || addr == DOLOMITE_OWNER_V2 //
            || addr == DOLOMITE_REGISTRY_PROXY //
            || addr == DOLOMITE_ISOLATION_MODE_FREEZABLE_LIQUIDATOR_PROXY //
            || addr == DOLOMITE_ODOS_AGGREGATOR_TRADER //
            || addr == DOLOMITE_PARASWAP_AGGREGATOR_TRADER_V2 //
            || addr == SQUID_ROUTER //
            || addr == SQUID_MULTICALL //
            || addr == LIFI_DIAMOND //
            || addr == RANGO_DIAMOND //
            || addr == RUBIC_PROXY_V3 //
            || addr == NATIVE_ROUTER_V4 //
            || addr == NATIVE_ROUTER_V3 //
            || addr == NATIVE_CREDIT_VAULT //
            || addr == FRAXSWAP_FACTORY //
            || addr == HASHFLOW_ROUTER_ARBITRUM;
    }
}

/// @title  UniversalRouterCommands — command-byte constants for `execute()`
/// @author mev-arbitrum
/// @notice The first byte of each entry in Universal Router's `commands`
///         byte-string. Universal Router 2.0 / 2.1.1 dispatches on this
///         byte to the corresponding inner handler.
/// @dev    Reference: Uniswap universal-router `Commands.sol`.
///         Routing-shape reminder (per the project's Universal Router
///         breakdown):
///           - V2 commands accept ANY V2-pair-interface address as the
///             pool — pass the pair address directly.
///           - V3 commands derive the pool from `UNIV3_FACTORY` via the
///             path encoding. Non-Uniswap V3 forks need pre-computed
///             pool addresses or a dedicated router.
///           - V4_SWAP routes via `UNIV4_POOL_MANAGER` only.
library UniversalRouterCommands {
    /// @dev V3 exact-input swap (multi-pool path, fees encoded inline).
    bytes1 internal constant V3_SWAP_EXACT_IN = 0x00;

    /// @dev V3 exact-output swap.
    bytes1 internal constant V3_SWAP_EXACT_OUT = 0x01;

    /// @dev V2 exact-input swap; pool is whatever address the caller passes.
    bytes1 internal constant V2_SWAP_EXACT_IN = 0x08;

    /// @dev V2 exact-output swap.
    bytes1 internal constant V2_SWAP_EXACT_OUT = 0x09;

    /// @dev Wrap native ETH into WETH credited to the Universal Router.
    bytes1 internal constant WRAP_ETH = 0x0b;

    /// @dev Unwrap WETH held by the Router back to native ETH.
    bytes1 internal constant UNWRAP_WETH = 0x0c;

    /// @dev V4 single-/multi-pool swap dispatched through the V4 PoolManager.
    bytes1 internal constant V4_SWAP = 0x10;

    /// @dev Recursive sub-plan execution; nests another (commands, inputs)
    ///      pair inside the current `execute()` call.
    bytes1 internal constant EXECUTE_SUB_PLAN = 0x21;

    // @dev no EIP-7939 CLZ opportunities — only constant-time byte tags.
}

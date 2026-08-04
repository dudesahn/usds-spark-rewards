# Invariant Map

> Grove USDS Compounder | 25 guards | 5 inferred | 2 not enforced on-chain

---

## 1. Enforced Guards (Reference)

Per-call preconditions. Heading IDs below (`G-N`) are anchor targets from x-ray.md attack surfaces.

#### G-1
`require(!STAKING.paused(), "!paused")` · `src/GroveCompounder.sol:39` · Prevents deployment against an already-paused staking dependency.

#### G-2
`require(PSM_WRAPPER.usds() == STAKING.stakingToken(), "!stakingToken")` · `src/GroveCompounder.sol:40` · Binds the strategy asset, staking asset, and PSM output to the same token.

#### G-3
`require(PSM_WRAPPER.tin() == 0, "!psmFee")` · `src/GroveCompounder.sol:98` · Prevents the direct-swap harvest path from accepting a fee-bearing PSM conversion.

#### G-4
`require(useAuction, "!useAuction")` · `src/GroveCompounder.sol:159` · Restricts manual auction kicks to the configured reward-sale mode.

#### G-5
`require(_token != address(asset), "!asset")` · `src/GroveCompounder.sol:175` · Prevents the auction helper from transferring principal to a sale venue.

#### G-6
`require(_auction != address(0), "!auction")` · `src/GroveCompounder.sol:177` · Requires a live auction target before reward tokens leave the strategy.

#### G-7
`require(Auction(_auction).receiver() == address(this), "receiver")` · `src/GroveCompounder.sol:211` · Requires sale proceeds to return to this strategy.

#### G-8
`require(Auction(_auction).want() == address(asset), "want")` · `src/GroveCompounder.sol:212` · Requires the auction output token to equal strategy asset.

#### G-9
`require(!useAuction, "!auction")` · `src/GroveCompounder.sol:214` · Prevents clearing the auction address while auction mode is selected.

#### G-10
`require(auction != address(0), "!auction")` · `src/GroveCompounder.sol:225` · Prevents switching into auction mode without a configured target.

#### G-11
`require(msg.sender == management, "!management")` · `src/periphery/GroveCompounderAprOracle.sol:92` · Enforces the APR oracle configuration authority boundary.

#### G-12
`if (assets == 0) revert("apr too high")` · `src/periphery/GroveCompounderAprOracle.sol:128` · Prevents a zero-denominator APR quote.

#### G-13
`require(oracleApr <= MAX_EXPECTED_APR, "apr too high")` · `src/periphery/GroveCompounderAprOracle.sol:132` · Caps the APR value exposed to downstream consumers.

#### G-14
`require(_management != address(0), "!management")` · `src/periphery/GroveCompounderAprOracle.sol:136` · Keeps oracle configuration authority recoverable.

#### G-15
`require(_uniV3PoolForFee(_rewardToBaseUniV3Fee) != address(0), "!pool")` · `src/periphery/GroveCompounderAprOracle.sol:142` · Restricts configured V3 fees to a factory-listed GROVE/USDC pool.

#### G-16
`require(_poolId != bytes32(0), "!pool")` · `src/periphery/GroveCompounderAprOracle.sol:148` · Keeps the single configured V4 candidate addressable.

#### G-17
`require(_poolId != bytes32(0), "!pool")` · `src/periphery/GroveCompounderAprOracle.sol:159` · Prevents appending an empty V4 pool identifier.

#### G-18
`require(!_hasUniV4Pool(_poolId), "duplicate")` · `src/periphery/GroveCompounderAprOracle.sol:160` · Keeps the incrementally managed V4 candidate set unique.

#### G-19
`require(length > 1, "!pool")` · `src/periphery/GroveCompounderAprOracle.sol:168` · Prevents removal of the final V4 fallback candidate.

#### G-20
`require(_index < length, "!index")` · `src/periphery/GroveCompounderAprOracle.sol:169` · Bounds V4 candidate removal to an existing array element.

#### G-21
`require(length > 0 && length == _groveIsToken0.length, "length")` · `src/periphery/GroveCompounderAprOracle.sol:340` · Requires a nonempty, one-to-one V4 pool/orientation configuration.

#### G-22
`require(poolId != bytes32(0), "!pool")` · `src/periphery/GroveCompounderAprOracle.sol:345` · Keeps every bulk-configured V4 candidate addressable.

#### G-23
`require(poolId != _poolIds[j], "duplicate")` · `src/periphery/GroveCompounderAprOracle.sol:348` · Keeps the bulk-configured V4 candidate set unique.

#### G-24
`require(amountSpecified != 0, "AS")` · `src/libraries/UniswapV3SwapSimulatorCore.sol:67` · Prevents a zero-sized simulated swap from entering Uniswap step math.

#### G-25
`require(zeroForOne ? sqrtPriceLimitX96 < sqrtPriceX96 && sqrtPriceLimitX96 > TickMath.MIN_SQRT_RATIO : sqrtPriceLimitX96 > sqrtPriceX96 && sqrtPriceLimitX96 < TickMath.MAX_SQRT_RATIO, "SPL")` · `src/libraries/UniswapV3SwapSimulatorCore.sol:71` · Constrains simulation direction and terminal price to Uniswap's valid range.

---

## 2. Inferred Invariants (Single-Contract)

#### I-1

`Bound` · On-chain: **Yes**

> `management` is never the zero address.

**Derivation** — guard-lift: constructor writes `management = msg.sender` at `src/periphery/GroveCompounderAprOracle.sol:96`; the only later write is guarded by `require(_management != address(0), "!management")` at lines 135-138.

**If violated** — Oracle pool configuration authority would be irrecoverably lost.

#### I-2

`Bound` · On-chain: **Yes**

> `v4Pools.length >= 1` after construction and after every successful configuration call.

**Derivation** — guard-lift + write sites: constructor pushes four entries at lines 97-100; single replacement pushes one at lines 147-151; bulk replacement requires nonzero length at lines 338-352; addition pushes at line 162; removal requires `length > 1` before `pop()` at lines 166-173.

**If violated** — Index-based getters and the V4 fallback would have no configured candidate.

#### I-3

`Bound` · On-chain: **Yes**

> Every configured V4 pool ID is nonzero and no two live entries share the same ID.

**Derivation** — guard-lift + write sites: nonzero and duplicate checks cover single replacement at lines 147-151, addition at lines 158-163, and bulk replacement at lines 338-352; the four constructor constants at lines 60-67 and 97-100 are nonzero and distinct; swap-and-pop removal at lines 166-173 preserves the property.

**If violated** — Candidate selection could count an unusable or duplicated market observation.

#### I-4

`Bound` · On-chain: **No**

> `useAuction == true` implies `auction != address(0)`.

**Derivation** — guard-lift + write sites: `setUseAuction(true)` checks `auction != address(0)` at lines 224-226 and `setAuction(0)` checks `!useAuction` at lines 209-216, but declaration-time writes set `useAuction = true` at line 22 while `auction` retains its zero default at line 19.

**If violated** — The auction-selected harvest path reaches `_kickAuction` without a configured target and reverts at G-6 once rewards exceed the sale threshold.

#### I-5

`Bound` · On-chain: **No**

> `rewardToBaseUniV3Fee` identifies a nonzero GROVE/USDC factory pool.

**Derivation** — guard-lift + write sites: `setUniV3Fee` validates the factory result before writing at lines 141-144, but the declaration-time default write at line 81 is not checked against the factory; `_uniV3PoolForFee` resolves the live factory mapping at lines 370-372.

**If violated** — V3 pricing is unavailable and the oracle relies exclusively on its V4 candidate path.

---

## 3. Inferred Invariants (Cross-Contract)

No cross-contract invariant met the x-ray verification gate because every stateful callee for staking, PSM, Auction, or Uniswap is outside the first-party scope.

---

## 4. Economic Invariants

No higher-order economic invariant could be derived solely from the verified first-party storage invariants above.

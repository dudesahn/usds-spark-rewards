# Invariant Map

> Grove USDS Compounder | 20 guards | 4 inferred | 0 scoped cross-contract | 1 economic

## 1. Enforced Guards (Reference)

#### G-1
`require(!STAKING.paused(), "!paused")` - `src/GroveCompounder.sol:39` - Prevents deployment against a paused staking venue.

#### G-2
`require(PSM_WRAPPER.usds() == STAKING.stakingToken(), "!stakingToken")` - `src/GroveCompounder.sol:40` - Binds the Yearn asset to the external staking principal token.

#### G-3
`require(PSM_WRAPPER.tin() == 0, "!psmFee")` - `src/GroveCompounder.sol:98` - Prevents the direct swap route from silently losing value to a nonzero PSM entry fee.

#### G-4
`require(_token != address(asset), "!asset")` - `src/GroveCompounder.sol:175` - Prevents keeper-triggered auctions from moving strategy principal out as a sell token.

#### G-5
`require(_auction != address(0), "!auction")` - `src/GroveCompounder.sol:177` - Ensures reward tokens are transferred only to a configured auction contract.

#### G-6
`require(Auction(_auction).receiver() == address(this), "receiver")` - `src/GroveCompounder.sol:211` - Ensures the configured auction sends proceeds back to this strategy.

#### G-7
`require(Auction(_auction).want() == address(asset), "want")` - `src/GroveCompounder.sol:212` - Ensures the configured auction sells rewards for the strategy asset.

#### G-8
`require(!useAuction, "!auction")` - `src/GroveCompounder.sol:214` - Prevents clearing the auction address while auction mode is active.

#### G-9
`if (_useAuction) require(auction != address(0), "!auction")` - `src/GroveCompounder.sol:225` - Prevents enabling auction mode without a configured auction address.

#### G-10
`if (block.timestamp > IStaking(STAKING).periodFinish()) return 0` - `src/periphery/GroveCompounderAprOracle.sol:114-116` - Treats finished reward periods as zero APR instead of using stale emissions.

#### G-11
`if (assets == 0) revert("apr too high")` - `src/periphery/GroveCompounderAprOracle.sol:128` - Prevents division by zero in APR calculation.

#### G-12
`require(oracleApr <= MAX_EXPECTED_APR, "apr too high")` - `src/periphery/GroveCompounderAprOracle.sol:132` - Rejects APR values above the configured 50% sanity cap.

#### G-13
`require(_management != address(0), "!management")` - `src/periphery/GroveCompounderAprOracle.sol:136` - Prevents orphaning oracle management.

#### G-14
`require(_uniV3PoolForFee(_rewardToBaseUniV3Fee) != address(0), "!pool")` - `src/periphery/GroveCompounderAprOracle.sol:142` - Restricts oracle V3 fee configuration to existing GROVE/USDC pools.

#### G-15
`require(_poolId != bytes32(0), "!pool")` - `src/periphery/GroveCompounderAprOracle.sol:148` - Prevents replacing V4 configuration with a zero pool id.

#### G-16
`require(_poolId != bytes32(0), "!pool")` - `src/periphery/GroveCompounderAprOracle.sol:159` - Prevents appending a zero V4 pool id.

#### G-17
`require(!_hasUniV4Pool(_poolId), "duplicate")` - `src/periphery/GroveCompounderAprOracle.sol:160` - Prevents duplicate V4 pool ids in the append path.

#### G-18
`require(length > 1, "!pool")` - `src/periphery/GroveCompounderAprOracle.sol:168` - Prevents removing the last configured V4 pool.

#### G-19
`require(_index < length, "!index")` - `src/periphery/GroveCompounderAprOracle.sol:169` - Prevents out-of-bounds V4 pool removal.

#### G-20
`require(length > 0 && length == _groveIsToken0.length, "length")` plus nonzero and duplicate checks - `src/periphery/GroveCompounderAprOracle.sol:338-354` - Ensures bulk V4 pool replacement leaves a nonempty, aligned, nonzero, unique pool set.

## 2. Inferred Invariants (Single-Contract)

#### I-1

`Bound` - On-chain: **Yes**

> The oracle's configured V4 pool list is always nonempty after construction.

**Derivation** - guard-lift: constructor writes four pools at `src/periphery/GroveCompounderAprOracle.sol:97-100`; `setUniV4Pool()` writes one nonzero pool at `147-151`; `setUniV4Pools()` requires `length > 0` at `338-354`; `addUniV4Pool()` only increases length at `158-163`; `removeUniV4Pool()` requires `length > 1` at `166-175`.

**If violated** - `_selectedV4Pool()` would iterate an empty list and `_grovePrice()` would be forced to revert whenever V3 pricing is unusable.

#### I-2

`Bound` - On-chain: **Yes**

> The oracle's V4 pool list contains no zero pool id and no duplicate pool id through the explicit setter paths.

**Derivation** - guard-lift: constructor constants are nonzero at `src/periphery/GroveCompounderAprOracle.sol:60-67`; `setUniV4Pool()` checks nonzero at `147-151`; `addUniV4Pool()` checks nonzero and `_hasUniV4Pool()` at `158-163`; `_setUniV4Pools()` checks nonzero and pairwise duplicates at `338-354`.

**If violated** - V4 selection could waste quote slots on invalid pools or overweight the same pool in median calculation.

#### I-3

`Temporal` - On-chain: **Yes**

> APR is zero after the Grove staking reward period ends.

**Derivation** - temporal: `if (block.timestamp > IStaking(STAKING).periodFinish()) return 0` at `src/periphery/GroveCompounderAprOracle.sol:114-116`.

**If violated** - the oracle could advertise stale reward APR after emissions have ended.

#### I-4

`Bound` - On-chain: **Yes**

> A selected V4 quote must have active liquidity at or above `MIN_REWARD_POOL_LIQUIDITY`, nonzero price, and price within `MAX_V4_POOL_PRICE_DEVIATION_BPS` of the configured-pool median.

**Derivation** - guard-lift: `_selectedV4Pool()` skips liquidity below threshold at `src/periphery/GroveCompounderAprOracle.sol:267-268`, skips zero sqrt price at `270-273`, skips zero converted price at `275-276`, computes median at `290`, and only selects quotes passing `_withinV4PriceDeviation()` at `293-304`.

**If violated** - a thin or outlier V4 pool could become the APR oracle price source.

## 3. Inferred Invariants (Cross-Contract)

No formal scoped cross-contract invariants were extracted because the counterpart implementations for Grove staking, PSM, UniV3/UniV4, auctions, and Yearn base contracts are outside the two-contract audit scope. Their assumptions are documented as x-ray trust boundaries.

## 4. Economic Invariants

#### E-1

On-chain: **Yes**

> A harvest report values the strategy as external staked USDS plus idle USDS held by the strategy.

**Follows from** - `G-2` plus `src/GroveCompounder.sol:111-117`, where idle USDS may be restaked above dust and `_totalAssets = balanceOfStake() + balanceOfAsset()`.

**If violated** - Yearn accounting could overstate or understate strategy assets relative to the principal actually withdrawable from staking plus idle USDS.

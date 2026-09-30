# Entry Point Map

> Grove USDS Compounder | 13 explicit state-changing entry points | 0 permissionless | 1 role-gated | 12 admin-only

---

## Protocol Flow Paths

### Strategy Setup (Management)

`GroveCompounder.constructor()` → `setAuction()` → `setUseAuction(true)`

`GroveCompounder.constructor()` → `setUniV3Fees()` → `setUseAuction(false)`

### Vault / User Flow (Inherited Runtime)

`[strategy deployment above]` → inherited `TokenizedStrategy.deposit()` → `GroveCompounder._deployFunds()` → `SkyRewards.stake()`

`[deposit above]` → inherited `TokenizedStrategy.withdraw()` → `GroveCompounder._freeFunds()` → `SkyRewards.withdraw()`

### Maintenance (Keeper / Management)

`[deposit above]` → inherited `TokenizedStrategy.report()` → `GroveCompounder._harvestAndReport()`
                                                   ├─→ `SkyRewards.getReward()` → `Auction.kick()`
                                                   └─→ Uniswap V3 swap → `PsmWrapper.sellGem()`

`[auction configured above]` → `kickAuction()` → `SkyRewards.getReward()` → `Auction.kick()`

### APR Oracle Setup (Oracle Management)

`GroveCompounderAprOracle.constructor()` → `setUniV3Fee()`

`GroveCompounderAprOracle.constructor()` → `setUniV4Pool()` / `setUniV4Pools()` / `addUniV4Pool()` / `removeUniV4Pool()`

The inherited ERC-4626 and report functions are implemented in imported Yearn dependencies and are shown only as call-path context; they are not counted as first-party entry points above.

---

## Permissionless

No first-party state-changing permissionless entry points were found. The first-party view surfaces and the imported TokenizedStrategy runtime are outside this entry-point count.

---

## Role-Gated

### `onlyKeepers`

#### `GroveCompounder.kickAuction(address)`

| Aspect | Detail |
|--------|--------|
| Visibility | external, `onlyKeepers` |
| Caller | Keeper |
| Parameters | `_token` (keeper-provided) |
| Call chain | `→ GroveCompounder._claimRewards()` when GROVE → ERC-20 balance read → GroveCompounder._kickAuction() → ERC20.safeTransfer() → Auction.kick()` |
| State modified | No local storage; external staking reward state, strategy token balances, and Auction state may change |
| Value flow | Token: GroveCompounder → Auction |
| Reentrancy guard | no |

---

## Admin-Only

All functions below execute immediately under `onlyManagement`; no timelock is implemented in the first-party contracts.

| Contract | Function | Parameters | State Modified |
|----------|----------|------------|----------------|
| GroveCompounder | `claimRewards()` | none | External staking reward state and strategy reward balance |
| GroveCompounder | `setMinAmountToSell()` | `_minAmountToSell` (management-controlled) | Inherited `minAmountToSell[GROVE]` |
| GroveCompounder | `setUniV3Fees()` | `_rewardToBase` (management-controlled) | Inherited GROVE/USDC fee configuration |
| GroveCompounder | `setAuction()` | `_auction` (management-controlled) | `auction` |
| GroveCompounder | `setUseAuction()` | `_useAuction` (management-controlled) | `useAuction` |
| GroveCompounder | `setReferral()` | `_referral` (management-controlled) | `referral` |
| GroveCompounderAprOracle | `setManagement()` | `_management` (management-controlled) | `management` |
| GroveCompounderAprOracle | `setUniV3Fee()` | `_rewardToBaseUniV3Fee` (management-controlled) | `rewardToBaseUniV3Fee` |
| GroveCompounderAprOracle | `setUniV4Pool()` | `_poolId`, `_groveIsToken0` (management-controlled) | Replaces `v4Pools` |
| GroveCompounderAprOracle | `setUniV4Pools()` | `_poolIds`, `_groveIsToken0` (management-controlled) | Replaces `v4Pools` |
| GroveCompounderAprOracle | `addUniV4Pool()` | `_poolId`, `_groveIsToken0` (management-controlled) | Appends to `v4Pools` |
| GroveCompounderAprOracle | `removeUniV4Pool()` | `_index` (management-controlled) | Reorders and shortens `v4Pools` |

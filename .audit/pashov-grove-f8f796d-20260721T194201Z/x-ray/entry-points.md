# Entry Point Map

> Grove USDS Compounder | 19 mapped entry points | 4 permissionless/inherited | 3 role-gated | 12 admin-only

## Protocol Flow Paths

### Setup (Management)

`new GroveCompounder()` -> `setPerformanceFeeRecipient()` -> `setKeeper()` -> `setEmergencyAdmin()` -> `setProfitMaxUnlockTime()` -> `setAllowed()` or `setOpen(true)` -> `setAuction()` -> `setUseAuction(true)`

### User Flow

`[setup above]` -> inherited `deposit()`/`mint()` -> `GroveCompounder.availableDepositLimit()` -> `_deployFunds()` -> `STAKING.stake()`

`[deposit above]` -> inherited `withdraw()`/`redeem()` -> `_freeFunds()` -> `STAKING.withdraw()`

### Maintenance (Keeper)

`[deposit above]` -> inherited `report()` -> `_harvestAndReport()` -> `STAKING.getReward()` -> auction branch `Auction.kick()` or swap branch `UniV3 -> PSM.sellGem()` -> optional `_deployFunds()`

`[setup above]` -> `kickAuction()` -> optional `STAKING.getReward()` -> `_kickAuction()` -> `Auction.kick()`

### Oracle Flow

`new GroveCompounderAprOracle()` -> optional pool setters -> `aprAfterDebtChange()` -> Grove staking reads -> V3 quote if usable -> V4 selected-pool quote otherwise -> APR cap

## Permissionless

### Inherited `GroveCompounder.deposit()` / `GroveCompounder.mint()`

| Aspect | Detail |
|---|---|
| Visibility | inherited external |
| Caller | Depositor, subject to inherited Yearn allow/open checks and custom `availableDepositLimit()` |
| Parameters | assets/shares and receiver (user-controlled) |
| Call chain | inherited Yearn entry -> `availableDepositLimit()` -> `_deployFunds()` -> `STAKING.stake()` |
| State modified | Inherited Yearn share/accounting state; external Grove staking balance |
| Value flow | USDS from caller into strategy, then strategy into Grove staking |
| Reentrancy guard | Inherited, out of scope |

### Inherited `GroveCompounder.withdraw()` / `GroveCompounder.redeem()`

| Aspect | Detail |
|---|---|
| Visibility | inherited external |
| Caller | Shareholder or approved spender |
| Parameters | assets/shares, receiver, owner (user-controlled within inherited allowance rules) |
| Call chain | inherited Yearn entry -> `_freeFunds()` -> `STAKING.withdraw()` |
| State modified | Inherited Yearn share/accounting state; external Grove staking balance |
| Value flow | USDS from Grove staking to strategy, then to receiver through inherited logic |
| Reentrancy guard | Inherited, out of scope |

### `GroveCompounderAprOracle.aprAfterDebtChange()`

| Aspect | Detail |
|---|---|
| Visibility | external view |
| Caller | Anyone |
| Parameters | `_strategy` unused, `_delta` user-controlled |
| Call chain | `aprAfterDebtChange()` -> `IStaking.totalSupply()` / `rewardRate()` / `periodFinish()` -> `_grovePrice()` -> V3 simulation or `_selectedV4Pool()` |
| State modified | None |
| Value flow | None |
| Reentrancy guard | Not applicable |

## Role-Gated

### Keeper

#### Inherited `GroveCompounder.report()`

| Aspect | Detail |
|---|---|
| Visibility | inherited external keeper path |
| Caller | Keeper or management through inherited Yearn permissions |
| Parameters | None in custom hook |
| Call chain | inherited `report()` -> `_harvestAndReport()` -> `STAKING.getReward()` -> reward sale branch -> optional `_deployFunds()` |
| State modified | Inherited Yearn accounting; Grove staking balance; reward balances; auction balances when auction branch is used |
| Value flow | GROVE to auction, or GROVE -> USDC -> USDS -> staking |
| Reentrancy guard | Inherited, out of scope |

#### `GroveCompounder.kickAuction(address)`

| Aspect | Detail |
|---|---|
| Visibility | external `onlyKeepers` |
| Caller | Keeper |
| Parameters | `_token` keeper-provided |
| Call chain | `kickAuction()` -> optional `_claimRewards()` -> `_kickAuction()` -> `ERC20.safeTransfer()` -> `Auction.kick()` |
| State modified | Token balances held by strategy and auction |
| Value flow | Non-asset token from strategy to auction |
| Reentrancy guard | None in custom code |

### Management

#### `GroveCompounder.claimRewards()`

| Aspect | Detail |
|---|---|
| Visibility | external `onlyManagement` |
| Caller | Management |
| Parameters | None |
| Call chain | `claimRewards()` -> `_claimRewards()` -> `STAKING.getReward()` |
| State modified | Strategy GROVE balance |
| Value flow | GROVE from staking contract to strategy |
| Reentrancy guard | None in custom code |

## Admin-Only

| Contract | Function | Parameters | State Modified |
|---|---|---|---|
| `GroveCompounder` | `setMinAmountToSell()` | `_minAmountToSell` management-controlled | inherited `minAmountToSell[REWARDS_TOKEN]` |
| `GroveCompounder` | `setUniV3Fees()` | `_rewardToBase` management-controlled | inherited UniV3 fee mapping for `REWARDS_TOKEN -> base` |
| `GroveCompounder` | `setAuction()` | `_auction` management-controlled | `auction` |
| `GroveCompounder` | `setUseAuction()` | `_useAuction` management-controlled | `useAuction` |
| `GroveCompounder` | `setReferral()` | `_referral` management-controlled | `referral` |
| `GroveCompounderAprOracle` | `setManagement()` | `_management` management-controlled | `management` |
| `GroveCompounderAprOracle` | `setUniV3Fee()` | `_rewardToBaseUniV3Fee` management-controlled | `rewardToBaseUniV3Fee` |
| `GroveCompounderAprOracle` | `setUniV4Pool()` | `_poolId`, `_groveIsToken0` management-controlled | replaces `v4Pools` with one config |
| `GroveCompounderAprOracle` | `setUniV4Pools()` | `_poolIds`, `_groveIsToken0` management-controlled | replaces `v4Pools` with provided configs |
| `GroveCompounderAprOracle` | `addUniV4Pool()` | `_poolId`, `_groveIsToken0` management-controlled | appends to `v4Pools` |
| `GroveCompounderAprOracle` | `removeUniV4Pool()` | `_index` management-controlled | removes one `v4Pools` entry by swap-pop |
| `GroveCompounder` | inherited management setters | keeper, emergency admin, open/allowed, health checks, fees | inherited Yearn strategy configuration |

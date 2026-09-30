# Auction Dilution Validation

Status: validated.

Temporary test source preserved at: `validation/CodexAuctionDilution.t.sol`

Command that passed:

```bash
forge test --match-path src/test/CodexAuctionDilution.t.sol --match-test test_jitDepositCapturesUnreportedAuctionProceeds -vv --fork-url https://ethereum.publicnode.com
```

Observed passing output:

```text
Ran 1 test for src/test/CodexAuctionDilution.t.sol:CodexAuctionDilutionTest
[PASS] test_jitDepositCapturesUnreportedAuctionProceeds() (gas: 1115355)
Suite result: ok. 1 passed; 0 failed; 0 skipped
Ran 1 test suite in 4.48s (4.05s CPU time): 1 tests passed, 0 failed, 0 skipped (1 total tests)
```

Proof shape:

1. Incumbent deposits `10_000e18` USDS.
2. Keeper report claims GROVE and kicks it to auction, with `firstProfit == 0` and `firstLoss == 0`.
3. `1_000e18` USDS is sent to the strategy, modeling `Auction.take()` paying `want` to the strategy as receiver.
4. Attacker deposits `10_000e18` USDS before the next report.
5. Deposit mints `10_000e18` shares at stale 1:1 accounting and stakes the full loose balance, including the unreported `1_000e18` auction proceeds.
6. Next keeper report records `1_000e18` profit.
7. After profit unlock, attacker redeems and captures approximately `500e18` USDS of the auction proceeds generated before the attacker deposit.

Tooling note:

After the passing run, attempts to save a redirected Forge output file hit a Foundry/macOS provider panic before test execution: `Attempted to create a NULL object` in `system-configuration`. That crash output is preserved at `validation/foundry-provider-panic-output.txt` and was not a test failure.

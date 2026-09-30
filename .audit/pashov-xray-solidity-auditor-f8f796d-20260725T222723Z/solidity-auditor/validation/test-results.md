# Validation Test Results

## Environment

- Command: `env ETH_RPC_URL=https://ethereum.publicnode.com forge test --match-path src/test/AuditValidation.t.sol -vvv --fork-url https://ethereum.publicnode.com`
- Fork block observed by Foundry: `25,612,756`
- Solidity: `0.8.28`
- Result: **2 passed, 0 failed, 0 skipped**
- Original-suite regression command: `env ETH_RPC_URL=https://ethereum.publicnode.com forge test --fork-url https://ethereum.publicnode.com -q`
- Original-suite result: **exit 0; all 26 repository tests passed** at fork block `25,612,780`

## Passing Proofs

1. `test_atomicAuctionCallbackMintsBeforeProceedsAreAccounted`
   - Kicks a real Yearn Auction created by the repository's fork setup.
   - Uses an Auction receiver callback to deposit before USDS payment.
   - Confirms shares are minted from stale assets, the payment is absent from `totalAssets`, the next report recognizes it as profit, and the callback depositor later redeems more than it deposited.

2. `test_permissionlessDustAuctionCanRepeatedlyBlockReport`
   - Sends one wei of GROVE to the Auction and kicks it from an arbitrary account.
   - Confirms an above-threshold keeper report reverts with `too soon`.
   - Advances beyond expiry, re-kicks the same unsold dust, and confirms the next report also reverts.

The exact PoC source is archived at `validation/pocs/AuditValidation.t.sol`. It was removed from the detached source worktree after execution; no production or repository test file was left modified.

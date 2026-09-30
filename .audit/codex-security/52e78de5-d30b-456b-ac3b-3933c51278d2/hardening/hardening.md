# Security Hardening Review: GroveCompounder reward settlement

## Evidence Basis

This review derives from two validated findings at revision
`f8f796db93c52432cca0ed26861e94f5aaf20975`: an active external auction can
make a keeper report revert, and a depositor can enter while incumbent-earned
rewards remain outside share-pricing accounting. I inspected the accepted
writeups, canonical finding records, threat model, and the affected
`src/GroveCompounder.sol` paths. The scan was still in final reporting, so this
portfolio is bound to the target revision and evidence hashes recorded in
`context.md`, not to a sealed manifest digest.

Both failures meet at one boundary: the strategy does not own a complete rule
for unsettled reward state. Staking, the strategy, the Auction, and Yearn's
report-boundary accounting each hold a partial view, while report completion
and share issuance assume that partial view is sufficient. We should harden
that boundary, but the evidence does not support redesigning unrelated oracle
or swap-library components.

## Constraints

We assume a balanced change profile, no supplied gas or memory budget, the
existing Yearn tokenized-strategy interface, and the pinned external staking
and Auction contracts. Principal withdrawal must remain available even when
reward settlement is delayed. The proposal does not change reward pricing,
replace the Auction, or claim that either finding is fixed before code and the
original PoCs are revalidated.

## Opportunity Portfolio

| Opportunity | Evidence | Options | Recommendation | Proposal |
| --- | --- | --- | --- | --- |
| Own the reward-lifecycle boundary | [Active-auction report denial](../findings/permissionless-auction-prekick-report-dos/permissionless-auction-prekick-report-dos.md) (`csf_caa09b28e81d6df8702f4f3b`); [late-deposit reward dilution](../findings/late-deposit-reward-dilution/late-deposit-reward-dilution.md) (`csf_b51d06995c5b3b21d7a6c516`) | Option 1: focused report idempotence and deposit settlement gate; Option 2: queued deposits behind an explicit settlement coordinator | Option 1 under the current proportionality and compatibility constraints | [Technical proposal](proposals/own-reward-lifecycle-boundary.md) |

## Recommendation Summary

I recommend Option 1 now. We can make reports tolerate an already-active
auction and prevent new share minting while material pre-entry reward value is
unsettled, without introducing a new custody component or changing ERC-4626
deposit semantics. The price is bounded deposit unavailability during cleanup,
plus care to ensure that dust donations cannot hold the gate closed.

Option 2 is the stronger architectural boundary when continuously available
deposit intake is a product requirement. A cancelable queue can accept USDS
without minting shares until the old reward epoch is settled, so it avoids both
stale entry pricing and report coupling. What gives me pause is the new escrow,
ordering, cancellation, and keeper-recovery surface. The two validated findings
do not by themselves justify that operational and audit burden.

## Next Decisions

Engineering should first confirm whether open deposits must remain immediately
mintable while rewards or an auction are pending. If not, select Option 1 and
define a materiality threshold plus a maximum gate duration. If immediate
intake is mandatory, return to design review for Option 2 with explicit queue
fairness, cancellation, maximum-delay, and failure-recovery requirements.
Whichever option is selected, the active-auction report PoC and the late-entry
cohort PoC remain acceptance tests; this proposal alone closes neither finding.


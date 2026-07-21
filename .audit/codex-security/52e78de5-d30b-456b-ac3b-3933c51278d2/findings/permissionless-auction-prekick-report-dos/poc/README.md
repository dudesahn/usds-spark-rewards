# Permissionless auction pre-kick report-denial PoC

This Forge integration test reproduces the issue against
`f8f796db93c52432cca0ed26861e94f5aaf20975` on a local fork of Ethereum
mainnet at block `25583832`. It does not broadcast transactions or modify a
live deployment.

## Requirements

- POSIX shell, Git, and GNU or BSD Make;
- Foundry with `forge` available on `PATH` (the validated compiler is Solidity
  `0.8.28`);
- internet access for the first repository/submodule checkout;
- an Ethereum mainnet archive RPC capable of serving block `25583832`.

Set `ETH_RPC_URL` to an archive-capable endpoint. The default source is the
public repository URL recorded in `run.sh`; set `REPOSITORY_URL` to an
equivalent mirror if necessary.

## Run

From the report directory:

```sh
export ETH_RPC_URL="https://your-archive-mainnet-rpc.example"
cd poc
make test
```

The command creates `poc/.worktree/`, checks out the exact affected revision
and its pinned submodules, installs
`PermissionlessAuctionPreKickReportDos.t.sol`, and runs:

```sh
forge test \
  --match-contract PermissionlessAuctionPreKickReportDosTest \
  --fork-url "$ETH_RPC_URL" \
  --fork-block-number 25583832 \
  --no-storage-caching --cache-path cache --out out \
  --fuzz-runs 16 -vv
```

The runner exits before downloading or testing if `ETH_RPC_URL` is unset.

## Expected output

On the affected revision, all three tests pass:

```text
[PASS] testFuzz_publicPreKickBlocksThroughoutActiveWindow(uint96,uint32) (runs: 16)
[PASS] test_normalTwoReportCollisionAndRecovery()
[PASS] test_permissionlessDustPreKickBlocksReportAndRecovery()
Suite result: ok. 3 passed; 0 failed; 0 skipped
```

The tests establish that:

- a normal second report reverts while its first reward auction is active;
- an arbitrary account can donate one wei and pre-kick the Auction;
- the keeper report reverts with `"too soon"` and does not advance
  `lastReport`;
- the same unsold wei can renew the denial after one auction window;
- reporting recovers after a window expires without renewal; and
- donations from `1..1e18` wei block reports at delays from `0..23 hours`
  across 16 bounded fuzz runs.

No corrected revision was available for comparison. Once fixed, the vulnerable
`expectRevert("too soon")` assertions should be replaced with assertions that
the report succeeds and defers reward sale while the Auction remains active.

## Safety and cleanup

The test operates only on an ephemeral local fork. It uses Foundry cheatcodes
to fund test accounts, so it spends no real GROVE or ETH. It does not require a
private key. The only persistent state is the downloaded `poc/.worktree/`
directory and Foundry build output inside it.

Remove that isolated checkout and all generated build artifacts with:

```sh
make clean
```

`make clean` targets only `poc/.worktree/`.

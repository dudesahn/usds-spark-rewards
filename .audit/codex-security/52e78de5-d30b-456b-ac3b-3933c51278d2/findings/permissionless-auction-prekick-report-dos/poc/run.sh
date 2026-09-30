#!/bin/sh
set -eu

REVISION="f8f796db93c52432cca0ed26861e94f5aaf20975"
REPOSITORY_URL="${REPOSITORY_URL:-https://github.com/dudesahn/usds-spark-rewards.git}"
: "${ETH_RPC_URL:?Set ETH_RPC_URL to an archive-capable Ethereum mainnet RPC}"
RPC_URL="$ETH_RPC_URL"
POC_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
WORKTREE="$POC_DIR/.worktree"

if [ ! -d "$WORKTREE/.git" ]; then
    git clone --recurse-submodules "$REPOSITORY_URL" "$WORKTREE"
fi

git -C "$WORKTREE" fetch origin "$REVISION"
git -C "$WORKTREE" checkout --detach "$REVISION"
git -C "$WORKTREE" submodule update --init --recursive
cp \
    "$POC_DIR/PermissionlessAuctionPreKickReportDos.t.sol" \
    "$WORKTREE/src/test/PermissionlessAuctionPreKickReportDos.t.sol"

cd "$WORKTREE"
forge test \
    --match-contract PermissionlessAuctionPreKickReportDosTest \
    --fork-url "$RPC_URL" \
    --fork-block-number 25583832 \
    --no-storage-caching \
    --cache-path cache \
    --out out \
    --fuzz-runs 16 \
    -vv

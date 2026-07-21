#!/bin/sh
set -eu

POC_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
WORKTREE="$POC_DIR/.worktree"

if [ -d "$WORKTREE" ]; then
    rm -rf -- "$WORKTREE"
fi

REPOSITORY := https://github.com/dudesahn/usds-spark-rewards.git
REVISION := f8f796db93c52432cca0ed26861e94f5aaf20975
FORK_BLOCK := 25583450
WORKTREE := worktree
TEST_FILE := CAN006Validation.t.sol

.PHONY: setup verify test clean

setup:
	@test -d "$(WORKTREE)/.git" || git clone --no-checkout "$(REPOSITORY)" "$(WORKTREE)"
	git -C "$(WORKTREE)" fetch origin "$(REVISION)"
	git -C "$(WORKTREE)" checkout --detach "$(REVISION)"
	git -C "$(WORKTREE)" submodule update --init --recursive
	cp "$(TEST_FILE)" "$(WORKTREE)/src/test/CAN006Validation.t.sol"

verify: setup
	@test "$$(git -C "$(WORKTREE)" rev-parse HEAD)" = "$(REVISION)"
	@cmp -s "$(TEST_FILE)" "$(WORKTREE)/src/test/CAN006Validation.t.sol"

test: verify
	@test -n "$$ETH_RPC_URL" || (echo "ETH_RPC_URL must point to an archive Ethereum RPC"; exit 1)
	forge test --root "$(WORKTREE)" \
		--match-contract CAN006ValidationTest \
		--fork-url "$$ETH_RPC_URL" \
		--fork-block-number "$(FORK_BLOCK)" \
		--fuzz-runs 32 -vv

clean:
	rm -rf -- "$(WORKTREE)"

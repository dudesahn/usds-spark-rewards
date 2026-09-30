-include .env

# deps
update:; forge update
build  :; forge build
size  :; forge build --sizes

# storage inspection
inspect :; forge inspect ${contract} storageLayout

# Reproducible historical mainnet fork; requires an archive-capable RPC.
# Grove oracle tests also roll to their own historical liquidity fixtures.
FORK_URL ?= $(ETH_RPC_URL)
FORK_BLOCK ?= 26006032
export FORK_URL
FORK_ARGS = --fork-url "$$FORK_URL" --fork-block-number "$(FORK_BLOCK)"

# if we want to run only matching tests, set that here
test := test_operation_fixed

# Run both strategy families and their coexistence test on the same fork.
test: check-pools test-python
	@forge test -vv $(FORK_ARGS)

test-spark:; @forge test -vv $(FORK_ARGS) --match-path "src/test/spark/*.t.sol"
test-grove:; @forge test -vv $(FORK_ARGS) --match-path "src/test/grove/*.t.sol"
test-coexistence:; @forge test -vv $(FORK_ARGS) --match-contract CompounderCoexistenceTest
test-python:; python3 -B -m unittest discover -s scripts/tests -v
check-pools:; python3 -B scripts/generate_grove_pool_config.py --check

trace  :; @forge test -vvv $(FORK_ARGS)
gas  :; @forge test --gas-report $(FORK_ARGS)
test-contract  :; @forge test -vv --match-contract $(contract) $(FORK_ARGS)
test-contract-gas  :; @forge test --gas-report --match-contract ${contract} $(FORK_ARGS)
trace-contract  :; @forge test -vvv --match-contract $(contract) $(FORK_ARGS)
test-test  :; @forge test -vv --match-test $(test) $(FORK_ARGS)
test-test-trace  :; @forge test -vvv --match-test $(test) $(FORK_ARGS)
trace-test  :; @forge test -vvvvv --match-test $(test) $(FORK_ARGS)
snapshot :; @forge snapshot -vv $(FORK_ARGS)
snapshot-diff :; @forge snapshot --diff -vv $(FORK_ARGS)
trace-setup  :; @forge test -vvvv $(FORK_ARGS)
trace-max  :; @forge test -vvvvv $(FORK_ARGS)
coverage :; @forge coverage $(FORK_ARGS) --no-match-coverage "script|libraries|Setup.sol"
coverage-report :; @forge coverage --report lcov $(FORK_ARGS) --no-match-coverage "script|libraries|Setup.sol"
coverage-debug :; @forge coverage --report debug $(FORK_ARGS) --no-match-coverage "script|libraries|Setup.sol"

coverage-html:
	@echo "Running coverage..."
	@forge coverage --report lcov $(FORK_ARGS) --no-match-coverage "script|libraries|Setup.sol"
	@if [ "`uname`" = "Darwin" ]; then \
		lcov --ignore-errors inconsistent --remove lcov.info 'src/test/**' --output-file lcov.info; \
		genhtml --ignore-errors inconsistent -o coverage-report lcov.info; \
	else \
		lcov --remove lcov.info 'src/test/**' --output-file lcov.info; \
		genhtml -o coverage-report lcov.info; \
	fi
	@echo "Coverage report generated at coverage-report/index.html"

clean  :; forge clean

.PHONY: build size test test-spark test-grove test-coexistence test-python check-pools

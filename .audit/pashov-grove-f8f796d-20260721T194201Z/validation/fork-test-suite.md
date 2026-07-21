# Fork Test Suite

Command:

```bash
forge test -vv --fork-url https://ethereum.publicnode.com
```

Result:

```text
Ran 4 test suites in 4.64s (14.81s CPU time): 26 tests passed, 0 failed, 0 skipped (26 total tests)
```

Notable oracle log:

```text
currentAPR: 72021778685172846
```

Interpreted as a 1e18 APR value, this is approximately 7.2021778685172846%.

Environment note:

A prior `forge test -vv` run without `--fork-url` compiled successfully but failed all fork-test `setUp()` calls. The explicit fork URL is required for meaningful test execution in this repository.

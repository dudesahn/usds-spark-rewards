#!/usr/bin/env python3
"""Generate or verify the Solidity deployment pool snapshot."""

import argparse

try:
    from scripts.grove_pool_registry import (
        GENERATED_CONFIG_PATH,
        generated_config_matches,
        load_registry,
        write_generated_config,
    )
except ModuleNotFoundError as error:
    if error.name != "scripts":
        raise
    from grove_pool_registry import (
        GENERATED_CONFIG_PATH,
        generated_config_matches,
        load_registry,
        write_generated_config,
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="fail instead of writing when the generated Solidity file is stale",
    )
    args = parser.parse_args()
    registry = load_registry()

    if args.check:
        if not generated_config_matches(registry):
            raise SystemExit(
                "{} is stale; run python3 scripts/generate_grove_pool_config.py".format(
                    GENERATED_CONFIG_PATH
                )
            )
        print("{} matches the pool registry".format(GENERATED_CONFIG_PATH))
        return

    changed = write_generated_config(registry)
    print("{} {}".format(GENERATED_CONFIG_PATH, "updated" if changed else "unchanged"))


if __name__ == "__main__":
    main()

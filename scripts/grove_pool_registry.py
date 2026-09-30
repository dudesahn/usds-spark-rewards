"""Validation and Solidity generation for the GROVE V4 pool registry."""

import json
from datetime import datetime
from pathlib import Path

try:
    from scripts.grove_maintenance_common import (
        GROVE,
        SUPPORTED_QUOTE_TOKENS,
        normalize_hex,
    )
except ModuleNotFoundError as error:
    if error.name != "scripts":
        raise
    from grove_maintenance_common import GROVE, SUPPORTED_QUOTE_TOKENS, normalize_hex


MAX_ORACLE_POOLS = 10
REGISTRY_PATH = Path(__file__).with_name("grove_univ4_pool_registry.json")
GENERATED_CONFIG_PATH = REGISTRY_PATH.parents[1] / "script" / "GroveUniV4PoolConfig.sol"


def validate_pool_id(pool_id):
    normalized = normalize_hex(pool_id)
    if len(normalized) != 66 or not normalized.startswith("0x"):
        raise RuntimeError("Invalid pool ID in registry: {}".format(pool_id))
    try:
        int(normalized[2:], 16)
    except ValueError as error:
        raise RuntimeError("Invalid pool ID in registry: {}".format(pool_id)) from error
    return normalized


def load_registry(path=REGISTRY_PATH):
    try:
        with path.open() as registry_file:
            registry = json.load(registry_file)
    except (OSError, ValueError) as error:
        raise RuntimeError("Could not load pool registry {}: {}".format(path, error))

    if registry.get("version") not in (2, 3):
        raise RuntimeError("Unsupported pool registry version")
    # Discovery alone did not prove positive flow. Preserve legacy last_seen
    # fields, but start contribution history as unknown until it is measured.
    registry["version"] = 3
    if registry.get("base_token", "").lower() != GROVE.lower():
        raise RuntimeError("Pool registry base token is not GROVE")
    quote_tokens = {token.lower() for token in registry.get("quote_tokens", [])}
    if quote_tokens != SUPPORTED_QUOTE_TOKENS:
        raise RuntimeError("Pool registry quote tokens are not USDC and USDT")

    entries_by_id = {}
    for entry in registry.get("pools", []):
        pool_id = validate_pool_id(entry.get("pool_id", ""))
        if pool_id in entries_by_id:
            raise RuntimeError("Duplicate pool in registry: {}".format(pool_id))
        entry["pool_id"] = pool_id
        quote_token = entry.get("quote_token", "").lower()
        if quote_token not in SUPPORTED_QUOTE_TOKENS:
            raise RuntimeError(
                "Unsupported registry quote token for {}: {}".format(
                    pool_id, quote_token
                )
            )
        entry["quote_token"] = quote_token
        entry["last_seen_block"] = int(entry.get("last_seen_block") or 0)
        entry.setdefault("last_contributed_block", 0)
        entry.setdefault("last_contributed_at", None)
        entry.setdefault("last_contribution_sources", [])
        entry.setdefault("last_contribution_quote_sizes", [])
        block = entry["last_contributed_block"]
        if isinstance(block, bool) or not isinstance(block, int) or block < 0:
            raise RuntimeError("Invalid contribution block for {}".format(pool_id))
        observed_at = entry["last_contributed_at"]
        if bool(block) != bool(observed_at):
            raise RuntimeError("Incomplete contribution timestamp for {}".format(pool_id))
        if observed_at:
            try:
                parsed = datetime.fromisoformat(observed_at.replace("Z", "+00:00"))
                if parsed.tzinfo is None:
                    raise ValueError("timezone required")
            except (AttributeError, TypeError, ValueError) as error:
                raise RuntimeError("Invalid contribution timestamp for {}".format(pool_id)) from error
        sources = entry["last_contribution_sources"]
        sizes = entry["last_contribution_quote_sizes"]
        if not isinstance(sources, list) or any(source not in ("kyber", "oracle") for source in sources):
            raise RuntimeError("Invalid contribution sources for {}".format(pool_id))
        if not isinstance(sizes, list) or any(type(size) is not int or size <= 0 for size in sizes):
            raise RuntimeError("Invalid contribution quote sizes for {}".format(pool_id))
        entries_by_id[pool_id] = entry

    oracle_pool_ids = [validate_pool_id(pool_id) for pool_id in registry.get("oracle_pool_ids", [])]
    if not oracle_pool_ids:
        raise RuntimeError("Pool registry must define oracle_pool_ids")
    if len(oracle_pool_ids) > MAX_ORACLE_POOLS:
        raise RuntimeError(
            "Pool registry exceeds the {}-pool oracle capacity".format(
                MAX_ORACLE_POOLS
            )
        )
    if len(set(oracle_pool_ids)) != len(oracle_pool_ids):
        raise RuntimeError("Duplicate pool in oracle_pool_ids")
    for pool_id in oracle_pool_ids:
        if pool_id not in entries_by_id:
            raise RuntimeError("oracle_pool_ids contains an unregistered pool: {}".format(pool_id))
    registry["oracle_pool_ids"] = oracle_pool_ids
    return registry


def serialized_registry(registry):
    return json.dumps(registry, indent=2) + "\n"


def write_registry(registry, path=REGISTRY_PATH):
    serialized = serialized_registry(registry)
    try:
        current = path.read_text()
    except OSError:
        current = None
    if serialized == current:
        return False
    path.write_text(serialized)
    return True


def render_solidity_config(pool_ids):
    assignments = "\n".join(
        "        pools[{}] = {};".format(index, pool_id) for index, pool_id in enumerate(pool_ids)
    )
    return """// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

// GENERATED from scripts/grove_univ4_pool_registry.json.
// Run `python3 scripts/generate_grove_pool_config.py` after intentionally changing
// oracle_pool_ids, and `python3 scripts/generate_grove_pool_config.py --check`
// before deploying. Do not edit this file manually.
library GroveUniV4PoolConfig {{
    function initialPools() internal pure returns (bytes32[] memory pools) {{
        pools = new bytes32[]({});
{}
    }}
}}
""".format(len(pool_ids), assignments)


def generated_config_matches(registry, path=GENERATED_CONFIG_PATH):
    try:
        current = path.read_text()
    except OSError:
        return False
    return current == render_solidity_config(registry["oracle_pool_ids"])


def write_generated_config(registry, path=GENERATED_CONFIG_PATH):
    rendered = render_solidity_config(registry["oracle_pool_ids"])
    try:
        current = path.read_text()
    except OSError:
        current = None
    if rendered == current:
        return False
    path.write_text(rendered)
    return True

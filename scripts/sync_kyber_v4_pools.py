#!/usr/bin/env python3
"""Reconcile the APR oracle's Uniswap V4 pools with Kyber and local history.

This is a read-only dry run unless ``BROADCAST=true`` or
``APPLY_REGISTRY=true``. Broadcasting updates the onchain oracle and then the
source-controlled registry. APPLY_REGISTRY updates only the registry and its
generated Solidity deployment snapshot. Brownie supplies the active network,
contract access, account loading, and transaction handling.

By default the script asks Kyber for its unrestricted best GROVE/USDC routes at
10,000, 50,000, and 100,000 GROVE. It records any hookless Uniswap V4 first leg
that sells GROVE for either USDC or USDT. Set ``QUOTE_AMOUNTS`` to a comma-
separated list of GROVE amounts to override the probes.

Discovered pools are recorded in ``grove_univ4_pool_registry.json``. The oracle
keeps currently active pools plus the most recently active historical pools up
to ``MAX_V4_POOLS``; a pool is not removed merely because one run did not use it.

Examples:

    ORACLE=0x... brownie run sync_kyber_v4_pools --network mainnet
    ORACLE=0x... APPLY_REGISTRY=true \
        brownie run sync_kyber_v4_pools --network mainnet
    ORACLE=0x... BROADCAST=true POOL_SETTER_ACCOUNT=pool-setter \
        brownie run sync_kyber_v4_pools --network mainnet
"""

import os
from datetime import datetime, timezone

from brownie import Contract, accounts, chain

try:
    from scripts.grove_maintenance_common import (
        GROVE,
        SUPPORTED_QUOTE_TOKENS,
        ZERO_ADDRESS,
        env_bool,
        fetch_kyber_route,
        load_authorized_account,
        normalize_hex,
        positive_int_env,
        require_mainnet,
    )
    from scripts.grove_pool_registry import (
        GENERATED_CONFIG_PATH,
        REGISTRY_PATH,
        load_registry,
        serialized_registry,
        validate_pool_id,
        write_generated_config,
        write_registry,
    )
except ModuleNotFoundError as error:
    if error.name != "scripts":
        raise
    from grove_maintenance_common import (
        GROVE,
        SUPPORTED_QUOTE_TOKENS,
        ZERO_ADDRESS,
        env_bool,
        fetch_kyber_route,
        load_authorized_account,
        normalize_hex,
        positive_int_env,
        require_mainnet,
    )
    from grove_pool_registry import (
        GENERATED_CONFIG_PATH,
        REGISTRY_PATH,
        load_registry,
        serialized_registry,
        validate_pool_id,
        write_generated_config,
        write_registry,
    )


QUOTE_AMOUNT = 10_000 * 10**18
DEFAULT_QUOTE_AMOUNTS = (
    QUOTE_AMOUNT,
    50_000 * 10**18,
    100_000 * 10**18,
)
CLIENT_ID = "grove-apr-oracle-pool-sync"

ORACLE_ABI = [
    {
        "inputs": [],
        "name": "MAX_V4_POOLS",
        "outputs": [{"type": "uint256"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [],
        "name": "management",
        "outputs": [{"type": "address"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [{"type": "address"}],
        "name": "poolSetters",
        "outputs": [{"type": "bool"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [],
        "name": "uniV4PoolCount",
        "outputs": [{"type": "uint256"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [{"type": "uint256"}],
        "name": "uniV4Pool",
        "outputs": [
            {"name": "poolId", "type": "bytes32"},
            {"name": "fee", "type": "uint24"},
            {"name": "tickSpacing", "type": "int24"},
            {"name": "quoteToken", "type": "address"},
            {"name": "zeroForOne", "type": "bool"},
        ],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [{"name": "_poolIds", "type": "bytes32[]"}],
        "name": "setUniV4Pools",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function",
    },
]


def _fetch_kyber_route(amount_in, timeout):
    return fetch_kyber_route(amount_in, timeout, CLIENT_ID)


def _hookless_v4_grove_pools(route_summary):
    observations = []
    seen = set()
    for split_route in route_summary.get("route", []):
        for leg in split_route:
            pool_extra = leg.get("poolExtra") or {}
            if leg.get("exchange", "").lower() != "uniswap-v4":
                continue
            if leg.get("tokenIn", "").lower() != GROVE.lower():
                continue
            quote_token = leg.get("tokenOut", "").lower()
            if quote_token not in SUPPORTED_QUOTE_TOKENS:
                continue
            if pool_extra.get("hookAddress", "").lower() != ZERO_ADDRESS:
                continue

            unvalidated_pool_id = leg.get("pool", "")
            try:
                pool_id = validate_pool_id(unvalidated_pool_id)
            except RuntimeError as error:
                raise RuntimeError(
                    "Invalid pool ID returned by Kyber: {}".format(
                        unvalidated_pool_id
                    )
                ) from error
            if pool_id not in seen:
                seen.add(pool_id)
                observations.append(
                    {"pool_id": pool_id, "quote_token": quote_token}
                )
    return observations


def _load_oracle(oracle_address):
    require_mainnet(chain.id)

    oracle = Contract.from_abi(
        "GroveCompounderAprOracle", oracle_address, ORACLE_ABI
    )
    return oracle


def _configured_pool_entries(oracle):
    entries = []
    for index in range(oracle.uniV4PoolCount()):
        pool = oracle.uniV4Pool(index)
        entries.append(
            {
                "pool_id": normalize_hex(pool[0]),
                "quote_token": str(pool[3]).lower(),
            }
        )
    return entries


def _configured_pools(oracle):
    return [entry["pool_id"] for entry in _configured_pool_entries(oracle)]


def _record_observations(registry, observations, block_number, block_timestamp):
    entries = {entry["pool_id"]: entry for entry in registry["pools"]}
    observed_at = datetime.fromtimestamp(block_timestamp, timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )
    for observation in observations:
        pool_id = observation["pool_id"]
        quote_token = observation["quote_token"]
        entry = entries.get(pool_id)
        if entry is None:
            entry = {
                "pool_id": pool_id,
                "quote_token": quote_token,
                "last_seen_block": block_number,
                "last_seen_at": observed_at,
            }
            registry["pools"].append(entry)
            entries[pool_id] = entry
        elif entry["quote_token"] != quote_token:
            raise RuntimeError("Kyber quote token changed for {}".format(pool_id))
        elif block_number >= entry["last_seen_block"]:
            entry["last_seen_block"] = block_number
            entry["last_seen_at"] = observed_at


def _register_configured_pools(registry, configured_entries):
    registered = {entry["pool_id"]: entry for entry in registry["pools"]}
    for configured in configured_entries:
        pool_id = configured["pool_id"]
        if pool_id not in registered:
            entry = {
                "pool_id": pool_id,
                "quote_token": configured["quote_token"],
                "last_seen_block": 0,
                "last_seen_at": None,
            }
            registry["pools"].append(entry)
            registered[pool_id] = entry
        elif registered[pool_id]["quote_token"] != configured["quote_token"]:
            raise RuntimeError(
                "Configured quote token disagrees with registry for {}".format(pool_id)
            )


def _selected_pools(registry, route_pools, max_pools):
    active_order = {pool_id: index for index, pool_id in enumerate(route_pools)}
    registry_order = {
        entry["pool_id"]: index for index, entry in enumerate(registry["pools"])
    }

    def sort_key(entry):
        pool_id = entry["pool_id"]
        is_active = pool_id in active_order
        return (
            0 if is_active else 1,
            active_order.get(pool_id, 0),
            -entry["last_seen_block"],
            registry_order[pool_id],
        )

    ordered = sorted(registry["pools"], key=sort_key)
    return [entry["pool_id"] for entry in ordered[:max_pools]]


def _preserve_configured_order(configured_pools, selected_pools):
    if len(configured_pools) == len(selected_pools) and set(configured_pools) == set(
        selected_pools
    ):
        return list(configured_pools)
    return selected_pools


def _print_pools(label, pools):
    print(label)
    for pool_id in pools:
        print("  {}".format(pool_id))


def sync_pools(
    oracle,
    route_summaries,
    broadcast=False,
    apply_registry=False,
):
    observations = []
    seen = set()
    for route_summary in route_summaries:
        for observation in _hookless_v4_grove_pools(route_summary):
            pool_id = observation["pool_id"]
            if pool_id not in seen:
                seen.add(pool_id)
                observations.append(observation)

    route_pools = [observation["pool_id"] for observation in observations]
    configured_entries = _configured_pool_entries(oracle)
    configured_pools = [entry["pool_id"] for entry in configured_entries]
    max_pools = oracle.MAX_V4_POOLS()
    registry = load_registry()
    original_registry = serialized_registry(registry)
    _register_configured_pools(registry, configured_entries)
    _record_observations(
        registry,
        observations,
        chain.height,
        chain.time(),
    )
    selected_pools = _selected_pools(registry, route_pools, max_pools)
    selected_pools = _preserve_configured_order(configured_pools, selected_pools)
    retained_pools = [pool for pool in selected_pools if pool not in seen]
    evicted_pools = [
        entry["pool_id"]
        for entry in registry["pools"]
        if entry["pool_id"] not in selected_pools
    ]
    registry["oracle_pool_ids"] = selected_pools
    registry_would_change = serialized_registry(registry) != original_registry

    for route_summary in route_summaries:
        print(
            "Kyber quote: {:,} GROVE -> {:,.6f} USDC".format(
                int(route_summary["amountIn"]) // 10**18,
                int(route_summary["amountOut"]) / 10**6,
            )
        )
    print("Configured oracle pools: {} / {}".format(len(configured_pools), max_pools))
    _print_pools("Configured:", configured_pools)
    _print_pools("V4 GROVE/stable pools in Kyber best routes:", route_pools)
    if not route_pools:
        print("No compatible V4 first leg appeared in Kyber's best routes.")
    _print_pools("Retained from registry history:", retained_pools)
    _print_pools("Selected for oracle:", selected_pools)
    if evicted_pools:
        _print_pools("Outside the {}-pool capacity:".format(max_pools), evicted_pools)
    if registry_would_change:
        print("Pool registry preview: changes available (not written yet).")
    else:
        print("Pool registry preview: unchanged.")

    onchain_update_needed = configured_pools != selected_pools
    if not onchain_update_needed:
        print("Oracle already matches the retained pool selection.")
    elif not broadcast:
        print(
            "Dry run only. Re-run with BROADCAST=true and POOL_SETTER_ACCOUNT set "
            "to apply the retained pool selection."
        )
    else:
        management = oracle.management()
        sender = load_authorized_account(
            accounts,
            "POOL_SETTER_ACCOUNT",
            "oracle pool update",
            lambda address: address.lower() == management.lower()
            or oracle.poolSetters(address),
        )
        print("Applying the retained pool selection from {}...".format(sender.address))
        transaction = oracle.setUniV4Pools(selected_pools, {"from": sender})
        print("  transaction: {}".format(transaction.txid))

        updated = _configured_pools(oracle)
        if updated != selected_pools:
            raise RuntimeError("Pool sync did not produce the requested configuration")
        print("Onchain pool sync complete.")

    if apply_registry or broadcast:
        registry_updated = write_registry(registry)
        generated_updated = write_generated_config(registry)
        print(
            "Pool registry: {} ({}).".format(
                REGISTRY_PATH, "updated" if registry_updated else "unchanged"
            )
        )
        print(
            "Generated deployment config: {} ({}).".format(
                GENERATED_CONFIG_PATH, "updated" if generated_updated else "unchanged"
            )
        )
    else:
        print("Registry files left unchanged; set APPLY_REGISTRY=true to write the preview.")
    return selected_pools


def _quote_amounts():
    raw_quote_amounts = os.environ.get("QUOTE_AMOUNTS")
    if not raw_quote_amounts:
        return list(DEFAULT_QUOTE_AMOUNTS)

    amounts = []
    for value in raw_quote_amounts.split(","):
        value = value.strip().replace("_", "")
        if not value:
            raise RuntimeError("QUOTE_AMOUNTS contains an empty value")
        amount = int(value)
        if amount <= 0:
            raise RuntimeError("QUOTE_AMOUNTS values must be positive")
        amount_wei = amount * 10**18
        if amount_wei not in amounts:
            amounts.append(amount_wei)
    return amounts


def main():
    oracle_address = os.environ.get("ORACLE")
    if not oracle_address:
        raise RuntimeError("Set ORACLE to the deployed APR oracle address")

    broadcast = env_bool("BROADCAST")
    apply_registry = env_bool("APPLY_REGISTRY")

    amounts_in = _quote_amounts()
    timeout = positive_int_env("KYBER_TIMEOUT", 30)
    oracle = _load_oracle(oracle_address)
    route_summaries = []
    failures = []
    for amount_in in amounts_in:
        try:
            route_summaries.append(_fetch_kyber_route(amount_in, timeout))
        except Exception as error:
            failures.append((amount_in, error))
            print(
                "WARNING: Kyber quote failed for {:,} GROVE: {}".format(
                    amount_in // 10**18, error
                )
            )

    if not route_summaries:
        raise RuntimeError("Every configured Kyber quote failed")
    if failures and (broadcast or apply_registry):
        raise RuntimeError("Refusing to apply a partial Kyber discovery run")
    return sync_pools(oracle, route_summaries, broadcast, apply_registry)

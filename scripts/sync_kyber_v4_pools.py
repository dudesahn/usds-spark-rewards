#!/usr/bin/env python3
"""Reconcile the APR oracle's Uniswap V4 pools with Kyber and local history.

This is a read-only dry run unless ``BROADCAST=true`` or
``APPLY_REGISTRY=true``. Broadcasting updates the onchain oracle and then the
source-controlled registry. APPLY_REGISTRY updates only the registry and its
generated Solidity deployment snapshot. Brownie supplies the active network,
contract access, account loading, and transaction handling. Contract loading
leaves Brownie's deployment cache unchanged and uses no handwritten ABIs.
Set VERBOSE=true for the full pool table and file paths.
Broadcasts use a 0.01 gwei tip and a max fee of 3 * base fee + tip. A base fee
above 0.5 gwei or an unavailable fee skips the transaction and local file writes.

By default the script asks Kyber for its unrestricted best GROVE/USDC routes at
10,000, 50,000, 100,000, 500,000, and 1,000,000 GROVE. It records any hookless
Uniswap V4 first leg that sells GROVE for either USDC or USDT. Set
``QUOTE_AMOUNTS`` to a comma-separated list of GROVE amounts to override the probes.

Positive input/output flows in the Kyber probes and the oracle's fixed 10,000
GROVE quote are recorded in grove_univ4_pool_registry.json. New contributors
fill free slots or replace the least recently contributing idle pool. Pools
contributing in the current run are protected; ties keep existing selections.
Unknown contribution history is evicted first, with stable order breaking ties.
Historical entries remain in the registry after eviction. History is saved only
with APPLY_REGISTRY=true or BROADCAST=true; previews do not write files.

Examples:

    brownie run sync_kyber_v4_pools --network mainnet
    APPLY_REGISTRY=true \
        brownie run sync_kyber_v4_pools --network mainnet
    BROADCAST=true \
        brownie run sync_kyber_v4_pools --network mainnet
"""

import os
from datetime import datetime, timezone

from brownie import Contract, accounts, chain

try:
    from scripts.grove_maintenance_common import (
        GROVE,
        MAINNET_GROVE_APR_ORACLE,
        MAINNET_GROVE_STRATEGY,
        SUPPORTED_QUOTE_TOKENS,
        ZERO_ADDRESS,
        address_env,
        broadcast_transaction,
        env_bool,
        fetch_kyber_route,
        load_authorized_account,
        load_contract,
        field,
        format_age,
        print_quotes,
        section,
        status,
        normalize_hex,
        positive_int_env,
        require_mainnet,
        validate_mainnet_deployment,
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
        MAINNET_GROVE_APR_ORACLE,
        MAINNET_GROVE_STRATEGY,
        SUPPORTED_QUOTE_TOKENS,
        ZERO_ADDRESS,
        address_env,
        broadcast_transaction,
        env_bool,
        fetch_kyber_route,
        load_authorized_account,
        load_contract,
        field,
        format_age,
        print_quotes,
        section,
        status,
        normalize_hex,
        positive_int_env,
        require_mainnet,
        validate_mainnet_deployment,
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
    500_000 * 10**18,
    1_000_000 * 10**18,
)
CLIENT_ID = "grove-apr-oracle-pool-sync"


def _fetch_kyber_route(amount_in, timeout):
    return fetch_kyber_route(amount_in, timeout, CLIENT_ID)


def _hookless_v4_grove_pools(route_summary):
    observations = {}
    quote_amount = int(route_summary["amountIn"])
    if quote_amount <= 0:
        raise RuntimeError("Kyber quote amount must be positive")
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
            try:
                pool_id = validate_pool_id(leg.get("pool", ""))
            except RuntimeError as error:
                raise RuntimeError("Invalid pool ID returned by Kyber: {}".format(leg.get("pool", ""))) from error
            try:
                amount_in, amount_out = int(leg["swapAmount"]), int(leg["amountOut"])
            except (KeyError, ValueError, TypeError) as error:
                raise RuntimeError("Missing or invalid Kyber flow amounts for {}".format(pool_id)) from error
            if min(amount_in, amount_out) < 0 or amount_in > quote_amount:
                raise RuntimeError("Invalid Kyber flow amounts for {}".format(pool_id))
            if not amount_in or not amount_out:
                continue
            if pool_id not in observations:
                observations[pool_id] = {
                    "pool_id": pool_id, "quote_token": quote_token,
                    "source": "kyber", "quote_amount": quote_amount,
                    "amount_in": 0, "amount_out": 0,
                }
            observation = observations[pool_id]
            if observation["quote_token"] != quote_token:
                raise RuntimeError("Kyber quote token changed for {}".format(pool_id))
            observation["amount_in"] += amount_in
            observation["amount_out"] += amount_out
    if sum(item["amount_in"] for item in observations.values()) > quote_amount:
        raise RuntimeError("Kyber GROVE pool contributions exceed the quoted input")
    return list(observations.values())


def _read(oracle, method, *args, block_identifier=None):
    call = getattr(oracle, method)
    if block_identifier is None:
        return call(*args)
    return call.call(*args, block_identifier=block_identifier)


def _oracle_contributions(oracle, configured_entries, block_identifier=None):
    quote_amount = int(_read(oracle, "GROVE_PRICE_QUOTE_AMOUNT", block_identifier=block_identifier))
    route = _read(oracle, "quoteUniV4Route", block_identifier=block_identifier)
    if len(route) != 6:
        raise RuntimeError("Oracle returned an unexpected quote shape")
    pool_ids, allocations, outputs = route[3:6]
    expected = {entry["pool_id"]: entry["quote_token"] for entry in configured_entries}
    pool_ids = [normalize_hex(pool_id) for pool_id in pool_ids]
    if not (len(pool_ids) == len(allocations) == len(outputs) == len(expected)):
        raise RuntimeError("Oracle returned inconsistent pool allocation lengths")
    if len(set(pool_ids)) != len(pool_ids) or set(pool_ids) != set(expected):
        raise RuntimeError("Oracle quote pools differ from the configured pool snapshot")
    allocations, outputs = list(map(int, allocations)), list(map(int, outputs))
    if any(value < 0 for value in allocations + outputs):
        raise RuntimeError("Oracle returned negative pool allocations")
    if quote_amount <= 0 or sum(allocations) != int(route[1]) or not 0 <= int(route[1]) <= quote_amount:
        raise RuntimeError("Oracle returned inconsistent input allocation totals")
    if sum(outputs) != int(route[0]):
        raise RuntimeError("Oracle returned inconsistent output totals")
    observations = [
        {"pool_id": pool_id, "quote_token": expected[pool_id], "source": "oracle",
         "quote_amount": quote_amount, "amount_in": amount_in, "amount_out": amount_out}
        for pool_id, amount_in, amount_out in zip(pool_ids, allocations, outputs)
        if amount_in > 0 and amount_out > 0
    ]
    return observations, int(route[1]), quote_amount


def _load_oracle(oracle_address):
    require_mainnet(chain.id)

    return load_contract(
        Contract, oracle_address,
        ("MAX_V4_POOLS", "management", "poolSetters", "uniV4PoolCount",
         "uniV4Pool", "setUniV4Pools", "GROVE_PRICE_QUOTE_AMOUNT", "quoteUniV4Route"),
    )


def _configured_pool_entries(oracle, block_identifier=None):
    entries = []
    for index in range(_read(oracle, "uniV4PoolCount", block_identifier=block_identifier)):
        pool = _read(oracle, "uniV4Pool", index, block_identifier=block_identifier)
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
                "last_contributed_block": 0, "last_contributed_at": None,
                "last_contribution_sources": [], "last_contribution_quote_sizes": [],
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
                "last_contributed_block": 0, "last_contributed_at": None,
                "last_contribution_sources": [], "last_contribution_quote_sizes": [],
            }
            registry["pools"].append(entry)
            registered[pool_id] = entry
        elif registered[pool_id]["quote_token"] != configured["quote_token"]:
            raise RuntimeError(
                "Configured quote token disagrees with registry for {}".format(pool_id)
            )


def _record_contributions(registry, observations, block_number, block_timestamp):
    entries = {entry["pool_id"]: entry for entry in registry["pools"]}
    grouped = {}
    for observation in observations:
        if observation["amount_in"] > 0 and observation["amount_out"] > 0:
            grouped.setdefault(observation["pool_id"], []).append(observation)
    observed_at = datetime.fromtimestamp(block_timestamp, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    for pool_id, contributions in grouped.items():
        entry = entries[pool_id]
        previous = entry.get("last_contributed_block", 0)
        if block_number < previous:
            continue
        sources = {item["source"] for item in contributions}
        sizes = {item["quote_amount"] // 10**18 for item in contributions}
        if block_number == previous:
            sources.update(entry.get("last_contribution_sources", []))
            sizes.update(entry.get("last_contribution_quote_sizes", []))
        entry.update(
            last_contributed_block=block_number, last_contributed_at=observed_at,
            last_contribution_sources=sorted(sources), last_contribution_quote_sizes=sorted(sizes),
        )


def _selected_pools(registry, contributors, max_pools, current_timestamp, configured_pools=None):
    del current_timestamp  # Recency is ordered by the recorded observation block.
    selected = list(registry["oracle_pool_ids"] if configured_pools is None else configured_pools)
    if len(selected) > max_pools or len(set(selected)) != len(selected):
        raise RuntimeError("Invalid initial oracle pool selection")
    entries = {entry["pool_id"]: entry for entry in registry["pools"]}
    protected = set(contributors)
    for pool_id in contributors:
        if pool_id in selected:
            continue
        if pool_id not in entries:
            raise RuntimeError("Unregistered contributing pool: {}".format(pool_id))
        if len(selected) < max_pools:
            selected.append(pool_id)
            continue
        idle = [pool for pool in selected if pool not in protected]
        if not idle:
            continue  # All slots contributed now: preserve incumbents on recency ties.
        victim = min(idle, key=lambda pool: (
            entries[pool].get("last_contributed_block", 0), selected.index(pool)
        ))
        selected[selected.index(victim)] = pool_id
    return selected


def _contribution_age(entry, timestamp):
    observed_at = entry.get("last_contributed_at")
    if not observed_at:
        return "no recorded contribution"
    observed = datetime.fromisoformat(observed_at.replace("Z", "+00:00"))
    return "{} ago".format(format_age(timestamp - int(observed.timestamp())))


def _preserve_configured_order(configured_pools, selected_pools):
    if len(configured_pools) == len(selected_pools) and set(configured_pools) == set(
        selected_pools
    ):
        return list(configured_pools)
    return selected_pools


def _print_pools(label, pools):
    if pools:
        print("  {}".format(label))
        for pool_id in pools:
            print("    {}".format(pool_id))


def sync_pools(
    oracle,
    route_summaries,
    broadcast=False,
    apply_registry=False,
    block_identifier=None,
    block_timestamp=None,
):
    kyber_observations = []
    for route_summary in route_summaries:
        kyber_observations.extend(_hookless_v4_grove_pools(route_summary))
    configured_entries = _configured_pool_entries(oracle, block_identifier)
    configured_pools = [entry["pool_id"] for entry in configured_entries]
    max_pools = int(_read(oracle, "MAX_V4_POOLS", block_identifier=block_identifier))
    oracle_observations, allocated, oracle_quote_amount = _oracle_contributions(
        oracle, configured_entries, block_identifier
    )
    observations = kyber_observations + oracle_observations
    contributors = list(dict.fromkeys(item["pool_id"] for item in observations))
    contributing_now = set(contributors)
    kyber_pools = {item["pool_id"] for item in kyber_observations}
    oracle_pools = {item["pool_id"] for item in oracle_observations}
    block_number = chain.height if block_identifier is None else block_identifier
    current_timestamp = chain.time() if block_timestamp is None else block_timestamp
    registry = load_registry()
    original_registry = serialized_registry(registry)
    if any(entry.get("last_contributed_block", 0) > block_number for entry in registry["pools"]):
        raise RuntimeError("Registry contribution history is newer than this snapshot; retry with current state")
    _register_configured_pools(registry, configured_entries)
    _record_observations(registry, kyber_observations, block_number, current_timestamp)
    _record_contributions(registry, observations, block_number, current_timestamp)
    selected_pools = _selected_pools(
        registry, contributors, max_pools, current_timestamp, configured_pools
    )
    selected_pools = _preserve_configured_order(configured_pools, selected_pools)
    retained_pools = [pool for pool in selected_pools if pool not in contributing_now]
    historical_pools = [entry["pool_id"] for entry in registry["pools"] if entry["pool_id"] not in selected_pools]
    capacity_excluded_pools = [pool for pool in contributors if pool not in selected_pools]
    registry["oracle_pool_ids"] = selected_pools
    registry_would_change = serialized_registry(registry) != original_registry

    section("💱 Kyber discovery quotes")
    print_quotes(route_summaries)
    section("🧩 Pool selection")
    additions = [pool for pool in selected_pools if pool not in configured_pools]
    removals = [pool for pool in configured_pools if pool not in selected_pools]
    field("Oracle slots", "{} / {} in use".format(len(configured_pools), max_pools))
    field("Kyber pools", "{} contributing, across {} quote sizes".format(len(kyber_pools), len(route_summaries)))
    field("Oracle pools", "{} contributing; {:,} / {:,} GROVE allocated".format(
        len(oracle_pools), allocated // 10**18, oracle_quote_amount // 10**18
    ))
    field("Proposed changes", "+{} / -{} pools".format(len(additions), len(removals)))
    field("Retained", "{} idle pool(s) kept as historical fallbacks".format(len(retained_pools)))
    field("History only", "{} pool(s) outside the selected list".format(len(historical_pools)))
    _print_pools("Add current contributors:", additions)
    entries_by_id = {entry["pool_id"]: entry for entry in registry["pools"]}
    if removals:
        print("  Replace idle pools (unknown history first, then oldest contribution):")
        for pool_id in removals:
            print("    {} — {}".format(pool_id, _contribution_age(entries_by_id[pool_id], current_timestamp)))
    if not kyber_pools:
        status("INFO", "No positive-flow compatible V4 leg in Kyber; retaining oracle contributors and history.")
    if capacity_excluded_pools:
        status("WARN", "{} contributor(s) exceed the {} slots; every selected pool contributed in this run.".format(
            len(capacity_excluded_pools), max_pools
        ))
        _print_pools("Excluded from the oracle:", capacity_excluded_pools)
    if env_bool("VERBOSE"):
        print("\n  {:66}  {:7} {:7} {:7} {:7} {}".format("Pool ID", "Current", "Next", "Kyber", "Oracle", "Last contribution"))
        for entry in registry["pools"]:
            pool_id = entry["pool_id"]
            print("  {:66}  {:7} {:7} {:7} {:7} {}".format(
                pool_id, "yes" if pool_id in configured_pools else "-",
                "yes" if pool_id in selected_pools else "-", "yes" if pool_id in kyber_pools else "-",
                "yes" if pool_id in oracle_pools else "-", _contribution_age(entry, current_timestamp),
            ))

    onchain_update_needed = configured_pools != selected_pools
    broadcast_skipped = False
    if onchain_update_needed:
        # eth_call validates the setter and pool configs without modifying state
        # or unlocking an account, including in preview/registry-only mode.
        oracle.setUniV4Pools.call(selected_pools, {"from": oracle.management()})
        status("OK", "Proposed pool configuration passes an onchain setter simulation.")
    if not onchain_update_needed:
        onchain_result = "UNCHANGED — no transaction; selected pool list already matches"

    elif not broadcast:
        onchain_result = "PREVIEW — pool changes available; use BROADCAST=true to apply"
    else:
        management = oracle.management()
        transaction = broadcast_transaction(
            chain, oracle.setUniV4Pools, selected_pools,
            load_sender=lambda: load_authorized_account(
                accounts,
                "oracle pool update",
                lambda address: address.lower() == management.lower()
                or oracle.poolSetters(address),
            ),
        )
        if transaction is None:
            broadcast_skipped = True
            onchain_result = "SKIPPED — gas policy blocked the pool transaction"
        else:
            field("Transaction", transaction.txid)
            updated = _configured_pools(oracle)
            if updated != selected_pools:
                raise RuntimeError("Pool sync did not produce the requested configuration")
            onchain_result = "UPDATED — pool selection confirmed onchain"

    if broadcast_skipped:
        registry_result = "NOT WRITTEN — pool transaction skipped"
        generated_result = "NOT WRITTEN — pool transaction skipped"
    elif apply_registry or broadcast:
        registry_updated = write_registry(registry)
        generated_updated = write_generated_config(registry)
        registry_result = "UPDATED" if registry_updated else "UNCHANGED"
        generated_result = "UPDATED" if generated_updated else "UNCHANGED"
    else:
        registry_result = "NOT WRITTEN — preview has changes" if registry_would_change else "UNCHANGED"
        generated_result = "NOT WRITTEN — preview only"
    section("📋 Result")
    field("Onchain oracle", onchain_result)
    field("Local registry", registry_result)
    field("Deployment config", generated_result)
    if not (apply_registry or broadcast) and registry_would_change:
        status("INFO", "APPLY_REGISTRY=true saves the local registry; BROADCAST=true also applies oracle changes.")
    if capacity_excluded_pools:
        status("WARN", "Ties favor existing pools; no current contributor was evicted.")
    status("INFO", "Positive quote contributions update history; idle slots are replaced only when new contributors need room.")
    status("INFO", "Setter simulation checks pool validity, not resulting quote coverage; refresh_grove_price checks the resulting V4 route.")
    if env_bool("VERBOSE"):
        field("Registry file", REGISTRY_PATH)
        field("Generated file", GENERATED_CONFIG_PATH)
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
    oracle_address = address_env("ORACLE", MAINNET_GROVE_APR_ORACLE)
    strategy_address = address_env("STRATEGY", MAINNET_GROVE_STRATEGY)

    broadcast = env_bool("BROADCAST")
    apply_registry = env_bool("APPLY_REGISTRY")
    mode = "BROADCAST" if broadcast else "LOCAL REGISTRY ONLY" if apply_registry else "PREVIEW — no changes"
    section("🌿 Grove pool sync | {}".format(mode))

    amounts_in = _quote_amounts()
    timeout = positive_int_env("KYBER_TIMEOUT", 30)
    oracle = _load_oracle(oracle_address)
    validate_mainnet_deployment(Contract, oracle_address, strategy_address)
    route_summaries = []
    failures = []
    for amount_in in amounts_in:
        try:
            route_summaries.append(_fetch_kyber_route(amount_in, timeout))
        except Exception as error:
            failures.append((amount_in, error))
            status("WARN", "Kyber quote unavailable for {:,} GROVE: {}".format(
                amount_in // 10**18, error
            ))

    if not route_summaries:
        status("ERROR", "No quotes succeeded. Oracle and registry were not changed.")
        raise RuntimeError("Every configured Kyber quote failed")
    if failures:
        section("💱 Partial Kyber results")
        print_quotes(route_summaries)
        status("ERROR", "Only {} / {} quotes succeeded. Oracle and registry were not changed; retry discovery.".format(
            len(route_summaries), len(amounts_in)
        ))
        raise RuntimeError("Refusing to select pools from a partial Kyber discovery run")
    # Pin all allocation reads to one recent block, after the Kyber probes.
    snapshot = chain[-1]
    return sync_pools(
        oracle, route_summaries, broadcast, apply_registry,
        block_identifier=snapshot.number, block_timestamp=snapshot.timestamp,
    )

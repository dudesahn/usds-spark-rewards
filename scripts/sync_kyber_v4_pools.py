#!/usr/bin/env python3
"""Reconcile the APR oracle's Uniswap V4 pools with a Kyber route.

This is a dry run unless ``BROADCAST=true``. Brownie supplies the active network,
contract access, account loading, and transaction handling.

Examples:

    ORACLE=0x... brownie run sync_kyber_v4_pools --network mainnet
    ORACLE=0x... BROADCAST=true POOL_SETTER_ACCOUNT=pool-setter \
        brownie run sync_kyber_v4_pools --network mainnet
"""

import json
import os
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from brownie import Contract, accounts, chain


GROVE = "0xB30FE1Cf884B48a22a50D22a9282004F2c5E9406"
USDC = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
QUOTE_AMOUNT = 10_000 * 10**18
KYBER_URL = "https://aggregator-api.kyberswap.com/ethereum/api/v1/routes"
CLIENT_ID = "grove-apr-oracle-pool-sync"
ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"

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
        ],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [{"name": "_poolId", "type": "bytes32"}],
        "name": "addUniV4Pool",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function",
    },
]


def _normalize_hex(value):
    if isinstance(value, bytes):
        return "0x" + value.hex()
    return str(value).lower()


def _fetch_kyber_route(amount_in, timeout):
    query = urlencode(
        {"tokenIn": GROVE, "tokenOut": USDC, "amountIn": str(amount_in)}
    )
    request = Request(
        "{}?{}".format(KYBER_URL, query),
        headers={"X-Client-Id": CLIENT_ID},
    )
    with urlopen(request, timeout=timeout) as response:
        payload = json.load(response)

    if payload.get("code") != 0:
        raise RuntimeError("Kyber route request failed: {}".format(payload))
    return payload["data"]["routeSummary"]


def _direct_hookless_v4_pools(route_summary):
    pools = []
    seen = set()
    for split_route in route_summary.get("route", []):
        for leg in split_route:
            pool_extra = leg.get("poolExtra") or {}
            if leg.get("exchange", "").lower() != "uniswap-v4":
                continue
            if leg.get("tokenIn", "").lower() != GROVE.lower():
                continue
            if leg.get("tokenOut", "").lower() != USDC.lower():
                continue
            if pool_extra.get("hookAddress", "").lower() != ZERO_ADDRESS:
                continue

            pool_id = leg.get("pool", "").lower()
            if len(pool_id) != 66 or not pool_id.startswith("0x"):
                raise RuntimeError("Invalid pool ID returned by Kyber: {}".format(pool_id))
            if pool_id not in seen:
                seen.add(pool_id)
                pools.append(pool_id)
    return pools


def _load_oracle(oracle_address):
    if chain.id != 1:
        raise RuntimeError("Expected Ethereum mainnet chain ID 1, got {}".format(chain.id))

    oracle = Contract.from_abi(
        "GroveCompounderAprOracle", oracle_address, ORACLE_ABI
    )
    return oracle


def _configured_pools(oracle):
    return [
        _normalize_hex(oracle.uniV4Pool(index)[0])
        for index in range(oracle.uniV4PoolCount())
    ]


def _print_pools(label, pools):
    print(label)
    for pool_id in pools:
        print("  {}".format(pool_id))


def sync_pools(oracle, route_summary, broadcast=False, account_name=None):
    route_pools = _direct_hookless_v4_pools(route_summary)
    if not route_pools:
        raise RuntimeError(
            "Kyber returned no direct hookless Uniswap V4 GROVE/USDC pools"
        )

    configured_pools = _configured_pools(oracle)
    configured = set(configured_pools)
    missing_pools = [pool for pool in route_pools if pool not in configured]
    max_pools = oracle.MAX_V4_POOLS()

    print(
        "Kyber quote: {:,} GROVE -> {:,.6f} USDC".format(
            int(route_summary["amountIn"]) // 10**18,
            int(route_summary["amountOut"]) / 10**6,
        )
    )
    print("Configured oracle pools: {} / {}".format(len(configured_pools), max_pools))
    _print_pools("Configured:", configured_pools)
    _print_pools("Kyber direct V4 route:", route_pools)

    if not missing_pools:
        print("Oracle already contains every eligible V4 pool in the Kyber route.")
        return []

    _print_pools("Missing:", missing_pools)
    if len(configured_pools) + len(missing_pools) > max_pools:
        raise RuntimeError(
            "Adding the missing pools would exceed MAX_V4_POOLS={}; review removals "
            "manually".format(max_pools)
        )

    if not broadcast:
        print(
            "Dry run only. Re-run with BROADCAST=true and POOL_SETTER_ACCOUNT set "
            "to add them."
        )
        return missing_pools

    if not account_name:
        raise RuntimeError("BROADCAST=true requires POOL_SETTER_ACCOUNT")

    sender = accounts.load(account_name)
    management = oracle.management()
    if sender.address.lower() != management.lower() and not oracle.poolSetters(
        sender.address
    ):
        raise RuntimeError(
            "{} is neither oracle management nor an authorized pool setter".format(
                sender.address
            )
        )

    for pool_id in missing_pools:
        print("Adding {} from {}...".format(pool_id, sender.address))
        transaction = oracle.addUniV4Pool(pool_id, {"from": sender})
        print("  transaction: {}".format(transaction.txid))

    updated = set(_configured_pools(oracle))
    unadded = [pool for pool in missing_pools if pool not in updated]
    if unadded:
        raise RuntimeError("Pool sync did not add: {}".format(", ".join(unadded)))

    print("Pool sync complete.")
    return missing_pools


def _positive_int(name, default):
    value = int(os.environ.get(name, default))
    if value <= 0:
        raise RuntimeError("{} must be positive".format(name))
    return value


def _broadcast_enabled():
    value = os.environ.get("BROADCAST", "false").lower()
    if value not in ("true", "false"):
        raise RuntimeError("BROADCAST must be 'true' or 'false'")
    return value == "true"


def main():
    oracle_address = os.environ.get("ORACLE")
    if not oracle_address:
        raise RuntimeError("Set ORACLE to the deployed APR oracle address")

    broadcast = _broadcast_enabled()
    account_name = os.environ.get("POOL_SETTER_ACCOUNT")
    if broadcast and not account_name:
        raise RuntimeError("BROADCAST=true requires POOL_SETTER_ACCOUNT")

    amount_in = _positive_int("AMOUNT_IN", QUOTE_AMOUNT)
    timeout = _positive_int("KYBER_TIMEOUT", 30)
    oracle = _load_oracle(oracle_address)
    route_summary = _fetch_kyber_route(amount_in, timeout)
    return sync_pools(oracle, route_summary, broadcast, account_name)

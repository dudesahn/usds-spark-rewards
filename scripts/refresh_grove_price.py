#!/usr/bin/env python3
"""Refresh the APR oracle's cached GROVE price from its live Uniswap V4 route.

The contract owns the policy and this script avoids unnecessary transactions:

* an incomplete 10,000 GROVE route does nothing;
* moves below 5% only refresh after the 12-hour heartbeat;
* moves from 5% through 10% update immediately; and
* moves above 10% require a second consistent observation 30 minutes to
  6 hours after the first.

This is a dry run unless ``BROADCAST=true``.

Examples:

    ORACLE=0x... brownie run refresh_grove_price --network mainnet
    ORACLE=0x... BROADCAST=true PRICE_SETTER_ACCOUNT=pool-setter \
        brownie run refresh_grove_price --network mainnet
"""

import os

from brownie import Contract, accounts, chain


ORACLE_ABI = [
    {
        "inputs": [],
        "name": "GROVE_PRICE_QUOTE_AMOUNT",
        "outputs": [{"type": "uint256"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [],
        "name": "CACHE_UPDATE_THRESHOLD_BPS",
        "outputs": [{"type": "uint256"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [],
        "name": "LARGE_PRICE_MOVE_BPS",
        "outputs": [{"type": "uint256"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [],
        "name": "CACHE_HEARTBEAT",
        "outputs": [{"type": "uint256"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [],
        "name": "PRICE_CONFIRMATION_DELAY",
        "outputs": [{"type": "uint256"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [],
        "name": "PRICE_CONFIRMATION_WINDOW",
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
        "name": "cachedGrovePrice",
        "outputs": [{"type": "uint256"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [],
        "name": "lastPriceVerification",
        "outputs": [{"type": "uint64"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [],
        "name": "pendingGrovePrice",
        "outputs": [{"type": "uint256"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [],
        "name": "pendingPriceTimestamp",
        "outputs": [{"type": "uint64"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [],
        "name": "quoteUniV4Route",
        "outputs": [
            {"name": "totalAmountOut", "type": "uint256"},
            {"name": "amountAllocated", "type": "uint256"},
            {"name": "price", "type": "uint256"},
            {"name": "poolIds", "type": "bytes32[]"},
            {"name": "allocations", "type": "uint256[]"},
            {"name": "outputs", "type": "uint256[]"},
        ],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [],
        "name": "refreshCachedGrovePrice",
        "outputs": [
            {"name": "livePrice", "type": "uint256"},
            {"name": "priceUpdated", "type": "bool"},
            {"name": "confirmationPending", "type": "bool"},
        ],
        "stateMutability": "nonpayable",
        "type": "function",
    },
]


def _load_oracle(oracle_address):
    if chain.id != 1:
        raise RuntimeError("Expected Ethereum mainnet chain ID 1, got {}".format(chain.id))
    return Contract.from_abi("GroveCompounderAprOracle", oracle_address, ORACLE_ABI)


def _broadcast_enabled():
    value = os.environ.get("BROADCAST", "false").lower()
    if value not in ("true", "false"):
        raise RuntimeError("BROADCAST must be 'true' or 'false'")
    return value == "true"


def _deviation_bps(price, reference_price):
    if reference_price == 0:
        return 0
    return abs(price - reference_price) * 10_000 // reference_price


def _format_price(price):
    return "{:.8f} USDC/GROVE".format(price / 10**18)


def _refresh_action(oracle, live_price, now):
    cached_price = int(oracle.cachedGrovePrice())
    verified_at = int(oracle.lastPriceVerification())
    pending_price = int(oracle.pendingGrovePrice())
    pending_at = int(oracle.pendingPriceTimestamp())

    threshold = int(oracle.CACHE_UPDATE_THRESHOLD_BPS())
    large_move = int(oracle.LARGE_PRICE_MOVE_BPS())
    heartbeat = int(oracle.CACHE_HEARTBEAT())
    confirmation_delay = int(oracle.PRICE_CONFIRMATION_DELAY())
    confirmation_window = int(oracle.PRICE_CONFIRMATION_WINDOW())

    if cached_price == 0:
        return "initialize cache", True

    deviation = _deviation_bps(live_price, cached_price)
    if deviation > large_move:
        if pending_price and pending_at:
            pending_age = max(0, now - pending_at)
            observations_agree = _deviation_bps(live_price, pending_price) <= threshold
            if observations_agree and confirmation_delay <= pending_age <= confirmation_window:
                return "confirm large price move", True
            if observations_agree and pending_age <= confirmation_window:
                wait = max(0, confirmation_delay - pending_age)
                return "large move confirmation waiting another {} seconds".format(wait), False
        return "stage large price move for confirmation", True

    if pending_price or pending_at:
        return "clear obsolete large-move confirmation", True
    if deviation >= threshold:
        return "update cached price ({} bps move)".format(deviation), True
    if verified_at == 0 or now >= verified_at + heartbeat:
        return "refresh 12-hour verification heartbeat", True
    return "no update needed ({} bps move; heartbeat current)".format(deviation), False


def main():
    oracle_address = os.environ.get("ORACLE")
    if not oracle_address:
        raise RuntimeError("Set ORACLE to the deployed APR oracle address")

    oracle = _load_oracle(oracle_address)
    route = oracle.quoteUniV4Route()
    amount_allocated = int(route[1])
    live_price = int(route[2])
    quote_amount = int(oracle.GROVE_PRICE_QUOTE_AMOUNT())

    print("Live route: {:,} / {:,} GROVE allocated".format(amount_allocated // 10**18, quote_amount // 10**18))
    if amount_allocated != quote_amount or live_price == 0:
        print("Live route is incomplete; cached price was not changed or verified.")
        return False

    cached_price = int(oracle.cachedGrovePrice())
    print("Live price:   {}".format(_format_price(live_price)))
    print("Cached price: {}".format(_format_price(cached_price)) if cached_price else "Cached price: not initialized")

    action, should_transact = _refresh_action(oracle, live_price, chain.time())
    print("Decision: {}".format(action))
    if not should_transact:
        return False

    if not _broadcast_enabled():
        print("Dry run only. Re-run with BROADCAST=true to execute this refresh.")
        return True

    account_name = os.environ.get("PRICE_SETTER_ACCOUNT") or os.environ.get("POOL_SETTER_ACCOUNT")
    if not account_name:
        raise RuntimeError("BROADCAST=true requires PRICE_SETTER_ACCOUNT or POOL_SETTER_ACCOUNT")

    sender = accounts.load(account_name)
    management = oracle.management()
    if sender.address.lower() != management.lower() and not oracle.poolSetters(sender.address):
        raise RuntimeError(
            "{} is neither oracle management nor an authorized pool setter".format(sender.address)
        )

    transaction = oracle.refreshCachedGrovePrice({"from": sender})
    print("Refresh transaction: {}".format(transaction.txid))
    print("Cached price after refresh: {}".format(_format_price(int(oracle.cachedGrovePrice()))))
    if int(oracle.pendingGrovePrice()):
        print("Large price move remains pending confirmation.")
    return True

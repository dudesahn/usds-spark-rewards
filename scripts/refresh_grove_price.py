#!/usr/bin/env python3
"""Maintain the GROVE APR price and review the auction floor.

The oracle uses its live 10,000 GROVE Uniswap V4 route whenever that price is
within 50% of the stored reference. Otherwise it keeps using the stored price.
This script is intended to be run manually around twice per day:

* a sane live V4 price refreshes the stored fallback only when it is manual,
  at least 72 hours old, or at least 10% away from the live price;
* a massive live move requires an interactive confirmation;
* when V4 cannot fill the quote, an unrestricted Kyber quote is discounted 5%
  in this script and stored as the manual fallback; and
* an auction-floor recommendation that differs by at least 10% is offered as
  an interactive update in the same run.

No transaction is sent unless ``BROADCAST=true``.

Examples:

    ORACLE=0x... STRATEGY=0x... brownie run refresh_grove_price --network mainnet

    ORACLE=0x... STRATEGY=0x... BROADCAST=true \
        POOL_SETTER_ACCOUNT=oracle-pool-setter \
        PRICE_SETTER_ACCOUNT=oracle-price-setter \
        STRATEGY_MANAGEMENT_ACCOUNT=strategy-management \
        brownie run refresh_grove_price --network mainnet
"""

import os
import sys

import click
from brownie import Contract, accounts, chain

try:
    from scripts.grove_maintenance_common import (
        MAX_BPS,
        ZERO_ADDRESS,
        deviation_bps as _deviation_bps,
        env_bool,
        fetch_kyber_route,
        format_price as _format_price,
        load_authorized_account,
        positive_int_env,
        require_mainnet,
    )
except ModuleNotFoundError as error:
    if error.name != "scripts":
        raise
    from grove_maintenance_common import (
        MAX_BPS,
        ZERO_ADDRESS,
        deviation_bps as _deviation_bps,
        env_bool,
        fetch_kyber_route,
        format_price as _format_price,
        load_authorized_account,
        positive_int_env,
        require_mainnet,
    )


MANUAL_PRICE_HAIRCUT_BPS = 500
AUCTION_FLOOR_DISCOUNT_BPS = 2_000
AUCTION_UPDATE_THRESHOLD_BPS = 1_000
STORED_PRICE_UPDATE_THRESHOLD_BPS = 1_000
STORED_PRICE_MAX_AGE = 72 * 60 * 60
KYBER_CLIENT_ID = "grove-apr-oracle-price-refresh"

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
        "name": "MAX_LIVE_PRICE_DEVIATION_BPS",
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
        "inputs": [{"type": "address"}],
        "name": "priceSetters",
        "outputs": [{"type": "bool"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [],
        "name": "storedGrovePrice",
        "outputs": [{"type": "uint256"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [],
        "name": "lastPriceUpdate",
        "outputs": [{"type": "uint64"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [],
        "name": "storedPriceIsManual",
        "outputs": [{"type": "bool"}],
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
        "name": "refreshStoredGrovePrice",
        "outputs": [{"name": "livePrice", "type": "uint256"}],
        "stateMutability": "nonpayable",
        "type": "function",
    },
    {
        "inputs": [{"name": "_expectedPrice", "type": "uint256"}],
        "name": "confirmLiveGrovePrice",
        "outputs": [{"name": "livePrice", "type": "uint256"}],
        "stateMutability": "nonpayable",
        "type": "function",
    },
    {
        "inputs": [{"name": "_price", "type": "uint256"}],
        "name": "setManualGrovePrice",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function",
    },
]

STRATEGY_ABI = [
    {
        "inputs": [],
        "name": "management",
        "outputs": [{"type": "address"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [],
        "name": "auction",
        "outputs": [{"type": "address"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [],
        "name": "minimumAuctionPrice",
        "outputs": [{"type": "uint256"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [{"name": "_minimumAuctionPrice", "type": "uint256"}],
        "name": "setMinimumAuctionPrice",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function",
    },
]

AUCTION_ABI = [
    {
        "inputs": [],
        "name": "minimumPrice",
        "outputs": [{"type": "uint256"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [],
        "name": "isAnActiveAuction",
        "outputs": [{"type": "bool"}],
        "stateMutability": "view",
        "type": "function",
    },
]


def _load_oracle(address):
    require_mainnet(chain.id)
    return Contract.from_abi("GroveCompounderAprOracle", address, ORACLE_ABI)


def _fetch_kyber_price(amount_in, timeout):
    route = fetch_kyber_route(amount_in, timeout, KYBER_CLIENT_ID)
    amount_out = int(route["amountOut"])
    return amount_out * 10**30 // amount_in, route


def _interactive_confirm(message):
    if not sys.stdin.isatty():
        print("Confirmation skipped because stdin is not interactive.")
        return False
    return click.confirm(message, default=False)


def _load_authorized_account(oracle, env_name, role):
    management = oracle.management()
    return load_authorized_account(
        accounts,
        env_name,
        "oracle {} setter".format(role),
        lambda address: address.lower() == management.lower()
        or (oracle.poolSetters(address) if role == "pool" else oracle.priceSetters(address)),
    )


def _refresh_reason(stored_price, age, deviation, replace_manual=False):
    if stored_price == 0:
        return "initialize the stored fallback"
    if replace_manual:
        return "replace the manual fallback with a live V4 price"
    if deviation >= STORED_PRICE_UPDATE_THRESHOLD_BPS:
        return "the price moved {} bps".format(deviation)
    if age >= STORED_PRICE_MAX_AGE:
        return "the stored fallback reached 72 hours old"
    return None


def _refresh_from_live(oracle, live_price, stored_price, stored_is_manual, age, broadcast):
    max_deviation = int(oracle.MAX_LIVE_PRICE_DEVIATION_BPS())
    deviation = _deviation_bps(live_price, stored_price)
    if stored_price and deviation > max_deviation:
        print(
            "ALERT: live V4 price is {} bps away from the stored price; "
            "the APR oracle will continue using the stored price.".format(deviation)
        )
        if not broadcast:
            print("Broadcast mode would ask whether to confirm this live price.")
            return stored_price, "stored fallback (live price awaiting confirmation)"
        if not _interactive_confirm(
            "Confirm {} as the new stored GROVE price?".format(_format_price(live_price))
        ):
            return stored_price, "stored fallback (live price not confirmed)"

        sender = _load_authorized_account(oracle, "PRICE_SETTER_ACCOUNT", "price")
        transaction = oracle.confirmLiveGrovePrice(live_price, {"from": sender})
        print("Confirmed live-price transaction: {}".format(transaction.txid))
        return live_price, "confirmed live V4"

    reason = _refresh_reason(stored_price, age, deviation, stored_is_manual)
    if reason is None:
        print(
            "Stored-price refresh: skipped "
            "({} bps move; stored fallback under 72 hours old).".format(deviation)
        )
        return live_price, "live V4 (stored fallback unchanged)"

    if broadcast:
        sender = _load_authorized_account(oracle, "POOL_SETTER_ACCOUNT", "pool")
        transaction = oracle.refreshStoredGrovePrice({"from": sender})
        print("Stored-price refresh transaction ({}): {}".format(reason, transaction.txid))
    else:
        print(
            "Dry run: the live V4 price would refresh the stored fallback "
            "because {}.".format(reason)
        )
    return live_price, "live V4"


def _refresh_from_kyber(oracle, quote_amount, stored_price, age, broadcast):
    quoted_price, route = _fetch_kyber_price(
        quote_amount, positive_int_env("KYBER_TIMEOUT", 30)
    )
    conservative_price = quoted_price * (MAX_BPS - MANUAL_PRICE_HAIRCUT_BPS) // MAX_BPS
    print("Price source: unrestricted Kyber executable quote")
    print(
        "Kyber quote: {:,} GROVE -> {:,.6f} USDC".format(
            int(route["amountIn"]) // 10**18, int(route["amountOut"]) / 10**6
        )
    )
    print("Quoted price:       {}".format(_format_price(quoted_price)))
    print(
        "Conservative price: {} ({} bps script haircut)".format(
            _format_price(conservative_price), MANUAL_PRICE_HAIRCUT_BPS
        )
    )

    deviation = _deviation_bps(conservative_price, stored_price)
    massive = stored_price and deviation > int(oracle.MAX_LIVE_PRICE_DEVIATION_BPS())
    if massive:
        print(
            "ALERT: proposed manual price is {} bps away from the stored price.".format(
                deviation
            )
        )
        if not broadcast:
            print("Broadcast mode would ask whether to confirm this manual price.")
            return stored_price, "stored fallback (manual price awaiting confirmation)"
        if not _interactive_confirm(
            "Store {} as the new manual GROVE price?".format(_format_price(conservative_price))
        ):
            return stored_price, "stored fallback (manual price not confirmed)"

    reason = _refresh_reason(stored_price, age, deviation)
    if reason is None:
        print(
            "Manual-price update: skipped "
            "({} bps move; stored fallback under 72 hours old).".format(deviation)
        )
        return conservative_price, "manual Kyber quote (stored fallback unchanged)"

    if broadcast:
        sender = _load_authorized_account(oracle, "PRICE_SETTER_ACCOUNT", "price")
        transaction = oracle.setManualGrovePrice(conservative_price, {"from": sender})
        print("Manual-price transaction ({}): {}".format(reason, transaction.txid))
    else:
        print(
            "Dry run: the conservative Kyber price would become the stored fallback "
            "because {}.".format(reason)
        )
    return conservative_price, "manual Kyber (5% haircut)"


def _review_auction_floor(strategy_address, selected_price, source, broadcast):
    if not strategy_address:
        print("Auction check: skipped (set STRATEGY to enable it)")
        return

    strategy = Contract.from_abi("GroveCompounder", strategy_address, STRATEGY_ABI)
    auction_address = strategy.auction()
    if str(auction_address).lower() == ZERO_ADDRESS:
        raise RuntimeError("Strategy auction address is zero")
    auction = Contract.from_abi("Auction", auction_address, AUCTION_ABI)

    strategy_floor = int(strategy.minimumAuctionPrice())
    auction_floor = int(auction.minimumPrice())
    target_floor = selected_price * (MAX_BPS - AUCTION_FLOOR_DISCOUNT_BPS) // MAX_BPS
    change_bps = _deviation_bps(target_floor, auction_floor)

    print("Auction reference: {} ({})".format(_format_price(selected_price), source))
    print("Strategy floor:    {}".format(_format_price(strategy_floor, "USDS")))
    print("Auction floor:     {}".format(_format_price(auction_floor, "USDS")))
    print("Recommended floor: {} (20% below reference)".format(_format_price(target_floor, "USDS")))

    mismatch = strategy_floor != auction_floor
    significant = auction_floor == 0 or change_bps >= AUCTION_UPDATE_THRESHOLD_BPS
    if not mismatch and not significant:
        print(
            "Auction check: no significant floor update needed "
            "({} bps change).".format(change_bps)
        )
        return

    if mismatch:
        print("ALERT: strategy and Auction minimum prices disagree.")
    if significant:
        print("ALERT: recommended auction floor differs by {} bps.".format(change_bps))

    if auction.isAnActiveAuction():
        print(
            "ALERT: an auction is active; the floor update is deferred until it ends."
        )
        return

    if not broadcast:
        print("Broadcast mode would ask whether to update the auction floor.")
        return
    if not _interactive_confirm(
        "Update the auction floor to {}?".format(_format_price(target_floor, "USDS"))
    ):
        print("Auction floor left unchanged.")
        return

    management = strategy.management()
    sender = load_authorized_account(
        accounts,
        "STRATEGY_MANAGEMENT_ACCOUNT",
        "auction floor update",
        lambda address: address.lower() == management.lower(),
    )
    transaction = strategy.setMinimumAuctionPrice(target_floor, {"from": sender})
    print("Auction-floor transaction: {}".format(transaction.txid))


def main():
    oracle_address = os.environ.get("ORACLE")
    if not oracle_address:
        raise RuntimeError("Set ORACLE to the deployed APR oracle address")

    oracle = _load_oracle(oracle_address)
    broadcast = env_bool("BROADCAST")
    quote_amount = int(oracle.GROVE_PRICE_QUOTE_AMOUNT())
    stored_price = int(oracle.storedGrovePrice())
    last_update = int(oracle.lastPriceUpdate())
    age = max(0, chain.time() - last_update) if stored_price else 0
    stored_is_manual = bool(oracle.storedPriceIsManual()) if stored_price else False

    if stored_price:
        source = "manual" if stored_is_manual else "onchain"
        print(
            "Stored price: {} ({}; {} seconds old)".format(
                _format_price(stored_price), source, age
            )
        )
        if age >= STORED_PRICE_MAX_AGE:
            print("ALERT: stored GROVE price is at least 72 hours old.")
    else:
        print("Stored price: not initialized")

    route = oracle.quoteUniV4Route()
    amount_allocated = int(route[1])
    live_price = int(route[2])
    print(
        "Live V4 route: {:,} / {:,} GROVE allocated".format(
            amount_allocated // 10**18, quote_amount // 10**18
        )
    )

    if amount_allocated == quote_amount and live_price:
        print("Live V4 price: {}".format(_format_price(live_price)))
        selected_price, selected_source = _refresh_from_live(
            oracle, live_price, stored_price, stored_is_manual, age, broadcast
        )
    else:
        print("Live V4 route is incomplete; using the manual Kyber fallback.")
        selected_price, selected_source = _refresh_from_kyber(
            oracle, quote_amount, stored_price, age, broadcast
        )

    if selected_price == 0:
        raise RuntimeError("No usable GROVE price is available")
    print("Selected price: {} ({})".format(_format_price(selected_price), selected_source))
    _review_auction_floor(
        os.environ.get("STRATEGY"), selected_price, selected_source, broadcast
    )
    return True

#!/usr/bin/env python3
"""Maintain the GROVE APR reference price and review the auction floor.

This script is intended to run around twice per day. It always obtains an
unrestricted 100,000 GROVE Kyber quote and stores the raw per-GROVE price when
the reference is uninitialized, at least 36 hours old, or at least 10% away
from the new quote. A move over 50% requires interactive confirmation.

The script also monitors the oracle's 10,000 GROVE Uniswap V4 fallback, prints
the effective onchain price/status/APR, and offers an auction-floor update when
the recommendation differs by at least 10%.

No transaction is sent unless ``BROADCAST=true``. Contract loading leaves
Brownie's deployment cache unchanged and uses no handwritten ABIs.

Examples:

    brownie run refresh_grove_price --network mainnet

    BROADCAST=true \
        brownie run refresh_grove_price --network mainnet
"""

import os
import sys

import click
from brownie import Contract, accounts, chain

try:
    from scripts.grove_maintenance_common import (
        MAX_BPS,
        MAINNET_GROVE_APR_ORACLE,
        MAINNET_GROVE_STRATEGY,
        ZERO_ADDRESS,
        address_env,
        deviation_bps as _deviation_bps,
        env_bool,
        fetch_kyber_route,
        format_price as _format_price,
        load_authorized_account,
        load_contract,
        positive_int_env,
        require_mainnet,
        validate_mainnet_deployment,
    )
except ModuleNotFoundError as error:
    if error.name != "scripts":
        raise
    from grove_maintenance_common import (
        MAX_BPS,
        MAINNET_GROVE_APR_ORACLE,
        MAINNET_GROVE_STRATEGY,
        ZERO_ADDRESS,
        address_env,
        deviation_bps as _deviation_bps,
        env_bool,
        fetch_kyber_route,
        format_price as _format_price,
        load_authorized_account,
        load_contract,
        positive_int_env,
        require_mainnet,
        validate_mainnet_deployment,
    )


AUCTION_FLOOR_DISCOUNT_BPS = 2_000
AUCTION_UPDATE_THRESHOLD_BPS = 1_000
STORED_PRICE_UPDATE_THRESHOLD_BPS = 1_000
STORED_PRICE_REFRESH_AGE = 36 * 60 * 60
STORED_PRICE_VALIDITY = 72 * 60 * 60
STORED_PRICE_DECAY_START = 7 * 24 * 60 * 60
DEFAULT_KYBER_QUOTE_GROVE = 100_000
KYBER_CLIENT_ID = "grove-apr-oracle-price-refresh"

PRICE_STATUS_NAMES = {
    0: "unavailable",
    1: "fresh stored reference",
    2: "live V4 fallback",
    3: "stale stored reference",
    4: "decaying stored reference",
}

def _load_oracle(address):
    require_mainnet(chain.id)
    return load_contract(
        Contract, address,
        ("GROVE_PRICE_QUOTE_AMOUNT", "MAX_LIVE_PRICE_DEVIATION_BPS", "management",
         "priceSetters", "storedGrovePrice", "lastPriceUpdate", "grovePriceWithStatus",
         "quoteUniV4Route", "setGrovePrice", "aprAfterDebtChange"),
    )


def _fetch_kyber_price(amount_in, timeout):
    route = fetch_kyber_route(amount_in, timeout, KYBER_CLIENT_ID)
    amount_out = int(route["amountOut"])
    return amount_out * 10**30 // amount_in, route


def _kyber_quote_amount():
    grove_amount = positive_int_env(
        "KYBER_QUOTE_AMOUNT", DEFAULT_KYBER_QUOTE_GROVE
    )
    return grove_amount * 10**18


def _interactive_confirm(message):
    if not sys.stdin.isatty():
        print("Confirmation skipped because stdin is not interactive.")
        return False
    return click.confirm(message, default=False)


def _load_authorized_account(oracle):
    management = oracle.management()
    return load_authorized_account(
        accounts,
        "oracle price setter",
        lambda address: address.lower() == management.lower()
        or oracle.priceSetters(address),
    )


def _refresh_reason(stored_price, age, deviation):
    if stored_price == 0:
        return "initialize the stored reference"
    if deviation >= STORED_PRICE_UPDATE_THRESHOLD_BPS:
        return "the price moved {} bps".format(deviation)
    if age >= STORED_PRICE_REFRESH_AGE:
        return "the stored reference reached 36 hours old"
    return None


def _refresh_from_kyber(oracle, quote_amount, stored_price, age, broadcast):
    quoted_price, route = _fetch_kyber_price(
        quote_amount, positive_int_env("KYBER_TIMEOUT", 30)
    )
    print("Price source: unrestricted Kyber executable quote")
    print(
        "Kyber quote: {:,} GROVE -> {:,.6f} USDC".format(
            int(route["amountIn"]) // 10**18, int(route["amountOut"]) / 10**6
        )
    )
    print("Reference price: {} (no haircut)".format(_format_price(quoted_price)))

    deviation = _deviation_bps(quoted_price, stored_price)
    massive = stored_price and deviation > int(oracle.MAX_LIVE_PRICE_DEVIATION_BPS())
    if massive:
        print(
            "ALERT: proposed Kyber price is {} bps away from the stored price.".format(
                deviation
            )
        )
        if not broadcast:
            print("Broadcast mode would ask whether to confirm this reference price.")
            return quoted_price, "Kyber reference (update awaiting confirmation)"
        if not _interactive_confirm(
            "Store {} as the new GROVE reference price?".format(_format_price(quoted_price))
        ):
            return quoted_price, "Kyber reference (update not confirmed)"

    reason = _refresh_reason(stored_price, age, deviation)
    if reason is None:
        print(
            "Reference-price update: skipped "
            "({} bps move; stored reference under 36 hours old).".format(deviation)
        )
        return quoted_price, "Kyber reference (stored reference unchanged)"

    if broadcast:
        sender = _load_authorized_account(oracle)
        transaction = oracle.setGrovePrice(quoted_price, {"from": sender})
        print("Reference-price transaction ({}): {}".format(reason, transaction.txid))
    else:
        print(
            "Dry run: the raw Kyber price would become the stored reference "
            "because {}.".format(reason)
        )
    return quoted_price, "Kyber executable reference"


def _print_oracle_status(oracle, strategy_address):
    selected_price, raw_status = oracle.grovePriceWithStatus()
    selected_price = int(selected_price)
    status = int(raw_status)
    print(
        "Effective oracle price: {} ({})".format(
            _format_price(selected_price),
            PRICE_STATUS_NAMES.get(status, "unknown status {}".format(status)),
        )
    )
    oracle_apr = int(oracle.aprAfterDebtChange(strategy_address, 0))
    print("Estimated current APR: {:.4f}%".format(oracle_apr / 10**16))


def _review_auction_floor(strategy_address, selected_price, source, broadcast):
    if not strategy_address:
        print("Auction check: skipped (set STRATEGY to enable it)")
        return

    # Shared TokenizedStrategy methods and Grove's own methods live at the same
    # address, but use separate verified interfaces without merging or caching.
    base = load_contract(Contract, strategy_address, ("management",))
    strategy = load_contract(
        Contract, strategy_address,
        ("auction", "minimumAuctionPrice", "setMinimumAuctionPrice"), strategy=True,
    )
    auction_address = strategy.auction()
    if str(auction_address).lower() == ZERO_ADDRESS:
        raise RuntimeError("Strategy auction address is zero")
    auction = load_contract(Contract, auction_address, ("minimumPrice", "isAnActiveAuction"))

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

    management = base.management()
    sender = load_authorized_account(
        accounts,
        "auction floor update",
        lambda address: address.lower() == management.lower(),
    )
    transaction = strategy.setMinimumAuctionPrice(target_floor, {"from": sender})
    print("Auction-floor transaction: {}".format(transaction.txid))


def main():
    oracle_address = address_env("ORACLE", MAINNET_GROVE_APR_ORACLE)
    strategy_address = address_env("STRATEGY", MAINNET_GROVE_STRATEGY)

    oracle = _load_oracle(oracle_address)
    validate_mainnet_deployment(Contract, oracle_address, strategy_address)
    broadcast = env_bool("BROADCAST")
    quote_amount = int(oracle.GROVE_PRICE_QUOTE_AMOUNT())
    stored_price = int(oracle.storedGrovePrice())
    last_update = int(oracle.lastPriceUpdate())
    age = max(0, chain.time() - last_update) if stored_price else 0

    if stored_price:
        print(
            "Stored reference: {} ({} seconds old)".format(
                _format_price(stored_price), age
            )
        )
        if age >= STORED_PRICE_DECAY_START:
            print("ALERT: stored GROVE reference is at least seven days old.")
        elif age >= STORED_PRICE_VALIDITY:
            print("ALERT: stored GROVE price is at least 72 hours old.")
    else:
        print("Stored reference: not initialized")

    kyber_price, kyber_source = _refresh_from_kyber(
        oracle, _kyber_quote_amount(), stored_price, age, broadcast
    )

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
        print(
            "V4/Kyber divergence: {} bps".format(
                _deviation_bps(live_price, kyber_price)
            )
        )
    else:
        print("ALERT: live V4 fallback route is incomplete.")

    _print_oracle_status(oracle, strategy_address)
    _review_auction_floor(
        strategy_address, kyber_price, kyber_source, broadcast
    )
    return True

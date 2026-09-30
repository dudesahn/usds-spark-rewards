#!/usr/bin/env python3
"""Maintain the GROVE APR reference price and review the auction floor.

This script is intended to run around twice per day. By default it obtains an
unrestricted 500,000 GROVE Kyber quote and stores the raw per-GROVE price when
the reference is uninitialized, at least 36 hours old, or at least 10% away
from the new quote. A move over 50% requires interactive confirmation.
Additional 100,000 and 1,000,000 GROVE quotes show total proceeds and the
average price for comparison; they do not set the reference or auction floor.
Set KYBER_QUOTE_AMOUNT to override the reference size in whole GROVE.

The script also monitors the oracle's 10,000 GROVE Uniswap V4 fallback, prints
the effective onchain price/status/APR, and offers an auction-floor update when
the recommendation differs by at least 10%.

No transaction is sent unless ``BROADCAST=true``. Contract loading leaves
Brownie's deployment cache unchanged and uses no handwritten ABIs.
Broadcasts use a 0.01 gwei tip and a max fee of 3 * base fee + tip, and are
skipped with a warning when the current base fee exceeds 0.5 gwei or is unavailable.
Set VERBOSE=true to include full deployment addresses.

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
        broadcast_transaction,
        deviation_bps as _deviation_bps,
        env_bool,
        fetch_kyber_route,
        format_price as _format_price,
        load_authorized_account,
        load_contract,
        field,
        format_age,
        print_quotes,
        section,
        status,
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
        broadcast_transaction,
        deviation_bps as _deviation_bps,
        env_bool,
        fetch_kyber_route,
        format_price as _format_price,
        load_authorized_account,
        load_contract,
        field,
        format_age,
        print_quotes,
        section,
        status,
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
DEFAULT_KYBER_QUOTE_GROVE = 500_000
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


def _print_kyber_comparison_quotes(reference_amount, reference_routes=()):
    timeout = positive_int_env("KYBER_TIMEOUT", 30)
    routes = list(reference_routes)
    failures = []
    for grove_amount in (100_000, 500_000, 1_000_000):
        amount_in = grove_amount * 10**18
        if amount_in == reference_amount:
            continue  # Already fetched as the operator-selected reference quote.
        try:
            _, route = _fetch_kyber_price(amount_in, timeout)
            routes.append(route)
        except Exception as error:
            failures.append((grove_amount, error))
    print("\n  Kyber quotes (GROVE -> USDC)")
    print_quotes(sorted(routes, key=lambda route: int(route["amountIn"])), reference_amount)
    for grove_amount, error in failures:
        status("WARN", "Comparison unavailable for {:,} GROVE: {}".format(grove_amount, error))


def _interactive_confirm(message):
    if not sys.stdin.isatty():
        status("WARN", "Confirmation requires an interactive terminal; update skipped.")
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


def _refresh_from_kyber(
    oracle, quote_amount, stored_price, age, broadcast, quote_rows=None, result_lines=None
):
    def result(level, message):
        if result_lines is None:
            status(level, message)
        else:
            result_lines.append((level, message))

    quoted_price, route = _fetch_kyber_price(
        quote_amount, positive_int_env("KYBER_TIMEOUT", 30)
    )
    if quote_rows is not None:
        quote_rows.append(route)

    deviation = _deviation_bps(quoted_price, stored_price)
    massive = stored_price and deviation > int(oracle.MAX_LIVE_PRICE_DEVIATION_BPS())
    if massive:
        status("REVIEW", "Price move exceeds the confirmation threshold ({:.2f}%).".format(deviation / 100))
        if not broadcast:
            result("PREVIEW", "Reference update needs confirmation in BROADCAST mode; no transaction sent.")
            return quoted_price, "Kyber reference (update awaiting confirmation)"
        if not _interactive_confirm(
            "Store {} as the new GROVE reference price?".format(_format_price(quoted_price))
        ):
            result("KEEP", "Reference update was not confirmed; stored price unchanged.")
            return quoted_price, "Kyber reference (update not confirmed)"

    reason = _refresh_reason(stored_price, age, deviation)
    if reason is None:
        result("KEEP", "No reference update needed: age <36h and price move <10%.")
        return quoted_price, "Kyber reference (stored reference unchanged)"

    if broadcast:
        field("Reference update", "Store {} from the {:,} GROVE quote: {}.".format(
            _format_price(quoted_price), quote_amount // 10**18, reason
        ))
        transaction = broadcast_transaction(
            chain, oracle.setGrovePrice, quoted_price,
            load_sender=lambda: _load_authorized_account(oracle),
        )
        if transaction is None:
            result("WAIT", "Stored reference unchanged; price transaction skipped.")
            return quoted_price, "Kyber reference (broadcast skipped)"
        result("UPDATED", "Stored reference price refreshed ({}).".format(reason))
        field("Transaction", transaction.txid)
    else:
        result("PREVIEW", "Would store {}: {}. No transaction sent.".format(
            _format_price(quoted_price), reason
        ))
    return quoted_price, "Kyber executable reference"


def _print_oracle_status(oracle, strategy_address):
    selected_price, raw_status = oracle.grovePriceWithStatus()
    selected_price = int(selected_price)
    price_status = int(raw_status)
    print()
    field("Oracle uses", _format_price(selected_price))
    field("Selected source", PRICE_STATUS_NAMES.get(price_status, "unknown status {}".format(price_status)))
    oracle_apr = int(oracle.aprAfterDebtChange(strategy_address, 0))
    field("Estimated APR", "{:.4f}% (strategy oracle)".format(oracle_apr / 10**16))
    if price_status == 0:
        status("ACTION", "Oracle has no usable price; refresh its reference or repair the V4 fallback.")
    return price_status


def _review_auction_floor(strategy_address, selected_price, source, broadcast):
    section("🔨 Auction floor")
    if not strategy_address:
        status("SKIP", "Set STRATEGY to enable the auction check.")
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

    field("Live Kyber price", "{} ({:,} GROVE quote)".format(
        _format_price(selected_price), _kyber_quote_amount() // 10**18
    ))
    if strategy_floor == auction_floor:
        field("Current floor", "{} (strategy and auction agree)".format(_format_price(auction_floor, "USDS")))
    else:
        field("Strategy floor", _format_price(strategy_floor, "USDS"))
        field("Auction floor", _format_price(auction_floor, "USDS"))
    field("Suggested floor", "{} (20% below live Kyber quote)".format(_format_price(target_floor, "USDS")))

    mismatch = strategy_floor != auction_floor
    significant = auction_floor == 0 or change_bps >= AUCTION_UPDATE_THRESHOLD_BPS
    if not mismatch and not significant:
        status("KEEP", "Floor change is {:.2f}%, below the 10% threshold; no update needed.".format(change_bps / 100))
        return

    if mismatch:
        status("REVIEW", "Strategy and auction floors disagree.")
    if significant:
        status("REVIEW", "Suggested floor differs by {:.2f}%.".format(change_bps / 100))

    if auction.isAnActiveAuction():
        status("WAIT", "Auction is active; defer the floor update until it ends.")
        return

    if not broadcast:
        status("PREVIEW", "Floor update needs confirmation in BROADCAST mode.")
        return

    def load_sender():
        if not _interactive_confirm(
            "Update the auction floor to {}?".format(_format_price(target_floor, "USDS"))
        ):
            status("KEEP", "Floor update declined; no change made.")
            return None
        management = base.management()
        return load_authorized_account(
            accounts,
            "auction floor update",
            lambda address: address.lower() == management.lower(),
        )

    transaction = broadcast_transaction(
        chain, strategy.setMinimumAuctionPrice, target_floor, load_sender=load_sender,
    )
    if transaction is None:
        return
    status("UPDATED", "Auction floor updated.")
    field("Transaction", transaction.txid)


def main():
    oracle_address = address_env("ORACLE", MAINNET_GROVE_APR_ORACLE)
    strategy_address = address_env("STRATEGY", MAINNET_GROVE_STRATEGY)

    broadcast = env_bool("BROADCAST")
    section("🌿 Grove price refresh | {}".format("BROADCAST" if broadcast else "PREVIEW — no transactions"))
    oracle = _load_oracle(oracle_address)
    validate_mainnet_deployment(Contract, oracle_address, strategy_address)
    quote_amount = int(oracle.GROVE_PRICE_QUOTE_AMOUNT())
    stored_price = int(oracle.storedGrovePrice())
    last_update = int(oracle.lastPriceUpdate())
    age = max(0, chain.time() - last_update) if stored_price else 0

    section("💰 Pricing & APR")
    if stored_price:
        field("Stored at start", _format_price(stored_price))
        field("Age at start", "{} ({:.1f} hours)".format(format_age(age), age / 3600))
        if age > STORED_PRICE_DECAY_START:
            status("WARN", "Reference is beyond 7 days; without valid V4 pricing its value decays to zero by day 14.")
        elif age > STORED_PRICE_VALIDITY:
            status("WARN", "Reference is stale (>72h); a valid V4 quote now has priority.")
    else:
        field("Stored at start", "not initialized")

    reference_amount = _kyber_quote_amount()
    quote_rows, result_lines = [], []
    kyber_price, kyber_source = _refresh_from_kyber(
        oracle, reference_amount, stored_price, age, broadcast,
        quote_rows=quote_rows, result_lines=result_lines,
    )
    _print_kyber_comparison_quotes(reference_amount, quote_rows)
    if stored_price:
        signed_move = (kyber_price - stored_price) * 100 / stored_price
        field("Reference move", "{:+.2f}% vs stored price at start".format(signed_move))
    price_status = _print_oracle_status(oracle, strategy_address)

    route = oracle.quoteUniV4Route()
    amount_allocated = int(route[1])
    live_price = int(route[2])
    field("V4 quote coverage", "{:,} / {:,} GROVE ({:.2f}%)".format(
        amount_allocated // 10**18, quote_amount // 10**18,
        amount_allocated * 100 / quote_amount if quote_amount else 0,
    ))
    if amount_allocated == quote_amount and live_price:
        field("V4 price", _format_price(live_price))
        field("V4 vs Kyber", "{:.2f}% difference".format(_deviation_bps(live_price, kyber_price) / 100))
        status("OK", "V4 quote covers the full requested amount.")
    else:
        status("ACTION", "V4 quote is incomplete, so it cannot be used as the fallback price.")

    if price_status == 1:
        status("INFO", "Fresh stored reference has priority for 72h, even if V4 is available.")
    elif price_status == 2:
        status("INFO", "Stored reference is stale or unset; using an acceptable live V4 price.")
    elif price_status == 3:
        status("WARN", "No acceptable V4 price; using the stale reference at full value through day 7.")
    elif price_status == 4:
        status("WARN", "No acceptable V4 price; the stale reference is decaying toward zero at day 14.")
    print()
    for level, message in result_lines:
        status(level, message)
    field("Age policy", "36h: refresh due | 72h: prefer V4")
    field("If V4 unavailable", "Day 7: stored price starts decaying | Day 14: zero price / APR")

    _review_auction_floor(
        strategy_address, kyber_price, kyber_source, broadcast
    )
    return True

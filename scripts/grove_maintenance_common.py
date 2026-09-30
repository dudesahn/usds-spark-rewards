"""Shared plumbing for the GROVE maintenance scripts."""

import json
import os
import ssl
from unittest.mock import patch
from urllib.parse import urlencode
from urllib.request import Request, urlopen


MAX_BPS = 10_000
GROVE = "0xB30FE1Cf884B48a22a50D22a9282004F2c5E9406"
USDC = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
USDT = "0xdAC17F958D2ee523a2206206994597C13D831ec7"
SUPPORTED_QUOTE_TOKENS = {USDC.lower(), USDT.lower()}
ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"
KYBER_URL = "https://aggregator-api.kyberswap.com/ethereum/api/v1/routes"

# Current Ethereum mainnet deployment. Environment variables with these names
# remain available as explicit overrides for migrations and fork testing.
MAINNET_GROVE_APR_ORACLE = "0xae71A2F0089fa802a55FcB2152BEF87A2C9Aadf9"
MAINNET_GROVE_STRATEGY = "0xe060B80438771f13078048c3b0d930efECA6E622"
YEARN_APR_ORACLE = "0x1981AD9F44F2EA9aDd2dC4AD7D075c102C70aF92"
USDS_1_VAULT = "0x182863131F9a4630fF9E27830d945B1413e347E8"
DEFAULT_BROWNIE_ACCOUNT = "llc2"


def load_contract(contract_factory, address, required_methods, strategy=False):
    """Use canonical metadata, or the approved strategy self-address override."""
    # Keep Brownie optional for the standalone pool-registry generator.
    from brownie._config import CONFIG

    previous_autofetch = CONFIG.settings["autofetch_sources"]
    try:
        # Contract(address) needs this to fetch canonical metadata on cache misses.
        CONFIG.settings["autofetch_sources"] = True
        # Brownie's recursive explorer paths can ignore persist=False.
        with patch("brownie.network.contract._add_deployment", return_value=None):
            if strategy:
                contract = contract_factory.from_explorer(
                    address, as_proxy_for=address, persist=False
                )
            else:
                contract = contract_factory(address)
    finally:
        CONFIG.settings["autofetch_sources"] = previous_autofetch

    missing = [method for method in required_methods if not hasattr(contract, method)]
    if missing:
        raise RuntimeError(
            "{}: resolved {}; missing {}. No alternate ABI was loaded.".format(
                address, contract._name, ", ".join(missing)
            )
        )
    return contract


def env_bool(name, default=False):
    value = os.environ.get(name, str(default).lower()).lower()
    if value not in ("true", "false"):
        raise RuntimeError("{} must be 'true' or 'false'".format(name))
    return value == "true"


def positive_int_env(name, default):
    value = int(os.environ.get(name, default))
    if value <= 0:
        raise RuntimeError("{} must be positive".format(name))
    return value


def address_env(name, default):
    value = os.environ.get(name, default).strip()
    if not value:
        raise RuntimeError("{} cannot be empty".format(name))
    return value


def require_mainnet(chain_id):
    if chain_id != 1:
        raise RuntimeError("Expected Ethereum mainnet chain ID 1, got {}".format(chain_id))


def normalize_hex(value):
    if isinstance(value, bytes):
        return "0x" + value.hex()
    return str(value).lower()


def deviation_bps(price, reference):
    if reference == 0:
        return 0
    return abs(price - reference) * MAX_BPS // reference


def format_price(price, unit="USDC"):
    return "{:.8f} {}/GROVE".format(price / 10**18, unit)


def section(title):
    print("\n{}".format(title))
    print("-" * len(title))


def field(label, value):
    print("  {:<18} {}".format(label, value))


def status(level, message):
    icon = {
        "OK": "✅", "KEEP": "✅", "UPDATED": "✅", "INFO": "ℹ️",
        "WARN": "⚠️", "REVIEW": "⚠️", "ACTION": "⚠️", "ERROR": "❌",
        "PREVIEW": "👀", "WAIT": "⏳", "SKIP": "ℹ️", "SEND": "🔄",
    }.get(level, "•")
    print("  {} {}: {}".format(icon, level, message))


def format_age(seconds):
    minutes = max(0, int(seconds)) // 60
    days, minutes = divmod(minutes, 24 * 60)
    hours, minutes = divmod(minutes, 60)
    if days:
        return "{}d {}h".format(days, hours)
    if hours:
        return "{}h {}m".format(hours, minutes)
    return "{}m".format(minutes) if minutes else "<1m"


def print_quotes(routes, reference_amount=None):
    print("  {:>12}  {:>16}  {:>14}  {}".format(
        "GROVE", "USDC proceeds", "USDC/GROVE", "Use" if reference_amount else ""
    ).rstrip())
    for route in routes:
        amount_in, amount_out = int(route["amountIn"]), int(route["amountOut"])
        purpose = ""
        if reference_amount is not None:
            purpose = "refresh + floor" if amount_in == reference_amount else "comparison only"
        price = amount_out * 10**30 // amount_in
        print("  {:>12,}  {:>16,.6f}  {:>14.8f}  {}".format(
            amount_in // 10**18, amount_out / 10**6, price / 10**18, purpose
        ).rstrip())


def load_authorized_account(accounts, description, is_authorized):
    account_name = os.environ.get("BROWNIE_ACCOUNT", DEFAULT_BROWNIE_ACCOUNT)
    sender = accounts.load(account_name)
    if not is_authorized(sender.address):
        raise RuntimeError(
            "Brownie account {} ({}) is not authorized for {}".format(
                account_name, sender.address, description
            )
        )
    return sender


def validate_mainnet_deployment(contract_factory, oracle_address, strategy_address):
    """Verify the deployed strategy/oracle link and report USDS-1 queue status."""
    yearn_oracle_address = address_env("YEARN_APR_ORACLE", YEARN_APR_ORACLE)
    yearn_oracle = load_contract(contract_factory, yearn_oracle_address, ("oracles",))
    registered_oracle = normalize_hex(yearn_oracle.oracles(strategy_address))
    expected_oracle = normalize_hex(oracle_address)
    if registered_oracle != expected_oracle:
        raise RuntimeError(
            "Yearn APR oracle {} maps strategy {} to {}, expected {}".format(
                yearn_oracle_address,
                strategy_address,
                registered_oracle,
                expected_oracle,
            )
        )
    status("OK", "Yearn APR registry links this strategy to the expected oracle.")

    vault_address = address_env("USDS_1_VAULT", USDS_1_VAULT)
    vault = load_contract(contract_factory, vault_address, ("get_default_queue",))
    queue = [normalize_hex(address) for address in vault.get_default_queue()]
    strategy_in_queue = normalize_hex(strategy_address) in queue
    if strategy_in_queue:
        status("OK", "Strategy is in the USDS-1 default queue.")
    else:
        status(
            "WARN", "Strategy is not in the USDS-1 default queue; check whether this is intended."
        )
    if env_bool("VERBOSE"):
        field("Strategy", strategy_address)
        field("APR oracle", oracle_address)
        field("USDS-1 vault", vault_address)
    return strategy_in_queue


def _tls_context():
    candidates = (ssl.get_default_verify_paths().cafile, "/etc/ssl/cert.pem")
    for cafile in candidates:
        if cafile and os.path.isfile(cafile):
            return ssl.create_default_context(cafile=cafile)
    return ssl.create_default_context()


def fetch_kyber_route(amount_in, timeout, client_id):
    """Fetch Kyber's unrestricted best GROVE -> USDC route."""
    query = urlencode({"tokenIn": GROVE, "tokenOut": USDC, "amountIn": str(amount_in)})
    request = Request(
        "{}?{}".format(KYBER_URL, query),
        headers={
            "Accept": "application/json",
            "User-Agent": "grove-apr-oracle/1.0",
            "X-Client-Id": client_id,
        },
    )
    with urlopen(request, timeout=timeout, context=_tls_context()) as response:
        payload = json.load(response)

    if payload.get("code") != 0:
        raise RuntimeError("Kyber route request failed: {}".format(payload))

    route = payload["data"]["routeSummary"]
    if int(route["amountIn"]) != amount_in or int(route["amountOut"]) <= 0:
        raise RuntimeError("Kyber returned an invalid quote amount")
    return route

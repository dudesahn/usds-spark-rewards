"""Shared plumbing for the GROVE maintenance scripts."""

import json
import os
import ssl
from urllib.parse import urlencode
from urllib.request import Request, urlopen


MAX_BPS = 10_000
GROVE = "0xB30FE1Cf884B48a22a50D22a9282004F2c5E9406"
USDC = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
USDT = "0xdAC17F958D2ee523a2206206994597C13D831ec7"
SUPPORTED_QUOTE_TOKENS = {USDC.lower(), USDT.lower()}
ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"
KYBER_URL = "https://aggregator-api.kyberswap.com/ethereum/api/v1/routes"


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


def load_authorized_account(accounts, env_name, description, is_authorized):
    account_name = os.environ.get(env_name)
    if not account_name:
        raise RuntimeError("Set {} to submit the {} transaction".format(env_name, description))
    sender = accounts.load(account_name)
    if not is_authorized(sender.address):
        raise RuntimeError("{} is not authorized for {}".format(sender.address, description))
    return sender


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

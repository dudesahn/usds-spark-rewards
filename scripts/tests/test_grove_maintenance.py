import copy
import importlib
import os
import sys
import types
import unittest
from unittest.mock import patch


if "brownie" not in sys.modules:
    brownie = types.ModuleType("brownie")
    brownie.Contract = object()
    brownie.accounts = object()
    brownie.chain = types.SimpleNamespace(id=1, height=123, time=lambda: 456)
    sys.modules["brownie"] = brownie

if "click" not in sys.modules:
    click = types.ModuleType("click")
    click.confirm = lambda message, default=False: default
    sys.modules["click"] = click


price_script = importlib.import_module("scripts.refresh_grove_price")
sync_script = importlib.import_module("scripts.sync_kyber_v4_pools")
registry_module = importlib.import_module("scripts.grove_pool_registry")


class FakeOracle:
    def __init__(self, registry):
        entries = {entry["pool_id"]: entry for entry in registry["pools"]}
        self.pool_ids = list(registry["oracle_pool_ids"])
        self.quote_tokens = [entries[pool_id]["quote_token"] for pool_id in self.pool_ids]
        self.set_calls = 0

    def uniV4PoolCount(self):
        return len(self.pool_ids)

    def uniV4Pool(self, index):
        return (self.pool_ids[index], 0, 0, self.quote_tokens[index], False)

    def MAX_V4_POOLS(self):
        return 10

    def setUniV4Pools(self, pool_ids, transaction):
        self.set_calls += 1
        self.pool_ids = list(pool_ids)


class FakePriceOracle:
    def __init__(self, max_deviation_bps=5_000):
        self.max_deviation_bps = max_deviation_bps
        self.confirm_calls = []
        self.manual_calls = []

    def MAX_LIVE_PRICE_DEVIATION_BPS(self):
        return self.max_deviation_bps

    def confirmLiveGrovePrice(self, expected_price, transaction):
        self.confirm_calls.append((expected_price, transaction))
        return types.SimpleNamespace(txid="0xconfirm")

    def setManualGrovePrice(self, price, transaction):
        self.manual_calls.append((price, transaction))
        return types.SimpleNamespace(txid="0xmanual")


class FakeStrategy:
    def __init__(self, floor):
        self.floor = floor
        self.floor_updates = []

    def auction(self):
        return "0x0000000000000000000000000000000000000001"

    def minimumAuctionPrice(self):
        return self.floor

    def management(self):
        return "0x0000000000000000000000000000000000000002"

    def setMinimumAuctionPrice(self, price, transaction):
        self.floor_updates.append((price, transaction))
        return types.SimpleNamespace(txid="0xfloor")


class FakeAuction:
    def __init__(self, floor, active):
        self.floor = floor
        self.active = active

    def minimumPrice(self):
        return self.floor

    def isAnActiveAuction(self):
        return self.active


class MaintenancePolicyTest(unittest.TestCase):
    def test_stored_price_refresh_policy(self):
        self.assertEqual(
            price_script._refresh_reason(0, 0, 0),
            "initialize the stored fallback",
        )
        self.assertIsNone(price_script._refresh_reason(1, 71 * 60 * 60, 999))
        self.assertIsNotNone(price_script._refresh_reason(1, 72 * 60 * 60, 0))
        self.assertIsNotNone(price_script._refresh_reason(1, 0, 1_000))
        self.assertIn("manual", price_script._refresh_reason(1, 0, 0, True))

    def test_large_live_confirmation_passes_the_displayed_price(self):
        oracle = FakePriceOracle()
        sender = object()
        live_price = 2 * 10**18

        with (
            patch.object(price_script, "_interactive_confirm", return_value=True),
            patch.object(price_script, "_load_authorized_account", return_value=sender),
        ):
            selected_price, source = price_script._refresh_from_live(
                oracle,
                live_price,
                10**18,
                False,
                0,
                True,
            )

        self.assertEqual(selected_price, live_price)
        self.assertEqual(source, "confirmed live V4")
        self.assertEqual(oracle.confirm_calls, [(live_price, {"from": sender})])

    def test_kyber_dry_run_applies_five_percent_haircut_without_transaction(self):
        oracle = FakePriceOracle()
        quoted_price = 10**18
        quote_amount = 10_000 * 10**18
        route = {
            "amountIn": str(quote_amount),
            "amountOut": str(10_000 * 10**6),
        }

        with (
            patch.object(
                price_script,
                "_fetch_kyber_price",
                return_value=(quoted_price, route),
            ),
            patch.object(price_script, "_load_authorized_account") as load_account,
        ):
            selected_price, source = price_script._refresh_from_kyber(
                oracle,
                quote_amount,
                0,
                0,
                False,
            )

        self.assertEqual(selected_price, 95 * 10**16)
        self.assertEqual(source, "manual Kyber (5% haircut)")
        self.assertEqual(oracle.manual_calls, [])
        load_account.assert_not_called()

    def test_active_auction_defers_floor_update_before_prompt_or_account_load(self):
        strategy = FakeStrategy(60 * 10**14)
        auction = FakeAuction(60 * 10**14, True)
        contract_factory = types.SimpleNamespace(
            from_abi=lambda name, address, abi: (
                strategy if name == "GroveCompounder" else auction
            )
        )

        with (
            patch.object(price_script, "Contract", contract_factory),
            patch.object(price_script, "_interactive_confirm") as confirm,
            patch.object(price_script, "load_authorized_account") as load_account,
        ):
            price_script._review_auction_floor(
                "0x0000000000000000000000000000000000000003",
                10**16,
                "test",
                True,
            )

        confirm.assert_not_called()
        load_account.assert_not_called()
        self.assertEqual(strategy.floor_updates, [])

    def test_malformed_kyber_pool_id_is_rejected(self):
        route = {
            "route": [
                [
                    {
                        "exchange": "uniswap-v4",
                        "tokenIn": sync_script.GROVE,
                        "tokenOut": next(iter(sync_script.SUPPORTED_QUOTE_TOKENS)),
                        "pool": "0x" + "g" * 64,
                        "poolExtra": {"hookAddress": sync_script.ZERO_ADDRESS},
                    }
                ]
            ]
        }

        with self.assertRaisesRegex(RuntimeError, "Invalid pool ID returned by Kyber"):
            sync_script._hookless_v4_grove_pools(route)

    def test_quote_amount_override_uses_grove_units(self):
        with patch.dict(os.environ, {"QUOTE_AMOUNTS": "10_000, 50000, 10_000"}, clear=True):
            self.assertEqual(
                sync_script._quote_amounts(),
                [10_000 * 10**18, 50_000 * 10**18],
            )

    def test_reordering_same_membership_preserves_configured_order(self):
        configured = ["a", "b", "c"]
        selected = ["c", "a", "b"]
        self.assertEqual(
            sync_script._preserve_configured_order(configured, selected),
            configured,
        )

    def test_pool_selection_keeps_only_pools_seen_during_the_last_week(self):
        current_timestamp = 2_000_000_000
        recent_timestamp = current_timestamp - sync_script.POOL_RETENTION_SECONDS
        stale_timestamp = recent_timestamp - 1
        registry = {
            "pools": [
                {
                    "pool_id": "recent",
                    "last_seen_at": sync_script.datetime.fromtimestamp(
                        recent_timestamp, sync_script.timezone.utc
                    ).strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "last_seen_block": 2,
                },
                {
                    "pool_id": "stale",
                    "last_seen_at": sync_script.datetime.fromtimestamp(
                        stale_timestamp, sync_script.timezone.utc
                    ).strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "last_seen_block": 1,
                },
                {
                    "pool_id": "never-seen",
                    "last_seen_at": None,
                    "last_seen_block": 0,
                },
            ]
        }

        self.assertEqual(
            sync_script._selected_pools(
                registry, [], 10, current_timestamp
            ),
            ["recent"],
        )

    def test_pool_selection_keeps_most_recent_when_every_pool_is_stale(self):
        current_timestamp = 2_000_000_000
        registry = {
            "oracle_pool_ids": ["older", "newer"],
            "pools": [
                {
                    "pool_id": "older",
                    "last_seen_at": "2020-01-01T00:00:00Z",
                    "last_seen_block": 1,
                },
                {
                    "pool_id": "newer",
                    "last_seen_at": "2020-01-02T00:00:00Z",
                    "last_seen_block": 2,
                },
            ],
        }

        self.assertEqual(
            sync_script._selected_pools(registry, [], 10, current_timestamp),
            ["newer"],
        )

    def test_sync_retains_configured_pool_when_registry_has_no_observations(self):
        quote_token = next(iter(sync_script.SUPPORTED_QUOTE_TOKENS))
        registry = {
            "oracle_pool_ids": ["stale"],
            "pools": [
                {
                    "pool_id": "stale",
                    "quote_token": quote_token,
                    "last_seen_at": None,
                    "last_seen_block": 0,
                }
            ],
        }
        oracle = FakeOracle(registry)
        route = {"amountIn": str(10_000 * 10**18), "amountOut": "1", "route": []}

        with patch.object(
            sync_script, "load_registry", return_value=copy.deepcopy(registry)
        ), patch.object(sync_script, "write_registry"), patch.object(
            sync_script, "write_generated_config"
        ):
            selected = sync_script.sync_pools(oracle, [route], broadcast=True)

        self.assertEqual(selected, ["stale"])
        self.assertEqual(oracle.set_calls, 0)

    def test_dry_run_does_not_write_registry_files(self):
        registry = registry_module.load_registry()
        oracle = FakeOracle(registry)
        route = {"amountIn": str(10_000 * 10**18), "amountOut": "1", "route": []}

        with (
            patch.object(sync_script, "load_registry", return_value=copy.deepcopy(registry)),
            patch.object(sync_script, "write_registry") as write_registry,
            patch.object(sync_script, "write_generated_config") as write_generated,
        ):
            sync_script.sync_pools(oracle, [route])

        write_registry.assert_not_called()
        write_generated.assert_not_called()

    def test_apply_registry_writes_both_registry_files(self):
        registry = registry_module.load_registry()
        oracle = FakeOracle(registry)
        route = {"amountIn": str(10_000 * 10**18), "amountOut": "1", "route": []}

        with (
            patch.object(sync_script, "load_registry", return_value=copy.deepcopy(registry)),
            patch.object(sync_script, "write_registry") as write_registry,
            patch.object(sync_script, "write_generated_config") as write_generated,
        ):
            sync_script.sync_pools(oracle, [route], apply_registry=True)

        write_registry.assert_called_once()
        write_generated.assert_called_once()

    def test_broadcast_does_not_transact_for_reorder_only_change(self):
        registry = registry_module.load_registry()
        registry["oracle_pool_ids"] = sync_script._selected_pools(
            registry, [], 10, sync_script.chain.time()
        )
        oracle = FakeOracle(registry)
        oracle.pool_ids.reverse()
        oracle.quote_tokens.reverse()
        route = {"amountIn": str(10_000 * 10**18), "amountOut": "1", "route": []}

        with (
            patch.object(sync_script, "load_registry", return_value=copy.deepcopy(registry)),
            patch.object(sync_script, "write_registry"),
            patch.object(sync_script, "write_generated_config"),
        ):
            selected = sync_script.sync_pools(oracle, [route], broadcast=True)

        self.assertEqual(selected, oracle.pool_ids)
        self.assertEqual(oracle.set_calls, 0)

    def test_generated_solidity_matches_registry(self):
        registry = registry_module.load_registry()
        self.assertTrue(registry_module.generated_config_matches(registry))

    def test_checked_in_registry_is_canonically_serialized(self):
        registry = registry_module.load_registry()
        self.assertEqual(
            registry_module.REGISTRY_PATH.read_text(),
            registry_module.serialized_registry(registry),
        )


if __name__ == "__main__":
    unittest.main()

import copy
import importlib
import os
import sys
import types
import unittest
from unittest.mock import Mock, patch


if "brownie" not in sys.modules:
    brownie = types.ModuleType("brownie")
    brownie.Contract = object()
    brownie.accounts = object()
    brownie.chain = types.SimpleNamespace(id=1, height=123, time=lambda: 456, base_fee=100_000_000)
    brownie.network = types.ModuleType("brownie.network")
    brownie.network.contract = types.ModuleType("brownie.network.contract")
    brownie.network.contract._add_deployment = Mock()
    sys.modules["brownie"] = brownie
    sys.modules["brownie.network"] = brownie.network
    sys.modules["brownie.network.contract"] = brownie.network.contract
    brownie._config = types.ModuleType("brownie._config")
    brownie._config.CONFIG = types.SimpleNamespace(settings={"autofetch_sources": False})
    sys.modules["brownie._config"] = brownie._config

if "click" not in sys.modules:
    click = types.ModuleType("click")
    click.confirm = lambda message, default=False: default
    sys.modules["click"] = click


price_script = importlib.import_module("scripts.refresh_grove_price")
sync_script = importlib.import_module("scripts.sync_kyber_v4_pools")
common_module = importlib.import_module("scripts.grove_maintenance_common")
registry_module = importlib.import_module("scripts.grove_pool_registry")


class FakeOracle:
    def __init__(self, registry):
        entries = {entry["pool_id"]: entry for entry in registry["pools"]}
        self.pool_ids = list(registry["oracle_pool_ids"])
        self.quote_tokens = [entries[pool_id]["quote_token"] for pool_id in self.pool_ids]
        self.set_calls = 0
        self.flows = {}
        self.setUniV4Pools = Mock(side_effect=self._set_pools)
        self.setUniV4Pools.call = Mock()

    def uniV4PoolCount(self):
        return len(self.pool_ids)

    def uniV4Pool(self, index):
        return (self.pool_ids[index], 0, 0, self.quote_tokens[index], False)

    def MAX_V4_POOLS(self):
        return 10

    def management(self):
        return "0xmanager"

    def GROVE_PRICE_QUOTE_AMOUNT(self):
        return 10_000 * 10**18

    def quoteUniV4Route(self):
        inputs = [self.flows.get(pool, (0, 0))[0] for pool in self.pool_ids]
        outputs = [self.flows.get(pool, (0, 0))[1] for pool in self.pool_ids]
        return (sum(outputs), sum(inputs), 0, self.pool_ids, inputs, outputs)

    def _set_pools(self, pool_ids, transaction):
        self.set_calls += 1
        tokens = dict(zip(self.pool_ids, self.quote_tokens))
        self.quote_tokens = [tokens.get(pool, common_module.USDC.lower()) for pool in pool_ids]
        self.pool_ids = list(pool_ids)
        return types.SimpleNamespace(txid="0xpools")


class FakePriceOracle:
    def __init__(self, max_deviation_bps=5_000):
        self.max_deviation_bps = max_deviation_bps
        self.price_calls = []

    def MAX_LIVE_PRICE_DEVIATION_BPS(self):
        return self.max_deviation_bps

    def setGrovePrice(self, price, transaction):
        self.price_calls.append((price, transaction))
        return types.SimpleNamespace(txid="0xprice")


class FakeStrategy:
    def __init__(self, floor):
        self.floor = floor
        self.floor_updates = []

    def auction(self):
        return "0x0000000000000000000000000000000000000001"

    def minimumAuctionPrice(self):
        return self.floor

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
    def test_uncached_contract_fetches_with_autofetch_initially_disabled(self):
        from brownie._config import CONFIG
        from brownie.network import contract as contract_module

        auction = FakeAuction(60 * 10**14, False)

        def uncached_contract(address):
            if not CONFIG.settings["autofetch_sources"]:
                raise ValueError("Unknown contract address: '{}'".format(address))
            contract_module._add_deployment(auction)
            return auction

        factory = Mock(side_effect=uncached_contract)
        with patch.dict(CONFIG.settings, {"autofetch_sources": False}):
            with patch.object(contract_module, "_add_deployment") as writer:
                loaded = common_module.load_contract(
                    factory, "0xauction", ("minimumPrice", "isAnActiveAuction")
                )
                self.assertIs(loaded, auction)
                writer.assert_not_called()
            self.assertFalse(CONFIG.settings["autofetch_sources"])
        factory.assert_called_once_with("0xauction")
        factory.from_explorer.assert_not_called()

    def test_autofetch_setting_restored_when_explorer_fails(self):
        from brownie._config import CONFIG

        def unavailable_explorer(address):
            self.assertTrue(CONFIG.settings["autofetch_sources"])
            raise RuntimeError("explorer unavailable")

        with patch.dict(CONFIG.settings, {"autofetch_sources": False}):
            with self.assertRaisesRegex(RuntimeError, "explorer unavailable"):
                common_module.load_contract(
                    unavailable_explorer, "0xauction", ("minimumPrice",)
                )
            self.assertFalse(CONFIG.settings["autofetch_sources"])

    def test_canonical_loader_blocks_cache_inserts_and_restores_writer(self):
        from brownie.network import contract as contract_module

        contract = types.SimpleNamespace(management=lambda: "0xmanager")

        def cached_or_fetched(address):
            contract_module._add_deployment(contract)
            return contract

        factory = Mock(side_effect=cached_or_fetched)
        with patch.object(contract_module, "_add_deployment") as writer:
            self.assertIs(
                common_module.load_contract(factory, "0xstrategy", ("management",)),
                contract,
            )
            writer.assert_not_called()
            self.assertIs(contract_module._add_deployment, writer)
        factory.assert_called_once_with("0xstrategy")
        factory.from_explorer.assert_not_called()

    def test_strategy_override_blocks_recursive_cache_inserts(self):
        from brownie.network import contract as contract_module

        contract = FakeStrategy(1)

        def explorer(address, **kwargs):
            self.assertEqual(kwargs, {"as_proxy_for": address, "persist": False})
            # Model Brownie's recursive fallback forgetting persist=False.
            contract_module._add_deployment(contract)
            return contract

        factory = Mock()
        factory.from_explorer.side_effect = explorer
        with patch.object(contract_module, "_add_deployment") as writer:
            self.assertIs(
                common_module.load_contract(
                    factory, "0xstrategy", ("auction",), strategy=True
                ), contract,
            )
            writer.assert_not_called()
            self.assertIs(contract_module._add_deployment, writer)
        factory.assert_not_called()
        factory.from_abi.assert_not_called()

    def test_failed_load_restores_cache_writer_without_an_abi_fallback(self):
        from brownie.network import contract as contract_module

        factory = Mock(side_effect=RuntimeError("metadata unavailable"))
        with patch.object(contract_module, "_add_deployment") as writer:
            with self.assertRaisesRegex(RuntimeError, "metadata unavailable"):
                common_module.load_contract(factory, "0xoracle", ("setGrovePrice",))
            self.assertIs(contract_module._add_deployment, writer)
            writer.assert_not_called()
        factory.from_explorer.assert_not_called()
        factory.from_abi.assert_not_called()

    def test_missing_method_reports_address_name_and_method_without_fallback(self):
        factory = Mock(return_value=types.SimpleNamespace(_name="CachedOracle"))
        with self.assertRaisesRegex(
            RuntimeError, "0xoracle: resolved CachedOracle; missing setGrovePrice"
        ):
            common_module.load_contract(factory, "0xoracle", ("setGrovePrice",))
        factory.from_explorer.assert_not_called()
        factory.from_abi.assert_not_called()

    def test_floor_update_uses_shared_management_and_separate_grove_interface(self):
        strategy_address = "0xstrategy"
        manager = "0xmanager"
        base = types.SimpleNamespace(management=lambda: manager)
        strategy = FakeStrategy(60 * 10**14)
        auction = FakeAuction(strategy.floor, False)
        factory = Mock(side_effect=lambda address: (
            base if address == strategy_address else auction
        ))
        factory.from_explorer.return_value = strategy
        sender = types.SimpleNamespace(address=manager)

        def load_authorized(accounts, description, is_authorized):
            self.assertTrue(is_authorized(manager))
            self.assertFalse(is_authorized("0xsomeoneelse"))
            return sender

        with (
            patch.object(price_script, "Contract", factory),
            patch.object(price_script, "_interactive_confirm", return_value=True),
            patch.object(price_script, "load_authorized_account", load_authorized),
        ):
            price_script._review_auction_floor(strategy_address, 10**16, "test", True)

        self.assertEqual(strategy.floor_updates, [(8 * 10**15, {"from": sender, "priority_fee": 10_000_000, "max_fee": 310_000_000})])
        self.assertEqual([call.args for call in factory.call_args_list], [
            (strategy_address,), (strategy.auction(),),
        ])
        factory.from_explorer.assert_called_once_with(
            strategy_address, as_proxy_for=strategy_address, persist=False
        )
        factory.from_abi.assert_not_called()

    def test_authorized_account_defaults_to_llc2(self):
        loaded = []
        sender = types.SimpleNamespace(
            address="0x0000000000000000000000000000000000000001"
        )
        fake_accounts = types.SimpleNamespace(
            load=lambda account_name: loaded.append(account_name) or sender
        )

        with patch.dict(os.environ, {}, clear=True):
            result = common_module.load_authorized_account(
                fake_accounts, "test operation", lambda address: True
            )

        self.assertIs(result, sender)
        self.assertEqual(loaded, ["llc2"])

    def test_mainnet_deployment_check_warns_when_strategy_is_not_queued(self):
        oracle_address = "0x0000000000000000000000000000000000000001"
        strategy_address = "0x0000000000000000000000000000000000000002"
        yearn_oracle = types.SimpleNamespace(
            oracles=lambda strategy: oracle_address
        )
        vault = types.SimpleNamespace(
            get_default_queue=lambda: [
                "0x0000000000000000000000000000000000000003"
            ]
        )
        contract_factory = lambda address: (
            yearn_oracle if address == common_module.YEARN_APR_ORACLE else vault
        )

        with patch("builtins.print") as output:
            in_queue = common_module.validate_mainnet_deployment(
                contract_factory, oracle_address, strategy_address
            )

        self.assertFalse(in_queue)
        self.assertTrue(
            any(
                call.args
                and "WARN: Strategy" in call.args[0]
                and "not in the USDS-1 default queue" in call.args[0]
                for call in output.call_args_list
            )
        )

    def test_mainnet_deployment_check_rejects_wrong_yearn_oracle(self):
        expected_oracle = "0x0000000000000000000000000000000000000001"
        registered_oracle = "0x0000000000000000000000000000000000000002"
        strategy_address = "0x0000000000000000000000000000000000000003"
        yearn_oracle = types.SimpleNamespace(
            oracles=lambda strategy: registered_oracle
        )
        contract_factory = lambda address: yearn_oracle

        with self.assertRaisesRegex(RuntimeError, "maps strategy"):
            common_module.validate_mainnet_deployment(
                contract_factory, expected_oracle, strategy_address
            )

    def test_stored_price_refresh_policy(self):
        self.assertEqual(
            price_script._refresh_reason(0, 0, 0),
            "initialize the stored reference",
        )
        self.assertIsNone(price_script._refresh_reason(1, 35 * 60 * 60, 999))
        self.assertIsNotNone(price_script._refresh_reason(1, 36 * 60 * 60, 0))
        self.assertIsNotNone(price_script._refresh_reason(1, 0, 1_000))

    def test_kyber_broadcast_stores_raw_quote_without_haircut(self):
        oracle = FakePriceOracle()
        sender = object()
        quoted_price = 7_809_813_320_000_000
        quote_amount = 100_000 * 10**18
        route = {
            "amountIn": str(quote_amount),
            "amountOut": str(780_981_332),
        }

        with (
            patch.object(
                price_script,
                "_fetch_kyber_price",
                return_value=(quoted_price, route),
            ),
            patch.object(price_script, "_load_authorized_account", return_value=sender),
        ):
            selected_price, source = price_script._refresh_from_kyber(
                oracle, quote_amount, 0, 0, True
            )

        self.assertEqual(selected_price, quoted_price)
        self.assertEqual(source, "Kyber executable reference")
        self.assertEqual(oracle.price_calls, [(quoted_price, {"from": sender, "priority_fee": 10_000_000, "max_fee": 310_000_000})])

    def test_kyber_dry_run_uses_raw_quote_without_transaction(self):
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

        self.assertEqual(selected_price, quoted_price)
        self.assertEqual(source, "Kyber executable reference")
        self.assertEqual(oracle.price_calls, [])
        load_account.assert_not_called()

    def test_kyber_price_quote_defaults_to_five_hundred_thousand_grove(self):
        with patch.dict(os.environ, {}, clear=True):
            self.assertEqual(
                price_script._kyber_quote_amount(),
                500_000 * 10**18,
            )

    def test_comparison_quotes_do_not_change_reference_or_block_maintenance(self):
        for comparison_fails in (False, True):
            with self.subTest(comparison_fails=comparison_fails):
                oracle = FakePriceOracle()
                oracle.GROVE_PRICE_QUOTE_AMOUNT = lambda: 10_000 * 10**18
                oracle.storedGrovePrice = lambda: 0
                oracle.lastPriceUpdate = lambda: 0
                oracle.quoteUniV4Route = lambda: (0, 0, 0)
                reference_price = 8 * 10**15
                sender = object()
                amounts = []

                def fetch_price(amount, timeout):
                    amounts.append(amount // 10**18)
                    if comparison_fails and amount == 100_000 * 10**18:
                        raise RuntimeError("HTTP 503")
                    price = reference_price if amount == 500_000 * 10**18 else 6 * 10**15
                    return price, {"amountIn": str(amount), "amountOut": str(amount * price // 10**30)}

                with (
                    patch.dict(os.environ, {"BROADCAST": "true"}, clear=True),
                    patch.object(price_script, "_load_oracle", return_value=oracle),
                    patch.object(price_script, "validate_mainnet_deployment"),
                    patch.object(price_script, "_fetch_kyber_price", side_effect=fetch_price),
                    patch.object(price_script, "_load_authorized_account", return_value=sender),
                    patch.object(price_script, "_print_oracle_status"),
                    patch.object(price_script, "_review_auction_floor") as review_floor,
                    patch("builtins.print") as output,
                ):
                    self.assertTrue(price_script.main())

                self.assertEqual(amounts, [500_000, 100_000, 1_000_000])
                self.assertEqual(oracle.price_calls, [(reference_price, {"from": sender, "priority_fee": 10_000_000, "max_fee": 310_000_000})])
                review_floor.assert_called_once_with(
                    price_script.MAINNET_GROVE_STRATEGY, reference_price,
                    "Kyber executable reference", True,
                )
                messages = [call.args[0] for call in output.call_args_list if call.args]
                self.assertTrue(any(
                    message.split() == ["500,000", "4,000.000000", "0.00800000", "refresh", "+", "floor"]
                    for message in messages
                ))
                self.assertTrue(any(
                    message.split() == ["1,000,000", "6,000.000000", "0.00600000", "comparison", "only"]
                    for message in messages
                ))
                if comparison_fails:
                    self.assertTrue(any("Comparison unavailable for 100,000 GROVE" in message for message in messages))

    def test_kyber_price_quote_amount_can_be_overridden_in_grove_units(self):
        with patch.dict(
            os.environ, {"KYBER_QUOTE_AMOUNT": "250000"}, clear=True
        ):
            self.assertEqual(
                price_script._kyber_quote_amount(),
                250_000 * 10**18,
            )

    def test_active_auction_defers_floor_update_before_prompt_or_account_load(self):
        strategy = FakeStrategy(60 * 10**14)
        auction = FakeAuction(60 * 10**14, True)
        base = types.SimpleNamespace(management=lambda: "0xmanager")
        contract_factory = Mock(side_effect=lambda address: (
            auction if address == strategy.auction() else base
        ))
        contract_factory.from_explorer.return_value = strategy

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
            "amountIn": str(10_000 * 10**18),
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

    def test_pool_selection_retains_active_pools_regardless_of_last_seen_time(self):
        registry = {
            "oracle_pool_ids": ["stale", "never-seen"],
            "pools": [
                {
                    "pool_id": "stale",
                    "last_seen_at": "2020-01-01T00:00:00Z",
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
                registry, [], 10, 2_000_000_000
            ),
            ["stale", "never-seen"],
        )

    def test_pool_selection_appends_new_kyber_discoveries(self):
        registry = {
            "oracle_pool_ids": ["existing"],
            "pools": [
                {"pool_id": "existing"},
                {"pool_id": "new-one"},
                {"pool_id": "new-two"},
            ],
        }

        self.assertEqual(
            sync_script._selected_pools(
                registry, ["new-one", "existing", "new-two"], 2, 0
            ),
            ["existing", "new-one"],
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

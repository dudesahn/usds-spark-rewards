"""Selection and persistence tests; no RPC, keys, or Brownie cache access."""

import copy
import os
import tempfile
import types
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

from scripts.tests.test_grove_maintenance import (
    FakeOracle, common_module, registry_module, sync_script,
)


def kyber_route(pool_id, amount=10_000, amount_in=None, amount_out=75_000_000):
    return {
        "amountIn": str(amount * 10**18), "amountOut": str(amount_out),
        "route": [[{
            "exchange": "uniswap-v4", "tokenIn": sync_script.GROVE,
            "tokenOut": common_module.USDC, "pool": pool_id,
            "poolExtra": {"hookAddress": sync_script.ZERO_ADDRESS},
            "swapAmount": str(amount * 10**18 if amount_in is None else amount_in),
            "amountOut": str(amount_out),
        }]],
    }


class ContributionPolicyTest(unittest.TestCase):
    def setUp(self):
        self.registry = registry_module.load_registry()
        self.oracle = FakeOracle(self.registry)
        self.existing = list(self.oracle.pool_ids)
        self.candidate = next(
            entry["pool_id"] for entry in reversed(self.registry["pools"])
            if entry["pool_id"] not in self.existing
        )
        self.route = kyber_route(self.candidate)
        self.sender = types.SimpleNamespace(address="0xmanager")
        for name, replacement in (
            ("load_registry", Mock(side_effect=lambda: copy.deepcopy(self.registry))),
            ("write_registry", Mock()),
            ("write_generated_config", Mock()),
            ("load_authorized_account", Mock(return_value=self.sender)),
        ):
            context = patch.object(sync_script, name, replacement)
            context.start()
            self.addCleanup(context.stop)
            setattr(self, name, replacement)
        for context in (patch("builtins.print"), patch.dict(os.environ, {}, clear=True)):
            context.start()
            self.addCleanup(context.stop)

    def assert_no_effects(self):
        self.write_registry.assert_not_called()
        self.write_generated_config.assert_not_called()
        self.load_authorized_account.assert_not_called()
        self.oracle.setUniV4Pools.assert_not_called()

    def test_default_probes_include_large_sizes(self):
        self.assertEqual(sync_script._quote_amounts(), [
            size * 10**18 for size in (10_000, 50_000, 100_000, 500_000, 1_000_000)
        ])

    def test_only_positive_input_and_output_count(self):
        for amount_in, amount_out in ((0, 1), (1, 0), (0, 0)):
            with self.subTest(amount_in=amount_in, amount_out=amount_out):
                route = kyber_route(self.candidate, amount_in=amount_in, amount_out=amount_out)
                self.assertEqual(sync_script._hookless_v4_grove_pools(route), [])

    def test_missing_negative_or_excessive_flow_aborts(self):
        for field, value in (("swapAmount", None), ("amountOut", "bad"),
                             ("swapAmount", "-1"), ("swapAmount", str(10**30))):
            with self.subTest(field=field, value=value):
                route = copy.deepcopy(self.route)
                if value is None:
                    del route["route"][0][0][field]
                else:
                    route["route"][0][0][field] = value
                with self.assertRaisesRegex(RuntimeError, "flow amounts"):
                    sync_script.sync_pools(self.oracle, [route], broadcast=True)
                self.assert_no_effects()

    def test_split_legs_for_same_pool_aggregate_without_double_counting(self):
        route = kyber_route(self.candidate, amount_in=4_000 * 10**18, amount_out=30_000_000)
        route["route"].append(copy.deepcopy(route["route"][0]))
        observations = sync_script._hookless_v4_grove_pools(route)
        self.assertEqual(len(observations), 1)
        self.assertEqual(observations[0]["amount_in"], 8_000 * 10**18)
        self.assertEqual(observations[0]["amount_out"], 60_000_000)
        route["route"].append(copy.deepcopy(route["route"][0]))
        with self.assertRaisesRegex(RuntimeError, "exceed the quoted input"):
            sync_script._hookless_v4_grove_pools(route)

    def test_incompatible_routes_do_not_become_candidates(self):
        for field, value in (("exchange", "uniswap-v3"),
                             ("tokenIn", common_module.USDC),
                             ("tokenOut", "0xother"),
                             ("poolExtra", {"hookAddress": "0xhook"})):
            route = copy.deepcopy(self.route)
            route["route"][0][0][field] = value
            self.assertEqual(sync_script._hookless_v4_grove_pools(route), [])

    def test_preview_replaces_unknown_idle_pool_without_writes(self):
        selected = sync_script.sync_pools(self.oracle, [self.route])
        self.assertEqual(selected, [self.candidate] + self.existing[1:])
        self.oracle.setUniV4Pools.call.assert_called_once_with(selected, {"from": "0xmanager"})
        self.assert_no_effects()

    def test_oracle_partial_quote_protects_its_contributors(self):
        self.oracle.flows[self.existing[0]] = (5_000 * 10**18, 37_000_000)
        selected = sync_script.sync_pools(self.oracle, [self.route], apply_registry=True)
        self.assertEqual(selected, [self.existing[0], self.candidate] + self.existing[2:])
        saved = self.write_registry.call_args.args[0]
        entry = next(item for item in saved["pools"] if item["pool_id"] == self.existing[0])
        self.assertEqual(entry["last_contribution_sources"], ["oracle"])
        self.assertEqual(entry["last_contribution_quote_sizes"], [10_000])

    def test_least_recent_contribution_wins_over_array_order_and_last_seen(self):
        for index, entry in enumerate(self.registry["pools"]):
            entry["last_contributed_block"] = 100 if index != 7 else 5
        selected = sync_script.sync_pools(self.oracle, [self.route])
        self.assertEqual(selected[7], self.candidate)
        self.assertEqual(set(self.existing) - set(selected), {self.existing[7]})

    def test_unknown_history_is_evicted_before_known_history(self):
        self.registry["pools"][0]["last_contributed_block"] = 1
        selected = sync_script.sync_pools(self.oracle, [self.route])
        self.assertEqual(selected[0], self.existing[0])
        self.assertEqual(selected[1], self.candidate)

    def test_all_current_contributors_keep_slots_on_recency_tie(self):
        self.oracle.flows = {pool: (1_000 * 10**18, 7_000_000) for pool in self.existing}
        selected = sync_script.sync_pools(self.oracle, [self.route], apply_registry=True)
        self.assertEqual(selected, self.existing)
        self.oracle.setUniV4Pools.call.assert_not_called()
        saved = self.write_registry.call_args.args[0]
        entry = next(item for item in saved["pools"] if item["pool_id"] == self.candidate)
        self.assertEqual(entry["last_contributed_block"], sync_script.chain.height)

    def test_union_across_probe_sizes_and_sources_saved_with_eviction_history(self):
        self.oracle.flows[self.existing[0]] = (1_000 * 10**18, 7_000_000)
        routes = [kyber_route(self.existing[0], size) for size in (10_000, 500_000)]
        for route in routes:
            route["route"][0][0]["tokenOut"] = common_module.USDT
        # This candidate is only used in the largest route, and is still selected.
        routes.append(kyber_route(self.candidate, 1_000_000))
        selected = sync_script.sync_pools(self.oracle, routes, apply_registry=True)
        saved = self.write_registry.call_args.args[0]
        entries = {item["pool_id"]: item for item in saved["pools"]}
        self.assertIn(self.candidate, selected)
        self.assertEqual(entries[self.existing[0]]["last_contribution_sources"], ["kyber", "oracle"])
        self.assertEqual(entries[self.existing[0]]["last_contribution_quote_sizes"], [10_000, 500_000])
        self.assertEqual(entries[self.candidate]["last_contribution_quote_sizes"], [1_000_000])
        self.assertIn(self.existing[1], entries)  # Eviction preserves history.
        self.assertNotIn(self.existing[1], saved["oracle_pool_ids"])
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "registry.json"
            registry_module.write_registry(saved, path)
            self.assertEqual(registry_module.load_registry(path), saved)
        self.oracle.setUniV4Pools.assert_not_called()
        self.load_authorized_account.assert_not_called()

    def test_selection_starts_from_onchain_pools_after_local_only_preview(self):
        self.registry["oracle_pool_ids"][0] = self.candidate
        self.oracle.flows[self.existing[0]] = (1_000 * 10**18, 7_000_000)
        selected = sync_script.sync_pools(self.oracle, [self.route])
        self.assertIn(self.existing[0], selected)
        self.assertNotIn(self.existing[1], selected)

    def test_broadcast_confirms_replacement_before_saving(self):
        def save(registry):
            self.assertEqual(self.oracle.set_calls, 1)
            self.assertEqual(self.oracle.pool_ids, registry["oracle_pool_ids"])
            return True

        self.write_registry.side_effect = save
        selected = sync_script.sync_pools(self.oracle, [self.route], broadcast=True)
        self.oracle.setUniV4Pools.assert_called_once_with(
            selected, {"from": self.sender, "priority_fee": 10_000_000, "max_fee": 310_000_000}
        )
        self.write_registry.assert_called_once()
        self.write_generated_config.assert_called_once_with(self.write_registry.call_args.args[0])

    def test_simulation_failure_aborts_before_account_or_file_changes(self):
        self.oracle.setUniV4Pools.call.side_effect = RuntimeError("invalid pool")
        with self.assertRaisesRegex(RuntimeError, "invalid pool"):
            sync_script.sync_pools(self.oracle, [self.route], broadcast=True)
        self.assert_no_effects()

    def test_transaction_failure_or_wrong_readback_never_saves_history(self):
        for wrong_readback in (False, True):
            with self.subTest(wrong_readback=wrong_readback):
                self.oracle.setUniV4Pools.side_effect = (
                    lambda *args: types.SimpleNamespace(txid="0xfailed")
                ) if wrong_readback else RuntimeError("transaction failed")
                with self.assertRaisesRegex(RuntimeError, "transaction failed|requested configuration"):
                    sync_script.sync_pools(self.oracle, [self.route], broadcast=True)
                self.write_registry.assert_not_called()
                self.write_generated_config.assert_not_called()

    def test_bad_oracle_allocations_abort_without_changes(self):
        for route in ((0, 0, 0), (0, 0, 0, [], [], []),
                      (0, 1, 0, self.existing, [0] * 10, [0] * 10)):
            with self.subTest(route=route):
                with patch.object(self.oracle, "quoteUniV4Route", return_value=route):
                    with self.assertRaisesRegex(RuntimeError, "Oracle returned"):
                        sync_script.sync_pools(self.oracle, [self.route], broadcast=True)
                self.assert_no_effects()

    def test_oracle_failure_aborts_without_changes(self):
        with patch.object(self.oracle, "quoteUniV4Route", side_effect=RuntimeError("RPC failed")):
            with self.assertRaisesRegex(RuntimeError, "RPC failed"):
                sync_script.sync_pools(self.oracle, [self.route], broadcast=True)
        self.assert_no_effects()

    def test_newer_saved_history_prevents_regression(self):
        self.registry["pools"][0]["last_contributed_block"] = sync_script.chain.height + 1
        with self.assertRaisesRegex(RuntimeError, "newer than this snapshot"):
            sync_script.sync_pools(self.oracle, [self.route], broadcast=True)
        self.assert_no_effects()

    def test_allocation_reads_share_requested_block(self):
        for method in ("uniV4PoolCount", "uniV4Pool", "MAX_V4_POOLS",
                       "GROVE_PRICE_QUOTE_AMOUNT", "quoteUniV4Route"):
            original = getattr(self.oracle, method)
            wrapped = Mock(side_effect=AssertionError("unpinned read"))
            wrapped.call = Mock(side_effect=lambda *args, _read=original, **kwargs: _read(*args))
            setattr(self.oracle, method, wrapped)
        sync_script.sync_pools(self.oracle, [self.route], block_identifier=123, block_timestamp=456)
        for method in ("uniV4PoolCount", "uniV4Pool", "MAX_V4_POOLS",
                       "GROVE_PRICE_QUOTE_AMOUNT", "quoteUniV4Route"):
            wrapped = getattr(self.oracle, method)
            wrapped.assert_not_called()
            self.assertTrue(wrapped.call.called)
            for call in wrapped.call.call_args_list:
                self.assertEqual(call.kwargs, {"block_identifier": 123})

    def test_partial_kyber_probes_abort_even_in_preview(self):
        for env in ({}, {"APPLY_REGISTRY": "true"}, {"BROADCAST": "true"}):
            with (
                patch.dict(os.environ, env, clear=True),
                patch.object(sync_script, "_load_oracle", return_value=self.oracle),
                patch.object(sync_script, "validate_mainnet_deployment"),
                patch.object(sync_script, "_fetch_kyber_route", side_effect=[
                    self.route, RuntimeError("HTTP 503"), self.route, self.route, self.route,
                ]),
                patch.object(sync_script, "sync_pools") as sync,
            ):
                with self.assertRaisesRegex(RuntimeError, "partial Kyber discovery"):
                    sync_script.main()
                sync.assert_not_called()
                self.assert_no_effects()

    def test_v2_migration_does_not_invent_contribution_history(self):
        legacy = copy.deepcopy(self.registry)
        legacy["version"] = 2
        for entry in legacy["pools"]:
            for key in list(entry):
                if key.startswith("last_contribut"):
                    del entry[key]
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "registry.json"
            registry_module.write_registry(legacy, path)
            original = path.read_text()
            loaded = registry_module.load_registry(path)
            self.assertEqual(path.read_text(), original)  # Loading never persists.
        self.assertEqual(loaded["version"], 3)
        for before, after in zip(legacy["pools"], loaded["pools"]):
            self.assertEqual(before["last_seen_at"], after["last_seen_at"])
            self.assertEqual(after["last_contributed_block"], 0)
            self.assertIsNone(after["last_contributed_at"])


if __name__ == "__main__":
    unittest.main()

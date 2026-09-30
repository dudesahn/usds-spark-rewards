"""Fee boundaries and no-send checks; all chain/account/transaction objects are fakes."""

import copy
import types
import unittest
from unittest.mock import Mock, patch

from scripts.tests.test_grove_maintenance import (
    FakeAuction, FakeOracle, FakePriceOracle, FakeStrategy,
    common_module, price_script, registry_module, sync_script,
)
from scripts.tests.test_grove_pool_contributions import kyber_route


class FeeChain:
    def __init__(self, fees):
        self.reads = Mock(side_effect=fees)

    @property
    def base_fee(self):
        return self.reads()


class GasPolicyTest(unittest.TestCase):
    def setUp(self):
        self.sender = types.SimpleNamespace(address="0xmanager")
        self.load_sender = Mock(return_value=self.sender)
        self.receipt = types.SimpleNamespace(txid="0xtest")
        self.send = Mock(return_value=self.receipt)
        printing = patch("builtins.print")
        self.output = printing.start()
        self.addCleanup(printing.stop)

    def test_exact_wei_fees_and_cutoff_boundary(self):
        for base_fee in (0, 1, 100_000_000, 499_999_999, 500_000_000):
            with self.subTest(base_fee=base_fee):
                chain = FeeChain([base_fee, base_fee])
                result = common_module.broadcast_transaction(
                    chain, self.send, "payload", load_sender=self.load_sender,
                )
                self.assertIs(result, self.receipt)
                self.send.assert_called_with("payload", {
                    "from": self.sender, "priority_fee": 10_000_000,
                    "max_fee": 3 * base_fee + 10_000_000,
                })
                self.assertEqual(chain.reads.call_count, 2)

    def test_high_gas_never_loads_account_or_sends(self):
        chain = FeeChain([500_000_001])
        self.assertIsNone(common_module.broadcast_transaction(
            chain, self.send, load_sender=self.load_sender,
        ))
        self.load_sender.assert_not_called()
        self.send.assert_not_called()
        messages = [str(call.args[0]) for call in self.output.call_args_list]
        self.assertTrue(any("WARN" in line and "0.500000001" in line and "transaction skipped" in line for line in messages))

    def test_gas_spike_while_unlocking_blocks_send(self):
        chain = FeeChain([100_000_000, 500_000_001])
        self.assertIsNone(common_module.broadcast_transaction(
            chain, self.send, load_sender=self.load_sender,
        ))
        self.load_sender.assert_called_once()
        self.send.assert_not_called()

    def test_second_read_sets_fees_when_still_under_limit(self):
        chain = FeeChain([100_000_000, 200_000_000])
        common_module.broadcast_transaction(chain, self.send, load_sender=self.load_sender)
        self.send.assert_called_once_with({
            "from": self.sender, "priority_fee": 10_000_000, "max_fee": 610_000_000,
        })

    def test_bad_or_unavailable_fee_blocks_send_without_echoing_error(self):
        for fee in (None, -1, True, "100000000", 0.1, RuntimeError("provider-secret")):
            for read_number in (1, 2):
                with self.subTest(fee=fee, read_number=read_number):
                    self.load_sender.reset_mock()
                    self.send.reset_mock()
                    chain = FeeChain([fee] if read_number == 1 else [100_000_000, fee])
                    self.assertIsNone(common_module.broadcast_transaction(
                        chain, self.send, load_sender=self.load_sender,
                    ))
                    self.assertEqual(self.load_sender.call_count, read_number - 1)
                    self.send.assert_not_called()
        self.assertFalse(any("provider-secret" in str(call) for call in self.output.call_args_list))

    def test_declined_sender_does_not_send(self):
        self.load_sender.return_value = None
        chain = FeeChain([100_000_000])
        self.assertIsNone(common_module.broadcast_transaction(
            chain, self.send, load_sender=self.load_sender,
        ))
        self.assertEqual(chain.reads.call_count, 1)
        self.send.assert_not_called()

    def test_refresh_skips_high_gas_but_preserves_quote_for_review(self):
        oracle = FakePriceOracle()
        quote = 8 * 10**15
        route = {"amountIn": str(500_000 * 10**18), "amountOut": "4000000000"}
        with (
            patch.object(price_script, "chain", FeeChain([500_000_001])),
            patch.object(price_script, "_fetch_kyber_price", return_value=(quote, route)),
            patch.object(price_script, "_load_authorized_account") as account,
        ):
            price, source = price_script._refresh_from_kyber(
                oracle, 500_000 * 10**18, 0, 0, True,
            )
        self.assertEqual(price, quote)
        self.assertIn("broadcast skipped", source)
        self.assertEqual(oracle.price_calls, [])
        account.assert_not_called()

    def test_floor_skips_high_gas_before_confirmation_or_account_loading(self):
        strategy = FakeStrategy(6 * 10**15)
        auction = FakeAuction(strategy.floor, False)
        base = types.SimpleNamespace(management=lambda: "0xmanager")
        factory = Mock(side_effect=lambda address: base if address == "0xstrategy" else auction)
        factory.from_explorer.return_value = strategy
        with (
            patch.object(price_script, "chain", FeeChain([500_000_001])),
            patch.object(price_script, "Contract", factory),
            patch.object(price_script, "_interactive_confirm") as confirm,
            patch.object(price_script, "load_authorized_account") as account,
        ):
            price_script._review_auction_floor("0xstrategy", 10**16, "Kyber", True)
        confirm.assert_not_called()
        account.assert_not_called()
        self.assertEqual(strategy.floor_updates, [])

    def test_skipped_pool_broadcast_never_saves_proposed_configuration(self):
        for fees in ([500_000_001], [100_000_000, 500_000_001]):
            with self.subTest(fees=fees):
                registry = registry_module.load_registry()
                oracle = FakeOracle(registry)
                original_pools = list(oracle.pool_ids)
                candidate = registry["pools"][-1]["pool_id"]
                chain = FeeChain(fees)
                chain.height, chain.time = 123, lambda: 456
                with (
                    patch.object(sync_script, "chain", chain),
                    patch.object(sync_script, "load_registry", return_value=copy.deepcopy(registry)),
                    patch.object(sync_script, "write_registry") as registry_write,
                    patch.object(sync_script, "write_generated_config") as config_write,
                    patch.object(sync_script, "load_authorized_account", return_value=self.sender) as account,
                ):
                    selected = sync_script.sync_pools(
                        oracle, [kyber_route(candidate)], broadcast=True, apply_registry=True,
                    )
                self.assertIn(candidate, selected)
                self.assertEqual(oracle.pool_ids, original_pools)
                oracle.setUniV4Pools.assert_not_called()
                registry_write.assert_not_called()
                config_write.assert_not_called()
                self.assertEqual(account.call_count, len(fees) - 1)
        self.assertTrue(any("SKIPPED — gas policy" in str(call) for call in self.output.call_args_list))

    def test_preview_and_local_registry_only_do_not_query_gas(self):
        registry = registry_module.load_registry()
        oracle = FakeOracle(registry)
        candidate = registry["pools"][-1]["pool_id"]
        chain = FeeChain([AssertionError("unexpected fee read")])
        chain.height, chain.time = 123, lambda: 456
        with (
            patch.object(sync_script, "chain", chain),
            patch.object(sync_script, "load_registry", side_effect=lambda: copy.deepcopy(registry)),
            patch.object(sync_script, "write_registry") as registry_write,
            patch.object(sync_script, "write_generated_config") as config_write,
            patch.object(sync_script, "load_authorized_account") as account,
        ):
            sync_script.sync_pools(oracle, [kyber_route(candidate)])
            registry_write.assert_not_called()
            config_write.assert_not_called()
            sync_script.sync_pools(oracle, [kyber_route(candidate)], apply_registry=True)
            registry_write.assert_called_once()
            config_write.assert_called_once()
        chain.reads.assert_not_called()
        account.assert_not_called()
        oracle.setUniV4Pools.assert_not_called()


if __name__ == "__main__":
    unittest.main()

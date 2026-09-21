import tempfile
import unittest
from pathlib import Path

from audit_world_integration import equipment_chains
from summarize_world_integration import summarize


class IntegrationAuditTests(unittest.TestCase):
    def test_purchase_requires_later_use_by_buyer(self):
        item = {"item_instance_id": "gear.1", "item_def_id": "vest", "holder": {"id": "buyer"},
                "provenance": {"created_by_fact_id": "production"}}
        facts = [{"fact_id": "production", "day": 1, "hour": 8},
                 {"fact_id": "purchase", "fact_type": "work_supply_purchased",
                  "goods_source_item_instance_id": "gear.1", "actor_id": "buyer", "day": 2, "hour": 8}]
        for ident, actor, day in [("before", "buyer", 1), ("other", "seller", 3), ("after", "buyer", 3)]:
            facts.append({"fact_id": ident, "actor_id": actor, "day": day, "hour": 9,
                          "modifier_explanations": [{"source_kind": "equipment", "source_id": "gear.1"}]})
        chain = equipment_chains([item], {"vest"}, facts, {f["fact_id"]: f for f in facts})[0]
        self.assertEqual(chain["purchased_then_modifier_facts"], ["after"])
        self.assertEqual(len(chain["combat_modifier_facts"]), 3)

    def test_missing_runs_cannot_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            report = summarize(Path(directory))
        self.assertFalse(report["passed"])
        self.assertFalse(report["checks"]["same_runtime"])
        self.assertFalse(report["checks"]["required_ablation_pairs"])


if __name__ == "__main__":
    unittest.main()

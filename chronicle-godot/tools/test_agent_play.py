"""Real Godot process tests, not a mock transport or injected game-state test."""

import json
import os
import subprocess
import sys
import unittest

from agent_play import ChronicleClient, PROJECT

PACKAGED = os.environ.get("CHRONICLE_TEST_PACKAGED") == "1"


def client(**kwargs):
    return ChronicleClient(packaged=PACKAGED, **kwargs)


class TransportTest(unittest.TestCase):
    def test_adventure_crafting_gear_growth_and_native_restore(self):
        with client(timeout=90) as game:
            response = game.request("start", mode="play", scenario="echo_realm", seed=81001,
                                    economy_variant="world_adventure_v1")
            self.assertTrue(response["ok"], response)
            self.assertEqual(len(response["observation"]["equipment_journal"]["catalog"]), 12)
            for choice in ("travel/generated_route.echo_landing.commons_to_reed_craft",
                           "player_life/work:recipe.hand_twist_cord",
                           "player_life/work:recipe.woven_sap"):
                self.assertTrue(any(c["choice_id"] == choice and c["enabled"] for c in response["choices"]))
                response = game.request("act", choice_id=choice)
                self.assertTrue(response["ok"], response)
            self.assertIn("沿岸编织", json.dumps(response["observation"]["feedback"], ensure_ascii=False))
            equip = next(c for c in response["choices"] if c["kind"] == "player_life"
                         and c["id"].startswith("equip:") and c["enabled"])
            response = game.request("act", choice_id=equip["choice_id"])
            self.assertTrue(response["ok"], response)
            journal = response["observation"]["equipment_journal"]
            self.assertEqual(len(journal["features"]), 8)
            self.assertTrue(any(i["definition_id"] == "item.woven_sap" and i["equipped"] for i in journal["items"]))
            self.assertFalse(any(c["choice_id"] == equip["choice_id"] for c in response["choices"]))
            slot = f"adventure_{os.getpid()}"
            self.assertTrue(game.request("save", slot=slot)["ok"])
            self.assertEqual(game.request("load", slot=slot)["observation"], response["observation"])
            self.assertEqual(game.request("inspect")["error"], "omniscient_inspection_disabled_in_play_mode")

    def test_integrated_danger_uses_legal_travel_combat_and_retreat(self):
        with client(timeout=90) as game:
            response = game.request("start", mode="play", scenario="echo_realm", seed=81001,
                                    economy_variant="world_integration_v1")
            self.assertTrue(response["ok"], response)
            for hint in (".network.", "commons_to_terrace_farming"):
                route = next(c for c in response["choices"] if c["kind"] == "travel" and hint in c["id"] and c["enabled"])
                response = game.request("act", choice_id=route["choice_id"])
                self.assertTrue(response["ok"], response)
                while response["observation"]["player"]["travel_remaining"]:
                    onward = next(c for c in response["choices"] if c["kind"] == "player_life" and c["id"] == "continue")
                    response = game.request("act", choice_id=onward["choice_id"])
                    self.assertTrue(response["ok"], response)
            combat = [c for c in response["choices"] if c["kind"] == "combat_encounter" and c["enabled"]]
            self.assertTrue(combat, response)
            guard = next(c for c in combat if "防守" in c["label"])
            response = game.request("act", choice_id=guard["choice_id"])
            self.assertTrue(response["ok"], response)
            self.assertIn("结算", json.dumps(response["observation"]["feedback"], ensure_ascii=False))
            for _ in range(6):
                retreat = next((c for c in response["choices"] if c["kind"] == "combat_encounter" and "脱离" in c["label"] and c["enabled"]), None)
                if retreat is None:
                    break
                response = game.request("act", choice_id=retreat["choice_id"])
                self.assertTrue(response["ok"], response)
            self.assertFalse(any(c["kind"] == "combat_encounter" for c in response["choices"]))
            route = next(c for c in response["choices"] if c["kind"] == "travel" and c["enabled"])
            response = game.request("act", choice_id=route["choice_id"])
            self.assertTrue(response["ok"], response)
            slot = f"integrated_danger_{os.getpid()}"
            self.assertTrue(game.request("save", slot=slot)["ok"])
            self.assertEqual(game.request("load", slot=slot)["observation"], response["observation"])

    def test_integrated_world_legal_actions_and_embedded_restore(self):
        with client(timeout=90) as game:
            response = game.request("start", mode="play", scenario="echo_realm", seed=81001,
                                    economy_variant="world_integration_v1")
            self.assertTrue(response["ok"], response)
            for choice in ("travel/generated_route.echo_landing.commons_to_fishery",
                           "player_life/gather:net_fisher"):
                self.assertTrue(any(c["choice_id"] == choice and c["enabled"] for c in response["choices"]))
                response = game.request("act", choice_id=choice)
                self.assertTrue(response["ok"], response)
            meal = next(c for c in response["choices"] if c["kind"] == "player_life" and c["id"].startswith("eat") and c["enabled"])
            response = game.request("act", choice_id=meal["choice_id"])
            self.assertTrue(response["ok"], response)
            for _ in range(18):
                wait = next(c for c in response["choices"] if c["kind"] == "wait" and c["enabled"])
                response = game.request("act", choice_id=wait["choice_id"])
                self.assertTrue(response["ok"], response)
            slot = f"integration_{os.getpid()}"
            self.assertTrue(game.request("save", slot=slot)["ok"])
            restored = game.request("load", slot=slot)
            self.assertEqual(restored["observation"], response["observation"])
            self.assertEqual(restored["choices"], response["choices"])
            self.assertEqual(game.request("inspect")["error"], "omniscient_inspection_disabled_in_play_mode")

    def test_natural_interrupted_work_explains_actual_cause_and_progress(self):
        with client(timeout=90) as game:
            response = game.request("start", mode="play", scenario="echo_realm", seed=86021,
                                    economy_variant="world_body_v1")
            self.assertTrue(response["ok"], response)
            for choice in ("travel/generated_route.echo_landing.commons_to_fishery",
                           "player_life/gather:net_fisher",
                           "player_life/ask_local:generated_resident.echo_landing.001",
                           "player_life/help:generated_resident.echo_landing.001:net_fisher"):
                self.assertTrue(any(c["choice_id"] == choice and c["enabled"] for c in response["choices"]))
                response = game.request("act", choice_id=choice)
                self.assertTrue(response["ok"], response)
            observation = response["observation"]
            self.assertEqual(observation["time"]["elapsed_hours"], 9)
            self.assertEqual(observation["feedback"]["status"], "interrupted")
            self.assertIn("陶苇已离开现场", observation["feedback"]["body"])
            self.assertIn("2/4", observation["feedback"]["body"])
            self.assertEqual(observation["player"]["coins"], 0)
            self.assertEqual(observation["player"]["food_count"], 6)
            slot = f"interrupted_{os.getpid()}"
            self.assertTrue(game.request("save", slot=slot)["ok"])
            self.assertEqual(game.request("load", slot=slot)["observation"], observation)

    def test_body_rules_apply_through_legal_protocol_and_native_save(self):
        with client(timeout=90) as game:
            response = game.request("start", mode="play", scenario="echo_realm", seed=81001,
                                    economy_variant="world_body_v1")
            self.assertTrue(response["ok"], response)
            for _ in range(24):
                wait = next(c for c in response["choices"] if c["kind"] == "wait" and c["enabled"])
                response = game.request("act", choice_id=wait["choice_id"])
                self.assertTrue(response["ok"], response)
            self.assertEqual(response["observation"]["player"]["health"], 98)
            self.assertIn("持续极饿", json.dumps(response["observation"], ensure_ascii=False))
            slot = f"body_{os.getpid()}"
            self.assertTrue(game.request("save", slot=slot)["ok"])
            loaded = game.request("load", slot=slot)
            self.assertEqual(loaded["observation"], response["observation"])
            meal = next(c for c in loaded["choices"] if c["id"] == "eat" and c["enabled"])
            after = game.request("act", choice_id=meal["choice_id"])
            self.assertEqual(after["observation"]["player"]["health"], 98)
            self.assertEqual(after["observation"]["player"]["hunger"], "medium")

    def test_provisions_variant_keeps_food_choice_and_benefit_public(self):
        with client(timeout=90) as game:
            response = game.request("start", mode="play", scenario="echo_realm", seed=81001,
                                    economy_variant="world_content_v2")
            self.assertTrue(response["ok"], response)
            route = next(c for c in response["choices"] if c["kind"] == "travel" and c["id"].endswith("commons_to_fishery"))
            response = game.request("act", choice_id=route["choice_id"])
            for action in ("gather:net_fisher", "work:recipe.smoke_lake_fish"):
                choice = next(c for c in response["choices"] if c["id"] == action and c["enabled"])
                response = game.request("act", choice_id=choice["choice_id"])
                self.assertTrue(response["ok"], response)
            meal = next(c for c in response["choices"] if c["id"].startswith("eat") and "熏湖鱼" in c["label"])
            self.assertIn("6小时", meal["hint"])
            response = game.request("act", choice_id=meal["choice_id"])
            self.assertTrue(response["ok"], response)
            self.assertEqual(response["observation"]["player"]["satiation_remaining_hours"], 5)
            slot = f"provisions_{os.getpid()}"
            self.assertTrue(game.request("save", slot=slot)["ok"])
            loaded = game.request("load", slot=slot)
            self.assertEqual(loaded["observation"], response["observation"])
            self.assertEqual(loaded["choices"], response["choices"])

    def test_content_variant_public_choices_and_native_restore(self):
        with client(timeout=90) as game:
            opened = game.request("start", mode="play", scenario="echo_realm", seed=81001,
                                  economy_variant="world_content_v1")
            self.assertTrue(opened["ok"], opened)
            route = next(c for c in opened["choices"] if c["kind"] == "travel" and c["id"].endswith("commons_to_fishery"))
            arrived = game.request("act", choice_id=route["choice_id"])
            self.assertTrue(arrived["ok"], arrived)
            processing = next(c for c in arrived["choices"] if c["id"] == "work:recipe.smoke_lake_fish")
            self.assertIn("鲜鱼", processing["hint"])
            self.assertIn("无需消耗工具耐久", processing["hint"])
            self.assertFalse(processing["enabled"], "New player has no raw processing input")
            self.assertFalse(any({"offer", "statement", "report"}.intersection(c) for c in arrived["choices"]))
            slot = f"content_{os.getpid()}"
            self.assertTrue(game.request("save", slot=slot)["ok"])
            restored = game.request("load", slot=slot)
            self.assertTrue(restored["ok"], restored)
            self.assertEqual(restored["observation"], arrived["observation"])
            self.assertEqual(restored["choices"], arrived["choices"])
            self.assertEqual(game.request("inspect")["error"], "omniscient_inspection_disabled_in_play_mode")

    def test_local_information_and_v2_native_restore(self):
        with client(timeout=90) as game:
            opened = game.request("start", mode="play", scenario="echo_realm", seed=81001,
                                  economy_variant="player_life_v2")
            self.assertTrue(opened["ok"], opened)
            self.assertEqual(opened["observation"]["local_information"], [])
            self.assertTrue(any(c.get("purpose") for c in opened["choices"] if c["kind"] == "travel"))
            for choice in opened["choices"]:
                self.assertFalse({"statement", "offer", "report"}.intersection(choice))
            for _ in range(12):
                ask = next((c for c in opened["choices"] if c["kind"] == "player_life"
                            and c["id"].startswith("ask_local:") and c["enabled"]), None)
                if ask:
                    break
                wait = next(c for c in opened["choices"] if c["kind"] == "wait" and c["enabled"])
                opened = game.request("act", choice_id=wait["choice_id"])
                self.assertTrue(opened["ok"], opened)
            self.assertIsNotNone(ask, "No adult came through the commons within twelve hours")
            heard = game.request("act", choice_id=ask["choice_id"])
            self.assertTrue(heard["ok"], heard)
            self.assertEqual(len(heard["observation"]["local_information"]), 1)
            self.assertIn("告诉你", heard["observation"]["feedback"]["body"])
            slot = f"local_information_{os.getpid()}"
            self.assertTrue(game.request("save", slot=slot)["ok"])
            restored = game.request("load", slot=slot)
            self.assertTrue(restored["ok"], restored)
            self.assertEqual(restored["observation"], heard["observation"])
            self.assertEqual(restored["choices"], heard["choices"])
            wait = next(c for c in restored["choices"] if c["kind"] == "wait" and c["enabled"])
            continued = game.request("act", choice_id=wait["choice_id"])
            self.assertTrue(continued["ok"], continued)
            self.assertGreater(continued["observation"]["local_information"][0]["age_hours"],
                               restored["observation"]["local_information"][0]["age_hours"])
            self.assertEqual(game.request("inspect")["error"], "omniscient_inspection_disabled_in_play_mode")

    def test_player_body_journey_and_native_restore(self):
        with client(timeout=90) as game:
            opened = game.request("start", mode="play", scenario="echo_realm", seed=81001,
                                  economy_variant="player_life_v1")
            self.assertTrue(opened["ok"], opened)
            self.assertEqual(opened["observation"]["player"]["hunger"], "low")
            route = next(c for c in opened["choices"] if c["kind"] == "travel" and ".network." in c["id"])
            departed = game.request("act", choice_id=route["choice_id"])
            self.assertTrue(departed["ok"], departed)
            self.assertGreater(departed["observation"]["player"]["travel_remaining"], 0)
            self.assertIn("路上", departed["observation"]["location"]["title"])
            self.assertEqual(departed["observation"]["visible_people"], [])
            self.assertFalse(any(c["kind"] == "travel" for c in departed["choices"]))
            slot = f"player_journey_{os.getpid()}"
            self.assertTrue(game.request("save", slot=slot)["ok"])
            restored = game.request("load", slot=slot)
            self.assertTrue(restored["ok"], restored)
            self.assertEqual(restored["observation"], departed["observation"])
            while restored["observation"]["player"]["travel_remaining"]:
                continuation = next(c for c in restored["choices"] if c["kind"] == "player_life" and c["id"] == "continue")
                restored = game.request("act", choice_id=continuation["choice_id"])
                self.assertTrue(restored["ok"], restored)
            self.assertNotEqual(restored["observation"]["location"]["id"], opened["observation"]["location"]["id"])
            self.assertEqual(game.request("inspect")["error"], "omniscient_inspection_disabled_in_play_mode")

    def test_community_in_actual_process(self):
        with client(timeout=90) as game:
            opened = game.request("start", mode="world", scenario="echo_realm", seed=81001,
                                  economy_variant="community_life_v1")
            self.assertTrue(opened["ok"], opened)
            for _ in range(3):
                self.assertTrue(game.request("advance", hours=24)["ok"])
            facts, offset = [], 0
            while True:
                page = game.request("inspect", kind="facts", offset=offset, limit=100)
                self.assertTrue(page["ok"], page)
                facts.extend(page["rows"])
                offset += len(page["rows"])
                if offset >= page["total"]:
                    break
            self.assertTrue(any(f.get("fact_type") == "community_message_heard" for f in facts))
            self.assertTrue(any(f.get("fact_type") == "community_policy_changed" for f in facts))
            self.assertFalse(any(f.get("fact_type") == "test_injection" for f in facts))
            slot = f"community_{os.getpid()}"
            self.assertTrue(game.request("save", slot=slot)["ok"])
            self.assertTrue(game.request("load", slot=slot)["ok"])
            self.assertTrue(game.request("advance", hours=1)["ok"])

    def test_work_framework_in_actual_process(self):
        with client(timeout=90) as game:
            opened = game.request("start", mode="world", scenario="echo_realm", seed=81001,
                                  economy_variant="work_framework_v1")
            self.assertTrue(opened["ok"], opened)
            for _ in range(4):
                self.assertTrue(game.request("advance", hours=24)["ok"])
            facts = []
            offset = 0
            while True:
                page = game.request("inspect", kind="facts", offset=offset, limit=100)
                self.assertTrue(page["ok"], page)
                facts.extend(page["rows"])
                offset += len(page["rows"])
                if offset >= page["total"]:
                    break
            recipes = {f.get("recipe_id") for f in facts if f.get("fact_type") == "npc_livelihood_produced"}
            self.assertIn("recipe.net_fishing", recipes)
            self.assertIn("recipe.reed_cordage", recipes)
            self.assertTrue(any(f.get("tools_used") for f in facts), "No actual tool use in the runtime")
            self.assertTrue(any(f.get("choice_version") == 1 and len(f.get("alternatives", [])) >= 2 for f in facts))
            slot = f"work_framework_{os.getpid()}"
            self.assertTrue(game.request("save", slot=slot)["ok"])
            self.assertTrue(game.request("load", slot=slot)["ok"])
            self.assertTrue(game.request("advance", hours=1)["ok"])

    def test_integrated_household_work_in_actual_process(self):
        with client(timeout=60) as game:
            opened = game.request("start", mode="world", scenario="echo_realm", seed=81001,
                                  economy_variant="household_livelihood_v1")
            self.assertTrue(opened["ok"], opened)
            for _ in range(3):
                self.assertTrue(game.request("advance", hours=24)["ok"])
            facts = []
            offset = 0
            while True:
                page = game.request("inspect", kind="facts", offset=offset, limit=100)
                self.assertTrue(page["ok"], page)
                facts.extend(page["rows"])
                offset += len(page["rows"])
                if offset >= page["total"]:
                    break
            receipts = {row["fact_id"] for row in facts if row.get("fact_type") == "food_hauling_stocked"
                        and row.get("fee_paid", 0) > 0}
            withdrawals = {row["fact_id"] for row in facts if row.get("fact_type") == "household_pantry_taken"
                           and receipts.intersection(row.get("source_fact_ids", []))}
            self.assertTrue(receipts, "No real paid delivery into household storage")
            self.assertTrue(any(row.get("work_kind") == "subsistence" and row.get("products")
                                for row in facts), "No autonomous alternate livelihood")
            self.assertTrue(withdrawals, "Delivered food was not actually taken by a household member")
            self.assertTrue(any(row.get("fact_type") in
                                {"npc_self_meal", "npc_household_shared_food", "npc_cross_household_shared_food"}
                                and withdrawals.intersection(row.get("source_fact_ids", [])) for row in facts),
                            "No meal descended from a paid delivery and local withdrawal")
            slot = f"household_work_{os.getpid()}"
            self.assertTrue(game.request("save", slot=slot)["ok"])
            self.assertTrue(game.request("load", slot=slot)["ok"])
            self.assertTrue(game.request("advance", hours=1)["ok"])

    def test_opt_in_worksite_stock_in_actual_process(self):
        with client(timeout=60) as game:
            opened = game.request("start", mode="world", scenario="echo_realm", seed=81001,
                                  economy_variant="worksite_carting_v1")
            self.assertTrue(opened["ok"], opened)
            self.assertTrue(game.request("advance", hours=24)["ok"])
            facts = []
            offset = 0
            while True:
                page = game.request("inspect", kind="facts", offset=offset, limit=100)
                self.assertTrue(page["ok"], page)
                facts.extend(page["rows"])
                offset += len(page["rows"])
                if offset >= page["total"]:
                    break
            self.assertTrue(any(row.get("stock_entity_id") and row.get("fact_type") == "npc_livelihood_produced"
                                for row in facts), "No worksite production in actual package")
            self.assertTrue(any(row.get("fact_type") == "worksite_food_withdrawn" for row in facts))
            slot = f"worksite_{os.getpid()}"
            self.assertTrue(game.request("save", slot=slot)["ok"])
            restored = game.request("load", slot=slot)
            self.assertTrue(restored["ok"], restored)
            self.assertTrue(game.request("advance", hours=1)["ok"])
            self.assertFalse(game.request("start", mode="world", scenario="echo_realm", economy_variant="invented")["ok"])

    def test_family_provisioning_in_actual_process(self):
        with client(timeout=60) as game:
            self.assertTrue(game.request("start", mode="world", scenario="echo_realm", seed=81001)["ok"])
            for _ in range(2):
                self.assertTrue(game.request("advance", hours=24)["ok"])
            facts = []
            offset = 0
            while True:
                page = game.request("inspect", kind="facts", offset=offset, limit=100)
                self.assertTrue(page["ok"], page)
                facts.extend(page["rows"])
                offset += len(page["rows"])
                if offset >= page["total"]:
                    break
            deliveries = {row["fact_id"] for row in facts if row.get("fact_type") == "household_food_delivered"}
            self.assertTrue(deliveries, "No autonomous family delivery in actual process")
            meals = [row for row in facts if row.get("fact_type") in
                     {"npc_self_meal", "npc_household_shared_food", "npc_cross_household_shared_food"}]
            self.assertTrue(any(deliveries.intersection(row.get("source_fact_ids", [])) for row in meals),
                            "Delivered goods never reached a real meal")

    def test_canon_world_and_play_entry(self):
        for mode in ("world", "play"):
            with self.subTest(mode=mode), client(timeout=60) as game:
                opened = game.request("start", mode=mode, scenario="echo_realm", seed=81001)
                self.assertTrue(opened["ok"], opened)
                observation = opened["observation"]
                canon = observation["canon"] if mode == "world" else observation["region_map"]["canon"]
                self.assertEqual(canon["place_name"], "回音港")
                self.assertEqual(len(canon["regions"]), 6)
                if mode == "world":
                    progressed = game.request("advance", hours=1)
                else:
                    wait = next(c for c in opened["choices"] if c["kind"] == "wait" and c["enabled"])
                    progressed = game.request("act", choice_id=wait["choice_id"])
                self.assertTrue(progressed["ok"], progressed)
                before_save = progressed["observation"]
                slot = f"canon_{mode}_{os.getpid()}"
                self.assertTrue(game.request("save", slot=slot)["ok"])
                restored = game.request("load", slot=slot)
                self.assertTrue(restored["ok"], restored)
                self.assertEqual(before_save, restored["observation"])

    def test_agent_flow_and_receipt(self):
        with client(timeout=60) as game:
            opened = game.request("start", mode="play", scenario="lake_town", seed=81001)
            self.assertTrue(opened["ok"])
            self.assertEqual(opened["observation"]["location"]["title"], "老陈铺子")
            command = {"protocol": 1, "command": "act", "request_id": "read-中文",
                       "session_id": game.session_id, "expected_revision": game.revision,
                       "choice_id": "player_action/read_visible_readable_object:old_chen_shop_price_notice"}
            result = game.send(command)
            self.assertTrue(result["ok"])
            self.assertIn("北路车未到", result["observation"]["feedback"]["body"])
            replay = game.send(command)
            self.assertTrue(replay["replayed"])
            self.assertEqual(result["revision"], replay["revision"])
            self.assertEqual(result["observation"], game.request("observe")["observation"])
        self.assertEqual(game.process.returncode, 0)
        self.assertFalse(any(t.is_alive() for t in game.readers))

    def test_fragmented_unicode_frame(self):
        with client(timeout=30) as game:
            request = {"protocol": 1, "command": "observe", "request_id": "逐字节输入"}
            payload = json.dumps(request, ensure_ascii=False).encode("utf-8")
            frame = f"{len(payload):08d}".encode("ascii") + payload
            for byte in frame:
                game.process.stdin.write(bytes([byte]))
                game.process.stdin.flush()
            result = game._receive()
            self.assertEqual(result["error"], "not_started")
            self.assertEqual(result["request_id"], request["request_id"])

    def test_malformed_json_does_not_desynchronize(self):
        with client(timeout=30) as game:
            game.process.stdin.write(b"00000001{")
            game.process.stdin.flush()
            self.assertEqual(game._receive()["error"], "invalid_json")
            self.assertEqual(game.request("observe")["error"], "not_started")

    def test_frame_bounds_and_truncation(self):
        for frame, error in [(b"00065537", "invalid_frame_length"),
                             (b"00000005{}", "incomplete_frame"),
                             (b"000", "invalid_frame_length"),
                             (b"0000xxxx", "invalid_frame_length")]:
            with self.subTest(frame=frame), client(timeout=30) as game:
                game.process.stdin.write(frame)
                game.process.stdin.close()
                self.assertEqual(game._receive()["error"], error)
            self.assertEqual(game.process.returncode, 2)

    def test_timeout_owns_and_reaps_process(self):
        game = client(timeout=30)
        game.timeout = 0.05
        with self.assertRaises(TimeoutError):
            game._receive()
        self.assertIsNotNone(game.process.returncode)
        self.assertFalse(any(t.is_alive() for t in game.readers))

    def test_jsonl_cli(self):
        result = subprocess.run(
            [sys.executable, str(PROJECT / "tools" / "agent_play.py")] + (["--packaged"] if PACKAGED else []),
            input=b'{"command":"observe"}\n[]\n', capture_output=True, timeout=40,
        )
        self.assertEqual(result.returncode, 0, result.stderr.decode("utf-8", errors="replace"))
        lines = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertEqual(lines[0]["event"], "client_ready")
        self.assertEqual(lines[1]["error"], "not_started")
        self.assertIn("client_error", lines[2])

    def test_generated_region_and_cross_town_travel(self):
        with client(timeout=60) as game:
            opened = game.request("start", mode="play", scenario="generated_network", seed=81001)
            self.assertTrue(opened["ok"])
            region = opened["observation"]["region_map"]
            self.assertEqual(len(region["sites"]), 3)
            self.assertEqual(len(region["roads"]), 2)
            self.assertEqual(region["layout"], "topology_not_geography")
            names = [s["name"] for s in region["sites"] if s["id"] != region["current_settlement_id"]]
            route = next(c for c in opened["choices"] if c["kind"] == "travel" and c["enabled"]
                         and any(name in c.get("destination_name", "") for name in names))
            traveled = game.request("act", choice_id=route["choice_id"])
            self.assertTrue(traveled["ok"])
            self.assertNotEqual(region["current_settlement_id"], traveled["observation"]["region_map"]["current_settlement_id"])
            self.assertEqual(game.request("inspect")["error"], "omniscient_inspection_disabled_in_play_mode")


if __name__ == "__main__":
    unittest.main(verbosity=2)

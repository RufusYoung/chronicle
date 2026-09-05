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

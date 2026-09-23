import array
from pathlib import Path
import sys
import unittest
import wave

from generate_world_audio import ART, PROFILES, RATE, samples


class WorldAudioTest(unittest.TestCase):
    def test_committed_cues_match_original_generator(self):
        for name, (duration, _, _) in PROFILES.items():
            with self.subTest(cue=name), wave.open(str(ART / "audio" / f"{name}_v1.wav")) as source:
                self.assertEqual((source.getnchannels(), source.getsampwidth(), source.getframerate()), (1, 2, RATE))
                self.assertEqual(source.getnframes(), round(duration * RATE))
                self.assertEqual(source.readframes(source.getnframes()), samples(name))

    def test_signals_are_bounded_and_distinct(self):
        signals = set()
        for name in PROFILES:
            encoded = samples(name)
            signals.add(encoded)
            pcm = array.array("h")
            pcm.frombytes(encoded)
            if sys.byteorder != "little":
                pcm.byteswap()
            self.assertEqual(max(abs(value) for value in pcm), 8191)
            self.assertEqual(pcm[0], 0)
            self.assertEqual(pcm[-1], 0)
        self.assertEqual(len(signals), len(PROFILES))


if __name__ == "__main__":
    unittest.main()

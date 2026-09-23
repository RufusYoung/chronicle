"""Reproducible original UI cues; no sampled third-party recording or music."""

import array
import hashlib
import json
import math
from pathlib import Path
import random
import sys
import wave


RATE = 24000
ART = Path(__file__).resolve().parents[1] / "art"
PROFILES = {
    "action": (0.12, (260, 390), 0.28),
    "arrival": (0.32, (330, 440), 0.05),
    "work": (0.20, (180, 270), 0.30),
    "warning": (0.28, (170, 165), 0.16),
    "growth": (0.55, (440, 550, 660), 0.02),
}


def samples(name):
    duration, notes, noise = PROFILES[name]
    random_source = random.Random("chronicle.original.cue.v1." + name)
    signal = []
    count = round(duration * RATE)
    for index in range(count):
        t = index / RATE
        envelope = min(t / 0.008, 1.0) * (1.0 - t / duration) ** 2
        tone = sum(math.sin(math.tau * frequency * t) for frequency in notes) / len(notes)
        signal.append(envelope * ((1 - noise) * tone + noise * random_source.uniform(-1, 1)))
    peak = max(abs(value) for value in signal)
    pcm = array.array("h", (round(value / peak * 8191) for value in signal))
    if sys.byteorder != "little":
        pcm.byteswap()
    return pcm.tobytes()


def main():
    folder = ART / "audio"
    folder.mkdir(parents=True, exist_ok=True)
    catalog_path = ART / "catalog.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    for name in PROFILES:
        path = folder / f"{name}_v1.wav"
        with wave.open(str(path), "wb") as stream:
            stream.setnchannels(1)
            stream.setsampwidth(2)
            stream.setframerate(RATE)
            stream.writeframes(samples(name))
        relative = path.relative_to(ART).as_posix()
        entry = {"path": relative, "status": "runtime", "source": "",
                 "provenance": "audio/PROVENANCE.md", "bytes": path.stat().st_size,
                 "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
        catalog["files"] = [row for row in catalog["files"] if row["path"] != relative] + [entry]
    catalog_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()

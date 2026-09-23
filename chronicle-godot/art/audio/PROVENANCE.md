# Original Result Cues

Created for Chronicle on 2026-09-23 by `tools/generate_world_audio.py`.
Five short original mono PCM waveforms use deterministic sine tones and seeded
noise, with an attack/release envelope. No external sample, melody, recording,
reference-game resource or unverified legacy asset was used.

- `action_v1.wav`: a quiet neutral completion cue.
- `arrival_v1.wav`: a short arrival cue.
- `work_v1.wav`: a dry completed-work cue.
- `warning_v1.wav`: an interruption/failure cue, without success celebration.
- `growth_v1.wav`: an acquired trait or changed skill-rank cue, not every XP tick.

24 kHz, 16-bit, mono, normalized peak below -12 dBFS. These are presentation
signals, not simulated footsteps, diegetic actor sounds, location ambience or a
finished soundtrack. The shared interface offers mute and a 0-100% volume slider.
Preferences live outside native world saves and do not consume world time or RNG.

Regenerate with `python tools/generate_world_audio.py` from the Godot project.
The generator updates only these five owned files and their catalog entries;
review hashes and rerun the art boundary tests before export.

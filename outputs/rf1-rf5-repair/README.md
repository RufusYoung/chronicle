# RF1-RF5 Integration Repair Evidence

2026-09-21. This archive contains passive frozen runs, explicit mechanism-off interventions, controlled contracts and actual renderer regressions. None is independent human play.

- `integration_summary.json`: nine structural checks and per-case outcomes. `natural_negotiated_delivery_observed` is deliberately separate and currently false.
- `natural/`: three seeds for thirty days and four same-seed ablations; every directory includes runtime SHA256 manifest, configuration, engine logs, native-continuation result and causal audit. Natural seeds81001/82002;87029 held out until runtime freeze. Without-equipment/livelihood/negotiation controls are test interventions, not player choices.
- `final-regression/`:171/171 source regression scripts, including actual renderer checks. The legacy dedicated long-run test is excluded by the standard runner; seven new thirty-day passive runs supply the scoped long-horizon evidence.
- `equipment-final/`:53 controlled checks, including third data-defined equipment produced with finite inputs, equipped, consumed by a combat modifier and restored from embedded bootstrap.
- `negotiation-final/`:34 controlled checks. Initial stock/presence/conversations are test injections; after agreement the normal clock carries goods to the pantry and the household takes and eats them.

Audit ordering matters: a buyer's passive must apply after their purchase. Earlier use by the craftsperson is not evidence of purchased equipment changing the buyer's combat. The audit-tool unit test guards this distinction.

Native checkpoint paths and byte hashes are recorded in each audit. Large intermediate saves are not duplicated into Git. Reproduce from the repository root, using Godot4.6.3 and Python3:

```powershell
./chronicle-godot/tools/run_work_phase.ps1 -Framework integration -RunLabel repair_frozen2 -Seeds 81001 -Days 30 -SkipAblations -CaseTimeoutSeconds 1800 -OutputDirectory work/rf1-rf5-repair/reproduction/81001
# Repeat natural runs for82002 and87029. For controls replace SkipAblations with:
# -OnlyAblation equipment / livelihood / negotiation at81001; negotiation at87029.
# Each case needs a separate output directory. Do not edit runtime during evaluation.
python chronicle-godot/tools/summarize_world_integration.py outputs/rf1-rf5-repair/natural --output work/rf1-rf5-repair/summary-recheck.json
```

The summary is not a full phase gate: inspect controlled negotiation, legal play, package checks and remaining hunger/coverage limitations in the report. File counts, clocks and event totals do not establish playability.

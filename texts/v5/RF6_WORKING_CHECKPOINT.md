# RF6 Working Checkpoint

Updated 2026-09-11. Recovery context only; the single active plan remains `CHRONICLE_WORLD_FIRST_PLAN_v5.1.md`.

## Source and Hypothesis

- Branch `codex/player-agency-world-surface`, source HEAD `95818c3`; RF6 changes still uncommitted. No RF6 package yet.
- Formal player opts in via `player_life_version=1` / API `player_life_v1`. Authoritative body and physical travel, shared hunger, real food, wages, stock quotes, production, wear, maintenance and local reports are implemented. Old worlds retain their rules; experimental life/danger/community remain off by default.
- No replacement money, inventory or history store. Owned player snapshot only opts this actor into existing resolvers, never into NPC autonomy. Details: `CHRONICLE_PLAYER_LIFE_CONTRACT_v5.1.md`.
- Runtime frozen after final UI legacy-body summary fix. `player_life_evidence/runtime_manifest.json` contains 236 hashes. Do not change runtime without rerunning the affected evidence.

## Evidence

- `player_life_contract_test.gd`: 82/82, including real full tool use/repair and native continuation. `player_life_boundary_test.gd`: 17/17, including corrupt bootstrap/journey, absent/unfunded employer and knowledge boundary.
- `tools/test_agent_play.py`: 14/14 real source process tests, 62.946 seconds. No mock transport or hidden play inspection.
- `frozen_81001/` and `heldout_85005/`: four lawful strategies from each exact same native start, 72 hours. Prepared intervention changes residents; direct risk does not improve their outcome; local help changes food/work/payments and produces local reports. Coins conserved at 301/282. This supports E3 mechanics, not complete visible causality or fun.
- `frozen_tool/`: 168-hour legal play from zero player coins. Two jobs earn six, purchase costs five, four fishery cycles wear bought rope to zero, actual materials repair it to two, twelve-hour cordage work completes after interruption and wears it to one. A new rope is actually present. 139 actions, 82 waits, 41 food held, eight residents still extremely hungry. Keep these negative limits.
- `tools/verify_player_life.py`: source audit 58/58. Optional `--package builds/h1-windows` checks clean manifest, executable/PCK hashes and four complete native state parity comparisons.
- Actual OpenGL life renderer verifies 720p/900p, wage callback, local inquiry content and being on the road. Screenshots under `%APPDATA%/Godot/app_userdata/CHRONICLE_GODOT/tests/player_life_render/`.

## Running Processes at This Checkpoint

- First full regression finished 155/156; one old community UI 720p overflow was fixed. All 26 final render tests passed. Both old sessions are closed; failed evidence retained.
- exec session **41384** reruns the complete final frozen suite to `%TEMP%/chronicle-rf6-frozen-regression`. Wait for completion, then copy logs into evidence. This keeps the repo clean during export.
- exec session **62828** runs a 168-hour lawful observer comparison to `%TEMP%/chronicle-rf6-tool-observer`; compare it with `frozen_tool` at the same time before attributing world hunger to the player. Wait and retain evidence.
- All earlier policy and protocol sessions finished. No automation or separate task created.

## Next Executable Actions

1. Finish both test sessions. Preserve first regression's failed result; combine with the final render reruns by exact test name, check discovery coverage and current runtime hashes. If there are further failures, diagnose rather than declaring a checkpoint.
2. Inspect/copy actual rendered screenshots, finish source report, then commit verified source, UID files, plans and evidence; push. Before export the workspace must be clean.
3. `tools/export_windows.ps1` refreshes `builds/h1-windows`. Run actual package protocol tests and `play_player_life.py --packaged --output .../packaged_81001`; then `verify_player_life.py .../player_life_evidence --package builds/h1-windows`.
4. `verify_household_package_save.py` can render `frozen_tool/tool_life.native.json` at 168 hours with `--expected-work-version 1`, and the previous thirty-day save for legacy continuity. It uses an isolated startup probe, preserving the manual player save.
5. Update report/build evidence and active plan, commit/push. This integrated player/world milestone may be reported, but RF6 remains active; do not declare complete Demo/E3 readability. Next block is meaningful supply/work information, voluntary surplus sales/delivery and visible danger-to-resident aftermath, then content/assets/first experience.

## Failed Approaches Kept

- Candidate1 used a wrong route fragment; no preparation/help executed. Candidate2 exposed hired output merging into an existing player food stack. Fixed output recipient before shared merge/create, with a matching-stack counterexample.
- Tool candidate1/2 were slow supply strategies. Tool candidate3 correctly repaired but controller called unfinished cordage work done. Final controller requires real inventory, and `frozen_tool` contains the actual completed product.
- Extra test money originally failed the global currency invariant; controlled test now transfers existing funds and explicitly labels the intervention. It is not evidence of natural wages.
- Hunger/death, migration membership, employment bargaining, food sale consent and whole-world balance are not complete. Do not invent free food, automatic payment or a guaranteed helpful ending.

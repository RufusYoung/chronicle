# RF6 Working Checkpoint

Updated 2026-09-11. Recovery context only; the single active plan remains `CHRONICLE_WORLD_FIRST_PLAN_v5.1.md`.

## Source and Hypothesis

- Branch `codex/player-agency-world-surface`, source HEAD `abddb86`, pushed. Final display cleanup, audit/client tools and evidence await a second verified source commit and clean re-export.
- Formal player opts in via `player_life_version=1` / API `player_life_v1`. Authoritative body and physical travel, shared hunger, real food, wages, stock quotes, production, wear, maintenance and local reports are implemented. Old worlds retain their rules; experimental life/danger/community remain off by default.
- No replacement money, inventory or history store. Owned player snapshot only opts this actor into existing resolvers, never into NPC autonomy. Details: `CHRONICLE_PLAYER_LIFE_CONTRACT_v5.1.md`.
- Simulation frozen at `abddb86`; final display-only removal of empty tradeoff captions passed all 26 render tests. `player_life_evidence/runtime_manifest.json` contains 236 final hashes; `simulation_runtime_manifest.json` records the prior freeze. Do not change runtime without rerunning affected evidence.

## Evidence

- `player_life_contract_test.gd`: 82/82, including real full tool use/repair and native continuation. `player_life_boundary_test.gd`: 17/17, including corrupt bootstrap/journey, absent/unfunded employer and knowledge boundary.
- `tools/test_agent_play.py`: 14/14 real source process tests, 62.946 seconds. No mock transport or hidden play inspection.
- `frozen_81001/` and `heldout_85005/`: four lawful strategies from each exact same native start, 72 hours. Prepared intervention changes residents; direct risk does not improve their outcome; local help changes food/work/payments and produces local reports. Coins conserved at 301/282. This supports E3 mechanics, not complete visible causality or fun.
- `frozen_tool/`: 168-hour legal play from zero player coins. Two jobs earn six, purchase costs five, four fishery cycles wear bought rope to zero, actual materials repair it to two, twelve-hour cordage work completes after interruption and wears it to one. A new rope is actually present. 139 actions, 82 waits, 41 food held, eight residents still extremely hungry. Keep these negative limits.
- `tools/verify_player_life.py`: source audit 63/63, including complete test discovery. Optional `--package builds/h1-windows` adds clean manifest, tracked export-source identity, executable/PCK hashes and four complete native state parity comparisons from `packaged_final_81001/`.
- Actual OpenGL life renderer verifies 720p/900p, wage callback, local inquiry content and being on the road. Screenshots under `%APPDATA%/Godot/app_userdata/CHRONICLE_GODOT/tests/player_life_render/`.

## Completed Processes and Remaining Closeout

- First full regression finished 155/156; one old community UI 720p overflow was fixed. Final full regression finished 156/156, summed durations 820.92 seconds. A subsequent display-only cleanup passed all 26 real render tests. Evidence is retained under `frozen_regression/` and `final_render/`.
- The supplemental 168-hour observer finished: same initial game truth/time, different save IDs/timestamps. Both branches have eight extremely hungry residents, but three residents' hunger bands and multiple production counts differ. Preserve these mixed effects, not a universal improvement claim.
- Source protocol 14/14, preliminary clean `abddb86` package protocol 14/14 and four native parity comparisons passed. Actual packaged UI loaded the formal seven-day and legacy thirty-day saves. Final display cleanup still requires a matching clean export and package rechecks.
- All earlier sessions are closed. No active process, automation or separate task at this checkpoint.

## Next Executable Actions

1. Commit verified final source/UI/client/audit tools, UID files, plans and evidence; push. Before export the workspace must be clean.
2. `tools/export_windows.ps1` refreshes `builds/h1-windows`. Run actual package protocol tests and `play_player_life.py --packaged --godot C:/code/game/chronicle/builds/h1-windows/Chronicle.exe --output .../packaged_final_81001`; then `verify_player_life.py .../player_life_evidence --package builds/h1-windows` (70 expected checks).
3. `verify_household_package_save.py` renders `tool_life.ui_probe.json` at 168 hours with `--expected-work-version 1`, and the previous thirty-day save for legacy continuity. The agent native envelope requires formal Live save wrapping; `prepare_agent_ui_probe.gd` already produced this probe while asserting unchanged game truth. Isolated startup probes preserve the manual player save.
4. Update report/build evidence and active plan, commit/push. This integrated player/world milestone may be reported, but RF6 remains active; do not declare complete Demo/E3 readability. Next block is meaningful supply/work information, voluntary surplus sales/delivery and visible danger-to-resident aftermath, then content/assets/first experience.

## Failed Approaches Kept

- Candidate1 used a wrong route fragment; no preparation/help executed. Candidate2 exposed hired output merging into an existing player food stack. Fixed output recipient before shared merge/create, with a matching-stack counterexample.
- Tool candidate1/2 were slow supply strategies. Tool candidate3 correctly repaired but controller called unfinished cordage work done. Final controller requires real inventory, and `frozen_tool` contains the actual completed product.
- Extra test money originally failed the global currency invariant; controlled test now transfers existing funds and explicitly labels the intervention. It is not evidence of natural wages.
- Hunger/death, migration membership, employment bargaining, food sale consent and whole-world balance are not complete. Do not invent free food, automatic payment or a guaranteed helpful ending.

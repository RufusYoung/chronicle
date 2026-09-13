# RF6 Working Checkpoint

Updated 2026-09-13. Recovery context only; the single active plan remains `CHRONICLE_WORLD_FIRST_PLAN_v5.1.md`.

## Current Sep 13 Source Checkpoint

- HEAD `0e291dd`, branch `codex/player-agency-world-surface`. The Sep 11 package remains at `b71ee27`; it does not yet contain this work. No unrelated user changes were present at start.
- New explicit `player_life_version=2` / API `player_life_v2`, UI new-world life checkbox selects v2. V1 and old saves retain their economic rules.
- `player_local_life.gd` connects voluntary paid food sales/gifts, actual resident meals, first-hand local information with 12-hour age/expiry, bounded hourly rest/travel, and public destination-use hints. It reuses Market, physical stock, provenance and existing bodies.
- NPC production can reference an actual still-active danger retreat plus the player's recent damage contribution, including an NPC final blow. This is a limited removed-obstacle association, not sole credit or a universal welfare gain. Reports require physical observation or a present actual participant.
- Shared UI now has purpose filters (work, trade/giving, talk, rest/travel) without new nested scrolling. Unread statements and private offer policies are stripped from public action rows. Filter/page changes consume no game time.
- Focused contract currently 67/67; real render tests `player_life_render_test` and new `player_local_life_render_test` pass at 720p/900p. These are program-driven UI, with clearly labeled controlled fixtures in the latter, not human play.
- First legal 72-hour four-policy candidate at `%TEMP%/chronicle-local-life-candidate1`: trade sells two portions for six coins, gift makes four transfers, prepared branch has a real resumed-work attribution; total coins stay 301. Trade/gift take 40/36 actions, observer 72. Gift ends with eight extremely hungry residents versus observer seven; preserve the negative outcome. Candidate predates final presentation/attribution guards, so rerun a frozen version before accepting it.
- Runtime freeze is 237 hashes; final 81001 and held-out 86013 four-policy 72h comparisons, 81001 three-policy 168h comparison, and natural danger checkpoint rendering passed. Source audit 124/124. Full regression finished 157/158 (790.89s), only a stale capacity wording assertion failed; test-only correction passed the scoped rerun (4.85s). Final effective coverage is 158 with 27 actual renders, not a new 30-day health run.
- Final source protocol transcript run passed 15/15 in 57.725s; all sessions are closed. Next: commit/push verified source with UIDs, clean export, actual packaged protocol/four-policy parity, and v2-week/v1-week/legacy-day30 package renders. Evidence is `chronicle-godot/texts/reports/2026/2026-9/2026-9-13/local_life_evidence/`. The old Sep 11 package is not current proof.
- Seven-day trade makes one sale and 42 single-hour waits; gifts make 11 transfers, but observer/trade/gift each end with eight extremely hungry residents. Keep this negative density/welfare result. Next RF6 dependency after package closure is the existing data-only expansion, canon art/short incidents and first-experience gate, not indefinite single-seed food tuning.
- Failed approaches: new `Array.has` version tests rejected JSON-restored float versions, freezing the loaded player's hunger/rest; fixed semantic numeric checks, with native continuation and unchanged-question tests. Public worksite guidance incorrectly assumed every generated worksite had a settlement field; fixed by its authored/generated production profile. Tall action filter buttons overflowed the dense 720p layout; compact existing styles fixed it without reducing text size. Early test method typo `build_view` was corrected to the real `build_view_data`.
- No new asset, video, public submission, automation, task or model-setting change. Remaining RF6 data-only content expansion, canonical assets and the 15-25 minute first experience are still pending.

## Previous Verified Checkpoint (Sep 11)

## Source and Hypothesis

- Branch `codex/player-agency-world-surface`, runtime/build source `b71ee27`, pushed. Final package evidence and closeout documents form a following documentation-only commit; use Git for its exact HEAD.
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
- Source protocol 14/14. Final clean `b71ee27` package protocol 14/14 in 41.864 seconds; four 72-hour strategies' native game truth matches source exactly. Actual package loaded/rendered the formal seven-day and legacy thirty-day saves in 4975.60/5670.11 ms. Audit 70/70, 236 runtime hashes, export-source tracking and EXE/PCK hashes match. Build manifest has `sourceDirty=false`.
- All earlier sessions are closed. No active process, automation or separate task at this checkpoint.

## Next Executable Actions

1. RF6 remains active. Next executable work is public local supply/work information with age, source, cost and a meaningful alternative to repeated waiting. Reuse current owned stock, actor presence and local knowledge; do not create an omniscient market feed.
2. Integrate voluntary surplus sale/delivery with real buyers, payments and later meals, and observable danger-to-work/livelihood aftermath. Use the existing market, transactions and fact provenance; preserve refusal, absence and poverty counterexamples.
3. Then finish data-only content expansion, canonical art/assets and a coherent first experience. This integrated player/world checkpoint is not full RF6, E3 readability or human play acceptance.
4. Reproduction: `verify_player_life.py .../player_life_evidence --package builds/h1-windows` gives 70 checks. Final package runs are `packaged_final_81001/`, `package_protocol_final.log`, `package_life_save_final.json` and `package_legacy_day30_final.json`. Do not rerun everything before changing a candidate; use scoped tests, freeze, then broader package checks.

## Failed Approaches Kept

- Candidate1 used a wrong route fragment; no preparation/help executed. Candidate2 exposed hired output merging into an existing player food stack. Fixed output recipient before shared merge/create, with a matching-stack counterexample.
- Tool candidate1/2 were slow supply strategies. Tool candidate3 correctly repaired but controller called unfinished cordage work done. Final controller requires real inventory, and `frozen_tool` contains the actual completed product.
- Extra test money originally failed the global currency invariant; controlled test now transfers existing funds and explicitly labels the intervention. It is not evidence of natural wages.
- Hunger/death, migration membership, employment bargaining, food sale consent and whole-world balance are not complete. Do not invent free food, automatic payment or a guaranteed helpful ending.

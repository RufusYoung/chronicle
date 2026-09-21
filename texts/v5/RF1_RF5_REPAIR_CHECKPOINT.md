# RF1-RF5 Repair Checkpoint

2026-09-21. Recovery record, not a second active plan. User explicitly redirected development to the gaps in the first five RF rounds. RF6 first-experience work resumes after this integration; earlier partial acceptance remains historical evidence.

## Baseline and Scope

- Branch: codex/player-agency-world-surface. Clean at start; baseline c83cdcd457bd494efe3a538672f1b8b52b039cdc. No user edits restored.
- Confirmed gaps: only work-recipe tools create autonomous procurement demand; NPC combat gear evidence used test injection. New-world retreat lacks lantern action/context tags. Subsistence candidates stop at the first eligible site. Community refusal is recorded but not transmitted as a reply; no bilateral renegotiation/recovery evidence.
- Implement explicit bootstrap-versioned integrated rules using existing items, market, work recipes, equipment loadouts, memories, transactions and native saves. Preserve all legacy world variants.
- No procedural loot/rich rarity system, continent politics, permanent death or full ecology expansion is implied. No new tasks, automation or model setting changes.

## Current Action

Source implementation, frozen validation and Windows package checks are complete. Source/export commit `f5f77b4394e35e68cf8cf237ec35ccb9bf8744c0`. Explicit integration v1 pack adds two fiber equipment definitions, production variants, wear/maintenance, witnessed-danger procurement, real market payment, automatic owned equipment selection, physically heard shortage feedback, transmitted aid refusal and bounded counterproposal, additional food alternatives and survival priorities. No previous world gains these rules. UI new coastal world and backend `world_integration_v1` select this version; old saves remain unchanged.

Latest authoritative recovery state: all seven frozen2 thirty-day sessions and regression39532 have finished. Final regression171/171; source legal protocol21/21; supplemental equipment53/53, negotiation initially34/34 and finally39/39, audit-tool2/2. The extra five checks save a known counterproposal before any accepted order, then48 ordinary hours make the resident choose and deliver without an explicit test order or movement. Archived evidence: `outputs/rf1-rf5-repair`. All nine structural summary checks pass. Natural samples have zero test injections; mechanism-off controls each have one explicitly labeled intervention. Runtime scripts/data/scenes have not changed during or after frozen2;247 current byte hashes verified. Extra test is not a runtime change.

Three natural seeds81001/82002/87029: equipment purchases2/4/3, repairs3/2/0, extreme-person-hours2498/2115/2442, maximum meal gaps55/45/74, final minimum health100/94/60. Same81001 without livelihood:5051 extreme-person-hours,201-hour gap,minhealth38. Without equipment:46 injuries versus26 with gear, but2282 versus2498 extreme-person-hours; gear does not universally improve food supply. Held-out87029 without negotiation:3 deliveries versus13,2276 versus2442 extreme-person-hours. This total includes ordinary household deliveries, not thirteen successful negotiations.

Natural held-out reply did not reach its original requester before expiry; zero natural counterproposals or negotiated deliveries in all three samples. Same-pair aid later resumed through a fresh request/policy change. Controlled34-check test proves physically exchanged reply/counterproposal, actual hauling, pantry receipt and later meal. Keep natural negotiation completion and universal food adequacy explicitly open. No forcing actors to reconcile for acceptance.

Package checks completed: session27874 legal protocol21/21 in63.761s; new integrated30-day and legacyRF4 30-day native saves rendered and restored the isolated probe path; sourceDirty=false manifest. Initial actual controllable frame3.51s, new30-day9.01s, legacy30-day7.05s on development machine. Autonomy supplemental runner16739 also completed39/39. No task-owned process remains. Final report records open natural-negotiation and food-adequacy coverage; active plan keeps those gaps open instead of silently moving to RF6. Next-stage reasoning: extra-high. Final step: publish the report/evidence-only follow-up commit and verify Git synchronization.

Metric correction: the original probe's extreme-person-hours includes the inactive traveler as well as generated residents. The resident health/meal table excludes that traveler. Audits and report now state this explicitly; old raw probe totals are preserved, not relabeled or rewritten. Structural summary pass is not full phase acceptance.

## Earlier Diagnostic Record

The following notes preserve earlier progress and process identifiers. They are historical, not instructions to resume completed sessions.

Focused evidence: resident_equipment_contract_test 52/52 (including actual spare equipment sale, third data-only production with finite material/tool wear, purchase/ownership/payment, no repeat equip, lantern night-only retreat, embedded save); community_negotiation_contract_test 31/31 (ordinary nonrepresentative reply candidate, physical reply/counterreply, expiry/oversize rejection, native restore and twelve ordinary clock hours reaching the actual recipient pantry without moving carrier in test); world_integration_contract_test 21/21 (new/old bootstrap, finite wildlife feeding and unauthorized actor/remote/wrong diet/oversize counterexamples, compiled signature rejection). Livelihood6/6. These are controlled tests, not autonomous acceptance.

Short natural diagnostics, all seed 81001:
- candidate1: corrected canonical `slot.*` lookup and int/float bootstrap signature mismatch. Old candidate1c evidence had three produced/equipped whips but consumed the only work rope; recipes now wear a retained tool instead.
- candidate2: seven days logged apparent PASS but had missing snapshot.get_fact script errors; invalid acceptance evidence. Added read-only snapshot lookup and strict runner scans stderr.
- candidate3: valid seven-day native continuation, 8 equips, no purchases, high terrace hunger. All-forage candidates alone did not solve production loss.
- candidate4: 7 days, 6 equips, no purchases, 804 extreme-person-hours, one injured resident still stuck. Runner correctly rejected final freeze because UI/runtime was edited during exploratory execution. Audit is diagnostic only at work/rf1-rf5-repair/candidate4.
- candidate5: 7 days, native continuation, 957 extreme-person-hours. Removing producer-shopping ban and urgency scoring alone worsened aggregate hunger. No improvement claimed.

Root-cause pivot: fixed-territory danger occupies most farm work hours without its own feeding/satiety. Added explicit versioned `threat_foraging` to integration only: six active hours consume 0.5 of the same local finite food/roots resource potential, then 18-hour respite. Depleted food cannot grant respite. ResourceAccess checks creature type, configured diet, presence, amount and meal source; it is wildlife consumption, not permission to use private ItemStore food. This is abstract resource pressure, not full ecology or raw crops/soil nutrition.

Current hypothesis: actual feeding/respite opens production windows while preserving contacts, injuries, gear demand and competition. Candidates6/7 finished fourteen days with native continuation. Candidate7 still had 1181 extreme-person-hours; its four work purchases were ropes, not combat equipment. Professional food production now reads known household need; equipment stock distinguishes worn personal gear from sale stock.

Frozen1 stopped intentionally after seed81001 finished30 days/native continuation (1170.9s): eleven equipment selections, zero combat purchases/replies,2458 extreme-person-hours. Seed82002 just started when session52360 was terminated; no child left running. The same naturally crafted whip has ten modifier-affected encounters, two material-consuming repairs, and later wear; all sixteen residents day21health100, but some meal gaps55hours. Runtime changed only after completed first sample. Archive as pre-fix diagnostic, not final three-seed acceptance.

Two discriminating tests then exposed and fixed real integration gaps: worn-to-spare upgrades were counted as sale stock but carried spares were invisible to market; ordinary nonrepresentatives had no dispatch candidate for replies. Both fixes retain physical presence, actual payment, worn/tool reservation, firsthand addresses and opportunity costs. No seed tuning followed held-out inspection.

Active frozen2: separate `run_work_phase.ps1 -Framework integration -RunLabel repair_frozen2 -Seeds SEED -Days 30 -SkipAblations -CaseTimeoutSeconds 1800 -OutputDirectory work/rf1-rf5-repair/frozen2/SEED` sessions12800(seed81001),7849(seed82002),47209(held-out87029). Three separate same-seed ablations use `-OnlyAblation equipment/negotiation/livelihood` instead of SkipAblations, sessions78044/76074/70234, output subdirswithout-equipment/without-negotiation/without-livelihood. DO NOT edit runtime scripts/data/scenes while these run. Seed87029 day7 naturally has one vest purchase, one refusal/reply, three heard replies, zero counterproposals so far. All six runs still pending. Tools/tests/docs may be edited; native saves under user://tests/food_economy_probe/canon_integration[_without_MECHANISM]_repair_frozen2_SEED.

Prior full regression99423 completed170/171. The sole old interruption-render timetable failure now passes after explicit legacy bootstrap restore; assertions unchanged. Final regression active session39532, outputwork/rf1-rf5-repair/final-regression. Source actual protocol20/20 passed in100.2s before two localized fixes; package suite must run current source. Godot editor import completed, new UIDs generated; inspect Git for unrelated imports before staging. No export, commit or push yet.

Additional active frozen ablation session81934: seed87029 without negotiation, samefrozen2 prefix, outputwithout-negotiation-87029. This held-out world actually emitted a refusal, so its comparison can discriminate message effects;81001 without-negotiation may be identical if no refusal occurred. Source protocol suite now21 tests (added real integrated legal travel, defend, withdraw, leave and restore), active session61549; added test itself passed in6.965s. Current main seeds aboutday20 and ablationsday13-19, no engine errors observed. Seven long runs plus final regression and protocol suite are active; do not abandon them.

Held-out87029 day14: purchased vest has two actual modifier uses; donor007 refused atday4.14, formed replyday4.15 and autonomously tried to carry it but missed recipient. Three others heard it, original requester had not. Donor later naturally delivered three portions atday6.0 after fresh request/policy change, not an accepted two-portion counterproposal. Report this distinction honestly. The controlled negotiation test proves actual twelve-hour delivery after bilateral agreement; it does not force every natural refusal to end in negotiation. Maximum meal gaps still include74hours for one resident; day14 all health98-100, not evidence of universal food adequacy.

Actual720p renderer inspected: layout fits and result text shows real meal/benefit; local organization still exposes representative internalID, and full player gear examination/equip UI remains pending. These were merged into existingRF6 first-experience scope in the single active plan, not silently counted as RF5 gameplay completion. BuildREADME andbodycontract now identify explicitintegrationv1 and preserve oldvariants. Work/rf1-rf5-repair is ignored; curate final evidence underoutputs, not all large intermediates.

At that earlier checkpoint the package, full frozen runs and later supplemental assertions were still required. Use Current Action above for live status. This document is a recovery record, not itself phase acceptance.

## Acceptance

- Existing RF1-RF3 scoped contracts and resource/save regressions remain valid.
- Natural acquisition and use of the same equipment instance, plus wear and repair/replacement; unavailable/unaffordable/absent counterexamples. A data-defined alternative must use the same consumer.
- Unknown/refused/expired replies cannot trigger omniscient aid. Negotiation can fail or reduce quantities; actual cooperation can resume and change recipient life, with source references.
- Frozen three-seed thirty-day natural integration and mechanism ablations, at least one held-out seed. Account for individual livelihood failures, not just total meals.
- Legal agent and real renderer checks, native old/new continuation, matching Windows package smoke. Not human play or RF6 completion.

Evidence will be kept in `work/rf1-rf5-repair`; final reproducible evidence archived under `outputs`. No active processes at initialization. Next-stage reasoning recommendation: extra-high.

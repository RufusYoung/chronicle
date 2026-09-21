# Chronicle Agent Entry

## Current Direction

- Use `texts/v5/CHRONICLE_WORLD_FIRST_PLAN_v5.1.md` as the single active plan. Read its current section, then only the contracts needed for the selected work. Historical next-step lists are not additional active plans.
- Preserve the creative direction in `texts/CHRONICLE_CREATIVE_DIRECTION_GUIDE.md`: a causal world that supports ordinary life, dangerous journeys, relationships and time, not an economic dashboard or a fixed quest sequence.
- Project development skill: `.agents/skills/chronicle-world-development/SKILL.md`. Use it for continued implementation, world evaluation and project review.
- For world content, start with `texts/v5/CHRONICLE_CANON_WORLD_FOUNDATION_v5.1.md` and its original region/history/faction sources. Authored geography and history constrain generation; current v5 contracts govern implementation. Do not promote UI prototype places to canon, rewrite an unresolved source conflict, or mistake the static atlas for active civilization simulation. Generate local detail inside explicit anchors; preserve later causal political change.

## Continuous Execution

The user explicitly authorized consecutive development iterations on 2026-09-05. A tested commit and report are checkpoints, not automatic turn endings. Select the next dependency-ready action and continue within the active request.

The user's 2026-09-21 clarification fixes the development reporting unit to the eight named integrated rounds RF1-RF8 in the active plan. A "round" in user-facing progress means one of these eight, never a mechanism, bug fix, work session, commit or package. The two Sep 21 work blocks were both inside RF6, not two completed rounds.

During an authorized development request, stop for a completion report only after the current RF round's full acceptance criteria and deliverables are satisfied. This overrides the earlier broad "substantive milestone" interpretation: several mechanisms running together or a tested Windows build does not justify ending RF6 while its first-experience, UI or asset requirements remain unfinished. Record internal checkpoints, commit/push and continue to the next dependency-ready item without requiring another user "continue". Brief commentary is a progress update, not a completion report or a reason to stop.

Other valid stops remain: the user pauses or redirects, a genuine product/authority decision is necessary, or an external blocker leaves no useful authorized work. State the unfinished RF round and exact missing decision/evidence in that case; never label it completed. Answer direct user questions and process corrections directly without misrepresenting that answer as a development milestone.

The user clarified on 2026-09-06 that a single new mechanism, even with an hour of work, tests and a package, is a small checkpoint. Several systems working together are necessary evidence, not sufficient grounds to stop before the named RF acceptance gate. Failed local experiments require continued diagnosis and integration, not a final milestone report. For H2, carry needs, work, physical goods, travel, payment and later reactions through an autonomous multi-day chain with counterexamples and persistence; do not substitute this subset for the rest of the current RF round.

Reversible implementation and balance choices are engineering work. State and record the assumption, test alternatives, and proceed. Ask about changes to genre, creative direction, public commitments, monetization, incompatible player-save policy or material deadline/scope tradeoffs. Do not invent recurring automations, new tasks or new account expenditure to keep running.

## Engineering and Evidence

- Keep existing Stores, Effects, Transactions and native SaveEnvelope as the source of truth. Do not add competing inventory, money or history representations.
- New world behavior is explicitly versioned in generated bootstrap data. Old saves must not acquire new economic rules silently.
- Separate passive simulation, legal agent play, program-driven UI rendering, human UI play and test injection. Never call injected events player choices.
- State who knows what, where they are, who owns the goods, what is spent, and what later becomes possible or impossible. Logging a consequence does not implement it.
- Preserve source art in `chronicle-godot/art/`; keep `素材包` originals intact. Do not redistribute third-party game assets or code as Chronicle assets.
- Validate scoped changes, causal counterexamples, persistence and relevant regressions. Runtime changes require a refreshed Windows package and actual package smoke test, not export exit status alone.
- Keep Git synchronized at verified checkpoints. Preserve user-authored changes; do not broadly restore a dirty workspace.

## Model and Context

The user defaults to extra-high (极高) reasoning. Every progress or checkpoint report must include a reasoning-effort recommendation for the next stage and a brief task-specific reason. Recommend Ultra only when the next integrated task has a concrete need for it; do not change global or task settings silently.

The requested development model is GPT-6 Astra. Model configuration is not proof of the current task's runtime identity; report only verified configuration or tool results. Do not silently edit global settings or hard-code assumed model capabilities into game logic.

Prefer concise goals, observable acceptance criteria and file ownership over a long prescriptive implementation script. Before compaction or handoff, record the current hypothesis, source commit, unfinished changes, active process IDs, evidence paths, failed approaches and next executable action. A stronger model does not replace product evidence.

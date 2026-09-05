# Chronicle Agent Entry

## Current Direction

- Use `texts/v5/CHRONICLE_WORLD_FIRST_PLAN_v5.1.md` as the single active plan. Read its current section, then only the contracts needed for the selected work. Historical next-step lists are not additional active plans.
- Preserve the creative direction in `texts/CHRONICLE_CREATIVE_DIRECTION_GUIDE.md`: a causal world that supports ordinary life, dangerous journeys, relationships and time, not an economic dashboard or a fixed quest sequence.
- Project development skill: `.agents/skills/chronicle-world-development/SKILL.md`. Use it for continued implementation, world evaluation and project review.
- For world content, start with `texts/v5/CHRONICLE_CANON_WORLD_FOUNDATION_v5.1.md` and its original region/history/faction sources. Authored geography and history constrain generation; current v5 contracts govern implementation. Do not promote UI prototype places to canon, rewrite an unresolved source conflict, or mistake the static atlas for active civilization simulation. Generate local detail inside explicit anchors; preserve later causal political change.

## Continuous Execution

The user explicitly authorized consecutive development iterations on 2026-09-05. A tested commit and report are checkpoints, not automatic turn endings. Select the next dependency-ready action and continue within the active request.

Stop when the user pauses or redirects, a decision genuinely requires their product preference or new authority, an external blocker leaves no useful authorized work, or a substantive milestone merits their review. A new document, test count, routine parameter choice or completed round alone is not a milestone.

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

The requested development model is GPT-6 Astra. Model configuration is not proof of the current task's runtime identity; report only verified configuration or tool results. Do not silently edit global settings or hard-code assumed model capabilities into game logic.

Prefer concise goals, observable acceptance criteria and file ownership over a long prescriptive implementation script. Before compaction or handoff, record the current hypothesis, source commit, unfinished changes, active process IDs, evidence paths, failed approaches and next executable action. A stronger model does not replace product evidence.

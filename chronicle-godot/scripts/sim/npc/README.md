# NPC Autonomous Decision System

`V5NpcNeedSystem` and `V5NpcDecisionSystem` run during a world tick after deferred and due settlements. Needs advance first, then decisions evaluate the resulting global state. A multi-hour tick is simulated in one-hour rounds so travel and long waits do not skip intermediate NPC actions.

Each decision round evaluates every matching actor in a global world snapshot, selects at most one action per actor, and writes the result through `V5TransactionWorldWriter`.

The UI still uses a location-scoped snapshot. Global simulation and local projection therefore remain separate.

## Rule Shape

Need profiles live in `data/sim/raw/npc_need_profiles/`. A profile matches actors by type and tags, then advances one or more ordered need scales. Each need can define its own clock, default interval, and actor-specific interval state.

Rules live in `data/sim/raw/npc_action_rules/` and contain:

- `actor`: reusable type, tag, and state filters.
- `bindings`: references read from the matched actor, such as a dependent, workplace, notice, or door.
- `requirements`: hard eligibility conditions.
- `utility_factors`: weighted conditions that explain why an action became preferable.
- `minimum_utility`: the score required before the actor acts.
- `once_fact_type`: an actor-scoped fact that prevents duplicate execution.
- `effects`: facts, state changes, relationships, pressures, memories, traces, rumors, exchanges, and player-facing narrative.

The system groups eligible actions by actor. Highest utility wins; priority and rule ID provide deterministic tie-breaking. Randomness is not required for emergence and should not replace causal state.

## Observation Boundary

All autonomous actions enter the global world log. An action is immediately visible when the player is at its source or destination, allowing an arriving NPC to be noticed. Unobserved facts stay out of immediate feedback. Persistent traces and location-bound rumors reveal selected offscreen events when the player later visits the affected location.

Entity location is mutable state. The global snapshot contains every actor; the location-scoped UI snapshot filters entities only after state-backed locations have been applied.

## Current Boundary

The Lake Town slice now proves a small reusable life loop:

- hunger increases with elapsed time;
- a food buyer can leave duty and move to a supplier;
- an open supplier can complete a real stock-and-coin exchange;
- a closed supplier causes a request for help;
- player help changes the NPC's need and next decision;
- the NPC returns to duty after eating or after an unsuccessful search;
- movement, trade, and requests leave memories, traces, rumors, and facts.

This is initial local emergence, not a fully emergent game. Hunger is the only time-driven need profile, the fixture has one active food buyer, and locations, routes, clue gates, Lu Huai's investigation, archive access, and Mist Salt Well outcomes remain authored.

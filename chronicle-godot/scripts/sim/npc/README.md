# NPC Autonomous Decision System

`V5NpcDecisionSystem` runs during a world tick after deferred and due settlements. It evaluates every matching actor in a global world snapshot, selects at most one action per actor, and writes the result through `V5TransactionWorldWriter`.

The UI still uses a location-scoped snapshot. Global simulation and local projection therefore remain separate.

## Rule Shape

Rules live in `data/sim/raw/npc_action_rules/` and contain:

- `actor`: reusable type, tag, and state filters.
- `bindings`: references read from the matched actor, such as a dependent, workplace, notice, or door.
- `requirements`: hard eligibility conditions.
- `utility_factors`: weighted conditions that explain why an action became preferable.
- `minimum_utility`: the score required before the actor acts.
- `once_fact_type`: an actor-scoped fact that prevents duplicate execution.
- `effects`: facts, state changes, relationship changes, pressures, and player-facing narrative.

The system groups eligible actions by actor. Highest utility wins; priority and rule ID provide deterministic tie-breaking. Randomness is not required for emergence and should not replace causal state.

## Observation Boundary

All autonomous actions enter the global world log. An action is immediately visible to the player only when the actor and player were at the same location during the tick. Unobserved facts stay in the simulation but are excluded from the current knowledge panel. Later systems should reveal them through traces, rumors, witnesses, or return visits.

## Current Boundary

This system currently proves one reusable household-merchant loop. It does not make the full vertical slice emergent. Travel discovery, the Lu Huai investigation chain, archive access, and the Mist Salt Well progression still contain authored gates and outcomes.

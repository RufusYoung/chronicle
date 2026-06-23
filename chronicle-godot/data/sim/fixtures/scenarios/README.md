# Sim Scenario Fixtures

Scenario fixtures are test-only continuous action scripts.

They are not location button tables.
They do not store final UI labels.
They only describe how a test runner should select generated action candidates from Sim Core rules.

Each step stores selection conditions such as:

```json
{
  "step_id": "give_food_to_chen_mi",
  "select": {
    "rule_id": "give_food_to_hungry_person",
    "target_id": "chen_mi"
  }
}
```

The runner must still use `ActionAffordanceSystem.generate_candidates()` before selecting a candidate.

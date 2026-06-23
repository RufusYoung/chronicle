# 2026-06-23 Transaction Contract + Legacy Resolver Cleanup 报告

## 1. 本次目标

本次目标是收口 raw action rule 的事务契约，让每条 action rule 显式声明自己的事务模式。

完成后的链路是：

```text
Raw Rule transaction_mode
-> ActionCandidate transaction_mode + effect_template_id
-> TransactionResolver 按契约执行
-> TransactionResult 记录 contract_status
-> SimRunner / SimWorldLog 记录和统计契约状态
```

## 2. Raw Rule transaction_mode

已为所有 raw action rules 增加 `transaction_mode`。

当前只允许两种模式：

- `effect_template`
- `candidate_only`

`effect_template` 规则必须绑定非空 `effect_template_id`，并且该模板必须存在于 `basic_effect_templates.json`。

`candidate_only` 是显式事务模式，不是错误。它表示该规则当前只生成候选动作，执行时不写入 Fact / State / Relationship / Memory / Trace / Rumor。

## 3. ActionCandidate 事务契约字段

已修改：

- `chronicle-godot/scripts/sim/action/action_candidate.gd`
- `chronicle-godot/scripts/sim/action/action_affordance_system.gd`

`ActionCandidate` 现在携带：

- `transaction_mode`
- `effect_template_id`

`to_dict()` 也会输出这两个字段。

如果 raw rule 缺少 `transaction_mode`，候选动作不会被静默填成默认值；后续契约校验会把它视为 raw rule 契约错误。

## 4. RawRuleContractValidator

新增：

```text
chronicle-godot/scripts/sim/action/raw_rule_contract_validator.gd
```

校验内容：

1. 每条 rule 必须有 `transaction_mode`。
2. `transaction_mode` 只能是 `effect_template` 或 `candidate_only`。
3. `effect_template` 模式必须有非空 `effect_template_id`。
4. `effect_template_id` 必须存在于 effect templates。
5. `candidate_only` 模式必须没有 `effect_template_id`。
6. `candidate_only` 会产生 warning，但不会让校验失败。

该 validator 不检查具体人物、地点或场景状态。

## 5. TransactionResolver 按契约执行

已修改：

```text
chronicle-godot/scripts/sim/transaction/transaction_resolver.gd
```

现在执行逻辑为：

- `transaction_mode == "effect_template"`：要求 `effect_template_id` 非空且存在，然后调用 `EffectTemplateResolver`。
- `transaction_mode == "candidate_only"`：返回明确的空事务结果，`contract_status = "candidate_only"`。
- 缺少 `transaction_mode`、非法模式、缺少模板 ID、未知模板 ID：返回 `contract_status = "invalid_contract"`。

`TransactionResolver` 不再依赖 `rule_id` 猜 effect template。

## 6. Candidate-only 行为

`candidate_only` 的结果是明确的空事务结果：

```text
contract_status = "candidate_only"
skip_reason = "candidate_only_rule"
```

它不会写入：

- facts
- state_changes
- relationship_changes
- memories
- traces
- rumors
- narrative_result

因此，空写回规则不会像“执行失败”一样崩溃，也不会被误认为缺配置。

## 7. Legacy fallback 清理情况

已从 `TransactionResolver` 删除 `_legacy_effect_template_for_rule()`。

新测试验证了：`transaction_mode = "effect_template"` 但缺少 `effect_template_id` 时，会返回 `invalid_contract`，不会靠旧的 `rule_id -> effect_template_id` 映射成功。

新增 alias 规则 `test_inquiry_concealed_item_alias` 仍然可以不改 resolver 成功执行，因为它通过 raw rule 明确绑定了 `effect_template_id`。

## 8. WorldLog 契约状态记录

已修改：

- `chronicle-godot/scripts/sim/core/sim_runner.gd`
- `chronicle-godot/scripts/sim/core/sim_world_log.gd`

WorldLog entry 新增：

- `transaction_mode`
- `contract_status`
- `skip_reason`
- `error_reason`

WorldLog summary 新增统计：

- `resolved_count`
- `candidate_only_count`
- `invalid_contract_count`

## 9. 测试结果

新增测试：

```text
Godot_v4.6.3-stable_win64_console.exe --headless --check-only --path . --script res://tests/sim/transaction_contract_cleanup_test.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/sim/transaction_contract_cleanup_test.gd --quit-after 200
```

结果：

```text
[V5 TRANSACTION CONTRACT CLEANUP RESULT] PASS
```

回归测试均通过：

- `[V5 RAW RULE PROTOTYPE RESULT] PASS`
- `[V5 TRANSACTION STATE MEMORY RESULT] PASS`
- `[V5 RELATIONSHIP TRACE RUMOR NARRATIVE RESULT] PASS`
- `[V5 SIM RUNNER WORLD LOG RESULT] PASS`
- `[V5 SIM SNAPSHOT CANDIDATE CONTEXT RESULT] PASS`
- `[V5 SNAPSHOT TRANSACTION EFFECT TEMPLATE RESULT] PASS`
- `[V5 RAW RULE EFFECT BINDING RESULT] PASS`

## 10. Sim Core 独立规则执行情况

本次仍保持 Sim Core 独立：

```text
Raw Action Rule
-> ActionCandidate
-> TransactionResolver
-> EffectTemplateResolver / TransactionResult
-> TransactionWorldWriter
-> Stores
-> SimRunner WorldLog
```

UI 不参与事务决策。Godot 场景树不持有世界状态。世界状态仍保存在 sim stores 中。

## 11. 未修改保护文件确认

本次未修改：

- `chronicle-godot/scenes/ui/story_player.gd`
- `chronicle-godot/scripts/gen/world_generation_v03.gd`
- `chronicle-godot/scenes/ui/mainui.tscn`
- `chronicle-godot/project.godot`
- `chronicle-godot/素材包/`
- `chronicle-godot/scripts/rebuild/`
- `chronicle-godot/scenes/rebuild/`
- `chronicle-godot/data/rebuild/`

本次未接 UI。
本次未实现完整世界 Tick。
本次未实现完整传闻传播。
本次未实现 AI 文本。
本次未实现湖湾镇完整闭环。
本次未实现第七哨站长期项目。
本次未把世界对象做成 Godot Node。
本次未把世界状态写入 Godot 场景树。

## 12. 未完成内容

本次没有为 `candidate_only` 规则补 effect template。

以下规则仍是显式候选型规则：

- `approach_visible_person`
- `ask_about_food_pressure_at_market`
- `confirm_ration_record_with_cook`
- `trade_watch_duty_for_silence`
- `delay_military_issue_until_after_patrol`
- `hear_rumor_seed`
- `request_favor_from_indebted_person`

本次没有实现完整世界 Tick、完整传闻传播、AI 文本、湖湾镇完整闭环、第七哨站长期项目，也没有把世界对象迁移成 Godot Node。

## 13. 下一步建议

下一步可以分批为 `candidate_only` 规则补充 effect template。

建议优先处理：

- `hear_rumor_seed`
- `request_favor_from_indebted_person`
- `ask_about_food_pressure_at_market`

每新增一个 effect template，都应通过 raw rule 的 `transaction_mode: "effect_template"` 和 `effect_template_id` 绑定，并继续用 contract validator 保证规则契约完整。

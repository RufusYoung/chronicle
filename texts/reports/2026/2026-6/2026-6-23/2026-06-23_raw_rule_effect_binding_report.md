# 2026-06-23 Raw Rule Effect Binding 报告

## 1. 本次目标

本次目标是把 `rule_id -> effect_template_id` 的主要绑定关系从 `TransactionResolver` 前移到 Raw Action Rule 数据层。

完成后，一条 raw action rule 只要声明了 `effect_template_id`，生成出的 `ActionCandidate` 就会携带该字段，`TransactionResolver` 会优先读取候选动作上的 `effect_template_id` 来执行事务模板。

## 2. Raw Action Rule 绑定 effect_template_id

已在 `chronicle-godot/data/sim/raw/action_rules/basic_action_rules.json` 中为以下规则补充绑定：

- `give_food_to_hungry_person` -> `give_food_help_effect`
- `ask_about_concealed_item` -> `inquiry_concealed_item_effect`
- `read_visible_readable_object` -> `read_object_effect`
- `inspect_visible_trace` -> `inspect_trace_effect`

已在 `chronicle-godot/data/sim/raw/action_rules/domain_action_rules.json` 中为以下规则补充绑定：

- `report_discipline_violation_to_superior` -> `discipline_report_effect`
- `conceal_discipline_violation_once` -> `discipline_conceal_effect`

当前没有事务写回模板的 domain 规则已显式设置为 `effect_template_id: null`，包括：

- `ask_about_food_pressure_at_market`
- `confirm_ration_record_with_cook`
- `trade_watch_duty_for_silence`
- `delay_military_issue_until_after_patrol`
- `hear_rumor_seed`
- `request_favor_from_indebted_person`

## 3. ActionCandidate 携带 effect_template_id

已修改 `chronicle-godot/scripts/sim/action/action_candidate.gd`：

- 新增 `effect_template_id` 字段。
- `_init(data)` 会读取 `effect_template_id`。
- `to_dict()` 会输出 `effect_template_id`。
- `null` 会被规整为空字符串。

已修改 `chronicle-godot/scripts/sim/action/action_affordance_system.gd`：

- `_build_candidate()` 会把 raw rule 中的 `effect_template_id` 传入 `ActionCandidate`。
- raw rule 中为 `null` 的规则会生成空 `effect_template_id`，不会生成字符串 `"null"`。

## 4. TransactionResolver 改造

已修改 `chronicle-godot/scripts/sim/transaction/transaction_resolver.gd`：

- `resolve_action()` 优先读取 `candidate.effect_template_id`。
- 如果候选动作没有 `effect_template_id`，才回退到旧的 `rule_id -> effect_template_id` 映射。
- 旧映射函数已重命名为 `_legacy_effect_template_for_rule()`，只作为过渡兼容 fallback。

这意味着新增规则可以通过 raw rule 绑定已有 effect template 执行事务，不需要修改 `TransactionResolver`。

## 5. Test Rule 验证

新增 `chronicle-godot/data/sim/raw/action_rules/test_action_rules.json`。

其中包含测试规则：

- `test_inquiry_concealed_item_alias`
- `effect_template_id`: `inquiry_concealed_item_effect`
- 目标条件与 `ask_about_concealed_item` 一致：可见人物，并且 state 中存在 `concealment`。

测试证明该 alias 规则没有加入 `TransactionResolver` 的 legacy 映射，仍然可以通过 raw rule 绑定执行事务，产生：

- `actor_asked_about_concealed_item` fact
- `being_questioned_about_hidden_item` memory
- `recruit_elai -> player fear +5`

## 6. 测试结果

新增测试：

```text
Godot_v4.6.3-stable_win64_console.exe --headless --check-only --path . --script res://tests/sim/raw_rule_effect_binding_test.gd
```

通过。

```text
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/sim/raw_rule_effect_binding_test.gd --quit-after 200
```

输出：

```text
[V5 RAW RULE EFFECT BINDING RESULT] PASS
```

回归测试均通过：

- `raw_rule_prototype_test.gd`
- `transaction_state_memory_test.gd`
- `relationship_trace_rumor_narrative_test.gd`
- `sim_runner_world_log_test.gd`
- `sim_snapshot_candidate_context_test.gd`
- `snapshot_transaction_effect_template_test.gd`

## 7. Sim Core 独立规则执行情况

本次验证的是 Sim Core 内部的 raw rule 独立执行路径：

1. `SimRegistry` 加载 raw action rules。
2. `ActionAffordanceSystem` 基于 context 或 snapshot 生成 `ActionCandidate`。
3. `ActionCandidate` 携带 `effect_template_id`。
4. `TransactionResolver` 读取 `candidate.effect_template_id`。
5. `EffectTemplateResolver` 执行对应 effect template。

新增规则 `test_inquiry_concealed_item_alias` 证明：只要 raw rule 绑定了已有 effect template，就可以执行事务，不需要修改事务解析器代码。

## 8. 未修改保护文件确认

本次未修改以下保护范围：

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

## 9. 未完成内容

`TransactionResolver` 仍保留 `_legacy_effect_template_for_rule()` 作为过渡 fallback。它现在只用于兼容旧候选动作或临时构造的候选动作。

后续当所有候选动作都稳定从 raw rule 携带 `effect_template_id` 后，可以删除该 legacy fallback。

本次没有为 `effect_template_id: null` 的规则补充新事务模板，因此这些规则仍然是“可生成候选，但不会产生事务写回”的规则。

## 10. 下一步建议

下一步可以把还没有写回的 raw rules 分批接入 effect templates，例如：

- `hear_rumor_seed`
- `request_favor_from_indebted_person`
- `ask_about_food_pressure_at_market`
- `confirm_ration_record_with_cook`

每新增一个 effect template，都应优先通过 raw rule 的 `effect_template_id` 绑定，并增加类似 alias 的测试，避免继续扩大 `TransactionResolver` 的 legacy 映射。

# 2026-06-23 Candidate-only Effect Template Batch 1 报告

## 1. 本次目标

本次目标是把三条已经具备后续世界意义的 `candidate_only` 规则升级为可写回事务规则：

- `hear_rumor_seed`
- `request_favor_from_indebted_person`
- `ask_about_food_pressure_at_market`

本次没有把所有 `candidate_only` 规则都升级为写回规则。

## 2. 新增 Effect Templates

已在 `chronicle-godot/data/sim/raw/effect_templates/basic_effect_templates.json` 新增：

- `hear_rumor_effect`
- `request_favor_effect`
- `ask_market_pressure_effect`

这些模板都通过现有 `EffectTemplateResolver` 执行。本次确认 `{actor_id}`、`{target_id}`、`{location_id}`、`{rule_id}` 等变量已经受支持，因此未修改 resolver。

## 3. Raw Rule transaction_mode 更新

已在 `chronicle-godot/data/sim/raw/action_rules/domain_action_rules.json` 更新：

- `hear_rumor_seed`: `transaction_mode = effect_template`, `effect_template_id = hear_rumor_effect`
- `request_favor_from_indebted_person`: `transaction_mode = effect_template`, `effect_template_id = request_favor_effect`
- `ask_about_food_pressure_at_market`: `transaction_mode = effect_template`, `effect_template_id = ask_market_pressure_effect`

## 4. 三条规则的事务写回

`hear_rumor_seed` 执行后写回：

- Fact: `actor_heard_rumor_seed`
- Memory: `remembers_heard_rumor`
- Narrative result

本次不删除 rumor seed，不实现完整传闻传播，不实现传闻失真或社交网络扩散。

`request_favor_from_indebted_person` 执行后写回：

- Fact: `actor_requested_favor_from_target`
- Relationship: `target -> actor debt -5`
- Memory: `remembers_favor_requested`
- Narrative result

本次不判断请求是否成功，只记录请求已经发生，并轻微消耗人情债。

`ask_about_food_pressure_at_market` 执行后写回：

- Fact: `actor_asked_about_market_pressure`
- Memory: `learned_market_pressure`
- Narrative result

本次不实现完整经济系统，不生成新粮价，不改变市场价格。

## 5. 保持 candidate_only 的规则

以下规则仍保持 `candidate_only`：

- `approach_visible_person`
- `confirm_ration_record_with_cook`
- `trade_watch_duty_for_silence`
- `delay_military_issue_until_after_patrol`

`approach_visible_person` 仍可保持 `candidate_only`，因为它更像交互入口，不一定应该写入世界历史。

`confirm_ration_record_with_cook`、`trade_watch_duty_for_silence`、`delay_military_issue_until_after_patrol` 暂不处理，因为它们需要更完整的军纪、交换和时间压力设计。

## 6. 测试结果

新增测试：

```text
Godot_v4.6.3-stable_win64_console.exe --headless --check-only --path . --script res://tests/sim/candidate_effect_template_batch1_test.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/sim/candidate_effect_template_batch1_test.gd --quit-after 200
```

结果：

```text
[V5 CANDIDATE EFFECT TEMPLATE BATCH1 RESULT] PASS
```

回归测试均通过：

- `[V5 RAW RULE PROTOTYPE RESULT] PASS`
- `[V5 TRANSACTION STATE MEMORY RESULT] PASS`
- `[V5 RELATIONSHIP TRACE RUMOR NARRATIVE RESULT] PASS`
- `[V5 SIM RUNNER WORLD LOG RESULT] PASS`
- `[V5 SIM SNAPSHOT CANDIDATE CONTEXT RESULT] PASS`
- `[V5 SNAPSHOT TRANSACTION EFFECT TEMPLATE RESULT] PASS`
- `[V5 RAW RULE EFFECT BINDING RESULT] PASS`
- `[V5 TRANSACTION CONTRACT CLEANUP RESULT] PASS`

## 7. Sim Core 独立规则执行情况

本次仍保持 Sim Core 独立：

```text
Raw Action Rule
-> effect_template_id
-> EffectTemplateResolver
-> TransactionResult
-> TransactionWorldWriter
-> Stores
```

三条规则均通过 raw rule 绑定执行，没有修改 `TransactionResolver`，也没有新增 `rule_id` 特判。

本次未新增 scenario 文件。测试直接使用现有湖湾镇与第七哨站 fixture / sequence 的自然链路：

- 先通过 report 事务生成 rumor seed，再测试 `hear_rumor_seed`。
- 先通过 conceal 事务生成 debt，再测试 `request_favor_from_indebted_person`。
- 直接用湖湾镇粮食压力 fixture 测试 `ask_about_food_pressure_at_market`。

## 8. 未修改保护文件确认

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

## 9. 未完成内容

本次没有升级全部 `candidate_only` 规则。

暂未处理：

- `approach_visible_person`
- `confirm_ration_record_with_cook`
- `trade_watch_duty_for_silence`
- `delay_military_issue_until_after_patrol`

本次没有实现完整传闻传播、完整经济系统、请求成功判定、湖湾镇完整闭环或第七哨站长期项目。

## 10. 下一步建议

下一步可以继续分批处理剩余 candidate-only 规则。

建议先设计第七哨站的军纪与时间压力，再决定：

- `confirm_ration_record_with_cook`
- `trade_watch_duty_for_silence`
- `delay_military_issue_until_after_patrol`

这些规则应先明确世界后果，再绑定 effect template。

# 2026-06-24 Tick Event Schema + Scoped Tick Result 报告

## 1. 本次目标

本次目标是把上一轮 Mini World Tick Adapter 的输入和输出先规范下来。

本次定义的是 `tick_event` 输入契约，不是完整世界 Tick。本次只按 `trigger_key + scope` 触发 pending deferred consequence，并返回可审计的 TickResult。

本次没有做完整时间推进，没有扫描全世界，没有自动结算所有 obligation / exchange，也没有接 UI。

## 2. TickEventSchema

新增：

```text
chronicle-godot/scripts/sim/world_tick/tick_event_schema.gd
```

`TickEventSchema` 提供：

```text
normalize(event)
validate(event)
```

返回结构为：

```gdscript
{
	"ok": true,
	"errors": [],
	"warnings": [],
	"event": normalized_event
}
```

校验失败不会崩溃，adapter 会返回：

```text
success = false
error_reason = "invalid_tick_event"
```

## 3. Tick Event 标准字段

本次标准字段为：

- `tick_event_id`：必填。
- `tick_type`：必填，允许 `time_event`、`manual_event`、`test_event`。
- `trigger_key`：必填。
- `scope_type`：必填，允许 `location`、`institution`、`region`、`global`。
- `scope_id`：非 `global` 时必填。
- `day`：可选。
- `time_key`：可选。
- `source`：可选。
- `label`：可选。
- `max_triggers`：可选，默认 0，表示不限制。

`max_triggers < 0` 会校验失败。

## 4. Deferred Consequence Scope

`delay_issue_until_after_patrol_effect` 生成的 deferred consequence 现在包含：

```text
deferred_id
trigger_key
status
source_fact_type
scope_type
scope_id
```

当前第一版使用 location scope：

```text
scope_type = "location"
scope_id = "{location_id}"
```

`DeferredConsequenceStore` 新增：

```text
find_pending_by_trigger_and_scope(trigger_key, scope_type, scope_id)
```

本次定义：`global` tick 匹配所有 scope；非 `global` tick 只匹配相同 `scope_type + scope_id` 的 pending consequence。

## 5. WorldTickAdapter Scope 过滤

`WorldTickAdapter` 现在执行流程为：

```text
TickEventSchema.normalize / validate
-> find pending by trigger_key + scope
-> apply max_triggers
-> ConsequenceTriggerSystem.trigger_deferred(deferred_id)
-> TransactionWorldWriter.apply_result()
-> build TickResult
-> write WorldLog tick_event entry
```

本次不再由 adapter 直接调用 `trigger_deferred_by_key()` 全量触发同名 trigger。adapter 会先过滤 scope，再逐条调用 `trigger_deferred()`。

## 6. TickResult 结构

TickResult 至少包含：

```gdscript
{
	"success": true,
	"tick_event_id": "...",
	"tick_type": "...",
	"trigger_key": "...",
	"scope_type": "...",
	"scope_id": "...",
	"source": "...",
	"max_triggers": 0,
	"matched_count": 0,
	"triggered_count": 0,
	"skipped_count": 0,
	"skipped_due_to_scope_count": 0,
	"skipped_due_to_status_count": 0,
	"skipped_due_to_limit_count": 0,
	"error_reason": "",
	"results": [],
	"world_log_entries": [],
	"world_log_summary": {},
	"store_summary": {}
}
```

`matched_count` 表示符合 `trigger_key + scope + pending` 的数量。`triggered_count` 表示实际触发数量。`skipped_due_to_limit_count` 表示因 `max_triggers` 截断而未触发的数量。

## 7. WorldLog Scoped Tick Summary

`SimWorldLog.summary()` 现在支持：

- `tick_event_count`
- `scoped_tick_event_count`
- `failed_tick_event_count`
- `triggered_deferred_count`
- `skipped_deferred_count`

并新增可选查询接口：

```text
find_entries_by_tick_event_id(tick_event_id)
find_tick_entries_by_scope(scope_type, scope_id)
```

`WorldTickAdapter` 写入的是聚合型 `tick_event` entry，一条 tick event 对应一条日志 entry。entry 会记录 scope、matched、triggered、skipped、limit 和 error reason。

## 8. 测试结果

新增测试：

```text
chronicle-godot/tests/sim/tick_event_schema_scoped_result_test.gd
```

已执行并通过：

- `tick_event_schema_scoped_result_test.gd` check-only：PASS
- `tick_event_schema_scoped_result_test.gd` headless run：PASS
- 输出包含 `[V5 TICK EVENT SCHEMA SCOPED RESULT] PASS`

完整回归已执行并全部 PASS：

- `raw_rule_prototype_test.gd`
- `transaction_state_memory_test.gd`
- `relationship_trace_rumor_narrative_test.gd`
- `sim_runner_world_log_test.gd`
- `sim_snapshot_candidate_context_test.gd`
- `snapshot_transaction_effect_template_test.gd`
- `raw_rule_effect_binding_test.gd`
- `transaction_contract_cleanup_test.gd`
- `candidate_effect_template_batch1_test.gd`
- `domain_pressure_deferred_foundation_test.gd`
- `consequence_trigger_settlement_test.gd`
- `mini_world_tick_adapter_test.gd`

最终回归输出包含：

```text
ALL_REGRESSIONS_PASS
```

## 9. Sim Core 独立规则执行情况

本次仍保持 Sim Core 独立：

- `TickEventSchema` 是输入契约，不依赖 UI。
- `WorldTickAdapter` 不依赖 Godot Node。
- `ConsequenceTriggerSystem` 仍只读 `SimSnapshot`。
- Store 写回仍由 `TransactionWorldWriter` 完成。
- `SimWorldLog` 只记录结构化 entry 和 summary。
- `RawRuleContractValidator` 仍保持 PASS。

本次未把世界对象做成 Godot Node。本次未把世界状态写入 Godot 场景树。

## 10. 未修改保护文件确认

本次未修改：

- `chronicle-godot/scenes/ui/story_player.gd`
- `chronicle-godot/scripts/gen/world_generation_v03.gd`
- `chronicle-godot/scenes/ui/mainui.tscn`
- `chronicle-godot/project.godot`
- `chronicle-godot/素材包/`
- `chronicle-godot/scripts/rebuild/`
- `chronicle-godot/scenes/rebuild/`
- `chronicle-godot/data/rebuild/`

本次未接 UI。本次未修改 Godot 场景树。本次未把世界状态写入 Godot scene tree。

## 11. 未完成内容

本次未实现完整世界 Tick。
本次未实现 NPC 自主行动。
本次未实现全地图 tick。
本次未实现完整日程系统。
本次未实现自动结算所有 obligation / exchange。
本次未实现完整传闻传播。
本次未实现 AI 文本。
本次未实现湖湾镇完整闭环。
本次未实现第七哨站长期项目。
本次未把世界对象做成 Godot Node。
本次未把世界状态写入 Godot 场景树。

本次没有做完整时间推进。本次只按 `trigger_key + scope` 触发 pending deferred consequence。

## 12. 下一步建议

下一步可以继续保持 Sim Core 独立，把 `tick_event` 输入模型接到更明确的小范围 location tick：

- 为 `tick_event` 增加更严格的来源与时间字段约定。
- 为 obligation / exchange 增加到期触发测试，但仍不自动结算全部记录。
- 给 region / institution scope 增加第一批真实 fixture。
- 继续扩展 WorldLog 审计字段，让 tick 输入、跳过原因、写回结果都能被报告稳定复盘。

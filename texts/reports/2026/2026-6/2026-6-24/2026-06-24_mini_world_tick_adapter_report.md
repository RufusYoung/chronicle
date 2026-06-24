# 2026-06-24 Mini World Tick Adapter 报告

## 1. 本次目标

本次目标是在 V5 Sim Core 现有的 deferred consequence、pressure、transaction 写回链路之上，补一个最小可用的世界 Tick 适配层。

本次只是 `tick_event` adapter，不是完整世界 Tick。它接收一个明确的 `tick_event`，读取其中的 `trigger_key`，只触发与该 `trigger_key` 匹配的 pending deferred consequence，然后把产生的 `TransactionResult` 写回 Store，并记录到 `SimWorldLog`。

核心链路为：

```text
tick_event
-> WorldTickAdapter
-> SimSnapshot
-> ConsequenceTriggerSystem.trigger_deferred_by_key()
-> TransactionResult
-> TransactionWorldWriter
-> Stores
-> SimWorldLog tick_event entry
```

## 2. WorldTickAdapter

新增文件：

```text
chronicle-godot/scripts/sim/world_tick/world_tick_adapter.gd
```

`WorldTickAdapter` 提供最小接口：

```text
apply_tick_event(context, stores, tick_event)
```

它负责：

- 校验 `deferred_consequence_store` 是否存在。
- 从 `tick_event` 中读取 `tick_event_id` 与 `trigger_key`。
- 使用 `SimSnapshotBuilder` 构造只读快照。
- 调用 `ConsequenceTriggerSystem.trigger_deferred_by_key(snapshot, trigger_key)`。
- 使用 `TransactionWorldWriter.apply_result(result, stores)` 写回结果。
- 为每个触发结果写入一条 `SimWorldLog` tick entry。
- 返回本次 tick adapter 执行摘要。

缺少 `deferred_consequence_store` 时返回失败结果，不崩溃。缺少 `trigger_key` 时返回失败结果，不执行触发。

## 3. Tick Event 结构

本次测试使用的最小 `tick_event` 结构为：

```gdscript
{
	"tick_event_id": "tick_after_patrol",
	"trigger_key": "after_patrol"
}
```

本次只触发指定 `trigger_key` 的 pending deferred consequence。未匹配的 `trigger_key` 不会触发任何后果，也不会改写已有 pending consequence。

本次没有自动推进时间，没有自动扫描全地图，也没有自动结算所有 obligation / exchange。

## 4. Deferred Consequence 触发链路

新增测试通过真实 Sim Core 链路构造 pending deferred consequence：

```text
ActionAffordanceSystem
-> delay_military_issue_until_after_patrol
-> TransactionResolver
-> TransactionWorldWriter
-> DeferredConsequenceStore pending
```

随后 `WorldTickAdapter` 接收 `trigger_key = "after_patrol"` 的 `tick_event`，调用 `ConsequenceTriggerSystem.trigger_deferred_by_key()`，产生 deferred consequence 触发结果，再由 `TransactionWorldWriter` 写回。

测试确认：

- `after_patrol` 会触发匹配的 pending deferred consequence。
- 触发后会写入 `deferred_consequence_triggered` fact。
- 触发后 deferred consequence 状态变为 `triggered`。
- 触发后会写入对应 pressure change。
- 同一个 `trigger_key` 第二次执行不会重复触发已经 triggered 的记录。
- 不匹配的 `trigger_key` 不会触发 pending deferred consequence。

## 5. WorldLog Tick Entry

`SimWorldLog` 新增对 `tick_event` entry 的摘要统计：

- `tick_event_count`
- `triggered_deferred_count`

`WorldTickAdapter` 写入的 tick entry 包含：

- `entry_type = "tick_event"`
- `tick_event_id`
- `trigger_key`
- `source = "WorldTickAdapter"`
- `transaction_mode`
- `contract_status`
- `facts_added`
- `fact_ids`
- `pressure_changes`
- `deferred_consequence_updates`
- `deferred_consequence_update_count`
- `obligation_update_count`
- `exchange_update_count`
- `narrative_summary`
- `narrative_result`

这让 tick adapter 的结果可以被 WorldLog 独立审计，而不需要接 UI 或 Godot 场景树。

## 6. 测试结果

新增测试：

```text
chronicle-godot/tests/sim/mini_world_tick_adapter_test.gd
```

已执行并通过：

- `mini_world_tick_adapter_test.gd` check-only：PASS
- `mini_world_tick_adapter_test.gd` headless run：PASS

回归测试已执行并全部 PASS：

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

## 7. Sim Core 独立规则执行情况

本次仍保持 Sim Core 独立：

- `WorldTickAdapter` 不依赖 UI。
- `WorldTickAdapter` 不依赖 Godot Node。
- `ConsequenceTriggerSystem` 只读 `SimSnapshot`。
- 状态写回仍由 `TransactionWorldWriter` 完成。
- `SimWorldLog` 只记录结构化 entry 与 summary。
- `RawRuleContractValidator` 仍在测试中保持 PASS。

本次未把世界对象做成 Godot Node。本次未把世界状态写入 Godot 场景树。

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

本次未接 UI。本次未修改 Godot 场景树。本次未把世界状态写入 Godot scene tree。

## 9. 未完成内容

本次未实现：

- 完整世界 Tick。
- NPC 自主行动。
- 全地图 tick。
- 完整日程系统。
- 完整传闻传播。
- AI 文本。
- 湖湾镇完整闭环。
- 第七哨站长期项目。
- 自动结算所有 obligation / exchange。
- 自动推进时间。
- 将世界对象做成 Godot Node。
- 将世界状态写入 Godot 场景树。

本次只是 `tick_event` adapter，只触发指定 `trigger_key` 的 pending deferred consequence。

## 10. 下一步建议

下一步可以继续保持 Sim Core 独立，补一个更明确的 world tick 输入模型：

- 增加标准化 `tick_event` 字段，例如时间、地点、来源与事件范围。
- 为 obligation / exchange 增加到期触发测试，但仍先不接 UI。
- 在不自动推进全世界的前提下，做小范围 location tick。
- 继续扩展 WorldLog，让 tick adapter 的输入、输出、写回数量都能被报告审计。

等这些结构稳定后，再考虑 UI 展示、时间系统和更完整的湖湾镇闭环。

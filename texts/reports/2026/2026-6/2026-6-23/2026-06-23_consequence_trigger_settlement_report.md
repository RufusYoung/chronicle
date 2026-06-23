# 2026-06-23 Consequence Trigger + Settlement Prototype 报告

## 1. 本次目标

本次目标是在上一轮 pressure / obligation / exchange / deferred consequence 记录结构之上，补一个最小手动触发与结算原型。

目标链路是：

```text
SimSnapshot
-> ConsequenceTriggerSystem
-> TransactionResult
-> TransactionWorldWriter
-> Stores
-> WorldLog
```

本次只证明这些结构可以被手动触发、手动结算，并再次写回世界状态。

## 2. Store 状态更新

本次扩展了三个 Store 的状态更新能力：

- `ObligationStore`
  - `apply_obligation_update`
  - `mark_fulfilled`
  - `mark_breached`
  - `find_obligation`
- `ExchangeStore`
  - `apply_exchange_update`
  - `mark_settled`
  - `mark_failed`
  - `find_exchange`
- `DeferredConsequenceStore`
  - `apply_deferred_consequence_update`
  - `mark_triggered`
  - `mark_resolved`
  - `find_deferred_consequence`

找不到对应记录时接口返回 `false`，不会崩溃。`PressureStore` 仍保持记录型 Store，本次没有给 pressure 加 settlement 状态。

## 3. TransactionResult / WorldWriter 更新 atoms

`TransactionResult` 新增：

- `obligation_updates`
- `exchange_updates`
- `deferred_consequence_updates`

`TransactionWorldWriter` 会把这些 update atom 写入对应 Store：

- `obligation_updates` -> `ObligationStore.apply_obligation_update`
- `exchange_updates` -> `ExchangeStore.apply_exchange_update`
- `deferred_consequence_updates` -> `DeferredConsequenceStore.apply_deferred_consequence_update`

Store 缺失时仍然跳过，不报错。

`SimWorldLog` 和 `SimRunner` entry 新增计数：

- `obligation_update_count`
- `exchange_update_count`
- `deferred_consequence_update_count`

## 4. ConsequenceTriggerSystem

新增：

```text
chronicle-godot/scripts/sim/consequence/consequence_trigger_system.gd
```

最小接口：

- `fulfill_obligation(snapshot, obligation_id)`
- `breach_obligation(snapshot, obligation_id)`
- `settle_exchange(snapshot, exchange_id)`
- `trigger_deferred_by_key(snapshot, trigger_key)`
- `trigger_deferred(snapshot, deferred_id)`

`ConsequenceTriggerSystem` 只读 `SimSnapshot`，只返回 `TransactionResult`，不直接写 Store。写回仍由 `TransactionWorldWriter` 完成。

## 5. 四个结算模板

新增 effect templates：

- `obligation_fulfilled_effect`
- `obligation_breached_effect`
- `exchange_settled_effect`
- `deferred_consequence_triggered_effect`

这些模板使用 `EffectTemplateResolver.resolve_template_with_bindings()` 执行，支持直接传入：

- `actor_id`
- `target_id`
- `location_id`
- `rule_id`
- `obligation_id`
- `exchange_id`
- `deferred_id`
- `trigger_key`

## 6. Pressure 对候选优先级的最小影响

`ActionAffordanceSystem` 新增最小 `pressure_priority` 支持。

当规则声明 `pressure_priority`，且输入是包含 pressure 的 `SimSnapshot` 时，系统会计算指定 `scope_id + pressure_type` 的压力值。达到 threshold 后：

- `candidate.priority += priority_delta`
- `candidate.extra.pressure_priority_applied = true`

本次只给 `confirm_ration_record_with_cook` 增加了一条 pressure priority，用于证明 pressure 可以影响候选优先级。pressure 不直接决定事务结果。

## 7. 测试结果

新增测试：

```text
chronicle-godot/tests/sim/consequence_trigger_settlement_test.gd
```

已运行：

- `consequence_trigger_settlement_test.gd` check-only：PASS
- `consequence_trigger_settlement_test.gd`：PASS

回归测试全部 PASS：

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

## 8. Sim Core 独立规则执行情况

本次仍保持 Sim Core 独立：

- 触发器读取 `SimSnapshot`
- 模板解析产生 `TransactionResult`
- `TransactionWorldWriter` 写回 Store
- `SimWorldLog` 记录 update count

没有依赖 UI、Godot Node、scene tree 或 AI 文本。

## 9. 未修改保护文件确认

本次未修改：

- `chronicle-godot/scenes/ui/story_player.gd`
- `chronicle-godot/scripts/gen/world_generation_v03.gd`
- `chronicle-godot/scenes/ui/mainui.tscn`
- `chronicle-godot/project.godot`
- `chronicle-godot/素材包/`
- `chronicle-godot/scripts/rebuild/`
- `chronicle-godot/scenes/rebuild/`
- `chronicle-godot/data/rebuild/`

本次未接 UI。本次未修改 Godot 场景树。本次未把世界对象做成 Godot Node。本次未把世界状态写入 Godot scene tree。

## 10. 未完成内容

本次未实现：

- 完整世界 Tick
- 完整传闻传播
- AI 文本
- 湖湾镇完整闭环
- 第七哨站长期项目
- 自动时间推进
- 自动执行所有 pending consequence
- NPC 自主履行义务
- exchange 公平性判断
- pressure 自动衰减或传播

本次只是手动触发 / 结算原型。

## 11. 下一步建议

下一步可以继续保持 Sim Core 独立，补一个很小的 world tick adapter：

- 输入明确的时间事件或 trigger_key
- 只触发指定范围内的 pending consequence
- 对 obligation / exchange 增加更清晰的记录来源和到期信息
- 在不接 UI 的前提下继续扩大测试切片

等这些数据链路稳定后，再考虑 UI 展示和更完整的时间推进。

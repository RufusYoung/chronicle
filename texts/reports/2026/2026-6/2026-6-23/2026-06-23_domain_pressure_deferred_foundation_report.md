# 2026-06-23 Domain Pressure + Deferred Consequence Foundation 报告

## 1. 本次目标

本次目标是在 v5 Sim Core 中补上领域压力、义务、交换、延后后果四类通用事务结构，让 raw rule 的 effect_template 可以写回这些结构。

本次不接 UI，不改世界 tick，不做 AI 文本，也不把世界对象放进 Godot scene tree。重点是让规则执行后能产生可记录、可查询、可进入 Snapshot 和 WorldLog 的结构化结果。

## 2. 新增 Store

新增四个独立内存 Store：

- `PressureStore`：记录 pressure change，支持按 domain、location 查询，并能按 `scope_id + pressure_type` 汇总压力值。
- `ObligationStore`：记录 obligation，支持按 owner、target 查询，以及查询 open obligations。
- `ExchangeStore`：记录 exchange，支持按参与者查询，以及查询 open exchanges。
- `DeferredConsequenceStore`：记录 deferred consequence，支持查询 pending consequences 和 trigger_key。

这些 Store 只负责保存和查询，不自动衰减压力，不履行义务，不结算交换，也不触发延后后果。

## 3. 新增 Effect Atoms

`TransactionResult` 新增四类数组：

- `pressure_changes`
- `obligations_added`
- `exchanges_added`
- `deferred_consequences_added`

`EffectTemplateResolver` 新增对应 JSON 字段解析：

- `pressure_changes`
- `obligations`
- `exchanges`
- `deferred_consequences`

`TransactionWorldWriter` 会把这些 atom 写入可选 Store。缺少对应 Store 时不会报错，保持原有 Sim Core 的轻量组合方式。

## 4. 三条军纪规则的事务写回

本次把三条原先只生成候选的军纪规则绑定到 effect_template：

- `confirm_ration_record_with_cook` -> `confirm_ration_record_effect`
- `trade_watch_duty_for_silence` -> `trade_watch_duty_for_silence_effect`
- `delay_military_issue_until_after_patrol` -> `delay_issue_until_after_patrol_effect`

执行结果：

- 确认口粮记录会写入 `actor_confirmed_ration_record` fact、记录 review trace、写入记忆，并增加 `ration_record_attention` pressure。
- 以值夜换沉默会写入 `actor_traded_watch_duty_for_silence` fact、关系变化、open obligation 和 open exchange。
- 延后军纪问题会写入 `actor_deferred_issue_until_after_patrol` fact、`unresolved_issue` pressure 和 pending deferred consequence。

## 5. Snapshot / Runner / WorldLog 扩展

`SimSnapshot` 现在能携带：

- pressures
- obligations
- exchanges
- deferred_consequences

并提供：

- `get_pressures()`
- `get_open_obligations()`
- `get_open_exchanges()`
- `get_pending_deferred_consequences()`

`SimRunner` 会创建四类新 Store，并在 `store_summary`、`store_snapshots`、`snapshot_summary` 中输出计数和快照。

`SimWorldLog` 现在汇总：

- `pressure_change_count`
- `obligation_count`
- `exchange_count`
- `deferred_consequence_count`

## 6. 测试结果

新增测试：

- `domain_pressure_deferred_foundation_test.gd`

覆盖 18 项：

- 四类 Store 的保存和查询
- TransactionResult 新数组
- TransactionWorldWriter 写入新 Store
- SimSnapshot 读取新 Store
- 三条军纪规则绑定
- confirm / trade / delay 三条规则的实际事务输出
- WorldLog 计数
- RawRuleContractValidator PASS

已运行：

- `domain_pressure_deferred_foundation_test.gd` check-only：PASS
- `domain_pressure_deferred_foundation_test.gd`：PASS

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

## 7. Sim Core 独立规则执行情况

本次 confirm / trade / delay 三条规则已经能在 Sim Core 内独立执行：

- 由 `ActionAffordanceSystem` 生成候选。
- 由 `TransactionResolver` 根据 `effect_template_id` 执行模板。
- 由 `TransactionWorldWriter` 写入 Store。
- 由 `SimSnapshotBuilder` 在后续 Snapshot 中读回。
- 由 `SimWorldLog` 记录新增 atom 数量。

整个过程不依赖 UI 点击、Godot Node、scene tree 或 AI 文本生成。

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

本次没有接 UI，没有修改 Godot 场景树，没有把世界状态写入 Godot scene tree。

## 9. 未完成内容

本次未实现：

- UI 接入
- 完整 world tick
- 完整 rumor propagation
- AI text
- lake closed loop
- seventh outpost long project
- 世界对象 Godot Node 化
- 世界状态写入 Godot scene tree
- obligation fulfillment
- exchange settlement
- deferred consequence trigger
- pressure decay 或压力自动传播

## 10. 下一步建议

下一步可以在保持 Sim Core 独立的前提下，补一个小型触发器层：

- open obligation 的履行或违约
- open exchange 的 settlement
- pending deferred consequence 的 trigger
- pressure 对后续候选生成或规则权重的影响

这些内容应继续保持在数据和 Sim Core 层，等行为稳定后再考虑 UI 展示。

# 2026-06-24 Due Resolution Policy Prototype 报告

## 1. 本次目标

本次目标是在上一轮 `due_status = due` 的基础上，建立一个显式的 due resolution policy 原型。

目标链路是：

```text
due obligation / due exchange
-> DueResolutionPolicy
-> DueResolutionSystem
-> TransactionResult
-> TransactionWorldWriter
-> ObligationStore / ExchangeStore
-> WorldLog summary
```

本次 resolution 来自显式策略输入。

本次不是 NPC 自主履约。

## 2. DueResolutionPolicy

新增：

```text
chronicle-godot/scripts/sim/consequence/due_resolution_policy.gd
```

`DueResolutionPolicy` 负责标准化和校验 decision：

- `resolution_id`
- `target_kind`
- `target_id`
- `resolution`
- `reason`
- `source`
- `resolver_actor_id`
- `tick_event_id`
- `trigger_key`
- `scope_type`
- `scope_id`

合法组合：

- obligation: `fulfilled` / `breached` / `keep_due`
- exchange: `settled` / `failed` / `keep_due`

非法组合会校验失败，例如：

- obligation + settled
- exchange + breached
- 缺少 target_id

## 3. DueResolutionSystem

新增：

```text
chronicle-godot/scripts/sim/consequence/due_resolution_system.gd
```

`DueResolutionSystem` 负责读取 `SimSnapshot` 中已经 due 的 obligation / exchange，并根据显式 decision 生成 `TransactionResult`。

最小接口：

- `resolve_due(snapshot, decision)`
- `resolve_many(snapshot, decisions)`

前置条件：

- decision 必须合法。
- target 必须存在。
- target 的 `status` 必须是 `open`。
- target 的 `due_status` 必须是 `due`。
- resolution 必须匹配 target_kind。

失败时复用现有 `invalid_contract`，并通过 `error_reason` 写明原因，例如：

- `target_not_found`
- `target_not_due`
- `target_not_open`
- `invalid_decision`

`DueResolutionSystem` 不直接写 Store。

## 4. Resolution Effect Templates

更新已有模板：

- `obligation_fulfilled_effect`
- `obligation_breached_effect`
- `exchange_settled_effect`

新增模板：

- `exchange_failed_effect`
- `due_resolution_keep_due_effect`

fulfilled / breached / settled / failed 会写入：

- 主 `status`
- `due_status = "resolved"`
- `resolution_status`
- `resolution_reason`
- `resolved_by`
- `resolved_tick_event_id`
- `resolution_count_delta = 1`

`keep_due` 不改变主 status。

`keep_due` 不改变 due_status。

`keep_due` 只写入 fact 和 resolution 审计字段。

## 5. Store Resolution 字段

`ObligationStore` 和 `ExchangeStore` 的 update merge 现在支持：

- `status`
- `due_status`
- `resolution_status`
- `resolution_reason`
- `resolved_by`
- `resolved_tick_event_id`
- `resolution_count_delta`

当 `resolution_count_delta` 存在时，会累加到 `resolution_count`。

原有 due 字段不会被删除。

## 6. WorldLog Resolution Summary

`SimWorldLog.summary()` 新增 due resolution 汇总字段：

- `due_resolution_count`
- `obligation_fulfilled_count`
- `obligation_breached_count`
- `exchange_settled_count`
- `exchange_failed_count`
- `keep_due_count`

本次没有新增复杂 log writer，只让 WorldLog 可以汇总 `entry_type = "due_resolution"` 的结构化 entry。

## 7. 测试结果

新增测试：

```text
chronicle-godot/tests/sim/due_resolution_policy_test.gd
```

新测试覆盖：

- `DueResolutionPolicy` 合法/非法 decision 校验。
- `trade_watch_duty_for_silence` 生成 obligation / exchange。
- `tick_event include_due_checks=true` 后 obligation / exchange 进入 due。
- fulfilled obligation 生成 `obligation_fulfilled` fact。
- fulfilled 写回 `status = fulfilled` 和 `due_status = resolved`。
- breached obligation 生成 `obligation_breached` fact。
- breached 写回 `status = breached`。
- settled exchange 生成 `exchange_settled` fact。
- settled 写回 `status = settled`。
- failed exchange 生成 `exchange_failed` fact。
- failed 写回 `status = failed`。
- keep_due 不改变主 status。
- 非 due target 不能 resolution。
- 已 fulfilled target 不能再次 resolution。
- `DueResolutionSystem` 不直接写 Store。
- `TransactionWorldWriter` 写回 resolution updates。
- `WorldLog` 汇总 due resolution entry。
- `RawRuleContractValidator` 仍 PASS。

完整回归结果：

```text
[V5 DUE RESOLUTION POLICY RESULT] PASS
[V5 RAW RULE PROTOTYPE RESULT] PASS
[V5 TRANSACTION STATE MEMORY RESULT] PASS
[V5 RELATIONSHIP TRACE RUMOR NARRATIVE RESULT] PASS
[V5 SIM RUNNER WORLD LOG RESULT] PASS
[V5 SIM SNAPSHOT CANDIDATE CONTEXT RESULT] PASS
[V5 SNAPSHOT TRANSACTION EFFECT TEMPLATE RESULT] PASS
[V5 RAW RULE EFFECT BINDING RESULT] PASS
[V5 TRANSACTION CONTRACT CLEANUP RESULT] PASS
[V5 CANDIDATE EFFECT TEMPLATE BATCH1 RESULT] PASS
[V5 DOMAIN PRESSURE DEFERRED FOUNDATION RESULT] PASS
[V5 CONSEQUENCE TRIGGER SETTLEMENT RESULT] PASS
[V5 MINI WORLD TICK ADAPTER RESULT] PASS
[V5 TICK EVENT SCHEMA SCOPED RESULT] PASS
[V5 OBLIGATION EXCHANGE DUE TRIGGER RESULT] PASS
```

终端回归输出包含：

```text
ALL_DUE_RESOLUTION_REGRESSIONS_PASS
```

## 8. Sim Core 独立规则执行情况

本次仍保持 Sim Core 独立：

- `DueResolutionPolicy` 只校验显式策略输入。
- `DueResolutionSystem` 只读取 `SimSnapshot`，只返回 `TransactionResult`。
- 状态写回仍由 `TransactionWorldWriter` 完成。
- Store 只接收 update atom。
- WorldLog 只汇总结构化 entry。

fulfilled / breached / settled / failed 通过 `TransactionResult -> TransactionWorldWriter` 写回。

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

本次未接 UI。

本次未修改 Godot 场景树。

## 10. 未完成内容

本次未接 UI。

本次未实现完整世界 Tick。

本次未实现 NPC 自主行动。

本次未实现全地图 tick。

本次未实现完整日程系统。

本次未实现自动判定所有 due 项。

本次未实现复杂成功率。

本次未实现人格 / 忠诚 / 恐惧驱动的履约判断。

本次未实现完整传闻传播。

本次未实现 AI 文本。

本次未实现湖湾镇完整闭环。

本次未实现第七哨站长期项目。

本次未把世界对象做成 Godot Node。

本次未把世界状态写入 Godot 场景树。

## 11. 下一步建议

下一步可以在 due resolution policy 之上增加一个更小的策略来源层，用于把测试 decision、日程 decision 或未来 NPC decision 统一成同一种 policy 输入。

仍建议先保持显式输入，不要直接做 NPC 自主履约，也不要自动扫描并判定所有 due 项。

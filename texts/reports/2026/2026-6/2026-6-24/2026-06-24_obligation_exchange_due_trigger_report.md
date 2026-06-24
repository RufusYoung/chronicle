# 2026-06-24 Obligation Deadline + Exchange Due Trigger 报告

## 1. 本次目标

本次目标是把 obligation / exchange 的到期状态接入 `tick_event`：当外部或测试传入的 tick 事件带有 `trigger_key` 和 scope 时，Sim Core 可以按 `deadline_key + scope` 找到已经到期但仍然 open 的 obligation / exchange，并生成可审计的 `TransactionResult`。

本次只把 obligation / exchange 的到期状态接入 tick_event。

due 不是 fulfilled，也不是 breached。due 也不是 settled 或 failed。

due 不会改变主 status，主 status 仍保持 open。

## 2. Deadline 与 Scope 字段

`trade_watch_duty_for_silence_effect` 现在会给生成的 obligation 和 exchange 写入：

- `deadline_key = "tonight_watch"`
- `scope_type = "location"`
- `scope_id = "{location_id}"`
- `due_status = "not_due"`
- `due_count = 0`

第一版使用 `deadline_key == tick_event.trigger_key` 做匹配，不做复杂日期比较。

scope 规则沿用 2026-06-24.2：`global` tick 匹配所有 scope；非 global tick 只匹配相同 `scope_type + scope_id`。

## 3. Obligation / Exchange Due 查询

`ObligationStore` 和 `ExchangeStore` 新增了：

- `find_open_due_by_deadline_and_scope(deadline_key, scope_type, scope_id)`
- `mark_due(id, tick_event)`

查询只返回 `status == "open"` 且 `deadline_key` 命中的记录，并按 tick scope 过滤。

已经在同一个 `last_due_trigger_key` 下标记过 `due_status = "due"` 的记录不会重复返回。

`mark_due` 只写入：

- `due_status`
- `last_due_tick_event_id`
- `last_due_trigger_key`
- `due_count`

它不改变 obligation / exchange 的主 `status`。

## 4. Due Effect Templates

新增通用模板：

- `obligation_due_effect`
- `exchange_due_effect`

两个模板都会生成 due fact、attention pressure 和 due update atom。

`obligation_due_effect` 生成 `obligation_due` fact，并写入 obligation update：

- `due_status = "due"`
- `last_due_tick_event_id`
- `last_due_trigger_key`
- `due_count_delta = 1`

`exchange_due_effect` 生成 `exchange_due` fact，并写入 exchange update，字段同上。

两个模板都不会生成 fulfilled / breached / settled / failed 判断。

## 5. DueTriggerSystem

新增 `DueTriggerSystem`，职责是：

- 从 `SimSnapshot` 读取 open obligation / exchange。
- 按 `tick_event.trigger_key + scope` 找到到期项。
- 通过 `EffectTemplateResolver.resolve_template_with_bindings()` 生成 `TransactionResult`。
- 默认使用 `obligation_due_effect` 和 `exchange_due_effect`。
- 如记录中存在 `due_template_id`，优先使用记录自带模板。

`DueTriggerSystem` 不直接写 Store。写回仍由 `TransactionWorldWriter` 完成。

## 6. WorldTickAdapter include_due_checks

`TickEventSchema` 新增可选字段：

- `include_due_checks: bool`，默认 `false`
- `due_kinds: Array`，默认 `["obligation", "exchange"]`

`WorldTickAdapter` 的流程现在是：

1. 校验并标准化 tick_event。
2. 先处理原有 deferred consequence。
3. deferred 写回后重建 snapshot。
4. 只有当 `include_due_checks = true` 时，才调用 `DueTriggerSystem`。
5. due 结果继续通过 `TransactionWorldWriter` 写回 Store。

`include_due_checks = false` 时不会触发 due checks，旧 tick 行为保持不变。

## 7. TickResult / WorldLog Due 字段

`TickResult` 新增：

- `obligation_due_count`
- `exchange_due_count`
- `due_result_count`
- `due_results`

`WorldLog` tick entry 新增：

- `obligation_due_count`
- `exchange_due_count`
- `due_result_count`
- `due_results`

`SimWorldLog.summary()` 也会汇总这些 due count，便于后续报告和调试。

## 8. 测试结果

新增测试：

- `chronicle-godot/tests/sim/obligation_exchange_due_trigger_test.gd`

新测试覆盖：

- Store 按 deadline + scope 查询 due。
- `trade_watch_duty_for_silence` 生成 deadline / scope / due 初始字段。
- `DueTriggerSystem` 生成 `obligation_due` / `exchange_due`。
- `DueTriggerSystem` 不直接写 Store。
- `TransactionWorldWriter` 写回 `due_status` 且不改变主 status。
- `include_due_checks = false` 不触发 due。
- `include_due_checks = true` 触发 obligation / exchange due。
- 不同 scope 不触发。
- global scope 行为沿用 24.2。
- 同 trigger_key 重复 tick 不重复标记已 due 记录。
- `TickResult` / `WorldLog` 记录 due count。
- `RawRuleContractValidator` 仍 PASS。

本次完整回归结果：

```text
[V5 OBLIGATION EXCHANGE DUE TRIGGER RESULT] PASS
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
```

## 9. Sim Core 独立规则执行情况

本次仍保持 Sim Core 独立执行：

- 没有接 UI。
- 没有依赖 Godot 场景树保存世界状态。
- 没有把世界对象改成 Godot Node。
- 所有写回仍通过 Store 和 `TransactionWorldWriter` 完成。
- `DueTriggerSystem` 只消费 `SimSnapshot`，产出 `TransactionResult`。

## 10. 未修改保护文件确认

本次未修改以下保护范围：

- `chronicle-godot/scenes/ui/story_player.gd`
- `chronicle-godot/scripts/gen/world_generation_v03.gd`
- `chronicle-godot/scenes/ui/mainui.tscn`
- `chronicle-godot/project.godot`
- `chronicle-godot/素材包/`
- `chronicle-godot/scripts/rebuild/`
- `chronicle-godot/scenes/rebuild/`
- `chronicle-godot/data/rebuild/`

## 11. 未完成内容

本次未接 UI。

本次未实现完整世界 Tick。

本次未实现 NPC 自主行动。

本次未实现全地图 tick。

本次未实现完整日程系统。

本次未实现自动结算所有 obligation / exchange。

本次未实现 obligation fulfilled / breached 的自动判定。

本次未实现 exchange settled / failed 的自动判定。

本次未实现完整传闻传播。

本次未实现 AI 文本。

本次未实现湖湾镇完整闭环。

本次未实现第七哨站长期项目。

本次未把世界对象做成 Godot Node。

本次未把世界状态写入 Godot 场景树。

## 12. 下一步建议

下一步可以做 fulfilled / breached / settled / failed 的判定层。它应当读取已经 due 的 obligation / exchange，再结合后续行动、NPC 自主行为或日程系统判断是否完成或失败。

另一个可选方向是把 tick_event 的来源从测试输入扩展到轻量日程系统，但仍建议保持 Sim Core 独立，不要先接 UI。

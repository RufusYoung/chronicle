# 2026-06-22 Relationship Metric + Trace / Rumor / Narrative Prototype 报告

## 1. 本次目标

本次任务在 v5 raw rule 与 transaction state memory 原型之后，继续补齐一次事务执行后的关系度量、痕迹、传闻种子与叙事表层结果。

本次目标不是做 UI，也不是做完整世界闭环，而是让 Sim Core 能在纯数据层完成以下链路：

- transaction resolver 根据规则产出 facts / state changes / relationship changes / memories。
- relationship changes 使用明确的 axis metric，而不是只用 1 这种占位增量。
- 某些事务可以额外产出 trace 与 rumor seed。
- transaction result 可以带一个可展示的 narrative_result。
- transaction world writer 可以把结果写入对应 store。

本次未接 UI。
本次未实现完整传闻传播。
本次未实现 AI 文本。
本次未实现湖湾镇完整闭环。
本次未实现第七哨站长期项目。
本次未把世界对象做成 Godot Node。
本次未把世界状态写入 Godot 场景树。

## 2. Relationship Axis Metric

新增关系轴定义文件：

- `chronicle-godot/data/sim/raw/relationship_defs/relationship_axis_defs.json`

当前覆盖的关系轴包括：

- `trust`
- `fear`
- `gratitude`
- `resentment`
- `discipline_respect`
- `familiarity`
- `debt`
- `shame`

`RelationshipStore` 已支持：

- 加载关系轴定义。
- 根据 axis 的 `min_value` / `max_value` clamp 数值。
- 根据阈值返回 tier。
- 在 `set_relation` / `adjust_relation` / `apply_relationship_change` 中统一走 clamp。
- 在没有外部定义时提供 fallback axis defs，保证测试与基础运行稳定。

本次将三个已有事务的关系变化改成明确数值：

- 给陈米食物：`gratitude +15`，`trust +5`，`fear -5`。
- 报告伊莱违纪：伊莱对外部行动者 `resentment +25`，`trust -20`；罗恩对外部行动者 `discipline_respect +15`。
- 替伊莱隐瞒：`gratitude +15`，`trust +15`，`debt +10`。

## 3. Trace Store

新增：

- `chronicle-godot/scripts/sim/trace/trace_store.gd`

`TraceStore` 当前是纯数据 store，支持：

- `add_trace`
- `list_traces`
- `list_traces_by_location`
- `find_traces_by_type`
- `find_traces_by_source_fact`

本次只实现 trace 的保存与查询，不实现地图可视化、场景节点、路径传播或长期衰减。

在第七哨站报告伊莱违纪的事务中，会生成一条 trace：

- `trace_type`: `institutional_record_mark`
- `display_name`: `被折起的口粮记录`
- `source_fact_type`: `actor_reported_discipline_violation`

这代表报告行为在制度记录层留下了痕迹。

## 4. Rumor Store

新增：

- `chronicle-godot/scripts/sim/rumor/rumor_store.gd`

`RumorStore` 当前保存 rumor seed，支持：

- `add_rumor_seed`
- `list_rumors`
- `list_rumors_by_location`
- `find_rumors_by_source_fact`

在报告伊莱违纪的事务中，会生成一条 rumor seed：

- `rumor_id`: `outpost_discipline_report_seed`
- `source_fact_type`: `actor_reported_discipline_violation`
- `spread_scope`: `squad`
- `truth_level`: `high`
- `distortion_level`: `low`

本次只生成传闻种子，不做完整传闻传播、变形、抵达角色、社会网络扩散或长期记忆整合。

## 5. Narrative Surface Adapter

新增：

- `chronicle-godot/scripts/sim/narrative/narrative_surface_adapter.gd`

`NarrativeSurfaceAdapter` 当前根据 `TransactionResult` 与 `SimContext` 生成确定性的 `narrative_result`。它不是 AI 文本生成，只是把事务结果整理成一个可被 UI 或日志层消费的摘要。

当前 narrative result 包括：

- `summary`
- `fact_types`
- `state_change_count`
- `relationship_change_count`
- `memory_count`
- `trace_count`
- `rumor_seed_count`

已覆盖的事务类型包括：

- 给食物。
- 报告违纪。
- 替人隐瞒。
- 阅读对象。
- 检查对象。

例如报告伊莱违纪时，事务结果会包含非空 `narrative_result`，并带有 `actor_reported_discipline_violation` 这一事实类型。

## 6. Transaction World Writer

新增：

- `chronicle-godot/scripts/sim/transaction/transaction_world_writer.gd`

`TransactionWorldWriter` 负责把 `TransactionResult` 写入传入的 store 集合：

- `facts_added` 写入 `FactStore`
- `state_changes` 写入 `StateStore`
- `relationship_changes` 写入 `RelationshipStore`
- `memories_added` 写入 `MemoryStore`
- `traces_added` 写入 `TraceStore`
- `rumors_added` 写入 `RumorStore`

`narrative_result` 不写入世界状态。它是事务表层结果，适合给 UI、debug log 或报告层使用，不属于 Sim Core 的持久世界事实。

## 7. Sim Core 独立规则执行情况

本次实现保持在 Sim Core 数据层：

- 不依赖 Godot 场景树节点来保存世界对象。
- 不把世界状态写入 Godot scene tree。
- 不新增 UI。
- 不新增玩家输入界面。
- 不新增湖湾镇场景闭环。
- 不新增长期项目系统。

事务执行仍然通过 raw action rules、fixture context、resolver、store、writer 这些纯数据对象完成。

这意味着当前原型可以继续作为可测试、可替换、可被 UI 调用的底层模拟层，而不是和具体 Godot 场景耦合。

## 8. 测试结果

新增测试：

- `chronicle-godot/tests/sim/relationship_trace_rumor_narrative_test.gd`

该测试覆盖：

- RelationshipStore 能加载关系轴定义。
- 关系值能按 axis range clamp。
- 关系 tier 能按阈值返回。
- 给陈米食物产生 `gratitude +15`、`trust +5`、`fear -5`。
- 报告伊莱产生 `resentment +25`、`trust -20`、`discipline_respect +15`。
- 替伊莱隐瞒产生 `gratitude +15`、`trust +15`、`debt +10`。
- TraceStore 能保存与查询 trace。
- RumorStore 能保存与查询 rumor seed。
- NarrativeSurfaceAdapter 能生成 summary。
- 报告伊莱时 TransactionResult 包含 trace。
- 报告伊莱时 TransactionResult 包含 rumor seed。
- 报告伊莱时 TransactionResult 包含非空 narrative_result。
- 替伊莱隐瞒时不生成 rumor seed。
- TransactionWorldWriter 能写入 fact / state / relationship / memory / trace / rumor stores。

同时更新了：

- `chronicle-godot/tests/sim/transaction_state_memory_test.gd`

更新原因是关系增量已经从占位值 `1` 改成明确 metric，所以原有断言同步改为新的数值。

本次已运行并通过：

- `relationship_trace_rumor_narrative_test.gd`
- `raw_rule_prototype_test.gd`
- `transaction_state_memory_test.gd`

## 9. 未修改保护文件确认

本次没有修改 Godot UI 场景文件。

本次没有修改：

- `chronicle-godot/scenes/ui/mainui.tscn`
- UI 控件脚本
- 世界场景树结构
- 素材包内容

本次新增与修改集中在：

- `chronicle-godot/data/sim/raw/relationship_defs/`
- `chronicle-godot/scripts/sim/relationship/`
- `chronicle-godot/scripts/sim/trace/`
- `chronicle-godot/scripts/sim/rumor/`
- `chronicle-godot/scripts/sim/narrative/`
- `chronicle-godot/scripts/sim/transaction/`
- `chronicle-godot/tests/sim/`
- `texts/reports/2026/2026-6/2026-6-22/`

## 10. 未完成内容

本次未完成内容如下：

- 未接 UI。
- 未实现完整传闻传播。
- 未实现传闻失真、扩散路径、可信度变化。
- 未实现 AI 文本。
- 未实现湖湾镇完整闭环。
- 未实现第七哨站长期项目。
- 未把世界对象做成 Godot Node。
- 未把世界状态写入 Godot 场景树。
- 未做 trace 的衰减、清理、可视化或交互。
- 未做 relationship axis 的策划平衡。

## 11. 下一步建议

下一步可以继续沿纯数据层推进：

1. 为 rumor seed 增加一次最小传播 step，但仍然保持在 store 与 resolver 层。
2. 为 trace 增加生命周期字段，例如 `created_day`、`decay_rate`、`visibility`。
3. 为 narrative result 增加更稳定的 debug 输出格式，方便 UI 接入前先看事务链路。
4. 在不改 UI 的前提下，增加一个 sim runner，把同一批事务连续跑成小型世界日志。
5. 等 Sim Core 足够稳定后，再让 Godot UI 只读取这些结果，而不是直接持有世界状态。

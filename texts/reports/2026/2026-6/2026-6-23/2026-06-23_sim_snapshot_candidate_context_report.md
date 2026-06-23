# 2026-06-23 Sim Snapshot + Candidate Context Refactor 报告

## 1. 本次目标

本次目标是把候选行动生成从“读取初始 `SimContext`”推进为“读取当前 Stores 组成的 `SimSnapshot`”。

目标链路：

```text
Fixture 初始状态
↓
SimContext
↓
Stores
↓
SimSnapshot
↓
ActionAffordanceSystem
↓
ActionCandidate
↓
Transaction
↓
WorldWriter 写回 Stores
↓
重新生成 SimSnapshot
↓
下一步候选行动读取当前世界状态
```

本次未接 UI。
本次未实现完整世界 Tick。
本次未实现完整传闻传播。
本次未实现 AI 文本。
本次未实现湖湾镇完整闭环。
本次未实现第七哨站长期项目。
本次未把世界对象做成 Godot Node。
本次未把世界状态写入 Godot 场景树。

## 2. SimSnapshot

新增：

```text
chronicle-godot/scripts/sim/core/sim_snapshot.gd
```

`SimSnapshot` 是某一时刻的当前世界读取视图。它不拥有永久世界状态，不写入 Store，也不执行事务。

当前包含：

```text
fixture_id
location
region_state
institution
player
entities
states
relationships
memories
traces
rumors
facts
```

最小读取接口包括：

```text
get_entity
get_entities
get_visible_entities
get_entities_by_type
get_entity_state
get_relation
get_memories
get_visible_traces
get_rumor_seeds
get_facts
get_location_tags
get_region_state_value
get_institution_value
get_player_value
```

## 3. SimSnapshotBuilder

新增：

```text
chronicle-godot/scripts/sim/core/sim_snapshot_builder.gd
```

`SimSnapshotBuilder` 从 `SimContext` 和当前 Stores 构建 snapshot。

构建规则：

```text
1. 从 SimContext 读取 fixture 初始 entities / location / region_state / institution / player。
2. 用 StateStore 覆盖实体当前状态。
3. 用 RelationshipStore 注入当前关系。
4. 用 MemoryStore 注入当前记忆。
5. 用 TraceStore 注入当前痕迹。
6. 用 RumorStore 注入当前传闻种子。
7. 用 FactStore 注入当前事实。
```

如果某个 store 不存在，Builder 使用空数据，不阻断 snapshot 构建。

## 4. ActionAffordanceSystem 改造

修改：

```text
chronicle-godot/scripts/sim/action/action_affordance_system.gd
```

`generate_candidates(input, rules)` 现在可以接受：

```text
SimContext
SimSnapshot
```

旧测试继续传 `SimContext`，仍然通过。新流程传 `SimSnapshot`，候选生成会读取当前 state / relationship / trace / rumor。

本次新增或扩展的匹配能力：

```text
state_in
relationship_any
trace store target
rumor seed target
```

同时更新 raw rule：

```text
give_food_to_hungry_person
```

它现在只在目标 `hunger` 为 `high` 或 `extreme` 时生成。给陈米食物后，`StateStore` 中 `chen_mi.hunger` 变成 `medium`，基于新 snapshot 不再生成给陈米食物候选。

新增 raw rule：

```text
hear_rumor_seed
```

用于证明 `RumorStore` 已经能进入候选生成。报告伊莱后产生 `outpost_discipline_report_seed`，重新构建 snapshot 后，可以生成 `[传闻] 听见小队议论`。

新增 raw rule：

```text
request_favor_from_indebted_person
```

用于证明 `RelationshipStore` 已经能进入候选生成。替伊莱隐瞒后，`recruit_elai -> player debt >= 10`，重新构建 snapshot 后，可以生成 `[关系] 请伊莱帮忙`。

## 5. SimRunner 改造

修改：

```text
chronicle-godot/scripts/sim/core/sim_runner.gd
```

现在每一步执行前都会：

```text
1. 用 SimSnapshotBuilder 从当前 stores 构建 snapshot。
2. 把 snapshot 传给 ActionAffordanceSystem.generate_candidates。
3. 从 candidates 里按 scenario step 选择 action。
4. resolve transaction。
5. TransactionWorldWriter 写入 stores。
6. WorldLog 记录本步。
7. 下一步重新构建 snapshot。
```

`run_sequence` 返回值新增：

```text
candidate_context_source: SimSnapshot
snapshot_summary
```

`snapshot_summary` 至少包含：

```text
final_fact_count
final_trace_count
final_rumor_count
final_relationship_count
final_memory_count
final_candidate_probe
```

旧的 context state sync 仍保留，用于兼容当前 `TransactionResolver`。但候选生成已经优先使用 snapshot。

## 6. Snapshot 参与候选生成的验证

本次验证了四类 store 进入 snapshot 后的效果。

StateStore：

```text
陈米初始 hunger = high
↓
执行 give_food_to_hungry_person
↓
StateStore 中 chen_mi.hunger = medium
↓
重新构建 snapshot
↓
不再生成 give_food_to_hungry_person:chen_mi
```

TraceStore：

```text
报告伊莱
↓
TraceStore 中生成 institutional_record_mark
↓
重新构建 snapshot
↓
生成 inspect_visible_trace:ration_record_marked_for_review
```

RumorStore：

```text
报告伊莱
↓
RumorStore 中生成 outpost_discipline_report_seed
↓
重新构建 snapshot
↓
生成 hear_rumor_seed:outpost_discipline_report_seed
```

RelationshipStore：

```text
替伊莱隐瞒
↓
RelationshipStore 中 recruit_elai -> player debt >= 10
同时 trust / gratitude 也达到 15
↓
重新构建 snapshot
↓
生成 request_favor_from_indebted_person:recruit_elai
```

MemoryStore：

```text
MemoryStore 已纳入 snapshot。
测试确认 snapshot.get_memories("recruit_elai") 可读取 being_protected。
```

MemoryStore 本次尚未参与候选生成。原因是“记忆如何转化为行动候选”需要更细的规则设计，本轮只先把读取通道打通。

## 7. 测试结果

新增测试：

```text
chronicle-godot/tests/sim/sim_snapshot_candidate_context_test.gd
```

测试结果：

```text
[V5 SIM SNAPSHOT CANDIDATE CONTEXT RESULT] PASS
```

该测试覆盖：

```text
1. SimSnapshotBuilder 能从 context + stores 构建 snapshot。
2. 给陈米食物后，StateStore 中 chen_mi.hunger 为 medium。
3. 基于新 snapshot 生成候选时，不再为 chen_mi 生成 give_food_to_hungry_person。
4. 报告伊莱后，TraceStore 中存在 institutional_record_mark。
5. 基于新 snapshot 生成候选时，可以从 trace store 生成 inspect_visible_trace 候选。
6. 报告伊莱后，RumorStore 中存在 outpost_discipline_report_seed。
7. 基于新 snapshot 生成候选时，可以生成 hear_rumor_seed 候选。
8. 替伊莱隐瞒后，RelationshipStore 中 recruit_elai -> player debt >= 10。
9. 基于新 snapshot 生成候选时，可以生成 request_favor_from_indebted_person 候选。
10. MemoryStore 能被 snapshot 读取。
11. SimRunner 每一步候选生成使用 snapshot。
```

同时回归通过：

```text
[V5 RAW RULE PROTOTYPE RESULT] PASS
[V5 TRANSACTION STATE MEMORY RESULT] PASS
[V5 RELATIONSHIP TRACE RUMOR NARRATIVE RESULT] PASS
[V5 SIM RUNNER WORLD LOG RESULT] PASS
```

## 8. Sim Core 独立规则执行情况

本次仍保持 Sim Core 独立：

```text
世界事实、实体状态、关系、记忆、痕迹、传闻和行动结果仍在 scripts/sim/ 与 data/sim/ 管理。
SimSnapshot 是只读视图。
ActionAffordanceSystem 只生成候选，不写世界。
TransactionWorldWriter 仍负责写入 stores。
Godot 场景树不拥有世界状态。
```

本次没有接 UI。
本次没有让 UI 控件保存世界状态。
本次没有让 `_process()` 驱动世界推进。
本次没有让按钮直接修改实体状态。
本次没有把 fixture entities 实例化成 Godot Node。
本次没有让 Narrative 文本反向决定事实。

## 9. 未修改保护文件确认

本次未修改：

```text
chronicle-godot/scenes/ui/story_player.gd
chronicle-godot/scripts/gen/world_generation_v03.gd
chronicle-godot/scenes/ui/mainui.tscn
chronicle-godot/project.godot
chronicle-godot/素材包/
```

本次也未修改：

```text
chronicle-godot/scripts/rebuild/
chronicle-godot/scenes/rebuild/
chronicle-godot/data/rebuild/
```

## 10. 未完成内容

本次未完成：

```text
未接 UI。
未实现完整世界 Tick。
未实现完整传闻传播。
未实现 AI 文本。
未实现湖湾镇完整闭环。
未实现第七哨站长期项目。
未把世界对象做成 Godot Node。
未把世界状态写入 Godot 场景树。
```

技术上仍未完成：

```text
MemoryStore 已纳入 snapshot，但尚未参与候选生成。
TraceStore / RumorStore 参与候选生成仍是最小原型。
RelationshipStore 参与候选生成只覆盖一个 request_favor 原型规则。
SimSnapshot 还不是完整世界查询 API。
ActionAffordanceSystem 的 rule DSL 仍然很轻量。
TransactionResolver 仍主要读取 context，后续可以逐步改为读取 snapshot。
```

## 11. 下一步建议

下一步建议：

1. 让 `TransactionResolver` 也能读取 `SimSnapshot`，逐步减少对初始 `SimContext` 的依赖。
2. 给 MemoryStore 设计最小候选规则，例如“向记得此事的人追问细节”。
3. 给 TraceStore / RumorStore 的候选生成补更明确的 raw rule 条件，而不是只做最小可见判断。
4. 为 `SimSnapshot` 增加稳定 debug dump，方便后续报告和 runner 输出。
5. 保持 UI 只读取 Sim Core 输出，不让 UI 持有世界状态。

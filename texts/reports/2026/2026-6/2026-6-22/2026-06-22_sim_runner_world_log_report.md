# 2026-06-22 Sim Runner + World Log Prototype 报告

## 1. 本次目标

本次目标是在已有链路：

```text
Action
→ Fact
→ State
→ Relationship
→ Memory
→ Trace
→ Rumor Seed
→ Narrative Surface
```

之上，新增一个纯数据层的连续事务 runner。

本次只做：

```text
Fixture
↓
Raw Rules
↓
Generate ActionCandidates
↓
Select Action By Scenario Step
↓
Resolve Transaction
↓
TransactionWorldWriter 写入 Stores
↓
Append World Log Entry
↓
Next Step
```

本次未接 UI。
本次未实现完整世界 Tick。
本次未实现完整传闻传播。
本次未实现 AI 文本。
本次未实现湖湾镇完整闭环。
本次未实现第七哨站长期项目。
本次未把世界对象做成 Godot Node。
本次未把世界状态写入 Godot 场景树。

## 2. 新增 Scenario Fixtures

新增目录：

```text
chronicle-godot/data/sim/fixtures/scenarios/
```

新增说明：

```text
chronicle-godot/data/sim/fixtures/scenarios/README.md
```

scenario 是测试用连续行动脚本，不是地点按钮表，也不保存最终 UI label。

每一步只保存选择条件：

```json
{
  "step_id": "give_food_to_chen_mi",
  "select": {
    "rule_id": "give_food_to_hungry_person",
    "target_id": "chen_mi"
  }
}
```

新增三条 sequence：

```text
lake_town_food_crisis_sequence.json
seventh_outpost_report_sequence.json
seventh_outpost_conceal_sequence.json
```

湖湾镇 sequence 包含：

```text
1. give_food_to_hungry_person，target: chen_mi
2. read_visible_readable_object，target: old_chen_shop_price_notice
3. inspect_visible_trace，target: gray_grain_powder
```

第七哨站 report sequence 包含：

```text
1. read_visible_readable_object，target: missing_ration_record
2. inspect_visible_trace，target: muddy_boot_trace
3. report_discipline_violation_to_superior，target: recruit_elai
```

第七哨站 conceal sequence 包含：

```text
1. ask_about_concealed_item，target: recruit_elai
2. conceal_discipline_violation_once，target: recruit_elai
```

## 3. SimWorldLog

新增：

```text
chronicle-godot/scripts/sim/core/sim_world_log.gd
```

`SimWorldLog` 负责保存连续事务运行后的结构化日志。

最小接口：

```text
append_entry(entry)
list_entries()
find_entries_by_fact_type(fact_type)
find_entries_by_rule_id(rule_id)
summary()
```

WorldLog entry 当前记录：

```text
step_index
step_id
rule_id
action_id
target_id
facts_added
state_changes
relationship_changes
memories_added
traces_added
rumors_added
narrative_summary
```

WorldLog 是调试和未来纪事前置素材。
它不是 UI 文本容器，也不是世界事实本身。
事实仍然写入 `FactStore`。

## 4. SimRunner

新增：

```text
chronicle-godot/scripts/sim/core/sim_runner.gd
```

核心接口：

```text
run_sequence(fixture_path, scenario_path, raw_rule_paths) -> Dictionary
```

`SimRunner` 内部建立并维护：

```text
FactStore
StateStore
RelationshipStore
MemoryStore
TraceStore
RumorStore
SimWorldLog
```

每一步执行顺序：

```text
1. 使用 ActionAffordanceSystem.generate_candidates(context, rules) 生成候选。
2. 根据 scenario step 的 rule_id + target_id 从候选中选择行动。
3. 使用 TransactionResolver.resolve_action(candidate, context) 生成 TransactionResult。
4. 使用 TransactionWorldWriter 写入 stores。
5. 将 state 写回同步到当前 context，供后续候选生成读取。
6. 把本步摘要写入 SimWorldLog。
```

Runner 返回：

```text
fixture_id
scenario_id
success
steps_executed
candidate_selection_source
candidate_generation_count
world_log
world_log_summary
store_summary
store_snapshots
```

本次没有直接构造 `ActionCandidate`。
每一步都通过 `ActionAffordanceSystem` 生成候选后再选择。

需要说明的是：本阶段只把 `StateStore` 写回同步回 `SimContext`，让后续行动候选可以读到状态变化。候选生成对 `RelationshipStore` / `MemoryStore` / `TraceStore` / `RumorStore` 的实时依赖仍需后续完善。本次没有为这个问题大改架构。

## 5. 三条 Sequence 运行结果

湖湾镇 `lake_town_food_crisis_sequence`：

| Step | Rule | Target | Facts | Narrative |
| --- | --- | --- | --- | --- |
| 0 | `give_food_to_hungry_person` | `chen_mi` | `actor_gave_food_to_target` | 对方接过食物，饥饿缓和了一些。感激和信任有所上升。 |
| 1 | `read_visible_readable_object` | `old_chen_shop_price_notice` | `actor_read_object` | 你读完了眼前的文字，并记住了其中的关键信息。 |
| 2 | `inspect_visible_trace` | `gray_grain_powder` | `actor_inspected_trace` | 你检查了痕迹，它指向刚刚发生过的事情。 |

第七哨站 `seventh_outpost_report_sequence`：

| Step | Rule | Target | Facts | Trace / Rumor | Narrative |
| --- | --- | --- | --- | --- | --- |
| 0 | `read_visible_readable_object` | `missing_ration_record` | `actor_read_object` | 无 | 你读完了眼前的文字，并记住了其中的关键信息。 |
| 1 | `inspect_visible_trace` | `muddy_boot_trace` | `actor_inspected_trace` | 无 | 你检查了痕迹，它指向刚刚发生过的事情。 |
| 2 | `report_discipline_violation_to_superior` | `recruit_elai` | `actor_reported_discipline_violation` | `institutional_record_mark` / `outpost_discipline_report_seed` | 罗恩听完报告，把口粮记录折了起来。小队里可能会有人听说这件事。 |

第七哨站 `seventh_outpost_conceal_sequence`：

| Step | Rule | Target | Facts | Rumor | Narrative |
| --- | --- | --- | --- | --- | --- |
| 0 | `ask_about_concealed_item` | `recruit_elai` | 无 | 无 | 无事务写回 |
| 1 | `conceal_discipline_violation_once` | `recruit_elai` | `actor_concealed_discipline_violation` | 无 | 伊莱意识到你没有把事情说出去。他欠下了一个不轻的人情。 |

## 6. Store 写回结果

湖湾镇 sequence 写回：

```text
facts: 3
relationships: 3
memories: 3
traces: 0
rumors: 0
```

关键内容：

```text
actor_gave_food_to_target
actor_read_object
actor_inspected_trace
chen_mi -> player gratitude / trust / fear
received_help
remembers_read_object
remembers_inspected_trace
```

第七哨站 report sequence 写回：

```text
facts: 3
relationships: 3
traces: 1
rumors: 1
```

关键内容：

```text
actor_read_object
actor_inspected_trace
actor_reported_discipline_violation
recruit_elai -> player resentment / trust
captain_ron -> player discipline_respect
institutional_record_mark
outpost_discipline_report_seed
```

第七哨站 conceal sequence 写回：

```text
facts: 1
relationships: 3
memories: 1
traces: 0
rumors: 0
```

关键内容：

```text
actor_concealed_discipline_violation
recruit_elai -> player trust / gratitude / debt
being_protected
```

## 7. 测试结果

新增测试：

```text
chronicle-godot/tests/sim/sim_runner_world_log_test.gd
```

已通过：

```text
[V5 SIM RUNNER WORLD LOG RESULT] PASS
```

测试覆盖：

```text
1. 能运行 lake_town_food_crisis_sequence。
2. 湖湾镇执行 3 步。
3. 湖湾镇 world_log 包含 actor_gave_food_to_target。
4. 湖湾镇 world_log 包含 actor_read_object。
5. 湖湾镇 world_log 包含 actor_inspected_trace。
6. 能运行 seventh_outpost_report_sequence。
7. 第七哨站 report sequence 产生 actor_reported_discipline_violation。
8. 第七哨站 report sequence 产生 institutional_record_mark trace。
9. 第七哨站 report sequence 产生 outpost_discipline_report_seed rumor seed。
10. 能运行 seventh_outpost_conceal_sequence。
11. 第七哨站 conceal sequence 产生 actor_concealed_discipline_violation。
12. 第七哨站 conceal sequence 不产生 rumor seed。
13. 每个 sequence 都通过 ActionAffordanceSystem 选择候选。
14. 湖湾镇 store 写回 facts / relationships / memories。
15. 第七哨站 report store 写回 facts / traces / rumors。
16. 第七哨站 conceal sequence 生成 narrative summary。
```

同时回归通过：

```text
[V5 RAW RULE PROTOTYPE RESULT] PASS
[V5 TRANSACTION STATE MEMORY RESULT] PASS
[V5 RELATIONSHIP TRACE RUMOR NARRATIVE RESULT] PASS
```

## 8. Sim Core 独立规则执行情况

本次仍保持 Sim Core 独立：

```text
scenario 是数据。
runner 是纯数据执行器。
store 保存世界事实、状态、关系、记忆、痕迹和传闻种子。
world log 是结构化调试输出。
Godot 场景树不拥有世界状态。
```

本次没有让 UI 控件保存世界状态。
本次没有让 `_process()` 驱动世界推进。
本次没有让按钮直接修改实体状态。
本次没有让 Narrative 文本反向决定事实。
本次没有把 fixture 里的 entities 实例化成 Godot Node。

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

技术上仍待完善：

```text
ActionAffordanceSystem 仍主要读取 SimContext。
RelationshipStore / MemoryStore / TraceStore / RumorStore 尚未参与候选生成条件。
WorldLog 只是结构化日志，还不是 Chronicle 输出系统。
ask_about_concealed_item 当前仍没有事务写回。
scenario 还没有分支、失败恢复或条件跳转。
```

## 11. 下一步建议

下一步建议继续保持纯数据层推进：

1. 让 `ActionAffordanceSystem` 可以读取 Store Snapshot，而不只读取初始 `SimContext`。
2. 给 `ask_about_concealed_item` 增加最小事务结果，例如 fact 或 memory seed。
3. 为 scenario 增加可选断言字段，用于描述每步期望写回。
4. 为 WorldLog 增加稳定导出格式，便于以后接纪事系统。
5. 再往后才考虑 UI 读取 runner 结果，不让 UI 拥有世界状态。

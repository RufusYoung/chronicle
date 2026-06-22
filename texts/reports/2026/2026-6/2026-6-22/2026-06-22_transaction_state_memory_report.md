# 2026-06-22 Transaction State / Memory Prototype 报告

## 1. 本次目标

本次目标是把 Transaction 从“只写 Fact”扩展为：

```text
Fact
+ State Change
+ Relationship Change
+ Memory Seed
```

本次未接 UI。

本次未实现传闻传播。

本次未实现完整记忆衰减。

本次未实现湖湾镇完整闭环。

本次未实现第七哨站长期项目。

## 2. 新增 / 修改系统

修改：

```text
chronicle-godot/scripts/sim/state/state_store.gd
chronicle-godot/scripts/sim/transaction/transaction_result.gd
chronicle-godot/scripts/sim/transaction/transaction_resolver.gd
```

新增：

```text
chronicle-godot/scripts/sim/relationship/relationship_store.gd
chronicle-godot/scripts/sim/memory/memory_store.gd
chronicle-godot/tests/sim/transaction_state_memory_test.gd
```

## 3. State 写回

`StateStore` 新增：

```text
load_from_context(context)
apply_state_change(change)
list_entity_states(entity_id)
```

当前支持：

- 直接 `to` 写入。
- `delta` 数值调整。
- 简单枚举降级：`extreme -> high -> medium -> low -> none`。

给陈米食物时，事务结果产生：

```text
chen_mi.hunger: high -> medium
player.food_count: 2 -> 1
```

## 4. Relationship 写回

新增 `RelationshipStore`，当前结构为：

```text
source -> target -> axis -> value
```

支持关系轴：

```text
trust
fear
gratitude
resentment
discipline_respect
shame
```

当前事务结果会生成关系变化，但不实现完整 NPC 行为系统。

## 5. Memory Seed 写回

新增 `MemoryStore`，用于保存结构化 memory seed。

当前支持：

```text
add_memory(memory)
list_memories(owner_id)
find_memories_by_type(owner_id, memory_type)
```

本阶段 memory seed 只表示“某人记住了一件事”，不做衰减、误解、传闻传播或叙事生成。

## 6. Transaction 示例

给陈米食物：

```text
Fact:
actor_gave_food_to_target

State:
chen_mi.hunger high -> medium
player.food_count 2 -> 1

Relationship:
chen_mi -> player gratitude +1
chen_mi -> player trust +1
chen_mi -> player fear -1

Memory:
chen_mi received_help
```

报告伊莱：

```text
Fact:
actor_reported_discipline_violation

Relationship:
recruit_elai -> player resentment +1
captain_ron -> player discipline_respect +1

Memory:
recruit_elai being_reported
captain_ron discipline_report
```

替伊莱隐瞒：

```text
Fact:
actor_concealed_discipline_violation

Relationship:
recruit_elai -> player trust +1
recruit_elai -> player gratitude +1

Memory:
recruit_elai being_protected
```

阅读对象和检查痕迹仍以 Fact 为主，并给 player 生成可选 memory seed：

```text
remembers_read_object
remembers_inspected_trace
```

## 7. 测试结果

新增测试：

```text
chronicle-godot/tests/sim/transaction_state_memory_test.gd
```

已执行：

```text
Godot --headless --check-only --path . --script res://tests/sim/transaction_state_memory_test.gd
Godot --headless --path . --script res://tests/sim/transaction_state_memory_test.gd --quit-after 200
Godot --headless --path . --script res://tests/sim/raw_rule_prototype_test.gd --quit-after 200
```

结果：

```text
[V5 TRANSACTION STATE MEMORY RESULT] PASS
[V5 RAW RULE PROTOTYPE RESULT] PASS
```

测试覆盖：

- 给陈米食物后写入 `actor_gave_food_to_target`。
- 给陈米食物后 hunger 从 `high` 降为 `medium`。
- 给陈米食物后 `chen_mi -> player gratitude` 增加。
- 给陈米食物后生成 `received_help` memory。
- 报告伊莱后写入 `actor_reported_discipline_violation`。
- 报告伊莱后 `recruit_elai -> player resentment` 增加。
- 报告伊莱后 `captain_ron -> player discipline_respect` 增加。
- 替伊莱隐瞒后 `recruit_elai -> player trust` 增加。
- 替伊莱隐瞒后生成 `being_protected` memory。

## 8. 未修改保护文件确认

本次未修改：

```text
chronicle-godot/scenes/ui/story_player.gd
chronicle-godot/scripts/gen/world_generation_v03.gd
chronicle-godot/scenes/ui/mainui.tscn
chronicle-godot/project.godot
chronicle-godot/素材包/
```

本次未修改：

```text
chronicle-godot/scripts/rebuild/
chronicle-godot/scenes/rebuild/
chronicle-godot/data/rebuild/
```

本次不接 UI。

## 9. 未完成内容

本次未完成：

- 未实现传闻传播。
- 未实现完整记忆衰减。
- 未实现 Memory 到 Rumor 的转换。
- 未实现关系驱动 NPC 行为。
- 未实现完整状态数值系统。
- 未实现物品系统实际扣除实体。
- 未实现湖湾镇完整闭环。
- 未实现第七哨站长期项目。

## 10. 下一步建议

下一步可以把 Transaction 结果接入更完整的系统写回流程：

```text
TransactionResult
↓
StateStore
RelationshipStore
MemoryStore
FactStore
↓
Trace / Rumor / Narrative Surface
```

也可以继续做湖湾镇与第七哨站双 fixture 对照，让同一套事务写回在民间粮食危机和军事口粮制度中产生不同后果。

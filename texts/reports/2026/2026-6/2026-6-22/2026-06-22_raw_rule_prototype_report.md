# 2026-06-22 Raw Object + Rule Prototype 报告

## 1. 本次目标

本次目标是验证 v5.1 世界模拟层的最小 Raw / Rule 原型：

```text
Raw 定义 + Fixture 测试切片 + ActionRule 匹配
↓
生成 ActionCandidate
↓
执行 Transaction
↓
写入 FactStore
```

本次未接入 UI。

本次未实现湖湾镇完整状态闭环。

本次未实现第七哨站长期项目。

本次只验证 Raw 定义、Fixture、行动候选生成、Transaction 和 Fact 写回。

## 2. 新增 Raw 定义

新增基础行动规则：

```text
chronicle-godot/data/sim/raw/action_rules/basic_action_rules.json
```

包含：

```text
approach_visible_person
give_food_to_hungry_person
ask_about_concealed_item
read_visible_readable_object
inspect_visible_trace
```

新增领域行动规则：

```text
chronicle-godot/data/sim/raw/action_rules/domain_action_rules.json
```

包含：

```text
ask_about_food_pressure_at_market
report_discipline_violation_to_superior
conceal_discipline_violation_once
confirm_ration_record_with_cook
trade_watch_duty_for_silence
delay_military_issue_until_after_patrol
```

新增对象定义：

```text
chronicle-godot/data/sim/raw/object_defs/basic_object_defs.json
```

新增状态定义：

```text
chronicle-godot/data/sim/raw/state_defs/basic_state_defs.json
```

这些定义仍然是轻量原型，不是完整百科。

## 3. 新增 Fixture

新增湖湾镇测试切片：

```text
chronicle-godot/data/sim/fixtures/lake_town_food_crisis_fixture.json
```

该 fixture 包含：

- `old_chen_shop`
- `chen_mi`
- `spoiled_grain_bag`
- `old_chen_shop_price_notice`
- `gray_grain_powder`
- `food_pressure = high`

新增第七哨站测试切片：

```text
chronicle-godot/data/sim/fixtures/seventh_outpost_ration_fixture.json
```

该 fixture 包含：

- `outpost_kitchen`
- `recruit_elai`
- `captain_ron`
- `cook_marta`
- `stolen_ration`
- `missing_ration_record`
- `muddy_boot_trace`
- `discipline_level = strict`
- `ration_pressure = high`
- `fog_patrol_tonight = true`

两个 fixture 均未保存 `actions` 字段。

测试期望只放在 `expected_generated_actions`，不作为按钮表使用。

## 4. 行动生成结果

湖湾镇生成的关键行动：

```text
[对话] 走近陈米
[普通] 给陈米食物
[对话] 问陈米藏着什么
[普通] 阅读涨价告示
[线索] 查看灰白粮粉
[线索] 打听粮食压力
```

第七哨站生成的关键行动：

```text
[对话] 走近伊莱
[对话] 走近罗恩
[对话] 走近玛塔
[普通] 给伊莱食物
[对话] 问伊莱藏着什么
[普通] 阅读缺失口粮记录
[线索] 查看泥脚印
[军纪] 向队长罗恩报告伊莱
[军纪] 替伊莱隐瞒一次
[军纪] 找厨子玛塔确认分发记录
[军纪] 让伊莱今晚替你站岗作为交换
[军纪] 把事情压到巡逻结束后再处理
```

湖湾镇行动来自人物、饥饿、隐藏物、可读告示、可检查痕迹与地区粮食压力。

第七哨站行动额外来自 `military` 地点标签、严格军纪、口粮压力、上下级结构、厨子口粮职责和夜间雾线巡逻。

本次未写 `location_id == "old_chen_shop"` 或 `location_id == "outpost_kitchen"` 的地点特判。

本次未写 `entity_id == "chen_mi"` 或 `entity_id == "recruit_elai"` 的实体特判。

## 5. Transaction 与 Fact 写回

新增事务执行器：

```text
chronicle-godot/scripts/sim/transaction/transaction_resolver.gd
```

当前支持以下 rule 到 fact 的最小写回：

```text
give_food_to_hungry_person
→ actor_gave_food_to_target

read_visible_readable_object
→ actor_read_object

inspect_visible_trace
→ actor_inspected_trace

report_discipline_violation_to_superior
→ actor_reported_discipline_violation

conceal_discipline_violation_once
→ actor_concealed_discipline_violation
```

扩展了：

```text
chronicle-godot/scripts/sim/transaction/transaction_result.gd
chronicle-godot/scripts/sim/fact/fact_store.gd
```

`FactStore` 现在支持：

```text
add_fact(fact)
list_facts()
find_facts_by_type(fact_type)
```

## 6. 测试结果

新增测试：

```text
chronicle-godot/tests/sim/raw_rule_prototype_test.gd
```

已执行：

```text
Godot --headless --check-only --path . --script res://tests/sim/raw_rule_prototype_test.gd
Godot --headless --path . --script res://tests/sim/raw_rule_prototype_test.gd --quit-after 200
```

结果：

```text
[V5 RAW RULE PROTOTYPE RESULT] PASS
```

测试覆盖：

- 能加载 raw action rules。
- 能加载湖湾镇 fixture。
- 湖湾镇能生成基础行动。
- 湖湾镇不依赖 `fixture.actions`。
- 能加载第七哨站 fixture。
- 第七哨站能生成基础行动。
- 第七哨站能生成至少 3 个军纪 / 口粮领域行动。
- 第七哨站行动不是湖湾镇换壳。
- 执行给食物后写入 `actor_gave_food_to_target`。
- 执行报告军纪问题后写入 `actor_reported_discipline_violation`。

## 7. 未修改保护文件确认

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

## 8. 未完成内容

本次未完成：

- 未实现完整 Raw / Rule DSL。
- 未实现湖湾镇完整状态闭环。
- 未实现第七哨站长期项目。
- 未实现关系、记忆、传闻的正式写回。
- 未实现物品消耗、状态变化和地区变化。
- 未把行动候选接入前台 rebuild UI。

## 9. 下一步建议

下一步可以把 Transaction 从只写 Fact 扩展到最小状态变化：

```text
给食物
→ 玩家 food_count -1
→ 目标 hunger 下降
→ 写入 fact
→ 生成 memory seed
```

也可以进入湖湾镇 + 第七哨站双 fixture 对照测试，让两个地点在同一套规则下继续分化出不同后果结构。

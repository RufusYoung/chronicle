# 2026-06-22 v5 世界模拟系统骨架整理报告

## 1. 本次目标

本次目标是按照 `texts/v5/CHRONICLE_WORLD_SIM_ARCHITECTURE_v5.1.md`，为 Chronicle v5.1 建立世界模拟系统的目录、README 和最小脚本骨架。

本次只整理系统边界，不实现新的玩法内容。

## 2. 新增目录

新增数据目录：

```text
chronicle-godot/data/sim/raw/
chronicle-godot/data/sim/fixtures/
chronicle-godot/data/sim/worlds/
```

新增系统目录：

```text
chronicle-godot/scripts/sim/core/
chronicle-godot/scripts/sim/entity/
chronicle-godot/scripts/sim/state/
chronicle-godot/scripts/sim/trait_tag/
chronicle-godot/scripts/sim/relationship/
chronicle-godot/scripts/sim/memory/
chronicle-godot/scripts/sim/item/
chronicle-godot/scripts/sim/equipment/
chronicle-godot/scripts/sim/location/
chronicle-godot/scripts/sim/region/
chronicle-godot/scripts/sim/institution/
chronicle-godot/scripts/sim/economy/
chronicle-godot/scripts/sim/action/
chronicle-godot/scripts/sim/transaction/
chronicle-godot/scripts/sim/fact/
chronicle-godot/scripts/sim/trace/
chronicle-godot/scripts/sim/rumor/
chronicle-godot/scripts/sim/life_project/
chronicle-godot/scripts/sim/world_tick/
chronicle-godot/scripts/sim/narrative/
chronicle-godot/scripts/sim/chronicle/
chronicle-godot/tests/sim/
```

## 3. 新增 README

新增了 `chronicle-godot/scripts/sim/README.md`，说明 `scripts/sim/` 是世界模拟层，不依赖 UI，不替代 `scripts/rebuild/` 原型。

每个系统子目录均新增 `README.md`，统一包含：

```text
职责
管理的数据
输入
输出
不负责什么
与其他系统的关系
当前状态
```

新增了 `chronicle-godot/data/sim/README.md` 以及 `raw/`、`fixtures/`、`worlds/` 三个数据子目录 README。

其中明确：

- `raw/` 是定义和规则，不是世界实例。
- `fixtures/` 是测试切片，例如湖湾镇和第七哨站。
- `worlds/` 是正式存档或生成后的世界实例。
- 当前阶段的湖湾镇和第七哨站都应视为 fixture，不是主 GDD，也不是永久地点按钮表。

## 4. 新增骨架脚本

新增最小 GDScript 骨架：

```text
chronicle-godot/scripts/sim/core/sim_context.gd
chronicle-godot/scripts/sim/core/sim_registry.gd
chronicle-godot/scripts/sim/entity/entity_store.gd
chronicle-godot/scripts/sim/state/state_store.gd
chronicle-godot/scripts/sim/action/action_candidate.gd
chronicle-godot/scripts/sim/action/action_affordance_system.gd
chronicle-godot/scripts/sim/transaction/transaction_result.gd
chronicle-godot/scripts/sim/fact/fact_store.gd
```

这些脚本只提供空骨架、基础字段和最小查询方法。

本次未实现 Raw / Rule 原型。

本次未实现湖湾镇状态闭环。

本次未实现第七哨站。

本次只建立系统骨架。

## 5. 测试结果

新增测试：

```text
chronicle-godot/tests/sim/sim_architecture_skeleton_test.gd
```

测试内容：

- 加载并实例化所有新增骨架类。
- 创建 `V5ActionCandidate`。
- 验证空 `V5ActionAffordanceSystem` 可调用。
- 验证 `V5TransactionResult` 可表示空事务结果。
- 验证 `V5FactStore` 可保存结构化事实。

已执行：

```text
Godot --headless --check-only --path . --script res://tests/sim/sim_architecture_skeleton_test.gd
Godot --headless --path . --script res://tests/sim/sim_architecture_skeleton_test.gd --quit-after 200
```

结果：

```text
[V5 SIM ARCHITECTURE SKELETON RESULT] PASS
```

## 6. 未修改保护文件确认

本次未修改：

```text
chronicle-godot/scenes/ui/story_player.gd
chronicle-godot/scripts/gen/world_generation_v03.gd
chronicle-godot/scenes/ui/mainui.tscn
chronicle-godot/project.godot
chronicle-godot/素材包/
```

本次也未修改现有 rebuild 原型目录：

```text
chronicle-godot/scripts/rebuild/
chronicle-godot/scenes/rebuild/
chronicle-godot/data/rebuild/
```

## 7. 未完成内容

本次未完成以下内容：

- 未实现 Raw / Rule 原型。
- 未实现行动规则匹配。
- 未实现事务写回规则。
- 未实现湖湾镇状态闭环。
- 未实现第七哨站 fixture。
- 未迁移现有 `scripts/rebuild/` 或旧 `scripts/sim/` 逻辑。

## 8. 下一步建议

下一步可以进入 Raw Object + Rule Prototype。

该阶段应基于本次新增的 `core/`、`action/`、`transaction/`、`fact/` 等骨架继续扩展，仍然保持 fixture 与正式世界实例分离。

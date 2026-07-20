# Chronicle v5 世界模拟系统

## 定位

`scripts/sim/` 是 Chronicle v5.1 的世界模拟层骨架。

它负责承载实体、状态、关系、行动候选、事务写回、事实、痕迹、传闻、长期项目、世界推进、叙事表面和纪事输出等系统边界。

当前目录不负责 Godot UI 展示，也不直接连接旧主界面。

## 与 rebuild 的关系

`scripts/rebuild/` 保留为 v5 前台地点局面原型目录。

`scripts/sim/` 不迁移现有 rebuild 逻辑，不复制湖湾镇按钮表，也不改写当前可运行原型。

后续若需要复用 rebuild 中的有效逻辑，应通过单独任务迁移到对应系统目录，并保持可测试边界。

## 系统清单

- Entity System
- State / Need System
- Trait / Tag System
- Relationship System
- Memory System
- Item / Material System
- Equipment System
- Location System
- Region System
- Institution System
- Economy / Pressure System
- Action Affordance System
- Transaction System
- Fact / History System
- Trace System
- Rumor System
- Life Project System
- World Tick System
- Narrative Surface System
- Chronicle Output System

## 数据入口

世界模拟数据优先放入 `data/sim/`：

- `raw/`：定义、规则和可复用原型。
- `fixtures/`：测试切片，例如湖湾镇、第七哨站。
- `worlds/`：正式存档或生成后的世界实例。

## 当前状态

世界模拟骨架已经具备可连续执行的最小运行生命周期：

```text
SimSession
↓
SimSnapshot
↓
ActionAffordanceSystem
↓
TransactionResolver
↓
TransactionWorldWriter
↓
Stores + SimWorldLog
```

当前已经实现并有测试覆盖的部分包括：

- Action Candidate / Raw Rule
- Transaction / Effect Template
- Fact / State / Relationship / Memory
- Trace / Rumor / Pressure
- Obligation / Exchange / Deferred Consequence
- Scoped Tick Event
- Due Trigger / Due Resolution
- 持久 SimSession 与脚本 Runner 兼容入口

Location、Region、Item、Equipment、Life Project 和 Chronicle Output 仍处于骨架阶段。正式 Godot UI 尚未接入 `SimSession`。

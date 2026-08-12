# Definition、Entity 与 State 唯一真值合同实施报告

日期：2026-08-12

分支：`exp/v5-definition-entity-contract`

## 1. 本轮目标

执行阶段 5.5 步骤 2A：把 Raw Definition 从目录骨架变成可校验的运行时合同，将 `EntityStore` 接入 `SimSession`，并消除 Context、EntityStore、StateStore 同时保存玩家与实体状态的多重真值。

本轮不新增剧情、线索、地点、UI、第二年内容，也不实现天赋、印记、装备或商店。

## 2. 结果结论

步骤 2A 已完成，结果改善。

改善不在于增加了可见内容，而在于底层运行时边界已经发生实际变化：

- Session 启动会严格注册 StateDef 与 ObjectDef，重复 ID、缺失版本和不合法 schema 会阻止启动。
- EntityStore 现在保存实体身份、类型和静态元数据。
- StateStore 现在保存人物、对象、地区与制度的可变状态。
- Snapshot 只合并 Store 数据，不再依赖 Context 中持续同步的玩家与实体副本。
- Context 完成初始化后会释放玩家、实体、地区、制度和事实源数据；篡改这些字段不会改变后续 Snapshot。
- 行动候选、世界时钟与事务写回仍沿用现有 `Store -> Snapshot -> Affordance -> Transaction -> Writer` 主链。

这为下一步角色特征、物品实例和装备位提供了单一接入点，避免它们再次形成 fixture 字段、Context 字段和 Store 字段三份数据。

## 3. 实现内容

### 3.1 Raw Definition

`SimRegistry` 新增按 kind 注册、查询和枚举 Definition 的能力，并支持一次加载多个 Raw Definition 文件。

Godot JSON 会把数字统一解析为浮点表示。Registry 与 StateStore 会在合同边界把无小数的 `int` 字段规范化为整数，再执行类型和范围校验；带小数的值仍会被 int 合同拒绝。

当前严格校验包括：

- 稳定 definition ID；
- `definition_version >= 1`；
- 重复 ID 拒绝；
- StateDef 的 key、所有者类型、值类型、默认值、枚举值、数值范围、允许操作、持久化策略和 UI 可见级别；
- ObjectDef 的对象类型、所有者类型和默认标签。

第一批 Raw 数据包含 23 个 StateDef 和 11 个 ObjectDef，共 34 个 Definition。除 definition ID 外，Registry 还拒绝多个 StateDef 复用同一 key，或多个 ObjectDef 复用同一 type，避免 Store 建索引时静默覆盖。

### 3.2 EntityStore

EntityStore 已接入 Session，并负责：

- 真实实体与玩家的稳定身份；
- 对象类型、所有者类型、显示名、描述、标签与交互元数据；
- 地区与制度的合成实体身份；
- 严格模式下拒绝未知对象类型。

位置、饥饿、属性等可变字段不再保存在 EntityStore 内。

### 3.3 StateStore

StateStore 已接管：

- 玩家属性、健康、疲劳、食物等可变状态；
- NPC 与对象的状态和位置；
- 地区压力与制度状态；
- StateDef 规定的类型、范围、所有者与操作校验。

新合同可使用严格模式直接拒绝未知字段和非法写入。旧 fixture 暂以兼容模式装载：未注册领域字段仍可运行，但会按字段汇总迁移警告，不会被悄悄视为正式 schema。兼容只作用于旧数据导入，已注册字段在运行时始终严格执行类型、范围、所有者与操作边界。

### 3.4 Snapshot 与 Session

`SimSnapshotBuilder` 现在从 EntityStore 读取静态元数据，从 StateStore 读取可变状态，再生成原有 Snapshot 结构。外部系统继续读取 Snapshot，不需要直接知道两个 Store 的内部结构。

Session 初始化成功后会清空 Context 中仅用于导入的：

- `player`；
- `entities`；
- `region_state`；
- `institution`；
- `known_facts`。

原有每次事务后同步 Context 的代码已移除。世界时钟仍在每轮结算前通过 SnapshotBuilder 读取最新 Store 状态。

## 4. 新增与修改文件

新增：

- `chronicle-godot/tests/sim/definition_entity_state_contract_test.gd`
- `chronicle-godot/tests/sim/definition_entity_state_contract_test.gd.uid`
- `chronicle-godot/texts/reports/2026/2026-8/2026-8-12/2026-08-12_definition_entity_state_contract_report.md`

主要修改：

- `chronicle-godot/scripts/sim/core/sim_registry.gd`
- `chronicle-godot/scripts/sim/core/sim_context.gd`
- `chronicle-godot/scripts/sim/core/sim_session.gd`
- `chronicle-godot/scripts/sim/core/sim_snapshot_builder.gd`
- `chronicle-godot/scripts/sim/entity/entity_store.gd`
- `chronicle-godot/scripts/sim/state/state_store.gd`
- `chronicle-godot/data/sim/raw/state_defs/basic_state_defs.json`
- `chronicle-godot/data/sim/raw/object_defs/basic_object_defs.json`
- 对应子系统 README、核心合同计划、v5 路线图与索引。

## 5. 保护范围

以下内容未修改：

- UI 场景与 UI 脚本；
- 湖湾镇和第七哨站 fixture；
- 剧情、事实、线索、痕迹与叙事文案；
- 第一冬及后续年份的生活项目内容；
- GDD 与创意方向文档；
- 现有历史报告正文。

全项目测试会重生成一份历史观察输出，本轮测试后已立即还原，没有纳入提交。

## 6. 测试

测试环境：Godot 4.6.3，Windows，headless。

测试结果：

- 修改前基线：`58 / 58` 通过。
- 新增合同测试：17 项断言全部通过。
- 高风险定向回归：Session、旅行、世界时间、第一冬 4 个测试全部通过。
- 修改后全项目回归：`59 / 59` 通过。
- Godot headless editor 扫描：退出码 0，并生成新测试 UID。

新增测试覆盖：

- Definition 严格注册、查询、重复拒绝与非法 schema 拒绝；
- EntityStore 静态身份和 StateStore 可变状态分离；
- 严格状态类型、操作和未知字段拒绝；
- 兼容 fixture 中已注册字段的运行时越界写入拒绝；
- Session 使用 EntityStore 构建 Snapshot；
- Context 导入副本释放；
- 篡改 Context 不影响 Store 真值；
- StateStore 变化立即影响 Snapshot 与行动候选阻塞解释。

## 7. 验收结论

本轮验收通过：

- Definition 已从占位 JSON 变成可校验合同。
- EntityStore 已正式接入 Session。
- EntityStore、StateStore 与 Snapshot 的所有权边界已由自动化测试固定。
- 旧闭环没有因真值迁移而回归。

## 8. 已知限制

- 当前只有 23 个基础 StateDef，旧 fixture 的领域专属状态仍在兼容清单中。
- 地区与制度已进入 EntityStore 和 StateStore，但 Snapshot 仍保留旧的 `region_state` 与 `institution` 投影字段以兼容上层代码。
- Context 仍保留导入字段和 SnapshotBuilder 兼容回退接口；正式 Session 初始化后已不再使用这些字段作为运行时真值。
- 尚未实现运行时通用实体创建、销毁和存档重建。
- 天赋、特质、印记、技艺、物品实例、装备位、市场投影与 SaveEnvelope 尚未进入本轮实现。

## 9. 下一步

执行步骤 2B：建立角色特征 Store 与只读 `CharacterProgress` 投影，首先统一属性、天赋、特质、印记和技艺的稳定定义、拥有关系、进度与来源记录。不得把这些数据重新写入 Context、UI 或场景专属 fixture 形成第二真值。

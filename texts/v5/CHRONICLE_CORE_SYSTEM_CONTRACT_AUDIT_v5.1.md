# Chronicle 核心系统合同现状审计 v5.1

日期：2026-08-12

状态：阶段 5.5 步骤 1 已完成

关联计划：`CHRONICLE_CORE_SYSTEM_CONTRACT_PLAN_v5.1.md`

## 1. 审计结论

Chronicle 当前不是缺少一套全新的底层架构。已经形成并被湖湾镇与第七哨站验证的主链是：

```text
Store
↓
SimSnapshot
↓
ActionAffordanceSystem
↓
TransactionResult
↓
TransactionWorldWriter
↓
新 Snapshot 与结果反馈
```

这条主链应保留并扩展，不应推倒重写。

当前真正阻碍天赋、特质、印记、技艺、装备、商店和长期存档接入的问题，是同一概念存在多份可写数据，以及部分领域只有临时字段，没有稳定定义、实例身份和事务操作。

最严重的例子包括：

- 玩家库存同时存在于旧 `WorldState.inventory`、场景或 NPC 内嵌库存、`player.inventory_item_ids` 和 v5 `ItemStore`。
- 玩家状态同时保存在 `SimContext.player` 与 `StateStore`，事务完成后依靠手动同步。
- 已知事实同时保存在 `FactStore` 与 `SimContext.known_facts`。
- 地区和制度状态保存在 `SimContext`，但 `TransactionResult.region_changes` 没有正式写入路径。
- `injury`、`mist_salt_echo`、`training`、`service_day` 等字段把生理状态、经历印记、技艺成长和长期项目游标混在同一个通用状态字典中。
- 当前没有正式存档、schema 版本、引用校验和迁移入口。

因此，阶段 5.5 不需要先堆完整天赋树、装备库或商店 UI。正确顺序是：

1. 裁定每类数据的唯一真值。
2. 给定义与实例稳定 ID。
3. 扩展事务类型和快照投影。
4. 建立可版本化存档。
5. 用湖湾镇与第一冬迁移验证。

## 2. 审计范围

本次读取并核对了以下现有边界：

- `scripts/sim/state/state_store.gd`
- `scripts/sim/fact/fact_store.gd`
- `scripts/sim/memory/memory_store.gd`
- `scripts/sim/relationship/relationship_store.gd`
- `scripts/sim/entity/entity_store.gd`
- `scripts/sim/item/item_store.gd`
- `scripts/sim/trace/trace_store.gd`
- `scripts/sim/chronicle/chronicle_store.gd`
- `scripts/sim/core/sim_context.gd`
- `scripts/sim/core/sim_snapshot.gd`
- `scripts/sim/core/sim_snapshot_builder.gd`
- `scripts/sim/core/sim_session.gd`
- `scripts/sim/action/action_candidate.gd`
- `scripts/sim/action/action_affordance_system.gd`
- `scripts/sim/action/raw_rule_contract_validator.gd`
- `scripts/sim/transaction/transaction_result.gd`
- `scripts/sim/transaction/transaction_world_writer.gd`
- `scripts/sim/transaction/transaction_resolver.gd`
- `scripts/sim/transaction/effect_template_resolver.gd`
- `scripts/sim/core/sim_world_log.gd`
- 当前 raw 定义、fixture、第一冬长期项目和相关测试。

旧 `scripts/sys/WorldState.gd` 也纳入了兼容边界检查，但不再视为 v5 核心系统的扩展基础。

本次没有修改代码，也没有重跑模拟。

## 3. 现有能力与裁决

| 领域 | 当前能力 | 裁决 |
| --- | --- | --- |
| `StateStore` | 按实体和 key 保存标量或任意 Variant，支持 `to`、`delta` 和等级降档 | 保留为短期可变状态与属性真值，但必须加载 `StateDef` 并校验类型、范围和写入操作 |
| `FactStore` | 保存事实并按 `fact_id` 去重 | 保留为已经发生之事的唯一真值；淘汰 `SimContext.known_facts` 第二副本 |
| `MemoryStore` | 保存角色持有的结构化记忆 | 保留；增加稳定 `memory_id`、来源事实校验和去重规则 |
| `RelationshipStore` | 保存有方向的多轴关系，支持范围与层级 | 保留；增加变更来源和存档合同 |
| `ItemStore` | 创建物品、保存 owner、来源与历史，按 owner 查询 | 保留并升级为 `ItemInstance` 真值；补齐转移、消耗、堆叠、耐久和销毁操作 |
| `EntityStore` | 有最小增查骨架 | 当前未接入 `SimSession`，且 `id` 与 `entity_id` 表达不一致；应接入或移除孤立骨架，不能继续两套实体来源 |
| `TraceStore` | 保存可见痕迹，并按类型、行为者和地点替换 | 保留；明确 `trace_id` 与“同类痕迹合并键”是两件事 |
| `ChronicleStore` | 保存结构化纪事条目 | 保留；纪事是事实压缩结果，不是角色状态真值 |
| `SimSnapshot` | 汇集主要 Store，供候选、结算和 UI 读取 | 保留为只读投影；不得成为可写存档本体 |
| `ActionCandidate` | 保存候选身份、目标、资格、阻塞原因和结果提示 | 保留；资格协议需从 `player_min` 扩展为通用 requirement |
| `TransactionResult` | 汇集事实、状态、关系、记忆、痕迹、压力、物品等变化 | 保留为唯一写回入口；去除别名数组并增加角色成长与装备变化 |
| `TransactionWorldWriter` | 顺序写入各 Store | 保留职责；正式合同要求写前完整校验，失败时不得部分写入 |
| `SimWorldLog` | 记录事务摘要并供测试审计 | 保留为审计日志；不能作为玩法条件或存档真值 |
| Raw 定义 | 已有状态、关系轴、对象、行动和效果模板 JSON | 保留方向；`SimRegistry.load_raw_definitions()` 仍是占位，尚未形成统一定义注册表 |
| 存档 | 只有 fixture 初始化和运行结果快照 | 未实现；必须在跨季度、跨年份前补齐 |

## 4. 必须先解决的冲突

### 4.1 P0：状态存在双写

`StateStore` 从 `SimContext` 载入玩家和实体状态。事务写入 `StateStore` 后，`SimSession` 再把结果同步回 `SimContext.player` 或 `SimContext.entities`。

这意味着两个对象都能成为写入源。一旦新增装备、印记、技能或存档载入，任何漏同步都会让候选读取旧值。

裁决：

- 初始化完成后，`StateStore` 是可变状态唯一真值。
- `SimContext` 只保存世界身份、当前观察范围和不重复的运行上下文。
- `SimSnapshotBuilder` 从 Store 构建玩家与实体投影。
- 兼容期可以生成镜像，但镜像必须只读，且不得进入存档。

### 4.2 P0：库存存在四种表达

当前可找到以下库存表达：

1. 旧 `WorldState.inventory` 的 `item_key -> count`。
2. 湖湾镇旧模拟和 NPC 数据中的内嵌 `inventory`、`food_stock`。
3. `player.inventory_item_ids`。
4. v5 `ItemStore` 中带 `owner_id` 的物品实例。

v5 旅途、挑战和回声逻辑同时检查 `ItemStore.owner_id` 与 `player.inventory_item_ids`。创建物品时也会同时写两处。

裁决：

- `ItemStore` 中 `ItemInstance.holder` 是物品位置和归属的唯一真值。
- “玩家背包”是 `holder = entity:player` 的查询投影，不再保存 ID 数组。
- 普通可堆叠资源使用带 `quantity` 的物品实例。
- 装备、遗物和有独立历史的物品必须是 `quantity = 1` 的独立实例。
- `inventory_item_ids` 标记为迁移字段，完成迁移后删除。
- 旧 `WorldState.inventory` 不与 v5 双向同步。

### 4.3 P0：事实存在运行时副本

`FactStore` 已按 `fact_id` 去重，但 `SimContext` 还保存 `known_fact_ids` 和 `known_facts`，事务后继续同步。

裁决：

- 世界事实只进入 `FactStore`。
- “某角色知道什么”通过 `MemoryStore`、事实可见性或知识引用表达。
- `known_facts` 不得继续承担事实存储职责。

### 4.4 P0：地区变化没有完整写入路径

`TransactionResult` 声明了 `region_changes`，但没有对应添加方法，`TransactionWorldWriter` 也不处理它。与此同时，`region_state` 和 `institution` 仍直接放在 `SimContext`。

裁决：

- 地区与机构都是实体。
- 它们的可变数值进入 `StateStore`，通过实体 ID 定位。
- 不新增另一套 `RegionStore` 标量字典。
- 现有 `region_changes` 迁移为普通 `state_changes`，然后删除死合同。

### 4.5 P0：没有正式持久化合同

当前 `get_store_snapshots()` 只用于结果与测试输出，缺少：

- `schema_version`；
- 完整世界时间与随机数状态；
- Store 反序列化；
- 稳定引用校验；
- 迁移注册表；
- 载入后候选一致性检查；
- 写入中断保护。

裁决：在阶段 5.5 步骤 4 完成前，不开始第二年至第五年内容。

### 4.6 P1：定义层没有真正接入

`state_defs`、`object_defs` 和关系轴定义已经存在，但 `SimRegistry.load_raw_definitions()` 仍为空实现。`StateStore` 接受任意 key 与任意 Variant，fixture 中很多字段没有定义。

裁决：

- Raw 只保存不可变定义。
- 所有正式定义由 `SimRegistry` 加载、校验并按 kind 与稳定 ID 注册。
- 未注册字段在测试 fixture 中可以临时允许，在正式存档中必须报错或经过显式兼容迁移。

### 4.7 P1：行动条件只能表达局部能力

现有 `player_min` 能处理力量、感知等最小值，关系和部分世界状态有专用判断，但天赋、特质、印记、技艺、装备、物品数量和动态价格没有共同协议。

裁决：保留现有候选生成方式，使用统一 `requirements[]` 替代不断增加的专属字段。旧 `player_min` 由适配器转换，不能继续扩写新能力。

### 4.8 P1：事务不是原子写入

`TransactionWorldWriter` 当前逐个 Store 写入，没有写前跨引用验证或回滚。未来一次交易会同时改变钱、商品 holder、库存数量、关系、压力和事实，顺序中途失败会产生半笔交易。

裁决：步骤 3 必须加入“先解析并校验完整结果，再一次提交”的原子边界。UI 不得直接调用 Store 修改函数。

### 4.9 P1：事务结果保留历史别名

`facts` 与 `facts_added`、`memories` 与 `memories_added`、`traces` 与 `traces_added`、`rumors` 与 `rumors_added` 同时存在。

裁决：正式 schema 只保留 `*_added` 形式。兼容适配器可以短期读取旧名，但 Store 与存档不得双存。

## 5. 术语裁决

### 5.1 属性 Attribute

定义：角色广泛适用的基础能力数值，例如力量、敏捷、智慧、魅力、体质、感知。

归属：带类型和范围定义的角色 `StateStore` 状态。

正例：感知 10 使角色更容易发现门槛上的新鞋印。

反例：连续三次巡逻带来的熟练度不是属性，应进入技艺进度。

### 5.2 天赋 Talent

定义：先天、出身或极难改变的潜能与感知方式。通常在角色生成时获得，运行中很少新增或移除。

归属：角色特征 Store 中的 `TalentAssignment`。

正例：夜视血统使黑暗不再完全阻断观察。

反例：“感知 +2”单独存在不是合格天赋；它必须同时改变资格、感知方式或代价结构。

### 5.3 特质 Trait

定义：相对稳定，但可因经历、伤病、身份或社会变化而获得、恶化、转化或消失的规则性条件。

归属：角色特征 Store 中的 `TraitInstance`。

正例：扭伤脚踝影响长途移动风险，经过休养可以恢复。

反例：当前健康 88 是短期状态，不是特质。

### 5.4 印记 Mark

定义：由可追溯经历形成的持久证据，强调来源事实、积累阶段和长期回声。

归属：角色特征 Store 中的 `MarkInstance`。

正例：深入雾盐井后留下的回响，来源于实际挑战事实，并在未来地点和人物反应中生效。

反例：UI 点击“选择雾盐印记”后直接获得，不符合印记定义。

### 5.5 技艺 Skill

定义：通过练习和使用逐步形成的领域能力，例如侦察、弓术、修缮、野外采集。

归属：角色特征 Store 中的 `SkillProgress`。

正例：完成巡逻、辨认痕迹和复盘失败后，侦察实践积累。

反例：第一冬所有职责共同增加一个无领域含义的 `training` 数值，不能直接当作技艺系统。

### 5.6 状态 State

定义：某实体当前可覆盖、可增减、通常不需要独立身份的值。

正例：健康、疲劳、饥饿、可见性、地点 ID、哨站士气。

反例：有独立来源、阶段和生命周期的伤势或印记不应永远压成一个字符串状态。

### 5.7 事实 Fact

定义：世界中已经发生、可被其他系统引用的一次确定记录。

正例：玩家在第 3 天完成雾线巡逻；陈米在某时刻认出了粮牌。

反例：疲劳为 6 是当前状态，不是事实。可以另写“因夜岗增加疲劳”的事实。

### 5.8 记忆 Memory

定义：某个角色对事实的持有、理解或主观印象。

正例：陈米记得玩家把粮牌带回来，并因此改变信任。

反例：不能用记忆替代事实本身，也不能假定所有 NPC 自动拥有所有事实。

### 5.9 物品与装备

`ItemDef` 是不可变定义，回答“这类东西是什么”。

`ItemInstance` 是世界实例，回答“这一件东西现在在哪里、状态如何、经历过什么”。

`EquipmentLoadout` 只保存角色各装备位引用了哪个物品实例。装备属性、耐久、来源和历史仍属于 `ItemInstance`。

“背包”是按 holder 查询得到的视图，不是第四套物品所有权数据。

### 5.10 商店与经济

商店是以下数据的投影：

- 商人或地点实际持有的可售 `ItemInstance`；
- 地区 `PressureStore`；
- 商人状态与营业策略；
- 双方关系与制度规则；
- 当前世界时间。

静态商品表可以作为商人生成初始库存的定义，但不能成为运行中库存真值。

## 6. 唯一真值表

| 数据 | 唯一真值 | 只读投影或引用 |
| --- | --- | --- |
| 实体身份与类型 | `EntityStore` | Snapshot 实体卡片 |
| 当前标量状态与基础属性 | `StateStore` | `Snapshot.player`、实体 `states` |
| 天赋、特质、印记、技艺进度 | 新角色特征 Store | `CharacterProgress` 投影 |
| 世界事实 | `FactStore` | 记忆来源、纪事来源、结果反馈 |
| 角色记忆 | `MemoryStore` | NPC 反应与叙事视图 |
| 关系轴 | `RelationshipStore` | 关系层级、候选解释 |
| 物品位置、数量、耐久、历史 | `ItemStore` | Inventory、Equipment、MarketStock 视图 |
| 装备位占用 | 新 `EquipmentStore` | 角色面板与行动修正 |
| 地区和机构数值 | 以地区或机构实体 ID 写入 `StateStore` | Region、Institution 视图 |
| 资源压力 | `PressureStore` | 价格因子、NPC 动机、地区摘要 |
| 债务与承诺 | `ObligationStore`、`ExchangeStore` | 商店赊账与社会后果 |
| 世界时间 | Session 时钟，进入 SaveEnvelope | Snapshot 时间投影 |
| 长期项目游标 | LifeProject runtime，进入 SaveEnvelope | `service_day` 等 UI 投影 |
| 调试事务记录 | `SimWorldLog` | 报告和测试，不参与规则真值 |
| 行动候选 | 每次从 Snapshot 生成 | 不存档 |

## 7. 现有字段迁移裁决

| 当前字段 | 当前含义 | 目标归属 | 处理 |
| --- | --- | --- | --- |
| `player.inventory_item_ids` | 玩家持有物品 ID | `ItemStore.holder` 查询 | 淘汰，不再写入 |
| `player.food_count` | 抽象口粮数量 | 可堆叠口粮 `ItemInstance.quantity` | 兼容读取后迁移；旅行消耗改写物品事务 |
| `player.injury` | 单个伤势字符串 | `TraitInstance` 或伤势条件实例 | 迁移为有来源与阶段的特质；健康仍留在状态 |
| `player.mist_salt_echo` | 不可逆经历回声 | `MarkInstance` | 由 `actor_acquired_mist_salt_echo` 等事实生成 |
| `player.training` | 第一冬职责累计值 | LifeProject 临时指标与具体 `SkillProgress` 分开 | 不直接迁成单一技能；按职责事实分别授予实践进度 |
| `player.last_duty` | 最近职责 ID | 最近职责事实的派生值 | 不持久化，按事实查询 |
| `player.service_day` | 第一冬日序 | LifeProject runtime 游标 | 从角色状态移出，UI 可继续显示投影 |
| `seventh_outpost.supply` | 抽象后勤储备 | 明确命名的机构状态加实际物品库存 | 保留后勤压力含义但改名；具体木料、粮食不得只扣该值 |
| NPC `food_stock` | 食物数量 | NPC holder 下的食物堆叠实例 | 迁移 |
| NPC `coin_count` | 货币数量 | 最小货币单位的物品堆叠或明确钱包账户 | Demo 优先使用物品堆叠；债务进入 Exchange/Obligation |
| `shop_policy` | 是否营业 | 商人或商店实体状态 | 保留并注册 StateDef |
| `region_state` | 地区标量字典 | 地区实体的 `StateStore` 状态 | 迁移后只保留 Snapshot 视图 |
| `institution` | 制度标量字典 | 机构实体的 `StateStore` 状态 | 迁移后只保留 Snapshot 视图 |
| `known_facts` | 事实副本 | `FactStore` 与 `MemoryStore` | 淘汰 |
| `WorldState.inventory` | 旧运行库存 | 旧版隔离 | 不同步到 v5，不新增依赖 |

## 8. 保留架构与新增边界

### 8.1 保留

- Store 持有运行真值。
- Snapshot 提供不可变读取面。
- Affordance 从世界状态生成候选。
- Resolver 只生成事务结果。
- Writer 是唯一落地入口。
- Fact、Memory、Trace、Relationship、Pressure、Obligation、Exchange、Chronicle 各自保留领域职责。

### 8.2 新增

- 统一 Raw Definition 注册与校验。
- 角色特征 Store，分别保存天赋指派、特质实例、印记实例和技艺进度。
- EquipmentStore，只保存装备位到物品实例的引用。
- 通用 requirement、modifier、effect 协议。
- 原子事务预检。
- SaveEnvelope、迁移注册表和引用完整性校验。

### 8.3 不新增

- 不新增独立可写 `InventoryStore`。
- 不新增与 ItemStore 重复的商店库存字典。
- 不新增与 StateStore 重复的 Region 标量 Store。
- 不把 `CharacterProgress` 做成复制所有角色数据的第二真值。
- 不让 UI 直接写入印记、技能、库存或装备状态。

## 9. 步骤 2 的实施输入

下一步以 `CHRONICLE_CORE_SYSTEM_MINIMUM_SCHEMAS_v5.1.md` 为实现草案，先完成：

1. Raw 定义与运行实例的稳定 ID 规则。
2. `CharacterProgress` 只读投影，以及角色特征实例 Store。
3. `ItemInstance.holder` 与堆叠规则。
4. `EquipmentLoadout` 引用规则。
5. `InventoryView` 与 `MarketStockView` 派生规则。
6. SaveEnvelope 中所有持久化 Store 的边界。

在这些 schema 通过 fixture 校验前，不接入完整数值平衡，也不扩写第七哨站第二年。

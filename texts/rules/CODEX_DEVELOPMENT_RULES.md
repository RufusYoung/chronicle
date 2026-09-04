# Chronicle Codex 开发规则

**文档定位**：Codex / AI 编程协作者必须遵守的工程规则
**依赖总纲**：`texts/CHRONICLE_CORE_DESIGN_GUIDE.md`
**版本**：v0.1
**日期**：2026-06-13

---

## 1. 本文档的作用

本文档用于约束 Codex 在 Chronicle 项目中的开发行为。

Chronicle 不是普通文字 RPG，不是事件池抽卡游戏，也不是靠 AI 文案支撑的随机故事生成器。

Codex 在任何开发任务开始前，应先读取：

```text
texts/CHRONICLE_CORE_DESIGN_GUIDE.md
texts/specs/DEMO_SCOPE_SPEC.md
texts/specs/WORLD_STATE_SCHEMA.md
texts/rules/CODEX_DEVELOPMENT_RULES.md
当天 log 指令文件
```

如果这些文档与任务指令冲突，优先级为：

```text
用户最新明确指令
↓
当天 log 指令
↓
CODEX_DEVELOPMENT_RULES.md
↓
CHRONICLE_CORE_DESIGN_GUIDE.md
↓
具体规格文档
↓
旧代码和旧文档
```

---

## 2. 项目核心方向

Chronicle 的核心方向是：

```text
世界先自我运转
↓
世界状态产生事实
↓
事实留下痕迹
↓
痕迹被投影为线索和场景
↓
玩家在关键节点选择
↓
选择写回世界
↓
世界继续演化
↓
多年后产生回声和纪事
```

任何新增功能都必须服务这条链。

---

## 3. 最高禁止事项

### 3.1 禁止事件池抽卡作为核心玩法

禁止实现以下结构：

```text
随机抽事件
↓
显示三个选项
↓
加属性 / 扣血 / 给装备
↓
继续抽事件
```

如果需要事件，也必须来自：

```text
WorldFact
Trace
RegionState
NPCState
FactionState
LifePhase
```

每个重要事件都必须有来源字段：

```text
world_cause
source_fact_id
source_trace_id
related_region_id
```

---

### 3.2 禁止没有来源的线索

所有线索必须来自世界状态。

错误：

```text
随机生成“远处有烟柱”
```

正确：

```text
粮食短缺
走私者劫粮
边境镇秩序下降
某处营地起火
↓
生成烟柱线索
```

线索对象必须保留：

```text
world_cause
related_fact_id / source_fact_id
source_region_id
source_faction_id 或 source_npc_id
```

---

### 3.3 禁止 AI 或模板决定世界事实

AI 和模板只能负责表达。

禁止 AI / 文本模板决定：

```text
谁死了
谁背叛了
谁爱上谁
战争胜负
NPC 是否原谅玩家
玩家获得什么物品
地区是否毁灭
势力是否胜利
```

这些必须由世界模拟层和规则层决定。

---

### 3.4 禁止 UI 层决定事实

UI 只能展示和提交玩家选择。

UI 不得直接修改重大世界事实。

错误：

```text
按钮点击后直接生成“罗恩死亡”
```

正确：

```text
按钮提交 Action
↓
规则层结算
↓
世界层写入 WorldFact
↓
表现层读取事实并显示结果
```

---

### 3.5 禁止玩家行为只改文本

玩家选择必须至少修改以下一类：

```text
RegionState
NPCState
FactionState
RelationshipState
WorldFact
Trace
Memory
LifePhase
ChronicleEntry
```

重要选择必须修改两类以上。

---

### 3.6 禁止长期玩法变成奖励结算

错误：

```text
你服役五年。
力量 +1，体质 +1，金币 +50。
```

正确：

```text
五年里，点名少了三个人。
伊莱不再提他的未婚妻。
罗恩把旧短刀留给你。
你获得【边境老兵】，但夜里再也睡不沉。
```

长期模式必须包含：

```text
固定人物变化
重复仪式变化
身体或性格变化
地点变化
错过感
离别或回归
纪事记录
```

---

## 4. 新增代码规则

### 4.1 新系统必须说明属于哪一层

新增系统前必须说明它属于：

```text
世界层
规则层
表现层
纪事层
工具层
```

不得混写。

### 4.2 新增字段必须说明用途

新增状态字段时，必须说明：

```text
字段含义
谁修改它
谁读取它
它如何影响线索 / 选项 / 纪事
```

### 4.3 新增事件必须有因果链

新增任何事件或场景前，必须写明：

```text
原因状态
实体行为
留下痕迹
玩家如何看见
可选行动
后果写回
未来回声
```

如果写不出，不应加入核心玩法。

### 4.4 新增选项必须来自可行动性

选项不得只是：

```text
稳
赌
退
```

选项应来自：

```text
玩家物品
玩家属性
玩家印记
NPC 状态
地区状态
关系
法律
风险
可见痕迹
```

示例：

```text
给她食物
买下麦子
问粮食从哪来的
举报给守卫
进去找老陈
装作没看见
低价收购
```

### 4.5 世界真实感必须能反推运行机制

场景中的生活细节、跨地变化和人物反应不能只是氛围描写。开发时必须能够从可见结果反查到实际规则：

```text
日常细节 → 资源、技艺、习俗或制度来源
跨地变化 → 路线、货物、迁徙、消息或组织决策
人物反应 → 身份、利益、信念、关系、记忆与当前约束
文明摩擦 → 双方真实目标、交换物、损失与适应
```

作者可以压缩前台信息，但不能用“世界似乎在变化”的文本代替 State、Fact、Item、Relationship、Exchange 或其他正式真值。外部文章和参考作品只能提出设计假设；在代码、测试或真实试玩产生证据前，不得把假设标成已完成。

玩家不是世界的默认中心。没有玩家介入时，规则仍应运行；玩家介入时，身份、时间、财产、关系和风险决定其能够改变什么。

---

## 5. 文件与目录规则

### 5.1 根目录 texts

根目录：

```text
C:\code\game\chronicle\texts\
```

用于存放项目级长期设计文档。

包括：

```text
CHRONICLE_CORE_DESIGN_GUIDE.md
specs/
rules/
```

这些文档约束整个项目。

### 5.2 Godot 项目 texts

Godot 子项目：

```text
C:\code\game\chronicle\chronicle-godot\texts\
```

用于存放实现报告、Godot 子项目结构说明、阶段报告、ADR、计划。

不要混淆两个 `texts` 目录。

### 5.3 log 目录

```text
C:\code\game\chronicle\log\
```

用于每日 Codex 指令。

命名规则：

```text
YYYY-MM-DD.N.md
```

例如：

```text
2026-06-13.1.md
2026-06-13.2.md
2026-06-13.3.md
```

同一天第几次指令，就用点号后的数字表示。

Codex 每次执行任务前，应读取当天最新指令文件。

---

## 6. 当前代码保护规则

除非用户明确要求，否则不要修改：

```text
chronicle-godot/素材包/
chronicle-godot/data/
chronicle-godot/scenes/ui/story_player.gd
chronicle-godot/scripts/gen/world_generation_v03.gd
chronicle-godot/project.godot
```

归档内容不要恢复依赖：

```text
chronicle-godot/_archive/
```

尤其不要恢复或继续扩展：

```text
_archive/damaged_or_legacy_scripts/world_generation.gd
```

---

## 7. 测试规则

### 7.1 世界模拟测试

世界模拟必须能无 UI 运行。

至少验证：

```text
同 seed 可复现
无玩家干预世界会变化
模拟干预会改变后续世界
线索有 world_cause
事实有 source / cause
```

### 7.2 线索适配测试

所有适配后的线索必须有：

```text
type
target
direction
freshness
risk
world_cause
related_fact_id
origin
```

### 7.3 Demo 测试

接入 UI 前必须先通过无头测试。

不要边写 UI 边验证世界核心。

---

## 8. 报告规则

每次任务完成后，必须输出报告。

报告放在：

```text
chronicle-godot/texts/reports/2026/
```

命名：

```text
YYYY-MM-DD_task_name_report.md
```

报告至少包含：

```text
本次目标
新增文件
修改文件
未修改的保护文件
测试方式
测试结果
是否满足验收标准
当前局限
下一步建议
```

报告中如果有测试注入行为，必须称为：

```text
测试注入
模拟干预
A/B 对照行为
```

不得称为“玩家选择”，除非该行为确实来自 UI 操作。

---

## 9. 分支与提交规则

每个独立任务使用独立分支。

命名示例：

```text
exp/project-cleanup-before-world-sim
exp/world-sim-mvp
exp/world-sim-lead-adapter
exp/demo-scope-lake-town
exp/life-phase-military-service
```

提交信息示例：

```text
chore: clean legacy files before world sim refactor
feat: add world sim mvp core
feat: add world sim lead adapter
feat: add lake town food crisis chain
feat: add military service life phase prototype
```

不要把清理、世界模拟、UI、事件内容混在一次提交里。

---

## 10. 当前阶段优先级

当前阶段优先级为：

```text
P0：世界状态与事实链
P1：痕迹 / 线索投影
P2：玩家行动写回世界
P3：人生模式原型
P4：纪事回收
P5：UI 展示
P6：战斗、装备、成长、美术、音频
```

不要提前做 P5 / P6。

---

## 11. 任务开始前自检

Codex 每次任务开始前必须回答：

```text
本任务属于哪一层？
是否会影响世界事实？
是否会生成线索？
线索是否有来源？
玩家行为是否会写回世界？
是否需要修改 UI？
是否违反核心总纲？
```

如果答案不清楚，先输出计划，不要直接改代码。

---

## 12. 任务完成后自检

Codex 每次任务完成后必须回答：

```text
新增了哪些世界事实？
新增了哪些痕迹或线索？
是否有 world_cause？
是否有测试？
是否修改了保护文件？
是否把测试注入误写成玩家行为？
是否生成报告？
```

---

## 13. 最终原则

Chronicle 的开发不是“多做几个系统”。

每个系统都必须服务：

```text
状态 → 行为 → 痕迹 → 选择 → 后果 → 回声 → 纪事
```

如果一个功能不能进入这条链，它就不是当前阶段的优先事项。

Chronicle 的目标不是内容多。

Chronicle 的目标是：

> 一个很小的世界，也能让玩家相信自己在那里生活过。

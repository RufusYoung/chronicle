# Chronicle 项目级文档索引

## 1. 文档定位

根目录 `texts/` 存放 Chronicle 项目级长期设计文档。

这些文档约束整个 Chronicle 项目方向，不只约束 Godot 子项目。

Godot 子项目内部的实现报告、阶段报告和工程结构说明，放在：

`chronicle-godot/texts/`

不要混淆两个 `texts` 目录。

---

## 2. Codex 开发前必读文档

任何 Codex 开发任务开始前，必须先读取：

1. `texts/CHRONICLE_CORE_DESIGN_GUIDE.md`
2. `texts/specs/DEMO_SCOPE_SPEC.md`
3. `texts/specs/WORLD_STATE_SCHEMA.md`
4. `texts/rules/CODEX_DEVELOPMENT_RULES.md`
5. 当天最新 `log/YYYY-MM-DD.N.md`

---

## 3. 四份核心文档说明

### `CHRONICLE_CORE_DESIGN_GUIDE.md`

项目最高方向文档。

用于回答 Chronicle 是什么、不是什么、玩家怎么玩、世界层与表现层如何分工、Demo 如何验证。

### `specs/DEMO_SCOPE_SPEC.md`

Demo 范围规格。

用于限定 Demo 阶段只验证湖湾镇、第七哨站、定居、服役、粮食危机、长期离别和纪事回收。

### `specs/WORLD_STATE_SCHEMA.md`

世界状态数据结构规格。

用于定义 `WorldState`、`RegionState`、`NPCState`、`WorldFact`、`Trace`、`Memory`、`LeadCandidate`、`LifePhase`、`ChronicleEntry` 等核心对象。

### `rules/CODEX_DEVELOPMENT_RULES.md`

Codex 工程规则。

用于禁止事件池抽卡、禁止无来源线索、禁止 AI 决定世界事实、禁止 UI 层直接决定事实。

---

## 4. 参考讨论档案

### `references/Chronicle_gameplay_mechanics_discussion_until_AI.md`

该文件保存早期完整玩法机制讨论，包括：

- Chronicle 与《矮人要塞》《冒险生活》的分工关系
- 老陈女儿藏发霉麦子的状态链示例
- Trace 痕迹系统
- 可叙述状态系统 Narratable State System
- NPC 按需唤醒与延迟结算
- 三层世界模拟
- 长期人生模式与边境服役五年结构
- 后期短文本 AI 文学翻译器方向

该文件是设计源材料，不是每次开发任务的必读文件。

只有在以下任务中需要读取：

- 扩展核心玩法机制
- 设计人生模式
- 设计痕迹系统
- 设计可叙述状态系统
- 设计 NPC 按需唤醒
- 设计 AI 叙事层
- 检查项目是否走偏

---

## 5. log 指令文件命名规则

Codex 指令放在：

`log/`

命名规则：

`YYYY-MM-DD.N.md`

例如：

- `2026-06-13.1.md`
- `2026-06-13.2.md`
- `2026-06-13.3.md`
- `2026-06-13.4.md`

同一天第几次指令，就用点号后的数字表示。

---

## 6. 当前最高原则

Chronicle 的核心链条是：

```text
状态 → 行为 → 痕迹 → 选择 → 后果 → 回声 → 纪事
```

任何系统如果不能进入这条链，就不是当前阶段优先事项。

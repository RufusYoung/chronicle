# Chronicle v5 文档索引

## 1. 当前文档定位

### Chronicle Game Design Document.md

当前 v5 主 GDD 的用户保存版。  
该文件来源于“重构版游戏设计文档：系统架构版”，用户已将版本号调整为 v5，并作为当前 v5 文件夹中的主 GDD 保存。

用途：

- 作为当前 v5 主 GDD 的阅读入口之一
- 保留完整的系统架构版设计文本
- 便于用户直接查看、编辑和继续扩写总纲
- 与 `CHRONICLE_GDD_v5.1_REBUILD.md` 共同构成当前 v5.1 重构设计依据

注意：

- 它不是旧版历史 GDD
- 不应再标记为“旧总纲”或“历史版本”
- 若与 `CHRONICLE_GDD_v5.1_REBUILD.md` 存在重复内容，后续可再决定合并、保留或改名

---

### CHRONICLE_GDD_v5.1_REBUILD.md

当前主 GDD。  
用于回答“Chronicle 到底是什么、玩家怎么玩、世界如何与人生结构连接”。

用途：

- 当前设计总纲
- 前台玩法结构
- 主界面设计
- 生涯、线索、地点、状态、成长、长期项目、传记等核心规则
- 后续所有系统文档的设计依据

---

### CHRONICLE_SYSTEM_MODULES_v5.1.md

当前系统模块拆分文档。  
用于回答“系统怎么拆、代码怎么搭、模块之间如何分工”。

用途：

- 指导后续重构开发
- 约束模块边界
- 防止所有功能混在一起
- 作为 Codex 执行任务前必须阅读的系统架构入口

---

### CHRONICLE_REBUILD_ROADMAP_v5.1.md

当前重构执行路线图。

用于记录已完成阶段、当前阶段、顺序调整与各阶段验收标准。

### CHRONICLE_CORE_SYSTEM_CONTRACT_PLAN_v5.1.md

当前优先执行的系统合同前置计划。

用于定义成长、天赋、特质、印记、技艺、物品装备、经济、统一结算与存档的最小边界。

该计划不要求现在完成全部系统内容与数值平衡。它要求在继续扩写第七哨站年份内容前，先让核心系统通过同一数据合同进入湖湾镇与第一冬。

---

## 2. 推荐阅读顺序

后续讨论、写规格、让 Codex 执行前，优先按以下顺序阅读：

1. `CHRONICLE_GDD_v5.1_REBUILD.md`
2. `CHRONICLE_SYSTEM_MODULES_v5.1.md`
3. `CHRONICLE_REBUILD_ROADMAP_v5.1.md`
4. `CHRONICLE_CORE_SYSTEM_CONTRACT_PLAN_v5.1.md`
5. 当前阶段的具体系统规格
6. `Chronicle Game Design Document.md`

说明：

- `CHRONICLE_GDD_v5.1_REBUILD.md` 是当前重构讨论后的主执行依据。
- `CHRONICLE_SYSTEM_MODULES_v5.1.md` 是当前系统拆分与开发架构依据。
- `Chronicle Game Design Document.md` 是用户保存的 v5 主 GDD 文本，后续可根据需要与 v5.1 重构文档合并或改名。

---

## 3. 后续文档扩展规则

不要把所有内容继续塞进一个大 GDD。

后续每细化一个系统，单独新建一个系统规格文档。

建议命名：

```text
CHRONICLE_REBUILD_ROADMAP_v5.1.md
CHRONICLE_LOCATION_UI_FLOW_v5.1.md
CHRONICLE_LIFE_PROJECT_SYSTEM_v5.1.md
CHRONICLE_RELATIONSHIP_RUMOR_SYSTEM_v5.1.md
CHRONICLE_ATTRIBUTE_STATE_SYSTEM_v5.1.md
CHRONICLE_COMBAT_SYSTEM_v5.1.md
CHRONICLE_EQUIPMENT_SYSTEM_v5.1.md
CHRONICLE_FOOD_SKILL_SYSTEM_v5.1.md
CHRONICLE_CHRONICLE_OUTPUT_SYSTEM_v5.1.md
```

写到哪个系统，再细化哪个系统。
不要一次性把所有系统文档都写完。

---

## 4. 当前开发原则

当前阶段采用“文档定方向，开发按模块逐步落地”。

开发顺序原则：

```text
总 GDD 定游戏是什么
↓
系统模块文档定系统怎么拆
↓
当前阶段规格文档定这一次做什么
↓
Codex 只执行这一小块
↓
测试
↓
写报告
↓
进入下一块
```

不要直接让 Codex 根据整个 GDD 一次性重构游戏。

---

## 5. 当前推荐下一步

截至 2026-08-12，湖湾镇调查闭环与第七哨站第一冬七日生活单元已经可以运行。当前暂停扩写第二年至第五年，先执行：

```text
texts/v5/CHRONICLE_CORE_SYSTEM_CONTRACT_PLAN_v5.1.md
```

第一项工作是审计现有数据合同，裁决属性、天赋、特质、印记和技艺的边界，并输出最小 schema 草案。

---

## 6. Codex 执行约束

在没有明确指令前，不要修改以下内容：

```text
chronicle-godot/scenes/ui/story_player.gd
chronicle-godot/scripts/gen/world_generation_v03.gd
chronicle-godot/scenes/ui/mainui.tscn
chronicle-godot/project.godot
chronicle-godot/素材包/
```

当前阶段的可修改范围由最新用户指令、路线图和具体系统计划共同决定，不再使用第 0 步的旧文件限制。

---

## 7. 当前阶段目标

让核心系统拥有统一、可保存、可解释的合同，并在已有可玩流程中验证。当前不以增加更多年份文本或独立演示场景作为进度。

# Chronicle 设计文档总索引

整理日期：2026-09-30。项目已按用户要求暂停开发。配套：[项目现状与暂停报告](C:/code/game/chronicle/texts/reports/2026/2026-9/2026-9-30/2026-09-30_project_pause_report.md)。

本索引列出之前的设计资料，帮助重新讨论方向，不把历史文档重新变成开发指令。条目存在不等于功能已实现；本次核对了路径，并阅读核心设计及相关关键段落，没有逐字重审全部历史原稿。运行现状以配套报告的证据边界为准。

## 1. 先读这七份

| 文档 | 用途与地位 |
| --- | --- |
| [核心设计总纲](C:/code/game/chronicle/texts/CHRONICLE_CORE_DESIGN_GUIDE.md) | 最直接的目标说明，包含对固定事件选择循环的警惕 |
| [创作方向指导](C:/code/game/chronicle/texts/CHRONICLE_CREATIVE_DIRECTION_GUIDE.md) | 矮人要塞、冒险生活、来自深渊、芙莉莲与奥德赛分别贡献什么；个别 UI 实施原则已有负面反馈，不能视为不可修改 |
| [v5 系统架构 GDD](<C:/code/game/chronicle/texts/v5/Chronicle Game Design Document.md>) | 世界、人物、事件呈现与人生结构的总体设计 |
| [v5.1 重建 GDD](C:/code/game/chronicle/texts/v5/CHRONICLE_GDD_v5.1_REBUILD.md) | 后续重建基线，事件是世界状态的呈现，不等于已完成实现 |
| [原设定世界基础](C:/code/game/chronicle/texts/v5/CHRONICLE_CANON_WORLD_FOUNDATION_v5.1.md) | 从原历史、地区和势力衔接当前生成世界，标明未解冲突 |
| [世界模拟架构](C:/code/game/chronicle/texts/v5/CHRONICLE_WORLD_SIM_ARCHITECTURE_v5.1.md) | 对象、行为、规则、记忆、事实与前台呈现如何分工 |
| [世界优先计划](C:/code/game/chronicle/texts/v5/CHRONICLE_WORLD_FIRST_PLAN_v5.1.md) | RF1–RF8 的唯一执行计划；现已暂停，历史“下一步”不构成恢复授权 |

本次用户要求的“把自运行世界的表层用文字表现出来，人只做决策”，与前述核心设计相容。不能解释为用户之前一直没有说明目标。

## 2. 历代总体设计

### v1：最初构想与模块拆分

| 文档 | 查阅主题 |
| --- | --- |
| [大纲](C:/code/game/chronicle/texts/v1/大纲.md) | 最早的整体游戏构想 |
| [蓝图](C:/code/game/chronicle/texts/v1/蓝图.md) | 系统蓝图；文件在 v1 目录，正文自称蓝图 v3，不能只按文件夹推断版本 |
| [地区、地点](C:/code/game/chronicle/texts/v1/地区、地点.md) | 地理层次与地点组织 |
| [地点 JSON 格式](C:/code/game/chronicle/texts/v1/地点json格式.md) | 早期地点数据表达 |
| [界面设计](C:/code/game/chronicle/texts/v1/界面设计.md) | 原始前台信息与操作构想，不能等同于当前漫游 UI |
| [生成器设计](C:/code/game/chronicle/texts/v1/生成器设计.md) | 生成器与内容组织构想 |
| [Core Algorithms](C:/code/game/chronicle/texts/v1/Core_Algorithms.md) | 早期算法设计 |
| [Data Schemas](C:/code/game/chronicle/texts/v1/Data_Schemas.md) | 早期数据模式 |
| [System Interactions](C:/code/game/chronicle/texts/v1/System_Interactions.md) | 系统之间的关系 |
| [Balancing Playbook](C:/code/game/chronicle/texts/v1/Balancing_Playbook.md) | 数值、平衡和调试思路 |

还保留九份 TXT 稿。未逐一做内容一致性比较，不因同名而认为它们与 Markdown 完全相同：

- [大纲.txt](C:/code/game/chronicle/texts/v1/txt/大纲.txt)、[蓝图.txt](C:/code/game/chronicle/texts/v1/txt/蓝图.txt)、[地区、地点.txt](C:/code/game/chronicle/texts/v1/txt/地区、地点.txt)。
- [地点 JSON 格式.txt](C:/code/game/chronicle/texts/v1/txt/地点json格式.txt)、[界面设计.txt](C:/code/game/chronicle/texts/v1/txt/界面设计.txt)。
- [Core Algorithms.txt](C:/code/game/chronicle/texts/v1/txt/Core_Algorithms.txt)、[Data Schemas.txt](C:/code/game/chronicle/texts/v1/txt/Data_Schemas.txt)、[System Interactions.txt](C:/code/game/chronicle/texts/v1/txt/System_Interactions.txt)、[Balancing Playbook.txt](C:/code/game/chronicle/texts/v1/txt/Balancing_Playbook.txt)。

### v2 至 v5.1：设计演进

| 文档 | 查阅主题与边界 |
| --- | --- |
| [GDD v2](<C:/code/game/chronicle/texts/v2/GDD v2.MD>) | 早期整合设计，含事件 DSL、优先级和事件池思路；不能覆盖后来世界优先的设计约束 |
| [GPT 使用策略](C:/code/game/chronicle/texts/v2/gpt使用策略.md) | 历史工具策略，不是当前模型推荐或可用性依据 |
| [矮人要塞与冒险生活的设计解析 DOCX](<C:/code/game/chronicle/texts/v2/矮人要塞 vs. 冒险生活：自运行游戏世界的设计解析.docx>) | 旧研究文档，路径已核实；本次没有重新提取和审阅其正文 |
| [GDD v3](<C:/code/game/chronicle/texts/v3/gdd v3.md>) | 中期总体方案 |
| [v4 目录中的 GDD](C:/code/game/chronicle/texts/v4/gdd.md) | 正文自称 v5.0 Final；正文日期不是本次核验的创建日期，不应凭路径和标题自动决定权威性 |
| [Chronicle Game Design Document](<C:/code/game/chronicle/texts/v5/Chronicle Game Design Document.md>) | 系统架构总体稿，与当前核心指导一起理解长期目标 |
| [v5.1 Rebuild GDD](C:/code/game/chronicle/texts/v5/CHRONICLE_GDD_v5.1_REBUILD.md) | 重建后的设计基线，具体执行受当前计划约束 |

## 3. 原始大世界、历史、地区与势力

这些是用户先期建立的设定，不应被界面原型中的湖湾镇、第七哨站取代。原稿与后续合同有冲突时先明确冲突，不静默重写设定。正式实现衔接入口仍是[原设定世界基础](C:/code/game/chronicle/texts/v5/CHRONICLE_CANON_WORLD_FOUNDATION_v5.1.md)。

### 世界背景与历史

| 原稿 | 内容范围 |
| --- | --- |
| [历史](C:/code/game/chronicle/texts/v1/txt/回响之境/神话、传说、历史/历史.txt) | 神话、传说、帝国、列国等时代背景 |
| [苍穹之痕传说](C:/code/game/chronicle/texts/v1/txt/回响之境/神话、传说、历史/苍穹之痕传说.txt) | 世界重要历史与传说锚点 |
| [势力分布](C:/code/game/chronicle/texts/v1/txt/回响之境/势力分布/势力.txt) | 各地势力原始设定；有条目不等于已运行的自主政治实体 |

### 六大地区

| 地区 | 原稿 |
| --- | --- |
| 北部，永夜与霜语之地 | [设定](C:/code/game/chronicle/texts/v1/txt/回响之境/地区/北部-永夜与霜语之地/设定.txt) |
| 东部海岸，千帆湾 | [设定.yxt](<C:/code/game/chronicle/texts/v1/txt/回响之境/地区/东部海岸 - 千帆湾/设定.yxt>)；原文件扩展名确为 `.yxt`，本次不改名 |
| 南部界域，悲歌与烈阳 | [南部设定](<C:/code/game/chronicle/texts/v1/txt/回响之境/地区/南部界域 - 悲歌与烈阳/南部设定.txt>) |
| 西部海岸，终末之海岸 | [设定](<C:/code/game/chronicle/texts/v1/txt/回响之境/地区/西部海岸 - 终末之海岸/设定.txt>) |
| 中央界域，苍穹之痕 | [设定](<C:/code/game/chronicle/texts/v1/txt/回响之境/地区/中央界域 - 苍穹之痕/设定.txt>) |
| 中央偏北界域，碎星与镜湖 | [设定](<C:/code/game/chronicle/texts/v1/txt/回响之境/地区/中央偏北界域 - 碎星与镜湖/设定.txt>) |

### 镜湖周边的地点原稿与数据

除 MD/TXT 外保留这些世界设计数据，它们不是新的运行时配置：

- [镜湖本体](<C:/code/game/chronicle/texts/v1/txt/回响之境/地区/中央偏北界域 - 碎星与镜湖/镜湖沿岸/镜湖/镜湖本体/mirror lake.txt>)。
- [镜湖森林带总定义](<C:/code/game/chronicle/texts/v1/txt/回响之境/地区/中央偏北界域 - 碎星与镜湖/镜湖森林带/境湖森林带.json>)。文件名为“境湖森林带”，保留原名。
- [沉默森林](<C:/code/game/chronicle/texts/v1/txt/回响之境/地区/中央偏北界域 - 碎星与镜湖/镜湖森林带/沉默森林 - Forest of Silence/沉默森林.json>)。
- [倒影之森](<C:/code/game/chronicle/texts/v1/txt/回响之境/地区/中央偏北界域 - 碎星与镜湖/镜湖森林带/倒影之森 - Forest of Echoing Reflections/倒影之森.json>)。
- [梦境之崖](<C:/code/game/chronicle/texts/v1/txt/回响之境/地区/中央偏北界域 - 碎星与镜湖/镜湖森林带/倒影之森 - Forest of Echoing Reflections/梦境之崖 - Cliffs of the Dreamrealm/梦境之崖.json>)。
- [光灭森林](<C:/code/game/chronicle/texts/v1/txt/回响之境/地区/中央偏北界域 - 碎星与镜湖/镜湖森林带/光灭森林 - Forest of Dying Light/光灭森林.json>)。
- [遗忘之森](<C:/code/game/chronicle/texts/v1/txt/回响之境/地区/中央偏北界域 - 碎星与镜湖/镜湖森林带/遗忘之森 - Forest of the Forgotten/遗忘之森.json>)。
- [碎星山脉区域](<C:/code/game/chronicle/texts/v1/txt/回响之境/地区/中央偏北界域 - 碎星与镜湖/碎星山脉区域/碎星山脉区域.json>)。

## 4. v5.1 架构与系统合同

“合同”是实现和验收约束，不是独立的新一轮，也不是功能完成证书。现行计划之外的旧排序只是演进记录。

### 总体结构与数据能力

| 文档 | 主题 |
| --- | --- |
| [System Modules](C:/code/game/chronicle/texts/v5/CHRONICLE_SYSTEM_MODULES_v5.1.md) | 模块职责 |
| [World Sim Architecture](C:/code/game/chronicle/texts/v5/CHRONICLE_WORLD_SIM_ARCHITECTURE_v5.1.md) | 世界运行架构 |
| [World Integration Contract](C:/code/game/chronicle/texts/v5/CHRONICLE_WORLD_INTEGRATION_CONTRACT_v5.1.md) | 系统共同运行与因果要求 |
| [Raw Object Rule System](C:/code/game/chronicle/texts/v5/CHRONICLE_RAW_OBJECT_RULE_SYSTEM_v5.1.md) | 底层对象、材料、能力和规则定义 |
| [Content Extension Contract](C:/code/game/chronicle/texts/v5/CHRONICLE_CONTENT_EXTENSION_CONTRACT_v5.1.md) | 内容扩展的实现边界 |
| [Core System Minimum Schemas](C:/code/game/chronicle/texts/v5/CHRONICLE_CORE_SYSTEM_MINIMUM_SCHEMAS_v5.1.md) | 核心数据最小结构 |
| [Core System Contract Audit](C:/code/game/chronicle/texts/v5/CHRONICLE_CORE_SYSTEM_CONTRACT_AUDIT_v5.1.md) | 核心系统缺口审计，不能当作当前全量复验 |
| [Core System Contract Plan](C:/code/game/chronicle/texts/v5/CHRONICLE_CORE_SYSTEM_CONTRACT_PLAN_v5.1.md) | 核心系统历史推进方案，执行排序已由世界优先计划统辖 |
| [Generative World Plan](C:/code/game/chronicle/texts/v5/CHRONICLE_GENERATIVE_WORLD_PLAN_v5.1.md) | 人物、组织、聚落的生成方向与边界 |

### 人物、家庭、生活与经济

| 文档 | 主题 |
| --- | --- |
| [Resident Daily Life](C:/code/game/chronicle/texts/v5/CHRONICLE_RESIDENT_DAILY_LIFE_CONTRACT_v5.1.md) | 居民日常候选与取舍 |
| [Body Condition](C:/code/game/chronicle/texts/v5/CHRONICLE_BODY_CONDITION_CONTRACT_v5.1.md) | 身体、疲劳、伤势与恢复 |
| [Economic Ownership](C:/code/game/chronicle/texts/v5/CHRONICLE_ECONOMIC_OWNERSHIP_CONTRACT_v5.1.md) | 所有权、支付与真实交换 |
| [Resident Food Access](C:/code/game/chronicle/texts/v5/CHRONICLE_RESIDENT_FOOD_ACCESS_CONTRACT_v5.1.md) | 居民取得食物的途径 |
| [Household Livelihood](C:/code/game/chronicle/texts/v5/CHRONICLE_HOUSEHOLD_LIVELIHOOD_CONTRACT_v5.1.md) | 家庭谋生 |
| [Household Provisioning](C:/code/game/chronicle/texts/v5/CHRONICLE_HOUSEHOLD_PROVISIONING_CONTRACT_v5.1.md) | 家庭供给、记忆与共同物资 |
| [Work Framework](C:/code/game/chronicle/texts/v5/CHRONICLE_WORK_FRAMEWORK_CONTRACT_v5.1.md) | 作业、投入、工具和时间 |
| [Worksite Food and Carting](C:/code/game/chronicle/texts/v5/CHRONICLE_WORKSITE_FOOD_AND_CARTING_CONTRACT_v5.1.md) | 作业地供给与运输 |
| [Community Life](C:/code/game/chronicle/texts/v5/CHRONICLE_COMMUNITY_LIFE_CONTRACT_v5.1.md) | 聚落间知识、援助、关系与利益 |

### 玩家、危险、旅途与界面

| 文档 | 主题 |
| --- | --- |
| [World Danger](C:/code/game/chronicle/texts/v5/CHRONICLE_WORLD_DANGER_CONTRACT_v5.1.md) | 危险、战斗、装备、伤后生活的共同规则 |
| [Player Life](C:/code/game/chronicle/texts/v5/CHRONICLE_PLAYER_LIFE_CONTRACT_v5.1.md) | 玩家进入同一生活与资源系统 |
| [Player Agency System Plan](C:/code/game/chronicle/texts/v5/CHRONICLE_PLAYER_AGENCY_SYSTEM_PLAN_v5.1.md) | 玩家能力、选择与成长的系统安排；不是第二个活动计划 |
| [Journey Content](C:/code/game/chronicle/texts/v5/CHRONICLE_JOURNEY_CONTENT_CONTRACT_v5.1.md) | 有状态的旅途内容，需与自主世界局面区分 |
| [Location UI Flow](C:/code/game/chronicle/texts/v5/CHRONICLE_LOCATION_UI_FLOW_v5.1.md) | 地点界面与信息组织；设计规则不等于真人可用性已通过 |

### 计划、审计与检查点

| 文档 | 地位 |
| --- | --- |
| [World First Plan](C:/code/game/chronicle/texts/v5/CHRONICLE_WORLD_FIRST_PLAN_v5.1.md) | 唯一活动计划，已暂停；RF6 未完成 |
| [Rebuild Roadmap](C:/code/game/chronicle/texts/v5/CHRONICLE_REBUILD_ROADMAP_v5.1.md) | 历史重建路线，不与 RF1–RF8 并行执行 |
| [2026-09-05 整体审阅](C:/code/game/chronicle/texts/v5/CHRONICLE_PROJECT_REVIEW_2026-09-05.md) | 代码、设计和计划偏差的历史诊断；需区分已经修复与仍存在的问题 |
| [RF1–RF5 修补检查点](C:/code/game/chronicle/texts/v5/RF1_RF5_REPAIR_CHECKPOINT.md) | 工程修补与保留缺口 |
| [RF5 工作检查点](C:/code/game/chronicle/texts/v5/RF5_WORKING_CHECKPOINT.md) | 危险与伤后生活阶段记录 |
| [RF6 工作检查点](C:/code/game/chronicle/texts/v5/RF6_WORKING_CHECKPOINT.md) | 当前候选、验证、未完成内容；顶部已记录本次暂停和最新真人反馈 |
| [v5 目录导航](C:/code/game/chronicle/texts/v5/README.md) | 文件导航；旧时态以暂停声明为准 |

## 5. 早期工程设计与架构决策

这些文档解释为什么形成现有代码，不表示应回到当时的切片目标。

| 文档 | 用途 |
| --- | --- |
| [Demo Scope Spec](C:/code/game/chronicle/texts/specs/DEMO_SCOPE_SPEC.md) | 早期 Demo 范围，不能覆盖当前正式地理与 RF 计划 |
| [World State Schema](C:/code/game/chronicle/texts/specs/WORLD_STATE_SCHEMA.md) | 旧世界状态设计 |
| [AI Game Control API](C:/code/game/chronicle/texts/specs/AI_GAME_CONTROL_API.md) | 后台观察和合法操作入口；与只读讨论 MCP 不同 |
| [ADR-0001](C:/code/game/chronicle/chronicle-godot/texts/decisions/ADR-0001-project-cleanup-before-world-sim.md) | 世界模拟前的工程清理 |
| [ADR-0002](C:/code/game/chronicle/chronicle-godot/texts/decisions/ADR-0002-world-sim-as-core-layer.md) | 世界模拟作为核心层 |
| [ADR-0003](C:/code/game/chronicle/chronicle-godot/texts/decisions/ADR-0003-events-as-projection-layer.md) | 事件作为投影层，是追溯原方向的重要记录 |
| [Milestone 0](C:/code/game/chronicle/chronicle-godot/texts/plans/milestone_0_project_cleanup.md) | 早期清理方案 |
| [Milestone 1](C:/code/game/chronicle/chronicle-godot/texts/plans/milestone_1_world_sim_mvp.md) | 早期世界模拟 MVP |
| [旧 Roadmap](C:/code/game/chronicle/chronicle-godot/texts/plans/roadmap.md) | 早期工程路线 |
| [Living Surface Spec](C:/code/game/chronicle/chronicle-godot/texts/specs/LIVING_SURFACE_SPEC.md) | 生活表层规范 |
| [Local Story Module Spec](C:/code/game/chronicle/chronicle-godot/texts/specs/LOCAL_STORY_MODULE_SPEC.md) | 本地故事模块规范 |
| [Microsession v0.5](C:/code/game/chronicle/chronicle-godot/texts/specs/microsession_v05.md) | 早期短会话方案 |
| [旧 World Engine Refactor Report](C:/code/game/chronicle/chronicle-godot/texts/archive/old_reports/World_Engine_Refactor_Report.md) | 旧重构记录，仅供追溯 |
| [损坏的旧 Microsession Constitution](C:/code/game/chronicle/chronicle-godot/texts/archive/damaged_docs/microsession_constitution.empty.md) | 已归档的空/损坏稿，不能作为有效设计依据 |

## 6. 参考研究、美术与交付

### 参考游戏和讨论

| 文档 | 边界 |
| --- | --- |
| [矮人要塞参考记录](C:/code/game/chronicle/texts/v5/CHRONICLE_DWARF_FORTRESS_REFERENCE_NOTES.md) | 本地 raw 定义学习，不是恢复模拟器源码 |
| [冒险生活参考记录](C:/code/game/chronicle/texts/v5/CHRONICLE_LIFE_IN_ADVENTURE_REFERENCE_NOTES.md) | 安装包资源与数据结构研究，不是恢复完整游戏代码；资产授权以用户最新确认和 AGENTS 例外为准 |
| [玩法机制讨论至 AI](C:/code/game/chronicle/texts/references/Chronicle_gameplay_mechanics_discussion_until_AI.md) | 讨论来源，不自动升格为实现事实 |
| [RPG 世界真实感文章笔记](C:/code/game/chronicle/texts/references/2026-09-04_RPG_WORLD_AUTHENTICITY_ARTICLE_NOTES.md) | 外部文章对项目的启发与检查项 |

### 视觉、素材与包交付

- [美术目录说明](C:/code/game/chronicle/chronicle-godot/art/README.md)、[统一像素方向](C:/code/game/chronicle/chronicle-godot/art/PIXEL_ART_DIRECTION.md)、[像素资产来源](C:/code/game/chronicle/chronicle-godot/art/PIXEL_ASSET_PROVENANCE.md)。
- [早期环境资产来源](C:/code/game/chronicle/chronicle-godot/art/environments/ASSET_PROVENANCE.md)、[回音港环境来源](C:/code/game/chronicle/chronicle-godot/art/environments/ECHO_PORT_PROVENANCE.md)、[旅途像素环境来源](C:/code/game/chronicle/chronicle-godot/art/environments/JOURNEY_PIXEL_PROVENANCE.md)。
- [沿岸装备图集说明](C:/code/game/chronicle/chronicle-godot/art/icons/coastal_equipment_atlas_v1.md)、[音效来源](C:/code/game/chronicle/chronicle-godot/art/audio/PROVENANCE.md)、[旧素材归档说明](C:/code/game/chronicle/chronicle-godot/art/reference/legacy/README.md)。
- [冒险生活临时授权资产来源与替换清单](C:/code/game/chronicle/chronicle-godot/art/licensed_temporary/life_in_adventure/PROVENANCE.md)。授权复用不等于 Chronicle 原创，也不表示已获得其完整源码。
- [Windows 原型包说明](C:/code/game/chronicle/chronicle-godot/texts/build/H1_WINDOWS_README.md)、[RF6 首次体验验收](C:/code/game/chronicle/chronicle-godot/texts/build/RF6_FIRST_EXPERIENCE_REVIEW.md)。验收表存在不代表已通过。

### 工作规范与讨论接口

- [AGENTS](C:/code/game/chronicle/AGENTS.md)、[项目开发 Skill](C:/code/game/chronicle/.agents/skills/chronicle-world-development/SKILL.md)、[开发规则](C:/code/game/chronicle/texts/rules/CODEX_DEVELOPMENT_RULES.md)。本次不修改 Skill 或开发权限。
- [MCP 说明](C:/code/game/chronicle/mcp/README.md)：已提交白名单文本的私人讨论接口，不是操控当前游戏或读取玩家存档的入口。
- [项目文档导航](C:/code/game/chronicle/texts/README.md)、[Godot 文档导航](C:/code/game/chronicle/chronicle-godot/texts/README.md)。

## 7. 关键阶段报告

报告记录“当时做了什么”，设计文档记录“想做什么”，两者不能混用。下列为关键证据入口，不是全部 125 份历史报告的逐项复述。

| 报告 | 主要价值 |
| --- | --- |
| [8 月 11 日初步涌现](C:/code/game/chronicle/texts/reports/2026/2026-8/2026-8-11/2026-08-11_initial_emergence_report.md) | 较早的局部因果证据与定义 |
| [9 月 8 日 RF1–RF3](C:/code/game/chronicle/chronicle-godot/texts/reports/2026/2026-9/2026-9-08/2026-09-08_rf1_rf3_work_emergence_report.md) | 作业、经济与局部涌现整合 |
| [9 月 9 日 RF4](C:/code/game/chronicle/chronicle-godot/texts/reports/2026/2026-9/2026-9-09/2026-09-09_rf4_community_emergence_report.md) | 聚落间知识与利益 |
| [9 月 10 日 RF5](C:/code/game/chronicle/chronicle-godot/texts/reports/2026/2026-9/2026-9-10/2026-09-10_rf5_world_danger_report.md) | 危险、战斗与伤后生活 |
| [9 月 21 日 RF1–RF5 修补](C:/code/game/chronicle/chronicle-godot/texts/reports/2026/2026-9/2026-9-21/2026-09-21_rf1_rf5_repair_report.md) | 保留有效工程成果，同时明确长期断餐和自然覆盖缺口 |
| [9 月 23 日像素冒险](C:/code/game/chronicle/chronicle-godot/texts/reports/2026/2026-9/2026-9-23/2026-09-23_rf6_pixel_adventure_report.md) | RF6 内容与视觉阶段记录 |
| [9 月 24 日旅途修补](C:/code/game/chronicle/chronicle-godot/texts/reports/2026/2026-9/2026-9-24/2026-09-24_rf6_journey_remediation_report.md) | 用户反馈后的修补范围 |
| [9 月 24 日私人 MCP](C:/code/game/chronicle/chronicle-godot/texts/reports/2026/2026-9/2026-9-24/2026-09-24_private_mcp_report.md) | 讨论基础设施，不算 RF6 游戏验收 |
| [9 月 28 日冒险体验](C:/code/game/chronicle/chronicle-godot/texts/reports/2026/2026-9/2026-9-28/2026-09-28_rf6_adventure_experience_report.md) | 当日较早阶段的体验修补 |
| [9 月 28 日漫游重建](C:/code/game/chronicle/chronicle-godot/texts/reports/2026/2026-9/2026-9-28/2026-09-28_rf6_roaming_rebuild_report.md) | 当前包的来源与历史验证；不能覆盖本次新出现的真人负面反馈 |
| [9 月 30 日暂停报告](C:/code/game/chronicle/texts/reports/2026/2026-9/2026-9-30/2026-09-30_project_pause_report.md) | 当前状态、设计偏移、可复用基础与暂停边界 |

全部历史报告保留在[项目级报告目录](C:/code/game/chronicle/texts/reports)与[Godot 报告目录](C:/code/game/chronicle/chronicle-godot/texts/reports)。不以旧报告标题中的“完成”“通过”推断今天的整体体验已经通过。

## 8. 历史任务指令

以下 39 份 Markdown 是早期逐次开发任务。仅供追溯，不重新执行；它们不与 RF1–RF8 叠加成新待办。

| 日期 | 指令文件 |
| --- | --- |
| 6 月 13 日 | [.1](C:/code/game/chronicle/log/2026-6/2026-6-13/2026-06-13.1.md)、[.2](C:/code/game/chronicle/log/2026-6/2026-6-13/2026-06-13.2.md)、[.3](C:/code/game/chronicle/log/2026-6/2026-6-13/2026-06-13.3.md)、[.4](C:/code/game/chronicle/log/2026-6/2026-6-13/2026-06-13.4.md)、[.5](C:/code/game/chronicle/log/2026-6/2026-6-13/2026-06-13.5.md)、[.6](C:/code/game/chronicle/log/2026-6/2026-6-13/2026-06-13.6.md)、[.7](C:/code/game/chronicle/log/2026-6/2026-6-13/2026-06-13.7.md)、[.8](C:/code/game/chronicle/log/2026-6/2026-6-13/2026-06-13.8.md) |
| 6 月 15 日 | [.1](C:/code/game/chronicle/log/2026-6/2026-6-15/2026-06-15.1.md)、[.2](C:/code/game/chronicle/log/2026-6/2026-6-15/2026-06-15.2.md)、[.3](C:/code/game/chronicle/log/2026-6/2026-6-15/2026-06-15.3.md)、[.4](C:/code/game/chronicle/log/2026-6/2026-6-15/2026-06-15.4.md)、[.5](C:/code/game/chronicle/log/2026-6/2026-6-15/2026-06-15.5.md)、[.6](C:/code/game/chronicle/log/2026-6/2026-6-15/2026-06-15.6.md)、[.7](C:/code/game/chronicle/log/2026-6/2026-6-15/2026-06-15.7.md)、[.8](C:/code/game/chronicle/log/2026-6/2026-6-15/2026-06-15.8.md) |
| 6 月 16 日 | [.1](C:/code/game/chronicle/log/2026-6/2026-6-16/2026-06-16.1.md)、[.2](C:/code/game/chronicle/log/2026-6/2026-6-16/2026-06-16.2.md) |
| 6 月 21 日 | [.1](C:/code/game/chronicle/log/2026-6/2026-6-21/2026-06-21.1.md)、[.2](C:/code/game/chronicle/log/2026-6/2026-6-21/2026-06-21.2.md)、[.3](C:/code/game/chronicle/log/2026-6/2026-6-21/2026-06-21.3.md)、[.4](C:/code/game/chronicle/log/2026-6/2026-6-21/2026-06-21.4.md) |
| 6 月 22 日 | [.1](C:/code/game/chronicle/log/2026-6/2026-6-22/2026-06-22.1.md)、[.2](C:/code/game/chronicle/log/2026-6/2026-6-22/2026-06-22.2.md)、[.3](C:/code/game/chronicle/log/2026-6/2026-6-22/2026-06-22.3.md)、[.4](C:/code/game/chronicle/log/2026-6/2026-6-22/2026-06-22.4.md)、[.5](C:/code/game/chronicle/log/2026-6/2026-6-22/2026-06-22.5.md)、[.6](C:/code/game/chronicle/log/2026-6/2026-6-22/2026-06-22.6.md) |
| 6 月 23 日 | [.1](C:/code/game/chronicle/log/2026-6/2026-6-23/2026-06-23.1.md)、[.2](C:/code/game/chronicle/log/2026-6/2026-6-23/2026-06-23.2.md)、[.3](C:/code/game/chronicle/log/2026-6/2026-6-23/2026-06-23.3.md)、[.4](C:/code/game/chronicle/log/2026-6/2026-6-23/2026-06-23.4.md)、[.5](C:/code/game/chronicle/log/2026-6/2026-6-23/2026-06-23.5.md)、[.6](C:/code/game/chronicle/log/2026-6/2026-6-23/2026-06-23.6.md)、[.7](C:/code/game/chronicle/log/2026-6/2026-6-23/2026-06-23.7.md) |
| 6 月 24 日 | [.1](C:/code/game/chronicle/log/2026-6/2026-6-24/2026-06-24.1.md)、[.2](C:/code/game/chronicle/log/2026-6/2026-6-24/2026-06-24.2.md)、[.3](C:/code/game/chronicle/log/2026-6/2026-6-24/2026-06-24.3.md)、[.4](C:/code/game/chronicle/log/2026-6/2026-6-24/2026-06-24.4.md) |

另有三份保留原文件名的 TXT 思路稿：[11.1 镜湖森林带与沉默森林完善思路](<C:/code/game/chronicle/log/11.1镜湖森林带-沉默森林 完善思路.txt>)、[11.2 开发路线](C:/code/game/chronicle/log/11.2开发路线.txt)、[11.6 开发路线](C:/code/game/chronicle/log/11.6开发路线.txt)。不凭文件名推断它们晚于本次暂停报告。

## 9. 使用索引时的判断顺序

1. 用核心指导确认游戏承诺，用原稿确认世界背景。
2. 用当前合同与代码确认实现，用历史报告确认当时真正验证过什么。
3. 用本次用户反馈更新产品判断，不能用工程测试覆盖负面体验。
4. 文档冲突、旧“下一步”或更多内容提案，都不构成恢复开发授权。
5. 新版时间显示已被用户明确排除为问题；等待、行动可达性和结果页阻断另行讨论。

本次没有重写旧 GDD，也没有设立新的独立开发路线。暂停后先讨论世界如何成为可理解的决策场面，再由用户决定是否恢复实施。

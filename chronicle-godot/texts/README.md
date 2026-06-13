# Chronicle 文档索引

## 文档目录分工

- `log/`：每日开发指令与执行流水，一天一个 md 文件，由用户追加维护。
- `texts/reports/`：任务完成后的报告。
- `texts/specs/`：长期系统规格。
- `texts/decisions/`：架构决策记录 ADR。
- `texts/plans/`：路线图和阶段计划。
- `texts/archive/`：过期、损坏或废弃但暂不删除的文档。

仓库根目录的 `log/` 不属于本目录，不应移动到 `texts/`。

## 当前核心方向

Chronicle 是一个自运行世界驱动的文字冒险 RPG。

世界演化层是核心。

事件与线索是表现层。

玩家控制的角色只是世界中的一个参与者，而不是世界唯一驱动源。

## 当前实际运行入口

- 主场景：`scenes/ui/mainui.tscn`
- 主交互脚本：`scenes/ui/story_player.gd`
- 当前世界逻辑：`scripts/gen/world_generation_v03.gd`

## 不要继续扩展的旧内容

- 不要继续扩展旧 `world_generation.gd`；它已归档到 `_archive/damaged_or_legacy_scripts/`。
- 不要在完成世界模拟层设计前继续扩写事件池。
- 不要把当前未接入的数据、素材、文档直接判定为无用。
- 不要清理 `素材包/`，该目录是备用素材库。

## 当前最值得保留的核心循环

线索变化 -> 目标化行动 -> 多阶段处理 -> 事件结果 -> 后果回流到线索、传闻和局部世界状态。

## 后续重构方向

下一阶段应建立 `world_sim_mvp`：

- 地区状态
- 势力状态
- 资源流动
- 生态变化
- 传闻生成
- 线索投影
- 玩家行为写回世界

## 当前文档

### Specs

- `specs/microsession_v05.md`：现有对象化行动、线索池和 MicroSession 规格。

### Reports

- `reports/2026/2026-06-13_project_cleanup_report.md`
- `reports/2026/2026-06-13_world_sim_mvp_report.md`

### Decisions

- `decisions/ADR-0001-project-cleanup-before-world-sim.md`
- `decisions/ADR-0002-world-sim-as-core-layer.md`
- `decisions/ADR-0003-events-as-projection-layer.md`

### Plans

- `plans/roadmap.md`
- `plans/milestone_0_project_cleanup.md`
- `plans/milestone_1_world_sim_mvp.md`

### Archive

- `archive/old_reports/`：与旧实现绑定的历史报告。
- `archive/old_specs/`：过期规格。
- `archive/old_plans/`：过期计划。
- `archive/damaged_docs/`：空文件、编码损坏或无法直接采用的文档。

# 项目清理报告

## 1. 本次目标

本次清理在不修改当前 Demo 玩法、UI 和数据目录的前提下完成：

- 审计当前项目的活动引用。
- 归档未被当前入口引用的旧副本和旧脚本。
- 建立长期文档目录、ADR 和阶段计划。
- 保持 `data/` 与 `素材包/` 原位。
- 验证当前 Demo 在清理后仍可加载和交互。

本次没有开发 `world_sim_mvp`，没有扩写事件，也没有修改 `world_generation_v03.gd`。

## 2. 当前运行入口确认

- 项目配置：`project.godot`
- 主场景：`scenes/ui/mainui.tscn`
- 主交互脚本：`scenes/ui/story_player.gd`
- 当前世界逻辑：`scripts/gen/world_generation_v03.gd`
- 默认地区文件：`data/regions/回响之境/地区/中央偏北界域 - 碎星与镜湖/镜湖森林带/镜湖森林带.json`

`story_player.gd` 通过 `load()` 明确加载 `world_generation_v03.gd`。旧 `world_generation.gd` 不在当前场景、autoload 或活动脚本的运行引用中。

## 3. 引用审计结果

### 3.1 当前 Demo 必需文件

核心入口：

- `project.godot`
- `scenes/ui/mainui.tscn`
- `scenes/ui/story_player.gd`
- `scripts/gen/world_generation_v03.gd`

场景与 UI 依赖：

- `scenes/ui/stats_area.gd`
- `scenes/ui/button.tscn`
- `scenes/player.tscn`
- `assets/fonts/SourceHanSerifSC-VF.ttf`
- 主场景引用的 HUD 图片、头像、玩家精灵及对应 `.import` 文件

autoload 与解析依赖：

- `scripts/sys/RNG.gd`
- `scripts/sys/WorldState.gd`
- `scripts/gen/registry.gd`
- `scripts/gen/common/json_util.gd`
- `scripts/gen/common/deep_merge.gd`

当前入口还会检查默认镜湖森林带 JSON 是否存在，因此该文件及 `data/` 目录保持原位。

### 3.2 当前未使用但未来可能有价值的文件

以下内容没有被当前 v0.3 Demo 主循环直接调用，但结构正常，后续 `world_sim_mvp` 可以参考或接入，因此保留原位：

- `scripts/gen/chain_engine.gd`
- `scripts/gen/event_generator.gd`
- `scripts/gen/region_loader.gd`
- `scripts/gen/region_generator.gd`
- `scripts/gen/resource_generator.gd`
- `scripts/gen/npc_interactions.gd`
- `scripts/gen/creatures_generator.gd`
- `scripts/gen/common/weighted_pick.gd`
- `scripts/gen/proc/equipment_generator.gd`
- `scripts/gen/proc/creature_variant_generator.gd`
- `data/` 下现有地区、天气、生物、资源、事件和物品数据
- `scenes/forrest.tscn`
- 当前未接入的音频和备用精灵

### 3.3 明显旧版或重复文件

- `chronicle/chronicle-godot/`：完整嵌套的旧 Godot 项目副本，未被主项目引用。
- `scenes/ui/mainui.gd`：未挂载到当前 `mainui.tscn`，依赖旧 `WorldGeneration` 类。
- `texts/v4/World_Engine_Refactor_Report.md`：与旧 `world_generation.gd` 实现绑定的历史报告。

### 3.4 损坏、乱码或不可直接使用文件

- `scripts/gen/world_generation.gd`：存在大量乱码、注释和变量声明粘连等损坏，且不是当前运行入口。
- `texts/microsession_constitution.md`：零字节空文件，无法提供其名称所声称的基础约束。

### 3.5 占位但未完成文件

- 地图、成长、背包、系统入口目前主要返回说明文本，不是完整面板。
- `scenes/forrest.tscn` 已有背景场景，但未接入主场景。
- 音频资源已存在，但当前没有 `AudioStreamPlayer` 接线。
- 当前没有正式存档系统。

这些内容没有在本次清理中移动或修改。

### 3.6 禁止移动或删除的文件

本次明确保护并保持原位：

- `project.godot`
- `scenes/`
- `scripts/gen/world_generation_v03.gd`
- `scripts/sys/`
- `data/`
- `素材包/`
- 所有仍与活动资源对应的 `.uid` 和 `.import` 文件

## 4. 本次移动到 _archive 的内容

### 4.1 嵌套旧项目副本

- 原路径：`chronicle/chronicle-godot/`
- 新路径：`_archive/legacy_project_copy/chronicle-godot/`
- 原因：独立旧项目副本，与当前主项目没有运行引用。
- 当前 Demo 引用：否。
- 恢复方式：确认目标路径为空后，将目录移回 `chronicle/chronicle-godot/`。

### 4.2 损坏的旧世界脚本

- 原路径：`scripts/gen/world_generation.gd`
- 新路径：`_archive/damaged_or_legacy_scripts/world_generation.gd`
- 同步移动：`world_generation.gd.uid`
- 原因：不是当前入口，且文件存在明显编码和结构损坏。
- 当前 Demo 引用：否。
- 恢复方式：将脚本与 UID 一并移回原路径；恢复前应先修复解析问题，但不要覆盖 v0.3 入口。

### 4.3 旧 UI 入口脚本

- 原路径：`scenes/ui/mainui.gd`
- 新路径：`_archive/old_experiments/scenes/ui/mainui.gd`
- 同步移动：`mainui.gd.uid`
- 原因：当前场景未挂载该脚本，并且脚本依赖已归档的旧世界类。
- 当前 Demo 引用：否。
- 恢复方式：将脚本与 UID 移回原路径；如需重新挂载，必须另行完成场景引用审计。

## 5. 本次没有移动但需要注意的内容

- `data/`：保持原位。大量 JSON 尚未接入当前 Demo，但属于未来世界模拟和内容系统资产。
- `素材包/`：保持原位。它既是备用素材库，也包含当前主场景直接引用的图片。
- 数据驱动生成器：保持原位。虽然多数未接入 v0.3，但代码可读且有架构参考价值。
- `scenes/forrest.tscn`：未接入主场景，但可能用于后续场景展示，暂不归档。
- 仓库根目录 `texts/`：属于更早的设计资料，本任务只整理 Godot 项目内的长期文档，未扩大清理范围。

## 6. 文档结构整理结果

建立了：

- `texts/reports/2026/`
- `texts/specs/`
- `texts/decisions/`
- `texts/plans/`
- `texts/archive/old_reports/`
- `texts/archive/old_specs/`
- `texts/archive/old_plans/`
- `texts/archive/damaged_docs/`

文档移动：

- `microsession_v05.md` -> `specs/microsession_v05.md`
- `World_Engine_Refactor_Report.md` -> `archive/old_reports/World_Engine_Refactor_Report.md`
- 空的 `microsession_constitution.md` -> `archive/damaged_docs/microsession_constitution.empty.md`

新增：

- 文档索引 `texts/README.md`
- ADR-0001 至 ADR-0003
- 总路线图与 Milestone 0、Milestone 1 计划
- `PROJECT_STRUCTURE.md`

## 7. 验证结果

验证工具：Godot 4.6.3 stable，Windows 64 位，无头模式。项目配置声明 Godot 4.5 特性；本次使用向后兼容版本进行加载验证。

### 编辑器加载

命令：

```powershell
godot_console --headless --path C:\code\game\chronicle\chronicle-godot --editor --quit
```

结果：通过。

- 项目完成文件扫描。
- autoload 创建成功。
- 编辑器布局加载成功。
- 没有关键资源缺失或脚本解析错误。

### Demo 交互冒烟测试

测试：`tests/project_cleanup_smoke.gd`

结果：通过。

- Godot 项目能打开：通过。
- `mainui.tscn` 能加载和实例化：通过。
- “继续”按钮可用：通过。
- 选择面板能渲染可点击行动：通过。
- 选择行动后进入多阶段待决流程：通过。
- “重新开始”能创建新的世界实例：通过。
- “新旅程”能再次创建新的世界实例：通过。
- 控制台没有关键资源丢失错误：通过。
- `素材包/` 仍位于原路径：通过。
- `data/` 仍位于原路径：通过。

## 8. 风险与遗留问题

- 当前 Demo 仍由硬编码的 `world_generation_v03.gd` 驱动，尚未真正读取大部分地区 JSON。
- 项目声明 Godot 4.5，本次实际验证版本为 4.6.3；建议发布环境最终固定并记录具体 Godot 版本。
- `_archive/legacy_project_copy/` 保留了一份大字体副本，仓库体积不会因本次归档下降。
- 根目录旧设计文档仍存在编码、重复和版本混杂问题，需要单独任务审计。
- 地区索引存在重复 ID 映射，后续接入世界模拟前需要建立 schema 验证。
- 当前缺少持续集成；无头冒烟测试尚未接入 CI。

## 9. 下一步建议

下一步应从新分支开始：

```text
exp/world-sim-mvp
```

开始前先以 ADR-0002、ADR-0003 和 `plans/milestone_1_world_sim_mvp.md` 为边界，确定最小地区状态、势力状态、tick、世界事实和投影接口。

不要直接恢复或继续扩展旧 `world_generation.gd`，也不要先扩写事件池。优先让同一个镜湖种子世界在没有玩家操作时产生可复现、可解释的状态变化。

# Chronicle 项目结构说明

## 当前实际运行入口

- 项目配置：`project.godot`
- 主场景：`scenes/ui/mainui.tscn`
- 主交互脚本：`scenes/ui/story_player.gd`
- 当前世界逻辑：`scripts/gen/world_generation_v03.gd`
- 默认地区文件：`data/regions/回响之境/地区/中央偏北界域 - 碎星与镜湖/镜湖森林带/镜湖森林带.json`

## 开发与验证环境

项目以 Godot 4.5 为目标版本。当前清理阶段曾使用 Godot 4.6.3 stable 进行无头加载和冒烟测试。后续发布或课程展示前，应固定最终 Godot 版本并重新验证。

## 当前 Demo 必需文件

核心运行文件：

- `project.godot`
- `scenes/ui/mainui.tscn`
- `scenes/ui/story_player.gd`
- `scenes/ui/stats_area.gd`
- `scenes/ui/button.tscn`
- `scenes/player.tscn`
- `scripts/gen/world_generation_v03.gd`
- `scripts/sys/RNG.gd`
- `scripts/sys/WorldState.gd`
- `scripts/gen/registry.gd`

主场景直接引用的字体、图片及其 `.import` 文件同样属于运行依赖。

## 目录说明

- `assets/`：当前项目字体等直接资源。
- `data/`：地区、天气、生物、事件、物品和通用内容数据。当前部分未接入，但禁止随意移动。
- `scenes/`：当前场景与直接挂载脚本。
- `scripts/gen/`：当前 v0.3 逻辑和保留的数据驱动生成器。
- `scripts/sys/`：自动加载的 RNG 与 WorldState。
- `texts/`：长期规格、报告、架构决策和阶段计划。
- `素材包/`：备用素材库及当前主场景直接引用的图片资源。
- `_archive/`：通过引用审计后退出活动结构的历史内容。
- `tests/`：当前项目的无头冒烟测试。

## archive 目录用途

`_archive/` 保存旧副本、损坏脚本和历史实验，不代表删除。

目录带有 `.gdignore`，Godot 不扫描其中的脚本和项目。恢复文件时应先移回原路径，再检查 `res://` 引用、UID 和场景加载。

## 素材包目录说明

`素材包/` 是备用素材库，不是未使用垃圾目录。清理时禁止删除、移动或重命名。

当前主场景还直接引用了其中的玩家精灵和 HUD 图片，因此它也是当前 Demo 的运行依赖。

## 不要继续扩展的旧文件

- `_archive/damaged_or_legacy_scripts/world_generation.gd`
- `_archive/old_experiments/scenes/ui/mainui.gd`
- `_archive/legacy_project_copy/chronicle-godot/`

以上内容只用于历史追溯。新功能不得重新建立对它们的运行依赖。

## 保留但尚未接入的框架

以下模块保持原位，供后续 `world_sim_mvp` 参考或接入：

- `Registry`
- `RegionLoader`
- `WeightedPick`
- `ChainEngine`
- `EventGenerator`
- `RegionGenerator`
- `ResourceGenerator`
- `EquipmentGenerator`
- `CreatureVariantGenerator`
- `NpcInteractions`
- `WorldState`
- `RNG`

## world_sim_mvp 当前位置

第一阶段无 UI 世界模拟核心位于：

```text
scripts/sim/
data/world_seed_mirror_lake.json
```

其中包含世界状态、每日 tick、势力行动、线索投影、玩家行为写回和无头调试 Runner。该模块目前保持独立，尚未接入 `story_player.gd` 或主界面。

`scripts/sim/world_sim_lead_adapter.gd` 属于表现层适配工具，只把已有 `LeadCandidate` 转换为 v0.3 四类线索字典。它不生成世界事实、不创建新线索，也未接入当前 Demo。

## 当前保留的核心循环

线索 -> 行动 -> 事件 -> 后果回流

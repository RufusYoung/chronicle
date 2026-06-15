# 湖湾镇开发者可视化世界面板报告

## 1. 本次目标

本次新增 `LakeTownWorldViewer`，用于在 Godot 内查看湖湾镇本地模拟的 20 个 seed、30 天时间线、每日状态和质量审计结果。

该面板属于开发者可视化层，不属于正式玩家 UI。本次没有接入正式 UI，没有改变当前 Demo 行为，没有让 UI 生成世界事实，也没有让 UI 修改世界状态。界面只消费 `LocalStoryModule / LocalStoryPipeline` 经 ViewModel 整理后的只读结果。

## 2. 新增 / 修改文件

新增：

- `scenes/dev/lake_town_world_viewer.tscn`
- `scripts/dev/lake_town_world_viewer.gd`
- `scripts/dev/lake_town_world_view_model.gd`
- `scripts/dev/lake_town_world_viewer_runner.gd`
- `tests/lake_town_world_viewer_data_test.gd`
- `texts/reports/2026/2026-6/2026-6-15/2026-06-15_lake_town_world_viewer_report.md`
- `../log/2026-6/2026-6-15/2026-06-15.8.md`

没有修改既有运行时代码、正式场景或项目入口。

## 3. 未修改的保护文件

以下保护文件相对任务开始时的 `HEAD` 均无差异：

- `scenes/ui/story_player.gd`
- `scripts/gen/world_generation_v03.gd`
- `scenes/ui/mainui.tscn`
- `project.godot`
- `素材包/`

## 4. 场景结构

场景根节点为 `Control`，使用 Godot 原生控件构建：

- 顶部：标题和批量模拟状态。
- 左侧：20 个 seed 的 `ItemList`。
- 中间：选中 seed 的湖湾镇关键事实时间线。
- 右侧：选中日期的新增记录、NPC 状态、地点状态和质量标记。
- 底部：七页只读 `TabContainer`。

界面没有按钮写入 `state`，没有调用 `resolve_action()`，也没有创建 `WorldFact`。

## 5. ViewModel 数据结构

`LakeTownWorldViewModel` 提供任务要求的全部接口：

- `build_view_data`
- `build_seed_summary`
- `build_timeline`
- `build_day_detail`
- `build_npc_snapshot`
- `build_location_snapshot`
- `build_fact_rows`
- `build_trace_rows`
- `build_memory_rows`
- `build_narratable_rows`
- `build_quality_summary`

ViewModel 通过湖湾镇模块和 `LocalStoryPipeline` 批量运行模拟，最终只向 UI 返回 `Dictionary / Array`。输出不携带 `WorldSimState`，所有读取接口返回复制后的结构，避免 UI 修改模拟结果。

## 6. Seed 列表展示

左侧列表固定运行 `2026061501` 至 `2026061520`，每行展示：

- seed
- `outcome_class`
- `quality_flags` 数量及具体标记，空列表显示 `OK`
- `bad_hunger_outcome`
- 是否发生取粮
- 是否发生守卫封仓
- 是否发现空粮仓

点击 seed 后会同时刷新时间线、日期详情和底部分页。

## 7. 历史时间线展示

时间线只优先展示湖湾镇相关 `WorldFact`，并按日期、事实 ID 排序。每行格式为：

```text
Day N | fact_type | 简短说明
```

点击任一事实会选择其发生日期，并刷新右侧 Day Detail。

## 8. Day Detail 展示

右侧详情显示：

- 当前 day
- 当日新增 `WorldFact`
- 当日新增 `Trace`
- 当日新增 `Memory`
- 当日新增 `NarratableState`
- 当前 NPC 快照
- 当前地点快照
- 当前质量标记

当天没有新增记录时显示“无”，缺失状态字段显示 `-`。

## 9. NPC / Location 状态展示

NPC 至少包含：

- `old_chen`
- `chen_mi`
- `ma_shen`
- `liu_zhangfang`

NPC 字段包括 `hunger`、`fear`、`health`、`stress`、`debt`、`family_food`、`location_id`、`status_tags`。

地点至少包含：

- `old_chen_shop`
- `abandoned_granary`
- `lake_town_market`
- `ma_shen_home_temp`

地点字段包括 `is_open`、`partial_open`、`food_stock`、`spoiled_grain_stock`、`status_tags`、`traces`。

## 10. WorldFact / Trace / Memory / NarratableState 分页

底部四个记录分页分别展示：

- `WorldFact`：`fact_id`、day、type、actors、location、cause facts、tags。
- `Trace`：`trace_id`、day、type、location、`source_fact_id`。
- `Memory`：`memory_id`、day、type、owner、`source_fact_id`、tags。
- `NarratableState`：ID、day、title、source facts、trace IDs、status、location。

所有分页均使用不可编辑的 `TextEdit`。

## 11. QualityAudit 展示

`QualityAudit` 分页展示：

- `quality_flags`
- `dangling_major_fact`
- `impossible_shop_state`
- `unresolved_extreme_hunger`
- `bad_hunger_outcome`
- `branch_closure_depth`
- `consequence_depth`

本次 20 个 seed 的汇总结果：

- `unresolved_extreme_hunger = 0`
- `impossible_shop_state = 0`
- `dangling_major_fact = 0`

## 12. 运行方式

在 Godot 编辑器中打开：

```text
scenes/dev/lake_town_world_viewer.tscn
```

命令行运行：

```powershell
godot --path chronicle-godot scenes/dev/lake_town_world_viewer.tscn
```

无头场景检查：

```powershell
godot --headless --path chronicle-godot --script res://scripts/dev/lake_town_world_viewer_runner.gd
```

## 13. 测试结果

专用数据测试：

```text
[LAKE TOWN WORLD VIEWER DATA RESULT] PASS
```

20 项数据断言全部通过，包括数据完整性、只读性、场景解析和保护文件检查。

场景运行器：

```text
[LAKE TOWN WORLD VIEWER RUNNER RESULT] PASS
```

指令要求的 13 项回归脚本全部通过：

- `local_story_module_test.gd`
- `lake_town_hunger_closure_test.gd`
- `lake_town_branch_closure_test.gd`
- `lake_town_history_variation_test.gd`
- `lake_town_recovery_system_test.gd`
- `lake_town_reaction_system_test.gd`
- `micro_action_resolver_test.gd`
- `lake_town_food_chain_test.gd`
- `world_sim_observer_test.gd`
- `world_news_digest_test.gd`
- `world_sim_lead_adapter_test.gd`
- `world_sim_debug_runner.gd`
- `project_cleanup_smoke.gd`

结果：`PASS (13/13)`。

## 14. 当前局限

- 第一版以开发调试清晰度为目标，没有新增美术资源或主题。
- 目前批量数据在场景启动后同步生成，seed 数量增加时需要考虑后台任务或缓存。
- 时间线当前按关键事实选日，还没有单独的 1 至 30 日空白日期导航。
- 分页使用格式化 JSON，适合核对数据，但还不是高密度表格视图。

## 15. 下一步建议

- 增加“只看异常 seed”和按 `outcome_class` 筛选。
- 增加完整日期导航，便于检查没有新事实但状态持续变化的日期。
- 增加事实因果链、Trace、Memory 和 NarratableState 的交叉跳转。
- 在保持只读边界的前提下增加结果导出和 seed 对比视图。

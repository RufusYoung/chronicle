# 湖湾镇局面卡片与世界表面层报告

## 1. 本次目标

本次建立湖湾镇 `LivingSurface` 世界表面层，并在开发者 viewer 中增加今日局面卡、人物状态卡、地点状态卡、可见痕迹和因果来源摘要。

本任务没有接正式 UI，没有修改当前 Demo 行为，没有让 UI 生成事实，没有接 AI 文本。本任务只是把已有湖湾镇事实翻译成开发者可读的世界局面。

## 2. 新增 / 修改文件

新增：

- `scripts/dev/lake_town_living_surface_builder.gd`
- `scripts/dev/lake_town_living_surface_templates.gd`
- `tests/lake_town_living_surface_test.gd`
- `texts/specs/LIVING_SURFACE_SPEC.md`
- `texts/reports/2026/2026-6/2026-6-16/2026-06-16_lake_town_living_surface_report.md`
- `../log/2026-6/2026-6-16/2026-06-16.1.md`

修改：

- `scripts/dev/lake_town_world_view_model.gd`
- `scripts/dev/lake_town_world_viewer.gd`
- `scripts/dev/lake_town_world_viewer_runner.gd`

## 3. 未修改的保护文件

以下文件未修改：

- `scenes/ui/story_player.gd`
- `scripts/gen/world_generation_v03.gd`
- `scenes/ui/mainui.tscn`
- `project.godot`
- `素材包/`

## 4. LivingSurfaceCard 数据结构

卡片包含：

- 基础字段：`card_id`、`seed`、`day`、`title`、`subtitle`、`location_id`、`location_name`
- 展示字段：`scene_summary`、`visible_details`、`people_present`、`location_state_lines`、`trace_lines`、`memory_echo_lines`、`cause_lines`、`quality_lines`
- 来源字段：`source_fact_ids`、`trace_ids`、`memory_ids`、`narratable_state_ids`、`state_keys`
- 分类字段：`tone_tags`、`severity`、`card_type`

每张卡至少保留事实来源或痕迹来源。

## 5. 卡片生成规则

生成优先级：

1. 当日 `NarratableState`
2. 当日关键 `WorldFact`
3. 有近三日事实或痕迹支撑的状态延续卡

每天最多返回三张卡。没有事实、没有 Trace、没有近三日来源时，不会凭空生成重大场景。

## 6. 模板系统

`lake_town_living_surface_templates.gd` 提供事实、痕迹、人物、地点和摘要模板。

已支持的事实类型包括：

```text
lake_town_food_price_rising
chen_mi_took_spoiled_grain
old_chen_closed_shop_due_to_family_crisis
chen_mi_ate_spoiled_grain
chen_mi_fell_sick_from_spoiled_grain
ma_shen_brought_porridge
creditor_left_debt_notice
guard_locked_abandoned_granary
chen_mi_blocked_by_guard_seal
guard_noticed_child_near_granary
chen_mi_found_empty_granary
chen_mi_returned_empty_handed
chen_mi_endured_hunger
chen_mi_weakened_from_enduring_hunger
old_chen_sold_shop_goods_for_food
chen_mi_collapsed_from_hunger
old_chen_took_chen_mi_to_seek_help
lake_town_emergency_credit_food
ma_shen_emergency_food_for_chen_mi
chen_mi_temporarily_stayed_with_ma_shen
chen_mi_health_crashed_from_hunger
```

未知事实类型会显示通用句，并保留 fact type。

## 7. ViewModel 更新

`LakeTownWorldViewModel` 新增接口：

- `build_living_surface_cards(run_result, day)`
- `build_primary_surface_card(run_result, day)`
- `build_surface_day_list(run_result)`
- `build_people_cards(run_result, day)`
- `build_location_cards(run_result, day)`

`build_day_detail()` 保留旧字段，并新增：

- `living_surface_cards`
- `primary_surface_card`
- `people_cards`
- `location_cards`

ViewModel 仍只返回 `Dictionary / Array`，不修改传入结果。

## 8. Viewer 界面更新

右侧 Day Detail 现在优先显示：

- 今日局面卡
- 人物状态卡
- 地点状态卡
- 可见痕迹
- 因果来源

底部 JSON 分页仍保留：

- `WorldFact`
- `Trace`
- `Memory`
- `NarratableState`
- `QualityAudit`
- `Profile`
- `Raw Signature`

## 9. 示例卡片

取粮：

```text
老陈的铺子今天没有正常开门。
陈米抱着一只旧布袋，袋口露出灰白色的发霉麦粒。
她看见有人靠近时，把布袋往身后挪了一下。
```

封仓：

```text
废弃粮仓门上多了一道守卫封条。
这条封锁来自已经发生的粮食危机事实。
```

倒下 / 求助：

```text
陈米倒在老陈铺子的门槛边。
她的饥饿已经进入极高区间，健康也在下降。
```

## 10. UI 只读边界

Viewer 脚本不包含：

- `add_fact(`
- `resolve_action(`
- `create_state_for_seed(`
- `tick_once(`
- `WorldSimState`

UI 只读取 ViewModel 输出，不直接修改 state，也不生成事实。

## 11. 测试结果

新增专项测试：

```text
[LAKE TOWN LIVING SURFACE RESULT] PASS
```

22 项断言全部通过，覆盖关键路径卡片、来源字段、人物卡、地点卡、等级转换、未知 fact type、ViewModel 兼容字段、UI 只读边界和质量计数。

已复跑：

```text
[LAKE TOWN WORLD VIEWER DATA RESULT] PASS
[LAKE TOWN WORLD VIEWER RUNNER RESULT] PASS
```

完整回归结果：

```text
[REGRESSION RESULT] PASS (16/16)
```

覆盖 `lake_town_living_surface_test.gd`、`lake_town_world_viewer_data_test.gd`、viewer runner，以及指令要求的 13 项既有回归入口。

## 12. 当前局限

- 第一版仍是开发者可视化，不是正式玩家 UI。
- 人物卡和地点卡以摘要文字为主，还没有做成高密度表格控件。
- 状态延续卡只检查近三日事实或痕迹，后续可按地点和人物关系扩展更细的支撑链。
- 模板覆盖了湖湾镇当前关键事实，还不是通用表现层模板系统。

## 13. 下一步建议

- 增加按 `card_type` 和 `severity` 筛选局面卡。
- 增加卡片到 WorldFact / Trace / Memory 的跳转定位。
- 为连续状态变化增加更精确的“昨日 / 前日对比”摘要。
- 保持只读边界，继续让世界层决定事实，LivingSurface 只负责看见。

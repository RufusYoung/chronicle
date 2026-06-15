# 局部故事模块接口与湖湾镇模块化报告

## 1. 本次目标

本次建立 `LocalStoryModule`、`RegionSimProfile`、`LocalStoryPipeline` 和 `HistoryQualityAudit` 四个结构，并将现有湖湾镇粮食危机包装为 `lake_town_food_crisis_module`。

本次没有新增第二地点，没有接 UI，没有扩写事件池，也没有改动当前 Demo 行为。

## 2. 新增 / 修改文件

新增运行时代码：

- `scripts/sim/local_story_module.gd`
- `scripts/sim/history_quality_audit.gd`
- `scripts/sim/region_sim_profile.gd`
- `scripts/sim/local_story_pipeline.gd`
- `scripts/sim/modules/lake_town_food_crisis_module.gd`
- `scripts/dev/local_story_module_runner.gd`

新增测试和文档：

- `tests/local_story_module_test.gd`
- `texts/specs/LOCAL_STORY_MODULE_SPEC.md`
- `texts/reports/2026/2026-6/2026-6-15/2026-06-15_local_story_module_report.md`
- `log/2026-6/2026-6-15/2026-06-15.7.md`

Godot 同时为新增 GDScript 生成对应 `.gd.uid` 文件。

没有修改原有湖湾镇系统代码、`world_simulator.gd` 或 `world_sim_state.gd`。

## 3. 未修改的保护文件

以下文件经 `git diff HEAD -- <path>` 检查没有改动：

- `scenes/ui/story_player.gd`
- `scripts/gen/world_generation_v03.gd`
- `scenes/ui/mainui.tscn`
- `project.godot`
- `素材包/`

## 4. LocalStoryModule 接口

接口包含：

- `get_module_id()`
- `get_module_version()`
- `get_region_id()`
- `get_location_ids()`
- `get_required_state_keys()`
- `initialize_module_state()`
- `tick_module()`
- `build_narratable_states()`
- `build_action_candidates()`
- `resolve_action()`
- `build_history_signature()`
- `audit_quality()`
- `describe_module()`

这是普通 GDScript 契约，不要求旧系统立即继承或拆分。

## 5. RegionSimProfile 结构

统一字段为：

```text
profile_id
seed
region_id
module_id
macro_pressure
resources
social_roles
npc_bias
location_bias
external_pressure
quality_targets
```

湖湾镇通过 `legacy_profile` 保留现有 `lake_town_seed_profile` 的完整输入，方便渐进迁移。profile 只写初始条件，没有创建 `WorldFact`，也没有指定 `outcome_class`。

## 6. LocalStoryPipeline 结构

`run_days()` 可选地初始化 profile，然后逐日调用模块。

`tick_once()` 比较推进前后的集合，输出：

```text
day
created_fact_ids
created_trace_ids
created_memory_ids
created_narratable_state_ids
quality_flags
```

`run_seed_batch()` 负责批量 seed、前三个 seed 双跑复现和汇总。通用管线不含湖湾镇地点、NPC 或事实类型。

## 7. 湖湾镇模块包装方式

湖湾镇模块没有复制或重写五个系统。`tick_module()` 继续调用现有 `WorldSimulator.advance_one_day()`，因此每日顺序仍为：

1. 宏观地区和势力推进。
2. `lake_town_food_chain`
3. `lake_town_reaction_system`
4. `lake_town_recovery_system`
5. `lake_town_branch_closure_system`
6. `lake_town_hunger_closure_system`
7. 世界投影。

动作接口委托 `micro_action_resolver`；历史签名委托旧 variation runner；质量审计委托旧 quality auditor。

## 8. 与旧 runner 结果对比

模块 runner 与旧 `lake_town_history_variation_runner` 使用同一组 20 seed、每组 30 天。

以下关键统计完全一致：

- seed 数：20
- 唯一历史签名：20
- 同 seed 复现：通过
- 结局分布：完全一致
- `unresolved_extreme_hunger`：0
- `dangling_major_fact`：0
- `impossible_shop_state`：0

结局分布：

```json
{
  "empty_granary_returned_empty": 1,
  "forced_shop_closure_no_theft": 2,
  "guard_locked_guard_attention": 6,
  "mixed_interwoven": 2,
  "silent_hunger_decline": 4,
  "theft_helped_recovery": 3,
  "theft_sickness_debt": 2
}
```

没有发现因包装层引入的日期或统计差异。

## 9. 20 seed 回归结果

- 20 / 20 seed 完成 30 天推进。
- 20 个唯一历史签名。
- 前三个 seed 双跑结果一致。
- 不同 seed 的历史差异继续存在。
- 所有结果仍由初始条件、每日状态和规则共同产生。

## 10. ActionCandidate 与 resolve_action 模块接口验证

无 profile 的基线推进到第 6 天后，模块接口能为 `chen_mi_hiding_spoiled_grain_scene` 返回候选行为。

通过模块接口执行 `give_food_to_chen_mi` 后：

- 返回成功结果。
- 写入 `WorldFact`。
- 写入 `Trace`。
- 写入 `Memory`。
- 锁定已处理的 `NarratableState`。

模块接口没有依赖正式 UI。

## 11. QualityAudit 模块接口验证

`audit_quality()` 可对当前状态或历史签名输出审计字典，并稳定包含 `quality_flags`。

本次 20 seed 汇总：

- `unresolved_extreme_hunger_count = 0`
- `dangling_major_fact_count = 0`
- `impossible_shop_state_count = 0`

## 12. 规格文档说明

规格文档位于：

`texts/specs/LOCAL_STORY_MODULE_SPEC.md`

文档明确了模块边界、profile、每日管线、事实与痕迹约束、行为接口、历史签名、质量审计、第二地点规则和禁止事项。

## 13. 测试结果

`tests/local_story_module_test.gd` 的 20 项断言全部通过，最终输出：

```text
[LOCAL STORY MODULE RESULT] PASS
```

以下回归入口全部返回 0：

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

## 14. 当前局限

- 当前只有湖湾镇一个模块样板，尚未用第二地点验证跨模块一致性。
- 湖湾镇每日推进仍由 `WorldSimulator` 统一调度，模块暂时是稳定包装层。
- `RegionSimProfile` 仍保留 `legacy_profile`，后续可按字段逐步迁移。
- `HistoryQualityAudit` 统一了最小字段，具体审计逻辑仍由地点审计器实现。

## 15. 下一步建议

下一步可以选择一个规模更小的第二地点，先实现 profile、模块接口、30 天批量 seed 和质量审计，再讨论跨模块事实传播。

在第二地点回归稳定前，不应接正式 UI，也不应把接口扩成事件池。

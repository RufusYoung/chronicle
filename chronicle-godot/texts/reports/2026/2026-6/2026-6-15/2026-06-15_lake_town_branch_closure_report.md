# 湖湾镇替代路径闭合与历史质量校准报告

## 1. 本次目标

本次工作属于替代路径闭合与历史质量校准层，不属于正式 UI 层。目标是在既有多 seed 历史分叉之后，继续从 `WorldFact`、NPC/地点状态、压力值、`Trace` 和 `Memory` 推导后续结果，并检查悬空路径、极端店铺状态和无理由分类。

本次没有扩写随机事件池，没有让 seed 直接决定剧情，也没有用 `outcome_class` 反向生成事实。

## 2. 新增 / 修改文件

新增：

- `scripts/sim/lake_town_branch_closure_system.gd`
- `scripts/dev/lake_town_history_quality_auditor.gd`
- `tests/lake_town_branch_closure_test.gd`
- `texts/reports/2026/2026-6/2026-6-15/2026-06-15_lake_town_history_quality_output.md`
- `texts/reports/2026/2026-6/2026-6-15/2026-06-15_lake_town_branch_closure_report.md`
- 两个 Godot 脚本 `.uid` 元数据文件

修改：

- `scripts/sim/world_simulator.gd`
- `scripts/sim/lake_town_food_chain.gd`
- `scripts/dev/lake_town_history_variation_runner.gd`
- `texts/reports/2026/2026-6/2026-6-15/2026-06-15_lake_town_history_variation_output.md`

## 3. 未修改的保护文件

以下保护文件未修改：

- `scenes/ui/story_player.gd`
- `scripts/gen/world_generation_v03.gd`
- `scenes/ui/mainui.tscn`
- `project.godot`
- `素材包/`

没有接入正式 UI，也没有改变当前 Demo 的无 profile 模拟行为。

## 4. 替代路径闭合系统

新增系统提供：

- `tick_branch_closure`
- `build_branch_closure_candidates`
- `apply_branch_closure`
- `has_branch_closure_happened`
- `record_branch_closure`

每日顺序为：

1. 宏观世界推进
2. 湖湾镇食物链
3. 微观反应
4. 恢复与关系回声
5. 替代路径闭合
6. 线索投影

闭合 tick 只在 `micro_state` 存在 `seed_profile` 时运行，因此正式 Demo 使用的默认 seed 行为不变。

## 5. 新增闭合规则

共实现 15 条规则，其中 12 条为任务要求的主要闭合，3 条用于保证早期帮助、赊账和未开口延期请求也留下后续。

主要闭合：

- `chen_mi_blocked_by_guard_seal`
- `guard_noticed_child_near_granary`
- `chen_mi_returned_empty_handed`
- `old_chen_saw_chen_mi_empty_handed`
- `chen_mi_weakened_from_enduring_hunger`
- `neighbor_noticed_silent_hungry_child`
- `old_chen_tried_to_delay_debt`
- `creditor_refused_delay_request`
- `chen_mi_found_other_family_tracks`
- `market_rumor_about_other_hungry_family`
- `old_chen_shop_forced_abnormal_closure`
- `old_chen_shop_half_open_under_debt`

补充回声：

- `ma_shen_early_help_became_household_memory`
- `old_chen_credit_purchase_raised_debt_pressure`
- `old_chen_withheld_delay_request`

所有闭合事实都有非空 `cause_fact_ids`，所有闭合痕迹都有 `source_fact_id`，同一 `closure_key` 不会每日重复生成。

## 6. 极端状态一致性规则

当老陈 `stress >= 95`、`debt >= 90`、店铺仍开门且没有半日恢复事实时，店铺进入强制异常关闭状态：

- `is_open = false`
- `partial_open = false`
- 状态标签加入 `forced_abnormal_closure`

若店铺已经通过恢复事实半日开门，但债务或债务压力仍高，则保留半开状态并加入 `half_open_under_debt`，使“开门但异常”有明确结构化解释。

## 7. 历史质量审计器

审计器检查：

- `dangling_major_fact`
- `impossible_shop_state`
- `unresolved_extreme_hunger`
- `unclassified_without_reason`
- `branch_closure_depth`
- `contradiction_flags`
- `consequence_depth`

它可审计单个签名、单个世界状态或批量结果，并生成独立 Markdown 质量输出。

## 8. 历史分类改进

分类改为根据实际事实组合返回 `outcome_class` 与 `outcome_reason`。新增或细化了守卫封仓、空粮仓返回、沉默饥饿衰弱、债务协商失败、其他家庭粮食冲突、强制闭店、带债半开和多路径交织等类别。

`mixed_or_unclassified` 不再作为默认值。`mixed_interwoven` 只用于多条结构化路径交织或无法归入单一主路径的实际事实组合，并始终附带原因。

## 9. 20 seed 闭合前后对比

| 指标 | 闭合前 | 闭合后 |
| --- | ---: | ---: |
| seed 数 | 20 | 20 |
| 唯一历史签名 | 20 | 20 |
| outcome_class 数 | 5 | 8 |
| 取粮 / 未取粮 | 5 / 15 | 7 / 13 |
| 守卫封仓主类 | 9 | 6 |
| mixed 类 | 4 | 3 |
| dangling_major_fact | 未审计 | 0 |
| impossible_shop_state | 可见异常状态 | 0 |
| 平均 branch_closure_depth | 未提供 | 3.05 |

守卫封仓判定阈值只在 profile 变体路径中由 `145` 调整为 `160`，降低该路径占比，不影响默认 Demo。

闭合后 17 个 seed 无质量警告，3 个 seed 仍被标记为 `unresolved_extreme_hunger`。这些 seed 已有店铺或债务后续，但孩子侧仍缺少更深的食物获得、迁移或照料结果，保留为后续校准问题。

## 10. 替代路径闭合样例

- Seed `2026061501`：Day 3 守卫封仓，Day 11 陈米被封条挡回，Day 12 守卫注意到孩子。
- Seed `2026061514`：Day 6 陈米发现空粮仓，Day 7 空手返回，Day 8 老陈看见她回来。
- Seed `2026061506`：Day 8 陈米忍耐饥饿，Day 10 变虚弱，Day 11 邻居注意到她。
- Seed `2026061509`：Day 12 老陈请求延期，Day 13 刘账房拒绝。
- Seed `2026061518`：Day 2 另一个家庭先取粮并形成市场传闻，Day 8 陈米发现陌生脚印。

## 11. 测试结果

新增 `lake_town_branch_closure_test.gd` 的 22 项断言全部通过，最终输出：

```text
[LAKE TOWN BRANCH CLOSURE RESULT] PASS
```

以下回归全部通过：

- `lake_town_history_variation_test.gd`
- `lake_town_recovery_system_test.gd`
- `lake_town_reaction_system_test.gd`
- `micro_action_resolver_test.gd`
- `lake_town_food_chain_test.gd`
- `world_sim_observer_test.gd`
- `world_news_digest_test.gd`
- `world_sim_lead_adapter_test.gd`
- `scripts/sim/world_sim_debug_runner.gd`
- `project_cleanup_smoke.gd`

任务说明把 debug runner 写在 `scripts/dev`，仓库实际路径是 `scripts/sim/world_sim_debug_runner.gd`，本次按实际路径执行并通过。

## 12. 当前局限

- 3 个 seed 仍有极端饥饿质量警告，说明“店铺闭合”不等于“孩子困境解决”。
- `mixed_interwoven` 已有明确原因，但仍是较粗的跨路径分类。
- 闭合规则目前只服务湖湾镇 profile 无头模拟，尚未抽象成通用地区规则框架。
- 质量审计针对最终状态和事实图，不记录每个数值处于极端区间的连续天数。

## 13. 下一步建议

后续可单独处理极端饥饿的二级闭合，例如邻居实际送食、家庭短期迁移、救济赊账或健康恶化，并为审计器增加连续天数窗口。完成这些校准后，再评估是否把闭合规则抽象成可复用的地区因果规则格式。

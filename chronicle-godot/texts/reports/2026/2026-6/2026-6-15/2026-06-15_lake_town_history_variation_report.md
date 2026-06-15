# 湖湾镇多 seed 历史差异验证报告

## 1. 本次目标

本次建立湖湾镇多 seed 历史差异验证层。验证目标是：同一套模拟规则在不同初始状态、NPC 性格、资源和外部压力下，可以产生可复现但不相同的局部历史。

本任务只涉及无头模拟、批量运行、历史签名、差异统计和观察输出。不接正式 UI，不扩写随机事件池，不让 seed 直接选择事实或结局，也不改变当前 Demo 的默认加载行为。

## 2. 新增 / 修改文件

新增：

- `scripts/sim/lake_town_seed_profile.gd`
- `scripts/dev/lake_town_history_variation_runner.gd`
- `tests/lake_town_history_variation_test.gd`
- `texts/reports/2026/2026-6/2026-6-15/2026-06-15_lake_town_history_variation_output.md`
- 本报告

修改：

- `scripts/sim/world_simulator.gd`
- `scripts/sim/lake_town_food_chain.gd`
- `scripts/sim/lake_town_reaction_system.gd`

任务指令归档于 `log/2026-6/2026-6-15/2026-06-15.4.md`。

## 3. 未修改的保护文件

未修改：

- `scenes/ui/story_player.gd`
- `scripts/gen/world_generation_v03.gd`
- `scenes/ui/mainui.tscn`
- `project.godot`
- `素材包/`

默认 `load_seed()` 继续使用原有固定种子数据。只有多 seed 运行器显式调用 `load_seed_with_lake_town_profile()` 时才应用差异 profile，因此当前 Demo 和既有单 seed 流程不受影响。

## 4. SeedProfile 结构

`LakeTownSeedProfile` 提供：

```gdscript
build_profile(seed_value: int) -> Dictionary
apply_profile_to_state(state: Variant, profile: Dictionary) -> void
describe_profile(profile: Dictionary) -> Dictionary
```

profile 包含：

- 宏观压力：初始匮乏、初始粮食、守卫压力、市场扰动。
- 老陈：债务、资金、家庭粮食、自尊、求助倾向、风险容忍。
- 陈米：饥饿、畏惧、胆量、对成年人的信任、抗病性。
- 玛婶：余粮、关注、风险规避、对老陈的信任。
- 刘账房：耐心、债权、严格程度。
- 废弃粮仓：发霉麦子库存、疾病风险、可见度、守卫关注。
- 湖湾镇集市：信用供给、邻里帮助、传闻速度、其他饥饿家庭压力。

## 5. 初始条件差异来源

seed 只初始化数值。它不会写入 `WorldFact`、Trace、Memory、NarratableState 或结局分类。

宏观偏置写入边境镇初始粮食与匮乏；人物字段写入对应 NPC；粮仓字段写入地点与物品库存；市场字段写入集市状态；守卫与市场压力写入微观状态。随后仍由每日宏观变化、粮食消耗、价格、债务、饥饿、人物倾向和地点状态共同推进。

## 6. 新增替代路径规则

新增七条结构化路径：

1. `ma_shen_helped_before_theft`：关注、余粮、信任和饥饿共同触发提前送食。
2. `old_chen_bought_food_on_credit`：求助倾向、自尊、信用供给、债务和家庭粮食共同触发赊账。
3. `chen_mi_found_empty_granary`：陈米达到找食条件，但粮仓库存已经为空。
4. `guard_locked_abandoned_granary`：守卫压力、粮仓可见度、守卫关注和宏观匮乏共同触发封锁。
5. `creditor_pressed_before_theft`：高债务、高严格度和低耐心共同触发提前催债。
6. `chen_mi_endured_hunger`：高畏惧、低胆量且缺少可靠食物来源时选择忍耐。
7. `other_family_took_granary_grain`：低邻里帮助、高匮乏、高其他家庭压力和剩余库存共同触发资源竞争。

每条路径均写入 `WorldFact`，对应 Trace 保存 `source_fact_id`；需要记忆或可叙述状态的路径同时写入 Memory 或 NarratableState。

## 7. HistorySignature 结构

历史签名包含：

- seed 与 profile 摘要。
- 16 类关键事实的首次发生日，缺失事实记为 `-1`。
- 陈米饥饿、恐惧、健康，老陈压力、债务，店铺开关和粮仓库存。
- NarratableState ID。
- Trace ID 与类型。
- Memory ID 与类型。
- 基于事实组合推导的 `outcome_class`。

历史 hash 不包含 seed 编号和 profile 本身，只使用事实日、最终状态、可叙述状态、Trace 类型、Memory 类型和结局分类，因此“唯一历史”不是由 seed 标签直接制造。

## 8. 结局分类规则

当前支持：

- `theft_sickness_debt`
- `theft_helped_recovery`
- `early_neighbor_help_no_theft`
- `credit_purchase_delayed_crisis`
- `empty_granary_no_theft`
- `guard_locked_granary`
- `early_debt_pressure`
- `endured_hunger_no_theft`
- `other_family_took_grain`
- `mixed_or_unclassified`

分类器只读取 `fact_days`。例如取粮、生病和催债同时存在时归为 `theft_sickness_debt`；提前帮助存在且没有取粮时归为 `early_neighbor_help_no_theft`。

## 9. 20 seed 批量结果

20 个 seed 各推进 30 天：

```text
唯一历史签名：20
结局类型：5
陈米取粮：5
陈米未取粮：15
出现替代路径：18
```

结局分布：

```text
guard_locked_granary: 9
mixed_or_unclassified: 4
endured_hunger_no_theft: 3
theft_helped_recovery: 3
empty_granary_no_theft: 1
```

日期范围：

```text
老陈闭店：Day 6 - Day 10
玛婶介入：Day 2 - Day 12
刘账房催债或提前催债：Day 1 - Day 13
```

## 10. 同 seed 复现性验证

运行器对前三个 seed 各重新完整运行一次。两次运行的完整 `HistorySignature` 和历史 hash 均一致。

专项测试还单独双跑 `2026061501`，结果一致。

## 11. 不同 seed 差异性验证

20 个 seed 得到 20 个不同历史 hash，并出现五种结局分类。

差异不仅来自最终数值，还包括：

- 关键事实是否发生。
- 关键事实发生日期。
- 是否取粮、吃粮、生病、闭店、恢复。
- 是否提前得到邻里帮助或市场信用。
- 粮仓是否为空、被其他家庭取走或被守卫封锁。
- Trace、Memory 和 NarratableState 组合。

## 12. 历史样例

- Seed `2026061501`：Day 1 守卫封锁粮仓，30 天内陈米未取粮。
- Seed `2026061504`：Day 3 老陈赊账，Day 10 陈米取粮并闭店，Day 12 吃粮，Day 13 催债。
- Seed `2026061506`：Day 8 陈米因高畏惧和低胆量忍耐饥饿，未取粮。
- Seed `2026061514`：Day 6 陈米发现粮仓为空，形成空手返回的事实、痕迹、记忆与可叙述状态。
- Seed `2026061515`：Day 1 老陈赊账，Day 8 陈米仍取粮并闭店，Day 12 玛婶送粥并促成半日开店。

完整 profile、事实日、最终状态、分类和 hash 位于单独的多 seed 输出文件。

## 13. 测试结果

专项测试 18 项断言全部通过，最终输出：

```text
[LAKE TOWN HISTORY VARIATION RESULT] PASS
```

以下回归测试全部通过：

- `lake_town_recovery_system_test.gd`
- `lake_town_reaction_system_test.gd`
- `micro_action_resolver_test.gd`
- `lake_town_food_chain_test.gd`
- `world_sim_observer_test.gd`
- `world_news_digest_test.gd`
- `world_sim_lead_adapter_test.gd`
- `world_sim_debug_runner.gd`
- `project_cleanup_smoke.gd`

同时通过 Godot 4.6.3 无头编辑器脚本扫描。清理冒烟当前通过标记为 `[SMOKE RESULT] PASS`。

## 14. 当前局限

- 本批样本中守卫封锁粮仓为 9 / 20，说明守卫压力组合目前相对强。
- 多个历史在 30 天末仍达到饥饿、债务或压力高位，危机缓解路径仍少于危机累积路径。
- `mixed_or_unclassified` 仍包含“发生取粮但未生病或未得到帮助”等组合，后续可继续细分，但本次没有为了增加类别强行修改事实。
- 当前只验证 20 个固定样本 seed，尚未建立大样本分布回归和阈值漂移警报。
- 多 seed 输出是开发者 Markdown，不是正式可视化工具。

## 15. 下一步建议

下一阶段可扩大到数百个 seed，统计路径频率、状态封顶率和关键事实日分布，并为守卫封锁、邻里援助、赊账与资源竞争建立可接受区间。完成分布稳定性验证后，再考虑让正式表现层只读取这些结构化历史结果；仍不应让 UI 或文本直接决定世界事实。

# 湖湾镇粮食危机最小因果链报告

## 1. 本次目标

本次在现有 `world_sim` 宏观模拟之上，加入一条可追溯、可复现的湖湾镇粮食危机微观因果链。它不是事件卡，也不依赖固定日期或随机抽取，而是由边境镇粮食压力、家庭库存、资金、饥饿与粮仓库存等结构化状态共同触发。

## 2. 新增 / 修改文件

新增：

- `scripts/sim/lake_town_food_chain.gd`
- `tests/lake_town_food_chain_test.gd`
- `texts/reports/2026/2026-06-13_lake_town_food_chain_report.md`

修改：

- `data/world_seed_mirror_lake.json`
- `scripts/sim/world_sim_state.gd`
- `scripts/sim/world_simulator.gd`
- `scripts/dev/world_sim_observer.gd`
- `tests/world_sim_observer_test.gd`
- `tests/world_news_digest_test.gd`
- `texts/reports/2026/2026-06-13_world_sim_observer_output.md`

其中 `world_news_digest_test.gd` 只调整事实计数口径：宏观新闻回归继续统计 `scope != "micro"` 的事实，因此宏观基线仍为 192 条，测试注入后仍为 202 条；新增的 3 条湖湾镇微观事实不会改变原有新闻断言。

## 3. 未修改的保护文件

以下保护文件未修改：

- `scripts/ui/story_player.gd`
- `scripts/world_generation_v03.gd`
- `scenes/mainui.tscn`
- `project.godot`
- `素材包` 目录下的素材

本次没有新增 UI、剧情播放逻辑或世界生成入口。

## 4. 微观对象结构

湖湾镇微观状态挂在 `WorldSimState.micro_state` 下，并通过 `macro_region_id = "border_town"` 读取宏观压力。

新增对象包括：

- NPC：`old_chen`、`chen_mi`
- 地点：`lake_town_market`、`old_chen_shop`、`abandoned_granary`
- 物品与状态标记：`spoiled_grain`、`price_notice`、`closed_shop`、`hidden_bag`、`grain_dust`
- 可追溯集合：`traces`
- 可叙述状态集合：`narratable_states`

这些对象都来自种子数据或模拟产生的结构化状态，不是观察器临时拼接的文本。

## 5. 老陈状态规则

老陈的家庭粮食、资金、债务、压力和需求每天根据宏观粮食压力与家庭消耗更新。边境镇 `scarcity` 上升、`food` 下降时，湖湾镇价格指数上升，店铺库存减少，家庭粮食也更难补充。

当家庭粮食不足且债务、资金短缺与压力达到阈值时，老陈关闭店铺。关店由状态组合触发，不依赖固定日期，并写入 `old_chen_closed_shop_due_to_family_crisis` 事实及 `closed_shop` Trace。

## 6. 陈米行为规则

陈米寻找食物时按以下优先级行动：

1. 家庭仍有可用粮食时，先消耗家庭粮食。
2. 老陈资金足够时，从市场购买食物。
3. 当陈米饥饿、家庭粮食不足、资金不足，并且已知废弃粮仓仍有存粮时，才取走发霉麦子。
4. 任一必要条件不满足时，不产生取粮事实，也不产生对应可叙述状态。

该行为是模拟规则根据状态作出的选择，不代表真实 UI 输入。

## 7. 废弃粮仓与发霉麦子

`abandoned_granary` 保存可用库存状态。陈米取粮后：

- 粮仓库存减少；
- `spoiled_grain` 进入陈米物品栏；
- 产生 `chen_mi_took_spoiled_grain` 事实；
- 产生粮袋、袖口粮尘和粮仓缺粮等 Trace。

因此“陈米拿到发霉麦子”同时改变地点、物品、NPC 和事实状态。

## 8. Trace 生成规则

本链会生成以下 Trace：

- `price_rise_notice`
- `child_hiding_bag`
- `spoiled_grain_bag`
- `grain_dust_on_sleeve`
- `granary_missing_grain`
- `closed_shop`

每条 Trace 都保存非空 `source_fact_id`，能够回溯到粮价上涨、陈米取粮或老陈关店的具体 `WorldFact`。Trace 只有在对应事实已发生时才生成。

## 9. 可叙述状态生成规则

当以下三个事实同时成立时，生成 `chen_mi_hiding_spoiled_grain_scene`：

- `lake_town_food_price_rising`
- `chen_mi_took_spoiled_grain`
- `old_chen_closed_shop_due_to_family_crisis`

该状态标题为“陈米藏着一袋发霉麦子”，保存完整的 `source_fact_ids` 和 `trace_ids`。基线运行中，它引用：

- `fact_d01_009_lake_town_food_price_rising`
- `fact_d06_044_chen_mi_took_spoiled_grain`
- `fact_d06_045_old_chen_closed_shop_due_to_family_crisis`
- `trace_closed_shop`
- `trace_price_rise_notice`
- `trace_child_hiding_bag`
- `trace_spoiled_grain_bag`

缺少任一必要前提时，不生成该可叙述状态。

## 10. 与宏观 world_sim 的连接方式

湖湾镇当前是 `border_town` 下的微观演示区域，不是新增的宏观 `RegionState`。每次宏观推进完成后，微观链读取边境镇的 `scarcity` 和 `food`，再更新湖湾镇价格、库存、家庭与 NPC 状态。

微观链产生的事实使用 `scope = "micro"`。它们进入统一事实存储和观察输出，但不会改变既有宏观新闻回归的事实计数口径，也不会生成新的 Lead 或事件池条目。

## 11. 观察输出样例

基线第 6 天，观察输出显示：

- 湖湾镇粮价指数达到 5.00；
- 老陈家庭粮食为 2.90，压力为 81.93，店铺已关闭；
- 陈米饥饿为 74.00，物品栏中有 `spoiled_grain`；
- 废弃粮仓库存降至 2；
- 当日新增取粮、关店事实及相关 Trace；
- 生成“陈米藏着一袋发霉麦子”可叙述状态，并列出完整原因与痕迹引用。

完整输出位于 `texts/reports/2026/2026-06-13_world_sim_observer_output.md`。

## 12. 测试结果

以下测试最终均通过：

- `lake_town_food_chain_test.gd`
- `world_sim_observer_test.gd`
- `world_news_digest_test.gd`
- `world_sim_lead_adapter_test.gd`
- `world_sim_debug_runner.gd`
- `project_cleanup_smoke.gd`

测试覆盖初始化、粮食充足时不取粮、各项必要前提分别缺失时不取粮、粮仓库存变化、陈米物品栏、三类事实、六类 Trace、关店状态、可叙述状态引用和相同种子复现。清理冒烟测试首次运行出现一次动态选项抽样断言不一致，立即复跑后全部通过；本次未修改 UI 或该测试涉及的受保护逻辑。

## 13. 当前局限

- 当前只覆盖老陈一家，尚未形成多家庭或多商户供需网络。
- 价格、消耗与压力采用确定性阈值，尚未建模运输、季节和替代食物。
- 湖湾镇仍是边境镇下的微观状态，不具备独立宏观区域生命周期。
- 可叙述状态只进入观察输出，尚未接入 UI、剧情播放器或 Lead。
- 微观状态尚未接入独立存档迁移。
- 冒烟测试中的动态选项抽样存在既有波动，后续应改成稳定种子或确定性断言。

## 14. 下一步建议

下一步可在保持状态驱动原则的前提下，加入市场补货、邻里援助和食物中毒等后果规则，并让多个微观家庭竞争同一批粮食资源。之后再评估如何将已验证的 `NarratableState` 接入剧情展示层，而不是直接从模拟器生成剧情文本。

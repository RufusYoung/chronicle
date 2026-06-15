# 湖湾镇极端饥饿二级闭合报告

## 1. 本次目标

本次任务属于极端饥饿二级闭合与生存出口校准层。目标是让湖湾镇 30 天批量模拟中达到极端饥饿的陈米，不再停留在“数值很高但世界没有继续记录”的悬空状态，而是由既有 NPC 状态、市场资源、店铺状态、WorldFact、Trace 与 Memory 推导出救助、迁移、资产牺牲、健康崩溃或坏结果记录。

本次没有接入正式 UI，没有新增事件池，没有让 seed 或 `outcome_class` 直接决定剧情结果。

## 2. 新增 / 修改文件

新增：

- `scripts/sim/lake_town_hunger_closure_system.gd`
- `scripts/sim/lake_town_hunger_closure_system.gd.uid`
- `tests/lake_town_hunger_closure_test.gd`
- `tests/lake_town_hunger_closure_test.gd.uid`
- `texts/reports/2026/2026-6/2026-6-15/2026-06-15_lake_town_hunger_closure_report.md`

修改：

- `scripts/sim/world_simulator.gd`
- `scripts/dev/lake_town_history_quality_auditor.gd`
- `scripts/dev/lake_town_history_variation_runner.gd`
- `texts/reports/2026/2026-6/2026-6-15/2026-06-15_lake_town_history_quality_output.md`
- `texts/reports/2026/2026-6/2026-6-15/2026-06-15_lake_town_history_variation_output.md`
- `log/2026-6/2026-6-15/2026-06-15.6.md`

## 3. 未修改的保护文件

以下文件和目录均未修改：

- `scenes/ui/story_player.gd`
- `scripts/gen/world_generation_v03.gd`
- `scenes/ui/mainui.tscn`
- `project.godot`
- `素材包/`

新的闭合层仅在 `micro_state` 存在 `seed_profile` 时运行，因此不会改变当前正式 Demo 的默认行为。

## 4. 极端饥饿状态结构

`micro_state.hunger_closure_state` 维护：

- `extreme_hunger_days`
- `last_extreme_hunger_day`
- `last_hunger_closure_day`
- `hunger_closure_history`
- `chen_mi_temporarily_relocated`
- `chen_mi_collapsed`
- `emergency_food_received`
- `critical_health_decline_recorded`

另保留最近饥饿值、健康值、缓解日和状态更新日，用于判断连续极端饥饿与健康下降。陈米饥饿低于 95 时，`extreme_hunger_days` 重置为 0；再次达到阈值后重新累计。

## 5. 二级闭合系统

每日顺序为：

1. world simulation 宏观推进
2. `lake_town_food_chain`
3. `lake_town_reaction_system`
4. `lake_town_recovery_system`
5. `lake_town_branch_closure_system`
6. `lake_town_hunger_closure_system`
7. 线索投影

系统每天最多自动结算一条新的极端饥饿闭合，避免同一天连续吞掉全部后续。规则只读取结构化状态和既有历史事实，所有写回均落为 WorldFact、Trace、Memory；需要展示的结果同时生成 NarratableState。

## 6. 八类二级闭合规则

已实现：

1. `chen_mi_collapsed_from_hunger`：连续极端饥饿或健康偏低时倒在店门口。
2. `ma_shen_emergency_food_for_chen_mi`：玛婶用自有食物或邻里支持紧急送食。
3. `old_chen_sold_shop_goods_for_food`：老陈牺牲店铺资产换取少量家庭食物。
4. `old_chen_took_chen_mi_to_seek_help`：闭店或异常关闭后，老陈带陈米去集市求助。
5. `lake_town_emergency_credit_food`：市场以临时赊食缓解饥饿，同时增加债务。
6. `chen_mi_health_crashed_from_hunger`：连续极端饥饿且缺少救助、迁移时记录健康严重恶化。
7. `chen_mi_temporarily_stayed_with_ma_shen`：紧急送食后，陈米在照看条件成立时暂住玛婶家。
8. `chen_mi_hunger_unresolved_but_recorded`：其他闭合均无法触发时记录坏结果，不再让历史悬空。

## 7. 历史质量审计器更新

单 seed 审计新增：

- `extreme_hunger_days`
- `hunger_closure_fact_count`
- `hunger_closure_type`
- `bad_outcome_recorded`

只有最终饥饿仍不低于 95、且没有任何 hunger closure fact、救助、迁移、健康崩溃或坏结果记录时，才标记 `unresolved_extreme_hunger`。

`chen_mi_health_crashed_from_hunger` 与 `chen_mi_hunger_unresolved_but_recorded` 会标记 `bad_hunger_outcome`，但不再算作悬空。

## 8. 20 seed 闭合前后对比

闭合前：

- `unresolved_extreme_hunger`：3
- 对应 seed：`2026061503`、`2026061507`、`2026061509`

闭合后：

- `unresolved_extreme_hunger`：0
- `bad_hunger_outcome`：4
- `emergency_food`：15
- `temporary_relocation`：20
- `health_crash`：4
- `hunger_unresolved_but_recorded`：0
- 唯一历史签名：20
- 结局分类：7

`temporary_relocation` 统计老陈带陈米离店求助或陈米暂住玛婶家的 seed，因此数值高于单独的“暂住玛婶家”事实数量。

## 9. 原 unresolved seed 的新后续

### Seed 2026061503

- Day 10：老陈卖掉店内物品换食物
- Day 12：陈米倒在店门口
- Day 13：老陈带陈米离店求助
- Day 14：湖湾镇提供临时救济赊食
- Day 19：玛婶紧急给陈米送食
- Day 21：陈米暂住玛婶家

### Seed 2026061507

- Day 5：陈米倒在店门口
- Day 6：陈米健康因饥饿严重恶化
- Day 7：老陈卖掉店内物品换食物
- Day 11：老陈带陈米离店求助

### Seed 2026061509

- Day 8：陈米倒在店门口
- Day 9：老陈带陈米离店求助
- Day 10：湖湾镇提供临时救济赊食
- Day 13：玛婶紧急给陈米送食
- Day 14：陈米暂住玛婶家

## 10. WorldFact / Trace / Memory 写回说明

所有新增 WorldFact 均包含：

- `cause_fact_ids`
- `hunger_closure_key`
- `world_cause = lake_town_hunger_closure`
- actors、location、effects 与 tags

所有新增 Trace 均包含 `source_fact_id`。每条规则至少写入一条 Memory；倒下、卖货、求助、健康崩溃、暂住与兜底记录同时生成可追溯的 NarratableState。

## 11. 测试结果

新增 `lake_town_hunger_closure_test.gd`，20 项断言全部通过，最终输出：

```text
[LAKE TOWN HUNGER CLOSURE RESULT] PASS
```

以下回归测试全部 PASS：

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

Godot 无头编辑器解析检查也通过。`project_cleanup_smoke.gd` 本次首次运行即 PASS。

## 12. 当前局限

- 该系统仍是湖湾镇 profile 批量模拟的质量校准层，不是正式通用生存系统。
- `emergency_food_received` 当前记录本轮历史中是否发生过紧急送食，没有实现长期后再次失去救助的衰减周期。
- 临时安置地点使用结构化 location id `ma_shen_home_temp`，尚未扩展为正式地点实体。
- 当前 20 seed 中兜底坏结果记录没有自然出现，但专项测试已覆盖其条件和写回。

## 13. 下一步建议

下一阶段可把极端饥饿闭合抽象为通用的生存压力闭合接口，并为救助有效期、临时安置地点、债务救济后续和长期健康恢复增加独立状态周期。正式 UI 仍应只读取可叙述状态，不参与历史事实生成。

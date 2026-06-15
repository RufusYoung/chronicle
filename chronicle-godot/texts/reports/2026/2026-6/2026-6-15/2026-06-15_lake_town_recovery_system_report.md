# 湖湾镇微观恢复与关系回声系统报告

## 1. 本次目标

在既有食物危机、微观行动与后续反应之后，增加可追溯的恢复和关系回声层。恢复不按固定日期触发，也不依赖随机事件池或文本判定，而是读取 `WorldFact`、`Trace`、`Memory`、关系、NPC 与地点状态。

## 2. 新增 / 修改文件

新增恢复系统及专项测试：

- `scripts/sim/lake_town_recovery_system.gd`
- `tests/lake_town_recovery_system_test.gd`
- 本报告

修改模拟器、反应系统、微观行动解析器、观察器、种子与相关回归测试，并重新生成 `2026-06-15_world_sim_observer_output.md`。

## 3. 未修改的保护文件

未修改：

- `scenes/ui/story_player.gd`
- `scripts/gen/world_generation_v03.gd`
- `scenes/ui/mainui.tscn`
- `project.godot`
- `素材包/`

本次没有接入正式 UI，也没有改变当前 Demo 的 UI 行为。

## 4. 微观关系结构

`micro_state.micro_relationships` 兼容迁移为多维关系结构，包含：

`trust`、`fear`、`gratitude`、`resentment`、`debt`、`familiarity`、`last_interaction_day`、`tags`。

同时保留 `source_fact_ids`、`source_memory_ids` 与 `history`。关系调整必须提供 `source_fact_id`，历史会记录日期、来源事实和数值变化或标签。

## 5. 恢复状态结构

`micro_state.recovery_state` 包含：

- `chen_mi_recovery_level`
- `old_chen_recovery_level`
- `shop_recovery_level`
- `community_support`
- `actor_reputation_in_lake_town`
- `actor_reputation_tags`
- `recovery_history`
- `last_recovery_day`

该结构只用于湖湾镇微观验证，不是正式角色声望系统。

## 6. 八类恢复与关系回声规则

五类恢复规则：

1. `chen_mi_stabilized_after_food_help`
2. `old_chen_softened_after_actor_help`
3. `old_chen_reopened_shop_half_day`
4. `ma_shen_kept_checking_on_chen_mi`
5. `creditor_delayed_collection_after_support`

三类关系回声：

1. `chen_mi_trust_echo_for_actor`
2. `chen_mi_avoidance_echo_for_actor`
3. `old_chen_closes_door_to_actor`

每条规则均检查结构化前置条件，并通过 `recovery_history` 防止逐日重复生成。

## 7. 行动候选受关系影响的规则

正向信任回声会生成 `chen_mi_recognizes_actor_scene`。陈米仍有明显恐惧时，新增 `comfort_chen_mi`，执行后生成 `actor_comforted_chen_mi`、`quiet_talk_at_shop_step` 和 `chen_mi_remembers_being_comforted`。

`chen_mi_avoidance_echo_for_actor` 会阻止 `ask_grain_origin` 与 `comfort_chen_mi`。`old_chen_closes_door_to_actor` 会阻止当前最小合作样例 `buy_spoiled_grain_low`。直接解析被阻止的行动会返回 `relationship_blocked`。

## 8. 无外部模拟行动时的恢复时间线

30 天基线中，Day 9 在玛婶送粥后生成：

- `ma_shen_kept_checking_on_chen_mi`
- `old_chen_reopened_shop_half_day`

对应留下 `neighbor_visit_marks`、`half_open_shop_door`、`limited_goods_on_shelf`，并产生持续探望与半日开店记忆。基线没有凭空生成面向测试 actor 的正向或负向回声。

## 9. 外部模拟行动后五日分支对照

`give_food_to_chen_mi`：陈米未立即吃发霉麦子；生成稳定、老陈缓和、信任回声、邻里持续探望和半日开店。五日后陈米对测试 actor 的 `trust=34`、`gratitude=35`，开放 `comfort_chen_mi`。

`ignore_chen_mi`：陈米吃下发霉麦子并生病，之后由玛婶介入并促成半日开店；没有面向测试 actor 的正向关系回声。

`report_to_guard`：守卫来访，陈米形成回避，老陈对测试 actor 关门。五日后陈米对测试 actor 的 `trust=-35`、`fear=40`、`resentment=37`，关系阻止询问、低价收购和安慰。

`buy_spoiled_grain_low`：发霉麦子被移出陈米物品栏，但饥饿压力仍高；陈米形成回避，老陈关门。五日后陈米对测试 actor 的 `trust=-30`、`resentment=37`，同样产生关系阻断。

四个分支都可能在邻里帮助后出现物理上的半日开店；举报和低价收购分支同时保留 `actor_access_blocked=true`，即店铺对社区半开，但拒绝该 actor。

## 10. WorldFact / Trace / Memory 写回说明

恢复和回声事实统一写入 `recovery_key` 或 `relationship_echo_key`，并保存非空 `cause_fact_ids`。

主要 Trace：

- `folded_food_wrap_kept_by_chen_mi`
- `shop_door_unlatched_for_actor`
- `neighbor_visit_marks`
- `half_open_shop_door`
- `limited_goods_on_shelf`
- `crossed_out_due_date_on_notice`
- `small_wave_from_chen_mi`
- `chen_mi_avoids_actor_gaze`
- `shop_door_closed_when_actor_near`

主要 Memory：

- `chen_mi_remembers_food_help_after_crisis`
- `old_chen_remembers_actor_helped_chen_mi`
- `kept_checking_on_chen_mi`
- `chen_mi_remembers_ma_shen_checking`
- `old_chen_remembers_reopening_half_day`
- `old_chen_remembers_delayed_collection`
- `chen_mi_recalls_actor_kindness`
- `chen_mi_recalls_actor_harm`
- `old_chen_remembers_actor_harmed_family`

所有恢复或回声 Trace 都保存对应 `source_fact_id`。

## 11. 观察输出变化

观察输出新增：

- `## 湖湾镇恢复与关系回声时间线`
- `## 外部模拟行动后五日恢复分支`

五日分支展示恢复事实、关系回声、最终 NPC 状态、店铺状态、双向关系、新增可叙述状态、可用候选与关系阻断候选。每日摘要只报告当天恢复/回声数量，不恢复完整状态 dump。

## 12. 测试结果

新增专项测试覆盖任务要求的 22 项断言，最终输出：

`[LAKE TOWN RECOVERY SYSTEM RESULT] PASS`

以下测试全部通过：

- `lake_town_recovery_system_test.gd`
- `lake_town_reaction_system_test.gd`
- `micro_action_resolver_test.gd`
- `lake_town_food_chain_test.gd`
- `world_sim_observer_test.gd`
- `world_news_digest_test.gd`
- `world_sim_lead_adapter_test.gd`
- `world_sim_debug_runner.gd`
- `project_cleanup_smoke.gd`

## 13. 当前局限

- `test_actor` 仍是无头验证对象，不是正式玩家实体。
- `actor_reputation_in_lake_town` 仅是局部实验字段。
- 暂缓催债规则已实现并由依赖测试覆盖，但当前 30 天自然基线通常先恢复半日营业，因此不一定自然出现催债后暂缓。
- 半日开店表示有限恢复，不代表食物、债务、健康和家庭压力彻底解决。

## 14. 下一步建议

后续可在保持结构化来源链的前提下，把关系拦截接口接给正式交互层；再扩展老陈债务协商、社区照看和更长期的恢复衰减规则。正式接入前仍应保持 UI 只读取状态，不决定事实。

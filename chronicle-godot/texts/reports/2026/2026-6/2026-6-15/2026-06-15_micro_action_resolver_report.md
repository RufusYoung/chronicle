# 湖湾镇微观行动解析报告

## 1. 本次目标

本次为 `chen_mi_hiding_spoiled_grain_scene` 增加微观行动解析与后果写回。行动候选由 NarratableState、Trace、测试 actor 和世界状态共同决定；结算后必须修改结构化世界状态，不能只生成文本。

本阶段只实现无头模拟行动，不接入正式 UI，不增加事件池，也不让叙述文本决定事实。

## 2. 新增 / 修改文件

新增：

- `scripts/sim/micro_action_resolver.gd`
- `tests/micro_action_resolver_test.gd`
- `texts/reports/2026/2026-6/2026-6-15/2026-06-15_world_sim_observer_output.md`
- `texts/reports/2026/2026-6/2026-6-15/2026-06-15_micro_action_resolver_report.md`

修改：

- `scripts/sim/world_sim_state.gd`
- `scripts/sim/lake_town_food_chain.gd`
- `scripts/dev/world_sim_observer.gd`
- `tests/world_sim_observer_test.gd`
- `data/world_seed_mirror_lake.json`

同时按当前仓库目录规划纳入了用户已完成的 2026-06-13 日志与报告目录迁移，以及本次任务指令 `log/2026-6/2026-6-15/2026-06-15.1.md`。

## 3. 未修改的保护文件

以下保护范围没有内容变更：

- `scenes/ui/story_player.gd`
- `scripts/gen/world_generation_v03.gd`
- `scenes/ui/mainui.tscn`
- `project.godot`
- `素材包/`

## 4. ActionCandidate 结构

当前候选包含：

- `id`
- `label`
- `source_narratable_state_id`
- `actor_id`
- `target_ids`
- `required_state`
- `visible_if`
- `risk`
- `outcome_preview`
- `condition_summary`
- `world_cause`
- `source_fact_ids`
- `trace_ids`
- `origin`

其中 `source_fact_ids` 和 `trace_ids` 直接复制自 NarratableState，保留行动与世界原因、可见痕迹之间的追溯关系。

## 5. 行动候选生成规则

- `give_food_to_chen_mi`：测试 actor 的 `inventory.food > 0`，且陈米饥饿值不低于 50。
- `ask_grain_origin`：世界中同时存在 `child_hiding_bag` 与 `spoiled_grain_bag` Trace。
- `report_to_guard`：守望者系统存在，且已有 `chen_mi_took_spoiled_grain` 事实。
- `ignore_chen_mi`：场景仍开放，测试 actor 可以离开。
- `buy_spoiled_grain_low`：测试 actor 有足够金钱，且陈米仍持有 `spoiled_grain`。

场景不存在、已经锁定或前置状态不足时，不生成对应候选，`can_resolve_action()` 返回 `false`。直接结算失败时返回 `ok: false` 与明确错误码。

## 6. 五类行动结算规则

- 给她食物：消耗一份食物，降低陈米的饥饿与恐惧，降低老陈压力，提高测试 actor 与老陈一家的信任。
- 问粮从哪来的：提高陈米少量恐惧，记录询问状态，并产生指向废弃粮仓的新痕迹。
- 举报她：提高陈米恐惧与老陈压力，降低关系信任，提高守望者关注度，并给老陈增加守卫关注状态。
- 装作没看见：不缓解饥饿，记录场景被看见但未解决，并锁定本次场景。
- 趁机低价收购：扣除测试 actor 金钱，将发霉麦子转入其临时背包，提高陈米恐惧和老陈压力，并降低关系信任。

每次成功结算都会更新 NarratableState 的状态、结算日和测试 actor 标识，并锁定场景，避免重复结算。

## 7. 状态写回说明

本次扩展了 `WorldSimState`：

- 增加 `memories` 集合。
- `snapshot()` 包含 Memory。
- 增加 `duplicate_state()`，深复制地区、势力、事实、新闻、线索、NPC、地点、物品、Trace、Memory、NarratableState 与随机数状态。

微观行动可写回测试 actor 临时状态、NPC 数值与标签、物品归属、地点 Trace、关系信任、守卫关注、Memory、WorldFact 和 NarratableState。观察器对同一场景基线分别克隆后结算五类行动，因此各组结果互不污染。

## 8. WorldFact / Trace / Memory 生成说明

| 行动 | WorldFact | Trace | Memory |
| --- | --- | --- | --- |
| `give_food_to_chen_mi` | `actor_gave_food_to_chen_mi` | `chen_mi_empty_food_wrap` | `chen_mi_remembers_actor_gave_food` |
| `ask_grain_origin` | `actor_asked_chen_mi_about_grain` | `granary_hint` | `chen_mi_was_asked_about_grain` |
| `report_to_guard` | `actor_reported_chen_mi_to_guard` | `guard_attention_at_old_chen_shop` | `chen_mi_remembers_actor_reported_her` |
| `ignore_chen_mi` | `actor_ignored_chen_mi_scene` | 无 | `scene_was_ignored` |
| `buy_spoiled_grain_low` | `actor_bought_spoiled_grain_low` | `missing_spoiled_grain_bag` | `chen_mi_remembers_actor_took_grain` |

五类行动全部生成 WorldFact，四类行动生成 Trace，五类行动生成 Memory。生成的事实保留场景来源事实、来源 Trace 和 `world_cause`。

## 9. 观察输出样例

观察输出新增：

- `湖湾镇可行动候选：`
- `## 湖湾镇模拟行动后果对照`
- 五个行动的 WorldFact、状态变化、Trace 和 Memory 摘要

输出明确说明各结果来自同一基线场景的独立克隆状态，是无头模拟行动，不是真实 UI 输入。输出只展示紧凑摘要，没有完整状态 dump。

观察输出路径：

`texts/reports/2026/2026-6/2026-6-15/2026-06-15_world_sim_observer_output.md`

## 10. 测试结果

以下测试全部 PASS：

- Godot 编辑器项目扫描与脚本解析
- `tests/micro_action_resolver_test.gd`
- `tests/lake_town_food_chain_test.gd`
- `tests/world_sim_observer_test.gd`
- `tests/world_news_digest_test.gd`
- `tests/world_sim_lead_adapter_test.gd`
- `scripts/sim/world_sim_debug_runner.gd`
- `tests/project_cleanup_smoke.gd`

专项测试覆盖候选数量、前置条件、失败错误、五类结算、WorldFact、Trace、Memory、至少两类状态变化、场景锁定和固定 seed 可复现性。

## 11. 当前局限

- 测试 actor 仍是临时 Dictionary，不是正式角色存档结构。
- 解析器当前只处理一个湖湾镇 NarratableState。
- Memory 目前是轻量结构化记录，尚未接入长期记忆衰减、检索或叙述系统。
- 微观行动结果尚未参与后续每日势力决策，也未接入正式 UI。
- 行动结算为单步原子操作，尚未处理多阶段确认、失败代价或异步响应。

## 12. 下一步建议

下一阶段可先统一正式 actor 与 Memory 数据结构，再让 WorldFact、Trace 和关系变化参与后续每日模拟。正式 UI 接入时应只消费 `build_action_candidates()` 的结果，并通过 `resolve_micro_action()` 写回状态，避免 UI 自行决定世界事实。

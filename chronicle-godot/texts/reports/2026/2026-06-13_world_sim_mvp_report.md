# world_sim_mvp 第一阶段报告

## 1. 本次目标

建立一个不依赖 UI 的最小世界演化核心，让地区资源、压力、势力目标和玩家行为能够共同改变世界，并将真实世界状态投影为新闻与线索候选。

本阶段未修改 `story_player.gd`、`world_generation_v03.gd`、`project.godot` 或 `素材包/`，也未把模拟结果接入当前 Demo。

## 2. 新增文件

- `scripts/sim/world_sim_state.gd`
- `scripts/sim/world_simulator.gd`
- `scripts/sim/world_to_leads_projector.gd`
- `scripts/sim/player_world_actions.gd`
- `scripts/sim/world_sim_debug_runner.gd`
- `data/world_seed_mirror_lake.json`
- `texts/reports/2026/2026-06-13_world_sim_mvp_report.md`

同时修正了根目录 `项目现状.md` 的测试状态，并在 `PROJECT_STRUCTURE.md` 中补充 Godot 版本和 world_sim 位置说明。

根目录旧设计资料将在后续单独任务审计，本阶段不处理。

## 3. 数据结构说明

`WorldSimState` 保存日期、固定种子、随机状态、地区、势力、世界事实、世界新闻和线索候选。

三个地区为：

- `mirror_lake_forest`
- `border_town`
- `old_ruins`

三个势力为：

- `wardens`
- `smugglers`
- `echo_cult`

地区状态包含危险、秩序、匮乏、神秘压力、人口、野兽和 food、herbs、relics、information 四类资源。

`WorldFact` 记录已经发生的真实变化。`WorldNews` 和 `LeadCandidate` 都保存关联事实 ID，避免脱离世界状态凭空生成。

## 4. 每日 tick 流程

每天按以下顺序推进：

1. 推进日期并降低旧线索新鲜度。
2. 计算地区资源自然变化。
3. 根据资源、人口、秩序、野兽和神秘压力计算地区压力。
4. 计算势力当前需求。
5. 每个势力根据目标和当前状态选择一个行动。
6. 结算地区、资源、势力和关系变化。
7. 更新地区动态标签。
8. 写入 `WorldFact` 并生成可听闻的 `WorldNews`。
9. 从最新世界状态与事实投影 `LeadCandidate`。

随机数状态保存在 `rng_state` 中。同一种子、相同行为序列可以复现相同演化。

## 5. 势力行动规则

守望者支持：

- `patrol`
- `suppress_smugglers`
- `seal_ruins`
- `escort_supplies`

走私者支持：

- `raid_supplies`
- `bribe_guards`
- `spread_rumor`
- `move_contraband`

回声教团支持：

- `gather_relics`
- `harvest_herbs`
- `perform_ritual`
- `spread_visions`

每个行动至少修改地区、资源、势力、关系或标签中的一项，并写入结构化世界事实。

## 6. 线索投影规则

当前支持七类线索：

- `smoke`
- `tracks`
- `rumor`
- `river`
- `apparition`
- `checkpoint`
- `caravan`

典型因果关系包括：

- 高匮乏和走私者袭击投影为商队线索。
- 教团仪式和高神秘压力投影为异象线索。
- 低秩序与高危险投影为烟柱线索。
- 野兽密度过高投影为足迹线索。
- 守望者安保行动投影为关卡线索。
- 情报市场活跃投影为传闻线索。
- 草药消耗和湖区神秘压力投影为河流线索。

所有线索都包含非空 `world_cause` 和 `related_fact_id`。

## 7. 玩家行为写回规则

当前提供：

- `help_faction`
- `steal_resource`
- `expose_secret`
- `ignore_crisis`
- `resolve_lead`

玩家帮助守望者时，会同时改变边境镇的粮食、匮乏和秩序，改变守望者力量与财富，削弱走私者力量与财富，并提高走私者对玩家的敌意。

其他行为同样至少修改两类世界内容，并写入世界事实；不会只追加文本日志。

## 8. 30 天无玩家干预模拟摘要

固定种子 `20260613` 的基线结果：

- 世界事实：192 条
- 世界新闻：98 条
- 线索候选：40 条
- 地区标签变化：12 次

线索数量：

- `apparition`：8
- `caravan`：8
- `checkpoint`：2
- `river`：3
- `rumor`：7
- `smoke`：5
- `tracks`：7

主要新闻来源包括守望者压制走私、护送补给，走私者袭击补给，教团收集遗物、采集草药、举行仪式、传播异象，以及地区标签变化。

第 30 天时，边境镇匮乏达到 98，旧日遗迹神秘压力达到 100，镜湖森林危险达到 71.66。三个势力的力量、财富、需求或关系均发生变化。

## 9. 第 3 天玩家干预后的对比摘要

B 组在第 3 天执行：

```text
help_faction(state, "wardens", "border_town")
```

第 10 天时，两组的地区状态、势力状态、新闻签名和线索签名已经全部不同。

第 30 天相对基线的主要差异：

- 边境镇危险降低 4.13。
- 边境镇秩序提高 1.53。
- 边境镇匮乏降低 22.63。
- 守望者力量提高 3.40，对玩家敌意降低 6。
- 走私者对玩家敌意提高 8。
- 世界新闻从 98 条变为 103 条。
- 线索候选从 40 条变为 39 条，商队线索从 8 条变为 7 条。

这证明玩家行为改变了后续势力选择和世界投影，而不仅是增加一条日志。

## 10. 验收标准完成情况

- 无玩家干预产生至少 3 条新闻：通过，实际 98 条。
- 产生至少 5 条线索：通过，实际 40 条。
- 至少一个地区标签变化：通过，实际 12 次。
- 势力力量、财富或敌意变化：通过。
- 至少两个地区主要指标明显变化：通过。
- 玩家干预后地区与势力不同：通过。
- 玩家干预后第 10 天新闻与线索不同：通过。
- 所有线索具有世界原因和关联事实：通过。
- Godot 4.6.3 stable 无头 Runner：通过。

Runner 最终输出：

```text
[WORLD SIM RESULT] PASS
```

## 11. 当前局限

- 数值平衡仍偏向长期恶化，边境镇匮乏和遗迹神秘压力容易接近上限。
- 势力目前每天只选择一个规则行动，还没有行动成本规划和长期项目。
- 新闻数量较多，尚未实现传播范围、失真链和去重摘要。
- 线索投影使用固定阈值，尚未接入当前 v0.3 的线索阶段与过期模型。
- 当前没有存档、完整单元测试或 CI。
- 根目录旧设计资料仍存在编码、重复和版本混杂问题，本阶段未扩大清理范围。

## 12. 下一步建议

新增一个独立适配层，将 `LeadCandidate` 映射为 v0.3 可接受的线索字典：

1. 将 `type` 映射到现有线索分类。
2. 将 `urgency`、`freshness`、`risk` 映射到现有数值字段。
3. 将 `possible_actions` 转换为当前目标化行动入口。
4. 保留 `world_cause` 与 `related_fact_id`，用于结果回写和调试。
5. 先通过测试脚本验证映射，不直接重构 `story_player.gd`。
6. 映射稳定后，再由现有 v0.3 世界对象按天请求 world_sim 输出。

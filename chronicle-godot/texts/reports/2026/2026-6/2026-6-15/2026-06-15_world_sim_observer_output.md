# world_sim 观察输出

## 1. 运行设置

- 固定 seed：`20260613`
- A 组：无模拟干预，运行 30 天
- B 组：第 3 天测试注入 `help_faction(state, "wardens", "border_town")`
- 输出为开发者观察数据，不接入正式 UI。

## 2. 无模拟干预 30 天总览

- 总量：world_fact 195（微观事实 3），world_news 41，新闻历史 13，LeadCandidate 40，适配后线索 40，Trace 6，可叙述状态 1
- 线索类型分布：`{"传闻":15,"河流":3,"烟柱":13,"足迹":9}`
- 30 天后地区最终状态：
  - border_town：danger 66.69 / order 0.00 / scarcity 98.00 / mystic 40.69 / food 3.61 / herbs 47.22 / relics 15.30 / information 100.00 / tags [danger_high, order_low, populated, resource_strained, scarcity_high, town, trade_route]
  - mirror_lake_forest：danger 71.66 / order 29.07 / scarcity 35.09 / mystic 65.59 / food 73.66 / herbs 61.65 / relics 22.30 / information 53.74 / tags [danger_high, forest, herb_rich, lake, order_low]
  - old_ruins：danger 100.00 / order 0.00 / scarcity 58.96 / mystic 100.00 / food 28.66 / herbs 62.82 / relics 57.32 / information 55.94 / tags [danger_high, mystic_surge, order_low, relic_rich, resource_strained, ruins, unstable]
- 30 天后势力最终状态：
  - echo_cult：power 72.30 / wealth 48.10 / hostility 0.00 / goal 获取遗物与草药，提高神秘压力并制造异象
  - smugglers：power 42.60 / wealth 100.00 / hostility 0.00 / goal 获取财富和情报，利用匮乏并削弱地区秩序
  - wardens：power 79.40 / wealth 10.00 / hostility 0.00 / goal 维护秩序、压制走私者、阻止回声教团扩张
- 地区 tag 变化：
  - border_town：新增 [danger_high, order_low, resource_strained, scarcity_high]，移除 []
  - mirror_lake_forest：新增 [danger_high, order_low]，移除 []
  - old_ruins：新增 [danger_high, mystic_surge, order_low, resource_strained]，移除 []

## 湖湾镇微观链观察

- 当前微观区域从 `border_town` 读取宏观粮食与匮乏压力，尚未独立为正式 RegionState。
- 粮价指数：5.00；微观事实：3；Trace：6；可叙述状态：1
- 可叙述状态：陈米藏着一袋发霉麦子
  原因：lake_town_food_price_rising (fact_d01_009_lake_town_food_price_rising) -> chen_mi_took_spoiled_grain (fact_d06_044_chen_mi_took_spoiled_grain) -> old_chen_closed_shop_due_to_family_crisis (fact_d06_045_old_chen_closed_shop_due_to_family_crisis)
  痕迹：closed_shop (trace_closed_shop) -> price_rise_notice (trace_price_rise_notice) -> child_hiding_bag (trace_child_hiding_bag) -> spoiled_grain_bag (trace_spoiled_grain_bag)

湖湾镇可行动候选：
- 给她食物：需要 actor.inventory.food > 0
- 问粮从哪来的：需要 child_hiding_bag 与 spoiled_grain_bag Trace
- 举报她：需要守卫系统存在
- 装作没看见：无特殊条件
- 趁机低价收购：需要 actor.money > 0 且陈米持有 spoiled_grain

## 湖湾镇模拟行动后果对照

- 以下结果来自同一基线场景的独立克隆状态，是无头模拟行动，不是真实 UI 输入。

### give_food_to_chen_mi

- 新事实：actor_gave_food_to_chen_mi
- 状态变化：actor.inventory.food: 1 -> 0；chen_mi.fear: 41.50 -> 31.50；chen_mi.hunger: 74.00 -> 39.00；chen_mi.status_tags: ["hiding_spoiled_grain","disease_risk"] -> ["hiding_spoiled_grain","disease_risk","helped_by_actor"]；micro_relationships: {} -> {"test_actor":{"chen_mi":{"last_interaction_day":6,"trust":20.0},"old_chen":{"last_interaction_day":6,"trust":8.0}}}；old_chen.stress: 81.93 -> 73.93
- 新 Trace：chen_mi_empty_food_wrap
- 新 Memory：chen_mi_remembers_actor_gave_food

### ask_grain_origin

- 新事实：actor_asked_chen_mi_about_grain
- 状态变化：chen_mi.fear: 41.50 -> 45.50；chen_mi.status_tags: ["hiding_spoiled_grain","disease_risk"] -> ["hiding_spoiled_grain","disease_risk","asked_about_grain"]
- 新 Trace：granary_hint
- 新 Memory：chen_mi_was_asked_about_grain

### report_to_guard

- 新事实：actor_reported_chen_mi_to_guard
- 状态变化：chen_mi.fear: 41.50 -> 61.50；chen_mi.status_tags: ["hiding_spoiled_grain","disease_risk"] -> ["hiding_spoiled_grain","disease_risk","reported_to_guard"]；guard_attention: {"wardens":0.0} -> {"wardens":25.0}；micro_relationships: {} -> {"test_actor":{"chen_mi":{"last_interaction_day":6,"trust":-25.0},"old_chen":{"last_interaction_day":6,"trust":-15.0}}}；old_chen.status_tags: ["family_crisis","shop_closed"] -> ["family_crisis","shop_closed","guard_attention"]；old_chen.stress: 81.93 -> 93.93
- 新 Trace：guard_attention_at_old_chen_shop
- 新 Memory：chen_mi_remembers_actor_reported_her

### ignore_chen_mi

- 新事实：actor_ignored_chen_mi_scene
- 状态变化：chen_mi.status_tags: ["hiding_spoiled_grain","disease_risk"] -> ["hiding_spoiled_grain","disease_risk","scene_ignored"]
- 新 Trace：无
- 新 Memory：scene_was_ignored

### buy_spoiled_grain_low

- 新事实：actor_bought_spoiled_grain_low
- 状态变化：actor.inventory.spoiled_grain: 0 -> 1；actor.money: 10.00 -> 9.00；chen_mi.fear: 41.50 -> 53.50；chen_mi.hunger: 74.00 -> 71.00；chen_mi.inventory: ["spoiled_grain"] -> []；chen_mi.status_tags: ["hiding_spoiled_grain","disease_risk"] -> ["hiding_spoiled_grain","disease_risk","grain_taken_by_actor"]；micro_relationships: {} -> {"test_actor":{"chen_mi":{"last_interaction_day":6,"trust":-20.0},"old_chen":{"last_interaction_day":6,"trust":-10.0}}}；old_chen.stress: 81.93 -> 89.93
- 新 Trace：missing_spoiled_grain_bag
- 新 Memory：chen_mi_remembers_actor_took_grain


## 3. 每日摘要

### Day 1

地区摘要：
- border_town：danger 35.02 / order 71.13 / scarcity 70.92 / mystic 24.39 / food 51.43 / herbs 40.33 / relics 17.78 / information 68.70 / tags [populated, scarcity_high, stable, town, trade_route]
- mirror_lake_forest：danger 52.48 / order 38.70 / scarcity 41.48 / mystic 54.97 / food 61.15 / herbs 83.07 / relics 24.88 / information 47.50 / tags [forest, herb_rich, lake]
- old_ruins：danger 77.52 / order 17.14 / scarcity 31.10 / mystic 71.17 / food 21.23 / herbs 55.62 / relics 84.03 / information 51.41 / tags [danger_high, mystic_surge, order_low, relic_rich, resource_strained, ruins, unstable]

势力摘要：
- echo_cult：power 47.00 / wealth 36.00 / hostility 0.00 / goal 获取遗物与草药，提高神秘压力并制造异象
- smugglers：power 46.50 / wealth 55.00 / hostility 0.00 / goal 获取财富和情报，利用匮乏并削弱地区秩序
- wardens：power 62.70 / wealth 57.00 / hostility 0.00 / goal 维护秩序、压制走私者、阻止回声教团扩张

湖湾镇微观状态：
- old_chen：stress 35.51 / debt 39.53 / family_food 21.10 / shop_open true / tags []
- chen_mi：hunger 45.00 / fear 20.00 / health 88.00 / inventory [] / tags []
- old_chen_shop：is_open true / food_stock 26.49 / family_crisis false / traces [trace_price_rise_notice]
- abandoned_granary：spoiled_grain_stock 3.00 / disease_risk 0.65 / traces []
湖湾镇新增事实：
- lake_town_food_price_rising / fact_d01_009_lake_town_food_price_rising / causes [fact_d01_005_raid_supplies]
湖湾镇新增痕迹：
- price_rise_notice / trace_price_rise_notice / source fact_d01_009_lake_town_food_price_rising
湖湾镇可叙述状态：

当天新新闻：
- border_town / 镜湖守望者 / 阶段 1 / 累计 1：守望者突袭了边境镇的走私据点。
- border_town / 雾路走私团 / 阶段 1 / 累计 1：一批补给在边境镇外被截走。
- old_ruins / 回声教团 / 阶段 1 / 累计 1：回声教团从遗迹深处带出了遗物。

连续事件摘要：
- 无

当天 LeadCandidate：
- caravan / scarcity_high_and_smuggler_raid / fact_d01_005_raid_supplies / risk 0.53 / urgency 0.71
- apparition / cult_ritual_and_mystic_pressure / fact_d01_003_region_daily_shift / risk 0.74 / urgency 0.71
- checkpoint / warden_security_response / fact_d01_004_suppress_smugglers / risk 0.29 / urgency 0.71

当天适配后 v0.3 线索：
- 烟柱 / 远处商队烟迹 / 东南 / freshness 1.00 / risk 0.53 / 调查, 护送, 劫掠, 放任
- 传闻 / 关于旧遗迹异象的传闻 / 北方 / freshness 1.00 / risk 0.74 / 观察, 打断, 跟随, 报告
- 足迹 / 道旁新设的盘查痕迹 / 东南 / freshness 1.00 / risk 0.29 / 配合盘查, 询问, 绕过关卡, 举报走私

### Day 2

地区摘要：
- border_town：danger 36.07 / order 70.20 / scarcity 76.11 / mystic 24.66 / food 45.42 / herbs 40.51 / relics 17.54 / information 68.29 / tags [populated, scarcity_high, stable, town, trade_route]
- mirror_lake_forest：danger 52.96 / order 38.41 / scarcity 42.90 / mystic 56.31 / food 62.31 / herbs 77.72 / relics 24.86 / information 46.92 / tags [forest, herb_rich, lake]
- old_ruins：danger 78.09 / order 16.27 / scarcity 32.16 / mystic 71.52 / food 21.97 / herbs 55.95 / relics 84.07 / information 50.86 / tags [danger_high, mystic_surge, order_low, relic_rich, resource_strained, ruins, unstable]

势力摘要：
- echo_cult：power 47.50 / wealth 37.20 / hostility 0.00 / goal 获取遗物与草药，提高神秘压力并制造异象
- smugglers：power 45.00 / wealth 58.00 / hostility 0.00 / goal 获取财富和情报，利用匮乏并削弱地区秩序
- wardens：power 63.40 / wealth 56.00 / hostility 0.00 / goal 维护秩序、压制走私者、阻止回声教团扩张

湖湾镇微观状态：
- old_chen：stress 39.62 / debt 41.22 / family_food 18.01 / shop_open true / tags []
- chen_mi：hunger 50.00 / fear 20.00 / health 88.00 / inventory [] / tags []
- old_chen_shop：is_open true / food_stock 24.88 / family_crisis false / traces [trace_price_rise_notice]
- abandoned_granary：spoiled_grain_stock 3.00 / disease_risk 0.65 / traces []
湖湾镇微观链：无新增事实、痕迹或可叙述状态。

当天新新闻：
- mirror_lake_forest / 回声教团 / 阶段 1 / 累计 1：森林中的稀有草药被成批采走。

连续事件摘要：
- border_town / 阶段 1 / 累计 2：守望者清剿走私据点已持续 2 次，盘查与暗线活动同时增加。
- border_town / 阶段 1 / 累计 2：走私者袭击补给线已持续 2 次，边境镇粮食压力仍在升高。

当天 LeadCandidate：
- 无

当天适配后 v0.3 线索：
- 无

### Day 3

地区摘要：
- border_town：danger 37.13 / order 67.23 / scarcity 81.59 / mystic 26.85 / food 38.92 / herbs 40.13 / relics 17.57 / information 72.76 / tags [populated, scarcity_high, town, trade_route]
- mirror_lake_forest：danger 53.48 / order 38.10 / scarcity 42.27 / mystic 56.22 / food 63.46 / herbs 78.33 / relics 24.87 / information 47.55 / tags [beast_migration, forest, herb_rich, lake]
- old_ruins：danger 78.69 / order 15.38 / scarcity 33.25 / mystic 71.82 / food 21.56 / herbs 56.09 / relics 83.94 / information 50.96 / tags [danger_high, mystic_surge, order_low, relic_rich, resource_strained, ruins, unstable]

势力摘要：
- echo_cult：power 48.10 / wealth 37.20 / hostility 0.00 / goal 获取遗物与草药，提高神秘压力并制造异象
- smugglers：power 43.50 / wealth 61.00 / hostility 0.00 / goal 获取财富和情报，利用匮乏并削弱地区秩序
- wardens：power 64.10 / wealth 55.00 / hostility 0.00 / goal 维护秩序、压制走私者、阻止回声教团扩张

湖湾镇微观状态：
- old_chen：stress 44.70 / debt 43.13 / family_food 14.64 / shop_open true / tags []
- chen_mi：hunger 55.00 / fear 20.00 / health 88.00 / inventory [] / tags []
- old_chen_shop：is_open true / food_stock 23.11 / family_crisis false / traces [trace_price_rise_notice]
- abandoned_granary：spoiled_grain_stock 3.00 / disease_risk 0.65 / traces []
湖湾镇微观链：无新增事实、痕迹或可叙述状态。

当天新新闻：
- border_town / 镜湖守望者 / 阶段 2 / 累计 3：守望者连续清剿走私据点，路口盘查变多。
- border_town / 雾路走私团 / 阶段 2 / 累计 3：补给线已遇袭 3 次，边境镇的空货架越来越多。
- border_town / 回声教团 / 阶段 1 / 累计 1：镇民开始梦见同一片倒悬的湖面。

连续事件摘要：
- border_town / 阶段 2 / 累计 3：守望者清剿走私据点已持续 3 次，盘查与暗线活动同时增加。
- border_town / 阶段 2 / 累计 3：走私者袭击补给线已持续 3 次，边境镇粮食压力仍在升高。

当天 LeadCandidate：
- tracks / beast_migration / fact_d03_017_region_daily_shift / risk 0.62 / urgency 0.70
- rumor / smuggler_information_market / fact_d03_016_region_daily_shift / risk 0.44 / urgency 0.73

当天适配后 v0.3 线索：
- 足迹 / 林中迁徙足迹 / 西北 / freshness 1.00 / risk 0.62 / 狩猎, 跟随, 设陷, 警告旅人
- 传闻 / 镇上的低声传闻 / 东南 / freshness 1.00 / risk 0.44 / 核实, 购买情报, 散播消息, 报告

### Day 4

地区摘要：
- border_town：danger 38.26 / order 66.21 / scarcity 87.38 / mystic 26.91 / food 32.17 / herbs 40.29 / relics 17.47 / information 72.45 / tags [populated, resource_strained, scarcity_high, town, trade_route]
- mirror_lake_forest：danger 54.03 / order 37.79 / scarcity 41.66 / mystic 56.40 / food 63.20 / herbs 78.84 / relics 24.88 / information 48.47 / tags [beast_migration, forest, herb_rich, lake]
- old_ruins：danger 82.32 / order 12.98 / scarcity 34.28 / mystic 78.54 / food 22.71 / herbs 56.01 / relics 83.81 / information 51.73 / tags [danger_high, mystic_surge, order_low, relic_rich, resource_strained, ruins, unstable]

势力摘要：
- echo_cult：power 49.60 / wealth 36.70 / hostility 0.00 / goal 获取遗物与草药，提高神秘压力并制造异象
- smugglers：power 42.00 / wealth 64.00 / hostility 0.00 / goal 获取财富和情报，利用匮乏并削弱地区秩序
- wardens：power 64.80 / wealth 54.00 / hostility 0.00 / goal 维护秩序、压制走私者、阻止回声教团扩张

湖湾镇微观状态：
- old_chen：stress 50.93 / debt 45.35 / family_food 10.90 / shop_open true / tags []
- chen_mi：hunger 60.00 / fear 20.00 / health 88.00 / inventory [] / tags []
- old_chen_shop：is_open true / food_stock 21.13 / family_crisis false / traces [trace_price_rise_notice]
- abandoned_granary：spoiled_grain_stock 3.00 / disease_risk 0.65 / traces []
湖湾镇微观链：无新增事实、痕迹或可叙述状态。

当天新新闻：
- old_ruins / 回声教团 / 阶段 1 / 累计 1：旧日遗迹上空出现了不自然的回声。
- border_town / 地区观察 / 阶段 1 / 累计 1：边境镇 的状态标签发生变化：populated, resource_strained, scarcity_high, town, trade_route

连续事件摘要：
- border_town / 阶段 2 / 累计 4：守望者清剿走私据点已持续 4 次，盘查与暗线活动同时增加。
- border_town / 阶段 2 / 累计 4：走私者袭击补给线已持续 4 次，边境镇粮食压力仍在升高。

当天 LeadCandidate：
- 无

当天适配后 v0.3 线索：
- 无

### Day 5

地区摘要：
- border_town：danger 38.60 / order 63.63 / scarcity 86.42 / mystic 27.06 / food 34.47 / herbs 40.23 / relics 17.24 / information 72.53 / tags [populated, resource_strained, scarcity_high, town, trade_route]
- mirror_lake_forest：danger 54.57 / order 37.49 / scarcity 43.06 / mystic 57.89 / food 62.80 / herbs 73.76 / relics 24.81 / information 49.29 / tags [beast_migration, forest, herb_rich, lake]
- old_ruins：danger 83.10 / order 12.05 / scarcity 35.29 / mystic 79.64 / food 23.30 / herbs 56.16 / relics 83.75 / information 51.88 / tags [danger_high, mystic_surge, order_low, relic_rich, resource_strained, ruins, unstable]

势力摘要：
- echo_cult：power 50.10 / wealth 37.90 / hostility 0.00 / goal 获取遗物与草药，提高神秘压力并制造异象
- smugglers：power 42.70 / wealth 66.80 / hostility 0.00 / goal 获取财富和情报，利用匮乏并削弱地区秩序
- wardens：power 65.30 / wealth 52.00 / hostility 0.00 / goal 维护秩序、压制走私者、阻止回声教团扩张

湖湾镇微观状态：
- old_chen：stress 58.35 / debt 47.85 / family_food 6.90 / shop_open true / tags []
- chen_mi：hunger 65.00 / fear 20.00 / health 88.00 / inventory [] / tags []
- old_chen_shop：is_open true / food_stock 18.95 / family_crisis false / traces [trace_price_rise_notice]
- abandoned_granary：spoiled_grain_stock 3.00 / disease_risk 0.65 / traces []
湖湾镇微观链：无新增事实、痕迹或可叙述状态。

当天新新闻：
- border_town / 镜湖守望者 / 阶段 1 / 累计 1：已护送 1 批粮车，边境镇的粮食压力仍未解除。
- border_town / 雾路走私团 / 阶段 3 / 累计 5：补给线已遇袭 5 次，边境镇的空货架越来越多。

连续事件摘要：
- border_town / 阶段 3 / 累计 5：走私者袭击补给线已持续 5 次，边境镇粮食压力仍在升高。
- border_town / 阶段 2 / 累计 4：守望者清剿走私据点已持续 4 次，盘查与暗线活动同时增加。
- mirror_lake_forest / 阶段 1 / 累计 2：森林草药采集已持续 2 次，湖岸资源压力继续累积。

当天 LeadCandidate：
- caravan / scarcity_high_and_smuggler_raid / fact_d05_035_raid_supplies / risk 0.63 / urgency 0.86
- apparition / cult_ritual_and_mystic_pressure / fact_d05_033_region_daily_shift / risk 0.81 / urgency 0.80
- checkpoint / warden_security_response / fact_d05_034_escort_supplies / risk 0.36 / urgency 0.64

当天适配后 v0.3 线索：
- 烟柱 / 远处商队烟迹 / 东南 / freshness 1.00 / risk 0.63 / 调查, 护送, 劫掠, 放任
- 传闻 / 关于旧遗迹异象的传闻 / 北方 / freshness 1.00 / risk 0.81 / 观察, 打断, 跟随, 报告
- 足迹 / 道旁新设的盘查痕迹 / 东南 / freshness 1.00 / risk 0.36 / 配合盘查, 询问, 绕过关卡, 举报走私

### Day 6

地区摘要：
- border_town：danger 38.99 / order 59.05 / scarcity 85.40 / mystic 28.89 / food 35.98 / herbs 40.04 / relics 17.28 / information 76.36 / tags [populated, scarcity_high, town, trade_route]
- mirror_lake_forest：danger 55.14 / order 37.17 / scarcity 42.48 / mystic 58.18 / food 62.37 / herbs 74.42 / relics 24.60 / information 49.18 / tags [beast_migration, forest, herb_rich, lake]
- old_ruins：danger 83.91 / order 11.10 / scarcity 36.33 / mystic 80.79 / food 22.51 / herbs 55.56 / relics 83.64 / information 51.83 / tags [danger_high, mystic_surge, order_low, relic_rich, resource_strained, ruins, unstable]

势力摘要：
- echo_cult：power 50.70 / wealth 37.90 / hostility 0.00 / goal 获取遗物与草药，提高神秘压力并制造异象
- smugglers：power 43.40 / wealth 69.60 / hostility 0.00 / goal 获取财富和情报，利用匮乏并削弱地区秩序
- wardens：power 65.80 / wealth 50.00 / hostility 0.00 / goal 维护秩序、压制走私者、阻止回声教团扩张

湖湾镇微观状态：
- old_chen：stress 81.93 / debt 50.63 / family_food 2.90 / shop_open false / tags [family_crisis, shop_closed]
- chen_mi：hunger 74.00 / fear 41.50 / health 84.00 / inventory [spoiled_grain] / tags [hiding_spoiled_grain, disease_risk]
- old_chen_shop：is_open false / food_stock 16.58 / family_crisis true / traces [trace_price_rise_notice, trace_child_hiding_bag, trace_spoiled_grain_bag, trace_grain_dust_on_sleeve, trace_closed_shop]
- abandoned_granary：spoiled_grain_stock 2.00 / disease_risk 0.65 / traces [trace_granary_missing_grain]
湖湾镇新增事实：
- chen_mi_took_spoiled_grain / fact_d06_044_chen_mi_took_spoiled_grain / causes [fact_d01_009_lake_town_food_price_rising]
- old_chen_closed_shop_due_to_family_crisis / fact_d06_045_old_chen_closed_shop_due_to_family_crisis / causes [fact_d01_009_lake_town_food_price_rising, fact_d06_044_chen_mi_took_spoiled_grain]
湖湾镇新增痕迹：
- child_hiding_bag / trace_child_hiding_bag / source fact_d06_044_chen_mi_took_spoiled_grain
- spoiled_grain_bag / trace_spoiled_grain_bag / source fact_d06_044_chen_mi_took_spoiled_grain
- grain_dust_on_sleeve / trace_grain_dust_on_sleeve / source fact_d06_044_chen_mi_took_spoiled_grain
- granary_missing_grain / trace_granary_missing_grain / source fact_d06_044_chen_mi_took_spoiled_grain
- closed_shop / trace_closed_shop / source fact_d06_045_old_chen_closed_shop_due_to_family_crisis
湖湾镇可叙述状态：
- 可叙述状态：陈米藏着一袋发霉麦子
  原因：lake_town_food_price_rising (fact_d01_009_lake_town_food_price_rising) -> chen_mi_took_spoiled_grain (fact_d06_044_chen_mi_took_spoiled_grain) -> old_chen_closed_shop_due_to_family_crisis (fact_d06_045_old_chen_closed_shop_due_to_family_crisis)
  痕迹：closed_shop (trace_closed_shop) -> price_rise_notice (trace_price_rise_notice) -> child_hiding_bag (trace_child_hiding_bag) -> spoiled_grain_bag (trace_spoiled_grain_bag)

当天新新闻：
- border_town / 地区观察 / 阶段 1 / 累计 2：边境镇 的状态标签发生变化：populated, scarcity_high, town, trade_route（第 2 次进入该状态）

连续事件摘要：
- border_town / 阶段 3 / 累计 6：走私者袭击补给线已持续 6 次，边境镇粮食压力仍在升高。
- border_town / 阶段 2 / 累计 4：守望者清剿走私据点已持续 4 次，盘查与暗线活动同时增加。
- border_town / 阶段 1 / 累计 2：回声教团的相关活动已持续 2 次，旧日遗迹神秘压力维持高位。

当天 LeadCandidate：
- 无

当天适配后 v0.3 线索：
- 无

### Day 7

地区摘要：
- border_town：danger 40.27 / order 57.99 / scarcity 91.36 / mystic 29.05 / food 28.30 / herbs 39.59 / relics 17.06 / information 76.87 / tags [populated, resource_strained, scarcity_high, town, trade_route]
- mirror_lake_forest：danger 55.72 / order 36.85 / scarcity 41.86 / mystic 58.08 / food 63.39 / herbs 75.29 / relics 24.59 / information 49.00 / tags [beast_migration, forest, herb_rich, lake]
- old_ruins：danger 85.72 / order 10.15 / scarcity 37.40 / mystic 83.16 / food 21.88 / herbs 55.46 / relics 79.56 / information 51.83 / tags [danger_high, mystic_surge, order_low, relic_rich, resource_strained, ruins, unstable]

势力摘要：
- echo_cult：power 51.70 / wealth 38.90 / hostility 0.00 / goal 获取遗物与草药，提高神秘压力并制造异象
- smugglers：power 41.90 / wealth 72.60 / hostility 0.00 / goal 获取财富和情报，利用匮乏并削弱地区秩序
- wardens：power 66.50 / wealth 49.00 / hostility 0.00 / goal 维护秩序、压制走私者、阻止回声教团扩张

湖湾镇微观状态：
- old_chen：stress 91.60 / debt 53.76 / family_food 0.00 / shop_open false / tags [family_crisis, shop_closed]
- chen_mi：hunger 85.00 / fear 43.00 / health 84.00 / inventory [spoiled_grain] / tags [hiding_spoiled_grain, disease_risk]
- old_chen_shop：is_open false / food_stock 14.08 / family_crisis true / traces [trace_price_rise_notice, trace_child_hiding_bag, trace_spoiled_grain_bag, trace_grain_dust_on_sleeve, trace_closed_shop]
- abandoned_granary：spoiled_grain_stock 2.00 / disease_risk 0.65 / traces [trace_granary_missing_grain]
湖湾镇微观链：无新增事实、痕迹或可叙述状态。

当天新新闻：
- border_town / 镜湖守望者 / 阶段 3 / 累计 5：走私者转入暗线，镇上公开冲突减少但传闻增多。
- old_ruins / 回声教团 / 阶段 1 / 累计 2：教团已 2 次带出遗物，遗迹附近的回声越发密集。
- border_town / 地区观察 / 阶段 1 / 累计 2：边境镇 的状态标签发生变化：populated, resource_strained, scarcity_high, town, trade_route（第 2 次进入该状态）

连续事件摘要：
- border_town / 阶段 3 / 累计 7：走私者袭击补给线已持续 7 次，边境镇粮食压力仍在升高。
- border_town / 阶段 3 / 累计 5：守望者清剿走私据点已持续 5 次，盘查与暗线活动同时增加。
- old_ruins / 阶段 1 / 累计 2：回声教团的相关活动已持续 2 次，旧日遗迹神秘压力维持高位。

当天 LeadCandidate：
- tracks / beast_migration / fact_d07_047_region_daily_shift / risk 0.63 / urgency 0.71
- rumor / smuggler_information_market / fact_d07_046_region_daily_shift / risk 0.42 / urgency 0.77

当天适配后 v0.3 线索：
- 足迹 / 林中迁徙足迹 / 西北 / freshness 1.00 / risk 0.63 / 狩猎, 跟随, 设陷, 警告旅人
- 传闻 / 镇上的低声传闻 / 东南 / freshness 1.00 / risk 0.42 / 核实, 购买情报, 散播消息, 报告

### Day 8

地区摘要：
- border_town：danger 40.75 / order 55.36 / scarcity 90.57 / mystic 28.92 / food 30.61 / herbs 40.02 / relics 17.05 / information 76.51 / tags [populated, resource_strained, scarcity_high, town, trade_route]
- mirror_lake_forest：danger 56.29 / order 36.53 / scarcity 41.22 / mystic 58.11 / food 63.68 / herbs 75.89 / relics 24.59 / information 48.57 / tags [beast_migration, forest, herb_rich, lake]
- old_ruins：danger 89.58 / order 7.67 / scarcity 38.48 / mystic 89.63 / food 21.57 / herbs 55.07 / relics 79.50 / information 52.73 / tags [danger_high, mystic_surge, order_low, relic_rich, resource_strained, ruins, unstable]

势力摘要：
- echo_cult：power 53.20 / wealth 38.40 / hostility 0.00 / goal 获取遗物与草药，提高神秘压力并制造异象
- smugglers：power 42.60 / wealth 75.40 / hostility 0.00 / goal 获取财富和情报，利用匮乏并削弱地区秩序
- wardens：power 67.00 / wealth 47.00 / hostility 0.00 / goal 维护秩序、压制走私者、阻止回声教团扩张

湖湾镇微观状态：
- old_chen：stress 100.00 / debt 57.23 / family_food 0.00 / shop_open false / tags [family_crisis, shop_closed]
- chen_mi：hunger 96.00 / fear 44.50 / health 84.00 / inventory [spoiled_grain] / tags [hiding_spoiled_grain, disease_risk]
- old_chen_shop：is_open false / food_stock 11.58 / family_crisis true / traces [trace_price_rise_notice, trace_child_hiding_bag, trace_spoiled_grain_bag, trace_grain_dust_on_sleeve, trace_closed_shop]
- abandoned_granary：spoiled_grain_stock 2.00 / disease_risk 0.65 / traces [trace_granary_missing_grain]
湖湾镇微观链：无新增事实、痕迹或可叙述状态。

当天新新闻：
- border_town / 镜湖守望者 / 阶段 2 / 累计 3：已护送 3 批粮车，边境镇的粮食压力仍未解除。
- old_ruins / 回声教团 / 阶段 1 / 累计 2：教团已举行 2 次仪式，遗迹上空的回声持续整夜。

连续事件摘要：
- border_town / 阶段 3 / 累计 8：走私者袭击补给线已持续 8 次，边境镇粮食压力仍在升高。
- border_town / 阶段 3 / 累计 5：守望者清剿走私据点已持续 5 次，盘查与暗线活动同时增加。
- border_town / 阶段 2 / 累计 3：守望者已护送 3 批补给，粮食危机仍未完全缓解。

当天 LeadCandidate：
- 无

当天适配后 v0.3 线索：
- 无

### Day 9

地区摘要：
- border_town：danger 41.27 / order 50.74 / scarcity 89.76 / mystic 30.95 / food 31.23 / herbs 40.20 / relics 16.91 / information 80.37 / tags [populated, resource_strained, scarcity_high, town, trade_route]
- mirror_lake_forest：danger 56.88 / order 36.21 / scarcity 40.57 / mystic 58.05 / food 63.97 / herbs 77.67 / relics 24.56 / information 49.52 / tags [beast_migration, forest, herb_rich, lake]
- old_ruins：danger 90.57 / order 6.66 / scarcity 39.52 / mystic 90.27 / food 22.61 / herbs 55.90 / relics 79.43 / information 53.07 / tags [danger_high, mystic_surge, order_low, relic_rich, resource_strained, ruins, unstable]

势力摘要：
- echo_cult：power 53.80 / wealth 38.40 / hostility 0.00 / goal 获取遗物与草药，提高神秘压力并制造异象
- smugglers：power 43.30 / wealth 78.20 / hostility 0.00 / goal 获取财富和情报，利用匮乏并削弱地区秩序
- wardens：power 67.50 / wealth 45.00 / hostility 0.00 / goal 维护秩序、压制走私者、阻止回声教团扩张

湖湾镇微观状态：
- old_chen：stress 100.00 / debt 61.03 / family_food 0.00 / shop_open false / tags [family_crisis, shop_closed]
- chen_mi：hunger 100.00 / fear 46.00 / health 84.00 / inventory [spoiled_grain] / tags [hiding_spoiled_grain, disease_risk]
- old_chen_shop：is_open false / food_stock 9.08 / family_crisis true / traces [trace_price_rise_notice, trace_child_hiding_bag, trace_spoiled_grain_bag, trace_grain_dust_on_sleeve, trace_closed_shop]
- abandoned_granary：spoiled_grain_stock 2.00 / disease_risk 0.65 / traces [trace_granary_missing_grain]
湖湾镇微观链：无新增事实、痕迹或可叙述状态。

当天新新闻：
- border_town / 回声教团 / 阶段 2 / 累计 3：镇民反复梦见同一片倒悬的湖面。

连续事件摘要：
- border_town / 阶段 3 / 累计 9：走私者袭击补给线已持续 9 次，边境镇粮食压力仍在升高。
- border_town / 阶段 3 / 累计 5：守望者清剿走私据点已持续 5 次，盘查与暗线活动同时增加。
- border_town / 阶段 2 / 累计 4：守望者已护送 4 批补给，粮食危机仍未完全缓解。

当天 LeadCandidate：
- caravan / scarcity_high_and_smuggler_raid / fact_d09_063_raid_supplies / risk 0.66 / urgency 0.90
- apparition / cult_ritual_and_mystic_pressure / fact_d09_061_region_daily_shift / risk 0.90 / urgency 0.90

当天适配后 v0.3 线索：
- 烟柱 / 远处商队烟迹 / 东南 / freshness 1.00 / risk 0.66 / 调查, 护送, 劫掠, 放任
- 传闻 / 关于旧遗迹异象的传闻 / 北方 / freshness 1.00 / risk 0.90 / 观察, 打断, 跟随, 报告

### Day 10

地区摘要：
- border_town：danger 42.67 / order 49.62 / scarcity 95.87 / mystic 30.75 / food 24.97 / herbs 40.93 / relics 16.81 / information 80.12 / tags [populated, resource_strained, scarcity_high, town, trade_route]
- mirror_lake_forest：danger 57.50 / order 35.90 / scarcity 39.90 / mystic 58.31 / food 64.25 / herbs 79.27 / relics 24.53 / information 50.42 / tags [beast_migration, forest, herb_rich, lake]
- old_ruins：danger 92.58 / order 5.63 / scarcity 40.55 / mystic 92.90 / food 22.73 / herbs 56.67 / relics 75.36 / information 53.43 / tags [danger_high, mystic_surge, order_low, relic_rich, resource_strained, ruins, unstable]

势力摘要：
- echo_cult：power 54.80 / wealth 39.40 / hostility 0.00 / goal 获取遗物与草药，提高神秘压力并制造异象
- smugglers：power 41.80 / wealth 81.20 / hostility 0.00 / goal 获取财富和情报，利用匮乏并削弱地区秩序
- wardens：power 68.20 / wealth 44.00 / hostility 0.00 / goal 维护秩序、压制走私者、阻止回声教团扩张

湖湾镇微观状态：
- old_chen：stress 100.00 / debt 65.08 / family_food 0.00 / shop_open false / tags [family_crisis, shop_closed]
- chen_mi：hunger 100.00 / fear 47.50 / health 84.00 / inventory [spoiled_grain] / tags [hiding_spoiled_grain, disease_risk]
- old_chen_shop：is_open false / food_stock 6.58 / family_crisis true / traces [trace_price_rise_notice, trace_child_hiding_bag, trace_spoiled_grain_bag, trace_grain_dust_on_sleeve, trace_closed_shop]
- abandoned_granary：spoiled_grain_stock 2.00 / disease_risk 0.65 / traces [trace_granary_missing_grain]
湖湾镇微观链：无新增事实、痕迹或可叙述状态。

当天新新闻：
- border_town / 雾路走私团 / 阶段 4 / 累计 10：补给线已遇袭 10 次，边境镇粮食接近见底。
- old_ruins / 回声教团 / 阶段 2 / 累计 3：教团已 3 次带出遗物，遗迹附近的回声越发密集。

连续事件摘要：
- border_town / 阶段 4 / 累计 10：走私者袭击补给线已持续 10 次，边境镇粮食压力仍在升高。
- border_town / 阶段 3 / 累计 6：守望者清剿走私据点已持续 6 次，盘查与暗线活动同时增加。
- old_ruins / 阶段 2 / 累计 3：回声教团的相关活动已持续 3 次，旧日遗迹神秘压力维持高位。

当天 LeadCandidate：
- 无

当天适配后 v0.3 线索：
- 无

### Day 11

地区摘要：
- border_town：danger 43.27 / order 46.94 / scarcity 95.26 / mystic 30.41 / food 26.77 / herbs 41.03 / relics 16.74 / information 81.05 / tags [populated, resource_strained, scarcity_high, town, trade_route]
- mirror_lake_forest：danger 58.12 / order 35.59 / scarcity 41.25 / mystic 59.68 / food 64.01 / herbs 74.00 / relics 24.50 / information 50.77 / tags [beast_migration, forest, herb_rich, lake]
- old_ruins：danger 93.64 / order 4.59 / scarcity 41.53 / mystic 93.87 / food 23.78 / herbs 57.14 / relics 75.28 / information 54.22 / tags [danger_high, mystic_surge, order_low, relic_rich, resource_strained, ruins, unstable]

势力摘要：
- echo_cult：power 55.30 / wealth 40.60 / hostility 0.00 / goal 获取遗物与草药，提高神秘压力并制造异象
- smugglers：power 42.50 / wealth 84.00 / hostility 0.00 / goal 获取财富和情报，利用匮乏并削弱地区秩序
- wardens：power 68.70 / wealth 42.00 / hostility 0.00 / goal 维护秩序、压制走私者、阻止回声教团扩张

湖湾镇微观状态：
- old_chen：stress 100.00 / debt 69.13 / family_food 0.00 / shop_open false / tags [family_crisis, shop_closed]
- chen_mi：hunger 100.00 / fear 49.00 / health 84.00 / inventory [spoiled_grain] / tags [hiding_spoiled_grain, disease_risk]
- old_chen_shop：is_open false / food_stock 4.08 / family_crisis true / traces [trace_price_rise_notice, trace_child_hiding_bag, trace_spoiled_grain_bag, trace_grain_dust_on_sleeve, trace_closed_shop]
- abandoned_granary：spoiled_grain_stock 2.00 / disease_risk 0.65 / traces [trace_granary_missing_grain]
湖湾镇微观链：无新增事实、痕迹或可叙述状态。

当天新新闻：
- border_town / 镜湖守望者 / 阶段 3 / 累计 5：已护送 5 批粮车，边境镇的粮食压力仍未解除。
- mirror_lake_forest / 回声教团 / 阶段 2 / 累计 3：湖岸药草变少，采药人开始深入危险地带。

连续事件摘要：
- border_town / 阶段 4 / 累计 11：走私者袭击补给线已持续 11 次，边境镇粮食压力仍在升高。
- border_town / 阶段 3 / 累计 6：守望者清剿走私据点已持续 6 次，盘查与暗线活动同时增加。
- border_town / 阶段 3 / 累计 5：守望者已护送 5 批补给，粮食危机仍未完全缓解。

当天 LeadCandidate：
- tracks / beast_migration / fact_d11_076_harvest_herbs / risk 0.65 / urgency 0.72
- rumor / smuggler_information_market / fact_d11_071_region_daily_shift / risk 0.43 / urgency 0.81

当天适配后 v0.3 线索：
- 足迹 / 林中迁徙足迹 / 西北 / freshness 1.00 / risk 0.65 / 狩猎, 跟随, 设陷, 警告旅人
- 传闻 / 镇上的低声传闻 / 东南 / freshness 1.00 / risk 0.43 / 核实, 购买情报, 散播消息, 报告

### Day 12

地区摘要：
- border_town：danger 43.91 / order 44.26 / scarcity 94.58 / mystic 30.39 / food 28.35 / herbs 41.41 / relics 16.78 / information 80.75 / tags [populated, resource_strained, scarcity_high, town, trade_route]
- mirror_lake_forest：danger 58.77 / order 35.26 / scarcity 40.58 / mystic 59.66 / food 64.32 / herbs 75.15 / relics 24.40 / information 50.60 / tags [beast_migration, forest, herb_rich, lake]
- old_ruins：danger 97.73 / order 2.03 / scarcity 42.48 / mystic 100.00 / food 24.65 / herbs 57.64 / relics 75.12 / information 54.59 / tags [danger_high, mystic_surge, order_low, relic_rich, resource_strained, ruins, unstable]

势力摘要：
- echo_cult：power 56.80 / wealth 40.10 / hostility 0.00 / goal 获取遗物与草药，提高神秘压力并制造异象
- smugglers：power 43.20 / wealth 86.80 / hostility 0.00 / goal 获取财富和情报，利用匮乏并削弱地区秩序
- wardens：power 69.20 / wealth 40.00 / hostility 0.00 / goal 维护秩序、压制走私者、阻止回声教团扩张

湖湾镇微观状态：
- old_chen：stress 100.00 / debt 73.18 / family_food 0.00 / shop_open false / tags [family_crisis, shop_closed]
- chen_mi：hunger 100.00 / fear 50.50 / health 84.00 / inventory [spoiled_grain] / tags [hiding_spoiled_grain, disease_risk]
- old_chen_shop：is_open false / food_stock 1.58 / family_crisis true / traces [trace_price_rise_notice, trace_child_hiding_bag, trace_spoiled_grain_bag, trace_grain_dust_on_sleeve, trace_closed_shop]
- abandoned_granary：spoiled_grain_stock 2.00 / disease_risk 0.65 / traces [trace_granary_missing_grain]
湖湾镇微观链：无新增事实、痕迹或可叙述状态。

当天新新闻：
- old_ruins / 回声教团 / 阶段 2 / 累计 3：教团已举行 3 次仪式，遗迹神秘压力接近失控。

连续事件摘要：
- border_town / 阶段 4 / 累计 12：走私者袭击补给线已持续 12 次，边境镇粮食压力仍在升高。
- border_town / 阶段 3 / 累计 6：守望者已护送 6 批补给，粮食危机仍未完全缓解。
- border_town / 阶段 3 / 累计 6：守望者清剿走私据点已持续 6 次，盘查与暗线活动同时增加。

当天 LeadCandidate：
- 无

当天适配后 v0.3 线索：
- 无

### Day 13

地区摘要：
- border_town：danger 45.36 / order 43.09 / scarcity 100.00 / mystic 30.24 / food 22.36 / herbs 40.96 / relics 16.53 / information 81.70 / tags [populated, resource_strained, scarcity_high, town, trade_route]
- mirror_lake_forest：danger 59.42 / order 34.93 / scarcity 39.92 / mystic 59.93 / food 64.29 / herbs 76.88 / relics 24.39 / information 51.04 / tags [beast_migration, forest, herb_rich, lake, order_low]
- old_ruins：danger 99.92 / order 0.94 / scarcity 43.43 / mystic 100.00 / food 24.49 / herbs 57.60 / relics 70.89 / information 54.76 / tags [danger_high, mystic_surge, order_low, relic_rich, resource_strained, ruins, unstable]

势力摘要：
- echo_cult：power 57.80 / wealth 41.10 / hostility 0.00 / goal 获取遗物与草药，提高神秘压力并制造异象
- smugglers：power 41.70 / wealth 89.80 / hostility 0.00 / goal 获取财富和情报，利用匮乏并削弱地区秩序
- wardens：power 69.90 / wealth 39.00 / hostility 0.00 / goal 维护秩序、压制走私者、阻止回声教团扩张

湖湾镇微观状态：
- old_chen：stress 100.00 / debt 77.23 / family_food 0.00 / shop_open false / tags [family_crisis, shop_closed]
- chen_mi：hunger 100.00 / fear 52.00 / health 84.00 / inventory [spoiled_grain] / tags [hiding_spoiled_grain, disease_risk]
- old_chen_shop：is_open false / food_stock 0.00 / family_crisis true / traces [trace_price_rise_notice, trace_child_hiding_bag, trace_spoiled_grain_bag, trace_grain_dust_on_sleeve, trace_closed_shop]
- abandoned_granary：spoiled_grain_stock 2.00 / disease_risk 0.65 / traces [trace_granary_missing_grain]
湖湾镇微观链：无新增事实、痕迹或可叙述状态。

当天新新闻：
- border_town / 雾路走私团 / 阶段 4 / 累计 13：补给线已遇袭 13 次，边境镇粮食接近见底。
- old_ruins / 回声教团 / 阶段 2 / 累计 4：教团第 4 次带出遗物，遗迹神秘压力接近失控。

连续事件摘要：
- border_town / 阶段 4 / 累计 13：走私者袭击补给线已持续 13 次，边境镇粮食压力仍在升高。
- border_town / 阶段 3 / 累计 7：守望者清剿走私据点已持续 7 次，盘查与暗线活动同时增加。
- border_town / 阶段 3 / 累计 6：守望者已护送 6 批补给，粮食危机仍未完全缓解。

当天 LeadCandidate：
- caravan / scarcity_high_and_smuggler_raid / fact_d13_087_raid_supplies / risk 0.73 / urgency 1.00
- apparition / cult_ritual_and_mystic_pressure / fact_d13_085_region_daily_shift / risk 1.00 / urgency 1.00
- smoke / order_collapse_and_forest_conflict / fact_d13_089_region_tags_changed / risk 0.59 / urgency 0.65

当天适配后 v0.3 线索：
- 烟柱 / 远处商队烟迹 / 东南 / freshness 1.00 / risk 0.73 / 调查, 护送, 劫掠, 放任
- 传闻 / 关于旧遗迹异象的传闻 / 北方 / freshness 1.00 / risk 1.00 / 观察, 打断, 跟随, 报告
- 烟柱 / 林间冲突升起的烟柱 / 西北 / freshness 1.00 / risk 0.59 / 靠近, 侦察, 绕行, 通知守望者

### Day 14

地区摘要：
- border_town：danger 46.03 / order 40.36 / scarcity 98.00 / mystic 30.56 / food 22.66 / herbs 41.21 / relics 16.51 / information 81.96 / tags [populated, resource_strained, scarcity_high, town, trade_route]
- mirror_lake_forest：danger 60.10 / order 34.61 / scarcity 41.24 / mystic 61.80 / food 64.61 / herbs 71.13 / relics 24.18 / information 51.14 / tags [beast_migration, forest, herb_rich, lake, order_low]
- old_ruins：danger 100.00 / order 0.00 / scarcity 44.35 / mystic 100.00 / food 25.15 / herbs 57.06 / relics 70.76 / information 54.17 / tags [danger_high, mystic_surge, order_low, relic_rich, resource_strained, ruins, unstable]

势力摘要：
- echo_cult：power 58.30 / wealth 42.30 / hostility 0.00 / goal 获取遗物与草药，提高神秘压力并制造异象
- smugglers：power 42.40 / wealth 92.60 / hostility 0.00 / goal 获取财富和情报，利用匮乏并削弱地区秩序
- wardens：power 70.40 / wealth 37.00 / hostility 0.00 / goal 维护秩序、压制走私者、阻止回声教团扩张

湖湾镇微观状态：
- old_chen：stress 100.00 / debt 81.28 / family_food 0.00 / shop_open false / tags [family_crisis, shop_closed]
- chen_mi：hunger 100.00 / fear 53.50 / health 84.00 / inventory [spoiled_grain] / tags [hiding_spoiled_grain, disease_risk]
- old_chen_shop：is_open false / food_stock 0.00 / family_crisis true / traces [trace_price_rise_notice, trace_child_hiding_bag, trace_spoiled_grain_bag, trace_grain_dust_on_sleeve, trace_closed_shop]
- abandoned_granary：spoiled_grain_stock 2.00 / disease_risk 0.65 / traces [trace_granary_missing_grain]
湖湾镇微观链：无新增事实、痕迹或可叙述状态。

当天新新闻：
- 无

连续事件摘要：
- border_town / 阶段 4 / 累计 14：走私者袭击补给线已持续 14 次，边境镇粮食压力仍在升高。
- border_town / 阶段 3 / 累计 7：守望者已护送 7 批补给，粮食危机仍未完全缓解。
- border_town / 阶段 3 / 累计 7：守望者清剿走私据点已持续 7 次，盘查与暗线活动同时增加。

当天 LeadCandidate：
- 无

当天适配后 v0.3 线索：
- 无

### Day 15

地区摘要：
- border_town：danger 46.73 / order 35.64 / scarcity 97.53 / mystic 32.35 / food 23.68 / herbs 41.25 / relics 16.51 / information 86.35 / tags [populated, resource_strained, scarcity_high, town, trade_route]
- mirror_lake_forest：danger 60.81 / order 34.27 / scarcity 40.55 / mystic 61.57 / food 64.82 / herbs 72.16 / relics 24.00 / information 50.75 / tags [beast_migration, forest, herb_rich, lake, order_low]
- old_ruins：danger 100.00 / order 0.00 / scarcity 45.30 / mystic 100.00 / food 24.62 / herbs 57.55 / relics 70.70 / information 54.00 / tags [danger_high, mystic_surge, order_low, relic_rich, resource_strained, ruins, unstable]

势力摘要：
- echo_cult：power 58.90 / wealth 42.30 / hostility 0.00 / goal 获取遗物与草药，提高神秘压力并制造异象
- smugglers：power 43.10 / wealth 95.40 / hostility 0.00 / goal 获取财富和情报，利用匮乏并削弱地区秩序
- wardens：power 70.90 / wealth 35.00 / hostility 0.00 / goal 维护秩序、压制走私者、阻止回声教团扩张

湖湾镇微观状态：
- old_chen：stress 100.00 / debt 85.33 / family_food 0.00 / shop_open false / tags [family_crisis, shop_closed]
- chen_mi：hunger 100.00 / fear 55.00 / health 84.00 / inventory [spoiled_grain] / tags [hiding_spoiled_grain, disease_risk]
- old_chen_shop：is_open false / food_stock 0.00 / family_crisis true / traces [trace_price_rise_notice, trace_child_hiding_bag, trace_spoiled_grain_bag, trace_grain_dust_on_sleeve, trace_closed_shop]
- abandoned_granary：spoiled_grain_stock 2.00 / disease_risk 0.65 / traces [trace_granary_missing_grain]
湖湾镇微观链：无新增事实、痕迹或可叙述状态。

当天新新闻：
- 无

连续事件摘要：
- border_town / 阶段 4 / 累计 15：走私者袭击补给线已持续 15 次，边境镇粮食压力仍在升高。
- border_town / 阶段 3 / 累计 8：守望者已护送 8 批补给，粮食危机仍未完全缓解。
- border_town / 阶段 3 / 累计 7：守望者清剿走私据点已持续 7 次，盘查与暗线活动同时增加。

当天 LeadCandidate：
- tracks / beast_migration / fact_d15_097_region_daily_shift / risk 0.67 / urgency 0.74
- rumor / smuggler_information_market / fact_d15_096_region_daily_shift / risk 0.43 / urgency 0.86

当天适配后 v0.3 线索：
- 足迹 / 林中迁徙足迹 / 西北 / freshness 1.00 / risk 0.67 / 狩猎, 跟随, 设陷, 警告旅人
- 传闻 / 镇上的低声传闻 / 东南 / freshness 1.00 / risk 0.43 / 核实, 购买情报, 散播消息, 报告

### Day 16

地区摘要：
- border_town：danger 48.30 / order 34.42 / scarcity 100.00 / mystic 32.37 / food 17.19 / herbs 42.18 / relics 16.34 / information 87.32 / tags [order_low, populated, resource_strained, scarcity_high, town, trade_route]
- mirror_lake_forest：danger 61.51 / order 33.93 / scarcity 39.84 / mystic 61.34 / food 65.44 / herbs 73.13 / relics 23.99 / information 51.20 / tags [beast_migration, forest, herb_rich, lake, order_low]
- old_ruins：danger 100.00 / order 0.00 / scarcity 46.27 / mystic 100.00 / food 23.93 / herbs 58.23 / relics 70.64 / information 53.73 / tags [danger_high, mystic_surge, order_low, relic_rich, resource_strained, ruins, unstable]

势力摘要：
- echo_cult：power 60.40 / wealth 41.80 / hostility 0.00 / goal 获取遗物与草药，提高神秘压力并制造异象
- smugglers：power 41.60 / wealth 98.40 / hostility 0.00 / goal 获取财富和情报，利用匮乏并削弱地区秩序
- wardens：power 71.60 / wealth 34.00 / hostility 0.00 / goal 维护秩序、压制走私者、阻止回声教团扩张

湖湾镇微观状态：
- old_chen：stress 100.00 / debt 89.38 / family_food 0.00 / shop_open false / tags [family_crisis, shop_closed]
- chen_mi：hunger 100.00 / fear 56.50 / health 84.00 / inventory [spoiled_grain] / tags [hiding_spoiled_grain, disease_risk]
- old_chen_shop：is_open false / food_stock 0.00 / family_crisis true / traces [trace_price_rise_notice, trace_child_hiding_bag, trace_spoiled_grain_bag, trace_grain_dust_on_sleeve, trace_closed_shop]
- abandoned_granary：spoiled_grain_stock 2.00 / disease_risk 0.65 / traces [trace_granary_missing_grain]
湖湾镇微观链：无新增事实、痕迹或可叙述状态。

当天新新闻：
- border_town / 镜湖守望者 / 阶段 3 / 累计 8：清剿累计 8 次，走私者转入暗线，镇上传闻更多了。
- border_town / 地区观察 / 阶段 1 / 累计 1：边境镇 的状态标签发生变化：order_low, populated, resource_strained, scarcity_high, town, trade_route

连续事件摘要：
- border_town / 阶段 4 / 累计 16：走私者袭击补给线已持续 16 次，边境镇粮食压力仍在升高。
- border_town / 阶段 3 / 累计 8：守望者清剿走私据点已持续 8 次，盘查与暗线活动同时增加。
- border_town / 阶段 3 / 累计 8：守望者已护送 8 批补给，粮食危机仍未完全缓解。

当天 LeadCandidate：
- 无

当天适配后 v0.3 线索：
- 无

### Day 17

地区摘要：
- border_town：danger 49.10 / order 31.67 / scarcity 98.00 / mystic 32.24 / food 19.37 / herbs 42.25 / relics 16.29 / information 87.27 / tags [order_low, populated, resource_strained, scarcity_high, town, trade_route]
- mirror_lake_forest：danger 62.21 / order 33.60 / scarcity 41.10 / mystic 62.70 / food 65.82 / herbs 68.06 / relics 23.86 / information 51.53 / tags [beast_migration, forest, herb_rich, lake, order_low]
- old_ruins：danger 100.00 / order 0.00 / scarcity 47.27 / mystic 100.00 / food 23.47 / herbs 57.72 / relics 70.67 / information 54.05 / tags [danger_high, mystic_surge, order_low, relic_rich, resource_strained, ruins, unstable]

势力摘要：
- echo_cult：power 60.90 / wealth 43.00 / hostility 0.00 / goal 获取遗物与草药，提高神秘压力并制造异象
- smugglers：power 42.30 / wealth 100.00 / hostility 0.00 / goal 获取财富和情报，利用匮乏并削弱地区秩序
- wardens：power 72.10 / wealth 32.00 / hostility 0.00 / goal 维护秩序、压制走私者、阻止回声教团扩张

湖湾镇微观状态：
- old_chen：stress 100.00 / debt 93.43 / family_food 0.00 / shop_open false / tags [family_crisis, shop_closed]
- chen_mi：hunger 100.00 / fear 58.00 / health 84.00 / inventory [spoiled_grain] / tags [hiding_spoiled_grain, disease_risk]
- old_chen_shop：is_open false / food_stock 0.00 / family_crisis true / traces [trace_price_rise_notice, trace_child_hiding_bag, trace_spoiled_grain_bag, trace_grain_dust_on_sleeve, trace_closed_shop]
- abandoned_granary：spoiled_grain_stock 2.00 / disease_risk 0.65 / traces [trace_granary_missing_grain]
湖湾镇微观链：无新增事实、痕迹或可叙述状态。

当天新新闻：
- mirror_lake_forest / 回声教团 / 阶段 3 / 累计 5：草药短缺开始影响镇上的伤病治疗。

连续事件摘要：
- border_town / 阶段 4 / 累计 17：走私者袭击补给线已持续 17 次，边境镇粮食压力仍在升高。
- border_town / 阶段 3 / 累计 9：守望者已护送 9 批补给，粮食危机仍未完全缓解。
- border_town / 阶段 3 / 累计 8：守望者清剿走私据点已持续 8 次，盘查与暗线活动同时增加。

当天 LeadCandidate：
- caravan / scarcity_high_and_smuggler_raid / fact_d17_113_raid_supplies / risk 0.74 / urgency 0.98
- apparition / cult_ritual_and_mystic_pressure / fact_d17_111_region_daily_shift / risk 1.00 / urgency 1.00
- smoke / order_collapse_and_forest_conflict / fact_d17_114_harvest_herbs / risk 0.62 / urgency 0.66

当天适配后 v0.3 线索：
- 烟柱 / 远处商队烟迹 / 东南 / freshness 1.00 / risk 0.74 / 调查, 护送, 劫掠, 放任
- 传闻 / 关于旧遗迹异象的传闻 / 北方 / freshness 1.00 / risk 1.00 / 观察, 打断, 跟随, 报告
- 烟柱 / 林间冲突升起的烟柱 / 西北 / freshness 1.00 / risk 0.62 / 靠近, 侦察, 绕行, 通知守望者

### Day 18

地区摘要：
- border_town：danger 49.93 / order 26.93 / scarcity 97.64 / mystic 34.00 / food 21.15 / herbs 43.21 / relics 16.11 / information 91.88 / tags [order_low, populated, resource_strained, scarcity_high, town, trade_route]
- mirror_lake_forest：danger 62.92 / order 33.24 / scarcity 40.34 / mystic 62.40 / food 66.37 / herbs 69.42 / relics 23.79 / information 51.20 / tags [beast_migration, forest, herb_rich, lake, order_low]
- old_ruins：danger 100.00 / order 0.00 / scarcity 48.28 / mystic 100.00 / food 23.16 / herbs 57.18 / relics 70.69 / information 53.89 / tags [danger_high, mystic_surge, order_low, relic_rich, resource_strained, ruins, unstable]

势力摘要：
- echo_cult：power 61.50 / wealth 43.00 / hostility 0.00 / goal 获取遗物与草药，提高神秘压力并制造异象
- smugglers：power 43.00 / wealth 100.00 / hostility 0.00 / goal 获取财富和情报，利用匮乏并削弱地区秩序
- wardens：power 72.60 / wealth 30.00 / hostility 0.00 / goal 维护秩序、压制走私者、阻止回声教团扩张

湖湾镇微观状态：
- old_chen：stress 100.00 / debt 97.48 / family_food 0.00 / shop_open false / tags [family_crisis, shop_closed]
- chen_mi：hunger 100.00 / fear 59.50 / health 84.00 / inventory [spoiled_grain] / tags [hiding_spoiled_grain, disease_risk]
- old_chen_shop：is_open false / food_stock 0.00 / family_crisis true / traces [trace_price_rise_notice, trace_child_hiding_bag, trace_spoiled_grain_bag, trace_grain_dust_on_sleeve, trace_closed_shop]
- abandoned_granary：spoiled_grain_stock 2.00 / disease_risk 0.65 / traces [trace_granary_missing_grain]
湖湾镇微观链：无新增事实、痕迹或可叙述状态。

当天新新闻：
- border_town / 镜湖守望者 / 阶段 4 / 累计 10：已护送 10 批粮车，边境镇的粮食压力仍未解除。
- border_town / 回声教团 / 阶段 3 / 累计 5：越来越多镇民梦见倒悬湖面，白日里也有人听见回声。

连续事件摘要：
- border_town / 阶段 4 / 累计 18：走私者袭击补给线已持续 18 次，边境镇粮食压力仍在升高。
- border_town / 阶段 4 / 累计 10：守望者已护送 10 批补给，粮食危机仍未完全缓解。
- border_town / 阶段 3 / 累计 8：守望者清剿走私据点已持续 8 次，盘查与暗线活动同时增加。

当天 LeadCandidate：
- 无

当天适配后 v0.3 线索：
- 无

### Day 19

地区摘要：
- border_town：danger 51.65 / order 25.69 / scarcity 100.00 / mystic 34.38 / food 14.37 / herbs 43.75 / relics 15.98 / information 91.66 / tags [order_low, populated, resource_strained, scarcity_high, town, trade_route]
- mirror_lake_forest：danger 63.63 / order 32.90 / scarcity 39.53 / mystic 62.44 / food 67.59 / herbs 70.49 / relics 23.60 / information 51.50 / tags [beast_migration, forest, herb_rich, lake, order_low]
- old_ruins：danger 100.00 / order 0.00 / scarcity 49.32 / mystic 100.00 / food 22.65 / herbs 57.98 / relics 66.55 / information 53.55 / tags [danger_high, mystic_surge, order_low, relic_rich, resource_strained, ruins, unstable]

势力摘要：
- echo_cult：power 62.50 / wealth 44.00 / hostility 0.00 / goal 获取遗物与草药，提高神秘压力并制造异象
- smugglers：power 41.50 / wealth 100.00 / hostility 0.00 / goal 获取财富和情报，利用匮乏并削弱地区秩序
- wardens：power 73.30 / wealth 29.00 / hostility 0.00 / goal 维护秩序、压制走私者、阻止回声教团扩张

湖湾镇微观状态：
- old_chen：stress 100.00 / debt 100.00 / family_food 0.00 / shop_open false / tags [family_crisis, shop_closed]
- chen_mi：hunger 100.00 / fear 61.00 / health 84.00 / inventory [spoiled_grain] / tags [hiding_spoiled_grain, disease_risk]
- old_chen_shop：is_open false / food_stock 0.00 / family_crisis true / traces [trace_price_rise_notice, trace_child_hiding_bag, trace_spoiled_grain_bag, trace_grain_dust_on_sleeve, trace_closed_shop]
- abandoned_granary：spoiled_grain_stock 2.00 / disease_risk 0.65 / traces [trace_granary_missing_grain]
湖湾镇微观链：无新增事实、痕迹或可叙述状态。

当天新新闻：
- old_ruins / 回声教团 / 阶段 3 / 累计 5：教团第 5 次带出遗物，遗迹神秘压力接近失控。

连续事件摘要：
- border_town / 阶段 4 / 累计 19：走私者袭击补给线已持续 19 次，边境镇粮食压力仍在升高。
- border_town / 阶段 4 / 累计 10：守望者已护送 10 批补给，粮食危机仍未完全缓解。
- border_town / 阶段 3 / 累计 9：守望者清剿走私据点已持续 9 次，盘查与暗线活动同时增加。

当天 LeadCandidate：
- tracks / beast_migration / fact_d19_122_region_daily_shift / risk 0.68 / urgency 0.72
- rumor / smuggler_information_market / fact_d19_121_region_daily_shift / risk 0.42 / urgency 0.92

当天适配后 v0.3 线索：
- 足迹 / 林中迁徙足迹 / 西北 / freshness 1.00 / risk 0.68 / 狩猎, 跟随, 设陷, 警告旅人
- 传闻 / 镇上的低声传闻 / 东南 / freshness 1.00 / risk 0.42 / 核实, 购买情报, 散播消息, 报告

### Day 20

地区摘要：
- border_town：danger 52.59 / order 22.92 / scarcity 98.00 / mystic 34.21 / food 16.68 / herbs 43.69 / relics 16.03 / information 92.64 / tags [order_low, populated, resource_strained, scarcity_high, town, trade_route]
- mirror_lake_forest：danger 64.34 / order 32.55 / scarcity 38.71 / mystic 62.30 / food 67.79 / herbs 71.21 / relics 23.64 / information 51.18 / tags [beast_migration, forest, herb_rich, lake, order_low]
- old_ruins：danger 100.00 / order 0.00 / scarcity 50.36 / mystic 100.00 / food 22.42 / herbs 58.55 / relics 66.47 / information 54.27 / tags [danger_high, mystic_surge, order_low, relic_rich, resource_strained, ruins, unstable]

势力摘要：
- echo_cult：power 64.00 / wealth 43.50 / hostility 0.00 / goal 获取遗物与草药，提高神秘压力并制造异象
- smugglers：power 42.20 / wealth 100.00 / hostility 0.00 / goal 获取财富和情报，利用匮乏并削弱地区秩序
- wardens：power 73.80 / wealth 27.00 / hostility 0.00 / goal 维护秩序、压制走私者、阻止回声教团扩张

湖湾镇微观状态：
- old_chen：stress 100.00 / debt 100.00 / family_food 0.00 / shop_open false / tags [family_crisis, shop_closed]
- chen_mi：hunger 100.00 / fear 62.50 / health 84.00 / inventory [spoiled_grain] / tags [hiding_spoiled_grain, disease_risk]
- old_chen_shop：is_open false / food_stock 0.00 / family_crisis true / traces [trace_price_rise_notice, trace_child_hiding_bag, trace_spoiled_grain_bag, trace_grain_dust_on_sleeve, trace_closed_shop]
- abandoned_granary：spoiled_grain_stock 2.00 / disease_risk 0.65 / traces [trace_granary_missing_grain]
湖湾镇微观链：无新增事实、痕迹或可叙述状态。

当天新新闻：
- border_town / 雾路走私团 / 阶段 5 / 累计 20：补给线已遇袭 20 次，边境镇粮食接近见底。
- old_ruins / 回声教团 / 阶段 3 / 累计 5：教团已举行 5 次仪式，遗迹神秘压力接近失控。

连续事件摘要：
- border_town / 阶段 5 / 累计 20：走私者袭击补给线已持续 20 次，边境镇粮食压力仍在升高。
- border_town / 阶段 4 / 累计 11：守望者已护送 11 批补给，粮食危机仍未完全缓解。
- border_town / 阶段 3 / 累计 9：守望者清剿走私据点已持续 9 次，盘查与暗线活动同时增加。

当天 LeadCandidate：
- 无

当天适配后 v0.3 线索：
- 无

### Day 21

地区摘要：
- border_town：danger 53.56 / order 18.16 / scarcity 97.83 / mystic 36.21 / food 16.89 / herbs 44.14 / relics 16.02 / information 96.53 / tags [order_low, populated, resource_strained, scarcity_high, town, trade_route]
- mirror_lake_forest：danger 65.07 / order 32.21 / scarcity 37.83 / mystic 62.10 / food 68.93 / herbs 72.46 / relics 23.41 / information 51.52 / tags [beast_migration, danger_high, forest, herb_rich, lake, order_low]
- old_ruins：danger 100.00 / order 0.00 / scarcity 51.35 / mystic 100.00 / food 23.75 / herbs 59.09 / relics 66.46 / information 54.45 / tags [danger_high, mystic_surge, order_low, relic_rich, resource_strained, ruins, unstable]

势力摘要：
- echo_cult：power 64.60 / wealth 43.50 / hostility 0.00 / goal 获取遗物与草药，提高神秘压力并制造异象
- smugglers：power 42.90 / wealth 100.00 / hostility 0.00 / goal 获取财富和情报，利用匮乏并削弱地区秩序
- wardens：power 74.30 / wealth 25.00 / hostility 0.00 / goal 维护秩序、压制走私者、阻止回声教团扩张

湖湾镇微观状态：
- old_chen：stress 100.00 / debt 100.00 / family_food 0.00 / shop_open false / tags [family_crisis, shop_closed]
- chen_mi：hunger 100.00 / fear 64.00 / health 84.00 / inventory [spoiled_grain] / tags [hiding_spoiled_grain, disease_risk]
- old_chen_shop：is_open false / food_stock 0.00 / family_crisis true / traces [trace_price_rise_notice, trace_child_hiding_bag, trace_spoiled_grain_bag, trace_grain_dust_on_sleeve, trace_closed_shop]
- abandoned_granary：spoiled_grain_stock 2.00 / disease_risk 0.65 / traces [trace_granary_missing_grain]
湖湾镇微观链：无新增事实、痕迹或可叙述状态。

当天新新闻：
- 无

连续事件摘要：
- border_town / 阶段 5 / 累计 21：走私者袭击补给线已持续 21 次，边境镇粮食压力仍在升高。
- border_town / 阶段 4 / 累计 12：守望者已护送 12 批补给，粮食危机仍未完全缓解。
- border_town / 阶段 3 / 累计 9：守望者清剿走私据点已持续 9 次，盘查与暗线活动同时增加。

当天 LeadCandidate：
- caravan / scarcity_high_and_smuggler_raid / fact_d21_137_raid_supplies / risk 0.76 / urgency 0.98
- apparition / cult_ritual_and_mystic_pressure / fact_d21_135_region_daily_shift / risk 1.00 / urgency 1.00
- smoke / order_collapse_and_forest_conflict / fact_d21_139_region_tags_changed / risk 0.65 / urgency 0.68

当天适配后 v0.3 线索：
- 烟柱 / 远处商队烟迹 / 东南 / freshness 1.00 / risk 0.76 / 调查, 护送, 劫掠, 放任
- 传闻 / 关于旧遗迹异象的传闻 / 北方 / freshness 1.00 / risk 1.00 / 观察, 打断, 跟随, 报告
- 烟柱 / 林间冲突升起的烟柱 / 西北 / freshness 1.00 / risk 0.65 / 靠近, 侦察, 绕行, 通知守望者

### Day 22

地区摘要：
- border_town：danger 54.62 / order 15.40 / scarcity 97.67 / mystic 36.40 / food 16.94 / herbs 44.76 / relics 15.84 / information 96.59 / tags [order_low, populated, resource_strained, scarcity_high, town, trade_route]
- mirror_lake_forest：danger 65.78 / order 31.87 / scarcity 36.95 / mystic 61.96 / food 69.06 / herbs 73.40 / relics 23.25 / information 51.53 / tags [beast_migration, danger_high, forest, herb_rich, lake, order_low]
- old_ruins：danger 100.00 / order 0.00 / scarcity 52.28 / mystic 100.00 / food 24.83 / herbs 59.54 / relics 62.24 / information 55.43 / tags [danger_high, mystic_surge, order_low, relic_rich, resource_strained, ruins, unstable]

势力摘要：
- echo_cult：power 65.60 / wealth 44.50 / hostility 0.00 / goal 获取遗物与草药，提高神秘压力并制造异象
- smugglers：power 43.60 / wealth 100.00 / hostility 0.00 / goal 获取财富和情报，利用匮乏并削弱地区秩序
- wardens：power 74.80 / wealth 23.00 / hostility 0.00 / goal 维护秩序、压制走私者、阻止回声教团扩张

湖湾镇微观状态：
- old_chen：stress 100.00 / debt 100.00 / family_food 0.00 / shop_open false / tags [family_crisis, shop_closed]
- chen_mi：hunger 100.00 / fear 65.50 / health 84.00 / inventory [spoiled_grain] / tags [hiding_spoiled_grain, disease_risk]
- old_chen_shop：is_open false / food_stock 0.00 / family_crisis true / traces [trace_price_rise_notice, trace_child_hiding_bag, trace_spoiled_grain_bag, trace_grain_dust_on_sleeve, trace_closed_shop]
- abandoned_granary：spoiled_grain_stock 2.00 / disease_risk 0.65 / traces [trace_granary_missing_grain]
湖湾镇微观链：无新增事实、痕迹或可叙述状态。

当天新新闻：
- 无

连续事件摘要：
- border_town / 阶段 5 / 累计 22：走私者袭击补给线已持续 22 次，边境镇粮食压力仍在升高。
- border_town / 阶段 4 / 累计 13：守望者已护送 13 批补给，粮食危机仍未完全缓解。
- border_town / 阶段 3 / 累计 9：守望者清剿走私据点已持续 9 次，盘查与暗线活动同时增加。

当天 LeadCandidate：
- 无

当天适配后 v0.3 线索：
- 无

### Day 23

地区摘要：
- border_town：danger 56.50 / order 14.13 / scarcity 100.00 / mystic 36.18 / food 10.44 / herbs 45.43 / relics 15.74 / information 97.18 / tags [order_low, populated, resource_strained, scarcity_high, town, trade_route]
- mirror_lake_forest：danger 66.49 / order 31.53 / scarcity 38.02 / mystic 63.28 / food 70.30 / herbs 68.40 / relics 23.05 / information 51.25 / tags [beast_migration, danger_high, forest, herb_rich, lake, order_low]
- old_ruins：danger 100.00 / order 0.00 / scarcity 53.19 / mystic 100.00 / food 25.42 / herbs 59.00 / relics 62.14 / information 55.65 / tags [danger_high, mystic_surge, order_low, relic_rich, resource_strained, ruins, unstable]

势力摘要：
- echo_cult：power 66.10 / wealth 45.70 / hostility 0.00 / goal 获取遗物与草药，提高神秘压力并制造异象
- smugglers：power 42.10 / wealth 100.00 / hostility 0.00 / goal 获取财富和情报，利用匮乏并削弱地区秩序
- wardens：power 75.50 / wealth 22.00 / hostility 0.00 / goal 维护秩序、压制走私者、阻止回声教团扩张

湖湾镇微观状态：
- old_chen：stress 100.00 / debt 100.00 / family_food 0.00 / shop_open false / tags [family_crisis, shop_closed]
- chen_mi：hunger 100.00 / fear 67.00 / health 84.00 / inventory [spoiled_grain] / tags [hiding_spoiled_grain, disease_risk]
- old_chen_shop：is_open false / food_stock 0.00 / family_crisis true / traces [trace_price_rise_notice, trace_child_hiding_bag, trace_spoiled_grain_bag, trace_grain_dust_on_sleeve, trace_closed_shop]
- abandoned_granary：spoiled_grain_stock 2.00 / disease_risk 0.65 / traces [trace_granary_missing_grain]
湖湾镇微观链：无新增事实、痕迹或可叙述状态。

当天新新闻：
- border_town / 镜湖守望者 / 阶段 4 / 累计 10：第 10 次清剿后，边境镇秩序仍跌入危险线。

连续事件摘要：
- border_town / 阶段 5 / 累计 23：走私者袭击补给线已持续 23 次，边境镇粮食压力仍在升高。
- border_town / 阶段 4 / 累计 13：守望者已护送 13 批补给，粮食危机仍未完全缓解。
- border_town / 阶段 4 / 累计 10：守望者清剿走私据点已持续 10 次，盘查与暗线活动同时增加。

当天 LeadCandidate：
- tracks / beast_migration / fact_d23_151_harvest_herbs / risk 0.69 / urgency 0.72
- river / resource_pressure_along_lake_routes / fact_d23_151_harvest_herbs / risk 0.49 / urgency 0.51
- rumor / smuggler_information_market / fact_d23_146_region_daily_shift / risk 0.42 / urgency 0.95

当天适配后 v0.3 线索：
- 足迹 / 林中迁徙足迹 / 西北 / freshness 1.00 / risk 0.69 / 狩猎, 跟随, 设陷, 警告旅人
- 河流 / 河岸资源异动 / 西北 / freshness 1.00 / risk 0.49 / 取水检验, 溯流追查, 提醒居民, 放任
- 传闻 / 镇上的低声传闻 / 东南 / freshness 1.00 / risk 0.42 / 核实, 购买情报, 散播消息, 报告

### Day 24

地区摘要：
- border_town：danger 57.60 / order 11.32 / scarcity 98.00 / mystic 35.97 / food 11.83 / herbs 45.67 / relics 15.79 / information 97.53 / tags [order_low, populated, resource_strained, scarcity_high, town, trade_route]
- mirror_lake_forest：danger 67.22 / order 31.18 / scarcity 37.12 / mystic 63.08 / food 69.52 / herbs 69.30 / relics 22.98 / information 51.96 / tags [beast_migration, danger_high, forest, herb_rich, lake, order_low]
- old_ruins：danger 100.00 / order 0.00 / scarcity 54.10 / mystic 100.00 / food 25.41 / herbs 59.92 / relics 62.11 / information 55.23 / tags [danger_high, mystic_surge, order_low, relic_rich, resource_strained, ruins, unstable]

势力摘要：
- echo_cult：power 67.60 / wealth 45.20 / hostility 0.00 / goal 获取遗物与草药，提高神秘压力并制造异象
- smugglers：power 42.80 / wealth 100.00 / hostility 0.00 / goal 获取财富和情报，利用匮乏并削弱地区秩序
- wardens：power 76.00 / wealth 20.00 / hostility 0.00 / goal 维护秩序、压制走私者、阻止回声教团扩张

湖湾镇微观状态：
- old_chen：stress 100.00 / debt 100.00 / family_food 0.00 / shop_open false / tags [family_crisis, shop_closed]
- chen_mi：hunger 100.00 / fear 68.50 / health 84.00 / inventory [spoiled_grain] / tags [hiding_spoiled_grain, disease_risk]
- old_chen_shop：is_open false / food_stock 0.00 / family_crisis true / traces [trace_price_rise_notice, trace_child_hiding_bag, trace_spoiled_grain_bag, trace_grain_dust_on_sleeve, trace_closed_shop]
- abandoned_granary：spoiled_grain_stock 2.00 / disease_risk 0.65 / traces [trace_granary_missing_grain]
湖湾镇微观链：无新增事实、痕迹或可叙述状态。

当天新新闻：
- 无

连续事件摘要：
- border_town / 阶段 5 / 累计 24：走私者袭击补给线已持续 24 次，边境镇粮食压力仍在升高。
- border_town / 阶段 4 / 累计 14：守望者已护送 14 批补给，粮食危机仍未完全缓解。
- border_town / 阶段 4 / 累计 10：守望者清剿走私据点已持续 10 次，盘查与暗线活动同时增加。

当天 LeadCandidate：
- 无

当天适配后 v0.3 线索：
- 无

### Day 25

地区摘要：
- border_town：danger 58.75 / order 8.53 / scarcity 97.99 / mystic 36.29 / food 13.49 / herbs 46.30 / relics 15.77 / information 97.81 / tags [order_low, populated, resource_strained, scarcity_high, town, trade_route]
- mirror_lake_forest：danger 67.94 / order 30.83 / scarcity 36.17 / mystic 63.42 / food 70.61 / herbs 69.83 / relics 22.82 / information 51.97 / tags [beast_migration, danger_high, forest, herb_rich, lake, order_low]
- old_ruins：danger 100.00 / order 0.00 / scarcity 54.97 / mystic 100.00 / food 26.40 / herbs 60.84 / relics 57.95 / information 55.13 / tags [danger_high, mystic_surge, order_low, relic_rich, resource_strained, ruins, unstable]

势力摘要：
- echo_cult：power 68.60 / wealth 46.20 / hostility 0.00 / goal 获取遗物与草药，提高神秘压力并制造异象
- smugglers：power 43.50 / wealth 100.00 / hostility 0.00 / goal 获取财富和情报，利用匮乏并削弱地区秩序
- wardens：power 76.50 / wealth 18.00 / hostility 0.00 / goal 维护秩序、压制走私者、阻止回声教团扩张

湖湾镇微观状态：
- old_chen：stress 100.00 / debt 100.00 / family_food 0.00 / shop_open false / tags [family_crisis, shop_closed]
- chen_mi：hunger 100.00 / fear 70.00 / health 84.00 / inventory [spoiled_grain] / tags [hiding_spoiled_grain, disease_risk]
- old_chen_shop：is_open false / food_stock 0.00 / family_crisis true / traces [trace_price_rise_notice, trace_child_hiding_bag, trace_spoiled_grain_bag, trace_grain_dust_on_sleeve, trace_closed_shop]
- abandoned_granary：spoiled_grain_stock 2.00 / disease_risk 0.65 / traces [trace_granary_missing_grain]
湖湾镇微观链：无新增事实、痕迹或可叙述状态。

当天新新闻：
- 无

连续事件摘要：
- border_town / 阶段 5 / 累计 25：走私者袭击补给线已持续 25 次，边境镇粮食压力仍在升高。
- border_town / 阶段 4 / 累计 15：守望者已护送 15 批补给，粮食危机仍未完全缓解。
- border_town / 阶段 4 / 累计 10：守望者清剿走私据点已持续 10 次，盘查与暗线活动同时增加。

当天 LeadCandidate：
- caravan / scarcity_high_and_smuggler_raid / fact_d25_162_raid_supplies / risk 0.78 / urgency 0.98
- apparition / cult_ritual_and_mystic_pressure / fact_d25_160_region_daily_shift / risk 1.00 / urgency 1.00
- smoke / order_collapse_and_forest_conflict / fact_d25_159_region_daily_shift / risk 0.68 / urgency 0.69

当天适配后 v0.3 线索：
- 烟柱 / 远处商队烟迹 / 东南 / freshness 1.00 / risk 0.78 / 调查, 护送, 劫掠, 放任
- 传闻 / 关于旧遗迹异象的传闻 / 北方 / freshness 1.00 / risk 1.00 / 观察, 打断, 跟随, 报告
- 烟柱 / 林间冲突升起的烟柱 / 西北 / freshness 1.00 / risk 0.68 / 靠近, 侦察, 绕行, 通知守望者

### Day 26

地区摘要：
- border_town：danger 60.75 / order 7.23 / scarcity 100.00 / mystic 36.33 / food 7.57 / herbs 46.66 / relics 15.61 / information 97.72 / tags [order_low, populated, resource_strained, scarcity_high, town, trade_route]
- mirror_lake_forest：danger 68.66 / order 30.49 / scarcity 37.19 / mystic 65.03 / food 71.30 / herbs 65.07 / relics 22.86 / information 51.78 / tags [beast_migration, danger_high, forest, herb_rich, lake, order_low]
- old_ruins：danger 100.00 / order 0.00 / scarcity 55.81 / mystic 100.00 / food 27.02 / herbs 61.79 / relics 57.81 / information 55.84 / tags [danger_high, mystic_surge, order_low, relic_rich, resource_strained, ruins, unstable]

势力摘要：
- echo_cult：power 69.10 / wealth 47.40 / hostility 0.00 / goal 获取遗物与草药，提高神秘压力并制造异象
- smugglers：power 42.00 / wealth 100.00 / hostility 0.00 / goal 获取财富和情报，利用匮乏并削弱地区秩序
- wardens：power 77.20 / wealth 17.00 / hostility 0.00 / goal 维护秩序、压制走私者、阻止回声教团扩张

湖湾镇微观状态：
- old_chen：stress 100.00 / debt 100.00 / family_food 0.00 / shop_open false / tags [family_crisis, shop_closed]
- chen_mi：hunger 100.00 / fear 71.50 / health 84.00 / inventory [spoiled_grain] / tags [hiding_spoiled_grain, disease_risk]
- old_chen_shop：is_open false / food_stock 0.00 / family_crisis true / traces [trace_price_rise_notice, trace_child_hiding_bag, trace_spoiled_grain_bag, trace_grain_dust_on_sleeve, trace_closed_shop]
- abandoned_granary：spoiled_grain_stock 2.00 / disease_risk 0.65 / traces [trace_granary_missing_grain]
湖湾镇微观链：无新增事实、痕迹或可叙述状态。

当天新新闻：
- 无

连续事件摘要：
- border_town / 阶段 5 / 累计 26：走私者袭击补给线已持续 26 次，边境镇粮食压力仍在升高。
- border_town / 阶段 4 / 累计 15：守望者已护送 15 批补给，粮食危机仍未完全缓解。
- border_town / 阶段 4 / 累计 11：守望者清剿走私据点已持续 11 次，盘查与暗线活动同时增加。

当天 LeadCandidate：
- 无

当天适配后 v0.3 线索：
- 无

### Day 27

地区摘要：
- border_town：danger 61.95 / order 2.40 / scarcity 98.00 / mystic 38.50 / food 8.30 / herbs 46.21 / relics 15.62 / information 100.00 / tags [order_low, populated, resource_strained, scarcity_high, town, trade_route]
- mirror_lake_forest：danger 69.41 / order 30.13 / scarcity 36.21 / mystic 64.75 / food 71.16 / herbs 65.65 / relics 22.84 / information 52.39 / tags [beast_migration, danger_high, forest, herb_rich, lake, order_low]
- old_ruins：danger 100.00 / order 0.00 / scarcity 56.65 / mystic 100.00 / food 27.05 / herbs 62.12 / relics 57.72 / information 56.18 / tags [danger_high, mystic_surge, order_low, relic_rich, resource_strained, ruins, unstable]

势力摘要：
- echo_cult：power 69.70 / wealth 47.40 / hostility 0.00 / goal 获取遗物与草药，提高神秘压力并制造异象
- smugglers：power 42.70 / wealth 100.00 / hostility 0.00 / goal 获取财富和情报，利用匮乏并削弱地区秩序
- wardens：power 77.70 / wealth 15.00 / hostility 0.00 / goal 维护秩序、压制走私者、阻止回声教团扩张

湖湾镇微观状态：
- old_chen：stress 100.00 / debt 100.00 / family_food 0.00 / shop_open false / tags [family_crisis, shop_closed]
- chen_mi：hunger 100.00 / fear 73.00 / health 84.00 / inventory [spoiled_grain] / tags [hiding_spoiled_grain, disease_risk]
- old_chen_shop：is_open false / food_stock 0.00 / family_crisis true / traces [trace_price_rise_notice, trace_child_hiding_bag, trace_spoiled_grain_bag, trace_grain_dust_on_sleeve, trace_closed_shop]
- abandoned_granary：spoiled_grain_stock 2.00 / disease_risk 0.65 / traces [trace_granary_missing_grain]
湖湾镇微观链：无新增事实、痕迹或可叙述状态。

当天新新闻：
- border_town / 镜湖守望者 / 阶段 4 / 累计 16：已护送 16 批粮车，但补给速度仍追不上消耗。

连续事件摘要：
- border_town / 阶段 5 / 累计 27：走私者袭击补给线已持续 27 次，边境镇粮食压力仍在升高。
- border_town / 阶段 4 / 累计 16：守望者已护送 16 批补给，粮食危机仍未完全缓解。
- border_town / 阶段 4 / 累计 11：守望者清剿走私据点已持续 11 次，盘查与暗线活动同时增加。

当天 LeadCandidate：
- tracks / beast_migration / fact_d27_171_region_daily_shift / risk 0.70 / urgency 0.71
- river / resource_pressure_along_lake_routes / fact_d27_171_region_daily_shift / risk 0.52 / urgency 0.50
- rumor / smuggler_information_market / fact_d27_170_region_daily_shift / risk 0.43 / urgency 0.95

当天适配后 v0.3 线索：
- 足迹 / 林中迁徙足迹 / 西北 / freshness 1.00 / risk 0.70 / 狩猎, 跟随, 设陷, 警告旅人
- 河流 / 河岸资源异动 / 西北 / freshness 1.00 / risk 0.52 / 取水检验, 溯流追查, 提醒居民, 放任
- 传闻 / 镇上的低声传闻 / 东南 / freshness 1.00 / risk 0.43 / 核实, 购买情报, 散播消息, 报告

### Day 28

地区摘要：
- border_town：danger 63.24 / order 0.00 / scarcity 98.00 / mystic 38.42 / food 9.19 / herbs 46.37 / relics 15.65 / information 100.00 / tags [order_low, populated, resource_strained, scarcity_high, town, trade_route]
- mirror_lake_forest：danger 70.16 / order 29.78 / scarcity 35.22 / mystic 64.47 / food 71.48 / herbs 66.03 / relics 22.63 / information 53.06 / tags [beast_migration, danger_high, forest, herb_rich, lake, order_low]
- old_ruins：danger 100.00 / order 0.00 / scarcity 57.43 / mystic 100.00 / food 28.11 / herbs 61.72 / relics 57.54 / information 55.63 / tags [danger_high, mystic_surge, order_low, relic_rich, resource_strained, ruins, unstable]

势力摘要：
- echo_cult：power 71.20 / wealth 46.90 / hostility 0.00 / goal 获取遗物与草药，提高神秘压力并制造异象
- smugglers：power 43.40 / wealth 100.00 / hostility 0.00 / goal 获取财富和情报，利用匮乏并削弱地区秩序
- wardens：power 78.20 / wealth 13.00 / hostility 0.00 / goal 维护秩序、压制走私者、阻止回声教团扩张

湖湾镇微观状态：
- old_chen：stress 100.00 / debt 100.00 / family_food 0.00 / shop_open false / tags [family_crisis, shop_closed]
- chen_mi：hunger 100.00 / fear 74.50 / health 84.00 / inventory [spoiled_grain] / tags [hiding_spoiled_grain, disease_risk]
- old_chen_shop：is_open false / food_stock 0.00 / family_crisis true / traces [trace_price_rise_notice, trace_child_hiding_bag, trace_spoiled_grain_bag, trace_grain_dust_on_sleeve, trace_closed_shop]
- abandoned_granary：spoiled_grain_stock 2.00 / disease_risk 0.65 / traces [trace_granary_missing_grain]
湖湾镇微观链：无新增事实、痕迹或可叙述状态。

当天新新闻：
- 无

连续事件摘要：
- border_town / 阶段 5 / 累计 28：走私者袭击补给线已持续 28 次，边境镇粮食压力仍在升高。
- border_town / 阶段 4 / 累计 17：守望者已护送 17 批补给，粮食危机仍未完全缓解。
- border_town / 阶段 4 / 累计 11：守望者清剿走私据点已持续 11 次，盘查与暗线活动同时增加。

当天 LeadCandidate：
- 无

当天适配后 v0.3 线索：
- 无

### Day 29

地区摘要：
- border_town：danger 65.36 / order 0.00 / scarcity 100.00 / mystic 38.73 / food 2.75 / herbs 46.75 / relics 15.48 / information 100.00 / tags [danger_high, order_low, populated, resource_strained, scarcity_high, town, trade_route]
- mirror_lake_forest：danger 70.90 / order 29.43 / scarcity 36.17 / mystic 65.66 / food 72.89 / herbs 61.27 / relics 22.49 / information 52.75 / tags [beast_migration, danger_high, forest, herb_rich, lake, order_low]
- old_ruins：danger 100.00 / order 0.00 / scarcity 58.20 / mystic 100.00 / food 28.71 / herbs 62.71 / relics 57.40 / information 55.94 / tags [danger_high, mystic_surge, order_low, relic_rich, resource_strained, ruins, unstable]

势力摘要：
- echo_cult：power 71.70 / wealth 48.10 / hostility 0.00 / goal 获取遗物与草药，提高神秘压力并制造异象
- smugglers：power 41.90 / wealth 100.00 / hostility 0.00 / goal 获取财富和情报，利用匮乏并削弱地区秩序
- wardens：power 78.90 / wealth 12.00 / hostility 0.00 / goal 维护秩序、压制走私者、阻止回声教团扩张

湖湾镇微观状态：
- old_chen：stress 100.00 / debt 100.00 / family_food 0.00 / shop_open false / tags [family_crisis, shop_closed]
- chen_mi：hunger 100.00 / fear 76.00 / health 84.00 / inventory [spoiled_grain] / tags [hiding_spoiled_grain, disease_risk]
- old_chen_shop：is_open false / food_stock 0.00 / family_crisis true / traces [trace_price_rise_notice, trace_child_hiding_bag, trace_spoiled_grain_bag, trace_grain_dust_on_sleeve, trace_closed_shop]
- abandoned_granary：spoiled_grain_stock 2.00 / disease_risk 0.65 / traces [trace_granary_missing_grain]
湖湾镇微观链：无新增事实、痕迹或可叙述状态。

当天新新闻：
- mirror_lake_forest / 回声教团 / 阶段 3 / 累计 8：草药已被集中采集 8 次，采药人开始深入危险地带。
- border_town / 地区观察 / 阶段 1 / 累计 1：边境镇 的状态标签发生变化：danger_high, order_low, populated, resource_strained, scarcity_high, town, trade_route

连续事件摘要：
- border_town / 阶段 5 / 累计 29：走私者袭击补给线已持续 29 次，边境镇粮食压力仍在升高。
- border_town / 阶段 4 / 累计 17：守望者已护送 17 批补给，粮食危机仍未完全缓解。
- border_town / 阶段 4 / 累计 12：守望者清剿走私据点已持续 12 次，盘查与暗线活动同时增加。

当天 LeadCandidate：
- caravan / scarcity_high_and_smuggler_raid / fact_d29_186_raid_supplies / risk 0.83 / urgency 1.00
- apparition / cult_ritual_and_mystic_pressure / fact_d29_184_region_daily_shift / risk 1.00 / urgency 1.00
- smoke / order_collapse_and_forest_conflict / fact_d29_187_harvest_herbs / risk 0.71 / urgency 0.71

当天适配后 v0.3 线索：
- 烟柱 / 远处商队烟迹 / 东南 / freshness 1.00 / risk 0.83 / 调查, 护送, 劫掠, 放任
- 传闻 / 关于旧遗迹异象的传闻 / 北方 / freshness 1.00 / risk 1.00 / 观察, 打断, 跟随, 报告
- 烟柱 / 林间冲突升起的烟柱 / 西北 / freshness 1.00 / risk 0.71 / 靠近, 侦察, 绕行, 通知守望者

### Day 30

地区摘要：
- border_town：danger 66.69 / order 0.00 / scarcity 98.00 / mystic 40.69 / food 3.61 / herbs 47.22 / relics 15.30 / information 100.00 / tags [danger_high, order_low, populated, resource_strained, scarcity_high, town, trade_route]
- mirror_lake_forest：danger 71.66 / order 29.07 / scarcity 35.09 / mystic 65.59 / food 73.66 / herbs 61.65 / relics 22.30 / information 53.74 / tags [danger_high, forest, herb_rich, lake, order_low]
- old_ruins：danger 100.00 / order 0.00 / scarcity 58.96 / mystic 100.00 / food 28.66 / herbs 62.82 / relics 57.32 / information 55.94 / tags [danger_high, mystic_surge, order_low, relic_rich, resource_strained, ruins, unstable]

势力摘要：
- echo_cult：power 72.30 / wealth 48.10 / hostility 0.00 / goal 获取遗物与草药，提高神秘压力并制造异象
- smugglers：power 42.60 / wealth 100.00 / hostility 0.00 / goal 获取财富和情报，利用匮乏并削弱地区秩序
- wardens：power 79.40 / wealth 10.00 / hostility 0.00 / goal 维护秩序、压制走私者、阻止回声教团扩张

湖湾镇微观状态：
- old_chen：stress 100.00 / debt 100.00 / family_food 0.00 / shop_open false / tags [family_crisis, shop_closed]
- chen_mi：hunger 100.00 / fear 77.50 / health 84.00 / inventory [spoiled_grain] / tags [hiding_spoiled_grain, disease_risk]
- old_chen_shop：is_open false / food_stock 0.00 / family_crisis true / traces [trace_price_rise_notice, trace_child_hiding_bag, trace_spoiled_grain_bag, trace_grain_dust_on_sleeve, trace_closed_shop]
- abandoned_granary：spoiled_grain_stock 2.00 / disease_risk 0.65 / traces [trace_granary_missing_grain]
湖湾镇微观链：无新增事实、痕迹或可叙述状态。

当天新新闻：
- border_town / 镜湖守望者 / 阶段 4 / 累计 18：已护送 18 批粮车，但补给速度仍追不上消耗。

连续事件摘要：
- border_town / 阶段 5 / 累计 30：走私者袭击补给线已持续 30 次，边境镇粮食压力仍在升高。
- border_town / 阶段 4 / 累计 18：守望者已护送 18 批补给，粮食危机仍未完全缓解。
- border_town / 阶段 4 / 累计 12：守望者清剿走私据点已持续 12 次，盘查与暗线活动同时增加。

当天 LeadCandidate：
- 无

当天适配后 v0.3 线索：
- 无

## 4. 第 3 天测试注入后 30 天总览

- 总量：world_fact 205（微观事实 3），world_news 46，新闻历史 12，LeadCandidate 39，适配后线索 39，Trace 6，可叙述状态 1
- 线索类型分布：`{"传闻":15,"河流":3,"烟柱":12,"足迹":9}`
- 30 天后地区最终状态：
  - border_town：danger 62.55 / order 1.53 / scarcity 75.37 / mystic 40.69 / food 32.61 / herbs 47.22 / relics 15.30 / information 100.00 / tags [order_low, populated, resource_strained, scarcity_high, town, trade_route]
  - mirror_lake_forest：danger 71.66 / order 29.07 / scarcity 35.09 / mystic 65.59 / food 73.66 / herbs 61.65 / relics 22.30 / information 53.74 / tags [danger_high, forest, herb_rich, lake, order_low]
  - old_ruins：danger 100.00 / order 0.00 / scarcity 58.96 / mystic 100.00 / food 28.66 / herbs 62.82 / relics 57.32 / information 55.94 / tags [danger_high, mystic_surge, order_low, relic_rich, resource_strained, ruins, unstable]
- 30 天后势力最终状态：
  - echo_cult：power 72.30 / wealth 48.10 / hostility 0.00 / goal 获取遗物与草药，提高神秘压力并制造异象
  - smugglers：power 43.20 / wealth 100.00 / hostility 8.00 / goal 获取财富和情报，利用匮乏并削弱地区秩序
  - wardens：power 82.80 / wealth 5.00 / hostility -6.00 / goal 维护秩序、压制走私者、阻止回声教团扩张
- 地区 tag 变化：
  - border_town：新增 [order_low, resource_strained, scarcity_high]，移除 []
  - mirror_lake_forest：新增 [danger_high, order_low]，移除 []
  - old_ruins：新增 [danger_high, mystic_surge, order_low, resource_strained]，移除 []

## 5. A/B 差异

- 第 10 天是否已出现差异：是
- 第 10 天差异项：`{"adapted_leads":false,"factions":true,"lead_candidates":false,"regions":true,"world_news":true}`
- 数量差：world_news +5，LeadCandidate -1，适配后线索 -1
- 线索签名是否不同：是；适配后线索签名是否不同：是
- 第 30 天地区状态差异：
  - border_town：`{"danger":-4.14,"food":29.0,"herbs":0.0,"information":0.0,"mystic":0.0,"order":1.53,"relics":0.0,"scarcity":-22.63}`
  - mirror_lake_forest：`{"danger":0.0,"food":0.0,"herbs":0.0,"information":0.0,"mystic":0.0,"order":0.0,"relics":0.0,"scarcity":0.0}`
  - old_ruins：`{"danger":0.0,"food":0.0,"herbs":0.0,"information":0.0,"mystic":0.0,"order":0.0,"relics":0.0,"scarcity":0.0}`
- 第 30 天势力状态差异：
  - echo_cult：`{"hostility_to_player":0.0,"power":0.0,"wealth":0.0}`
  - smugglers：`{"hostility_to_player":8.0,"power":0.6,"wealth":0.0}`
  - wardens：`{"hostility_to_player":-6.0,"power":3.4,"wealth":-5.0}`

## 6. 适配后线索样例

- 烟柱｜远处商队烟迹｜东南｜新鲜度 1.00｜风险 0.53｜行动：调查, 护送, 劫掠, 放任
- 传闻｜关于旧遗迹异象的传闻｜北方｜新鲜度 1.00｜风险 0.74｜行动：观察, 打断, 跟随, 报告
- 足迹｜道旁新设的盘查痕迹｜东南｜新鲜度 1.00｜风险 0.29｜行动：配合盘查, 询问, 绕过关卡, 举报走私
- 足迹｜林中迁徙足迹｜西北｜新鲜度 1.00｜风险 0.62｜行动：狩猎, 跟随, 设陷, 警告旅人
- 传闻｜镇上的低声传闻｜东南｜新鲜度 1.00｜风险 0.44｜行动：核实, 购买情报, 散播消息, 报告

## 7. 结论

固定 seed 下，world_sim 可稳定输出地区、势力、新闻与线索；第 3 天测试注入会改变后续状态与线索签名。
观察器只读取并整理模拟结果，没有创建新的世界事实规则。

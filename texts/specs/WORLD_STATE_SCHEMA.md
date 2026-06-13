# Chronicle 世界状态 Schema

**文档定位**：世界模拟层数据结构规格
**依赖总纲**：`texts/CHRONICLE_CORE_DESIGN_GUIDE.md`
**版本**：v0.1
**日期**：2026-06-13

---

## 1. 本文档的作用

本文档定义 Chronicle 世界模拟层的核心数据对象。

它的目标不是一次性设计完整矮人要塞式世界，而是定义 Demo 和 MVP 阶段必须稳定下来的世界事实结构。

Chronicle 的基本原则：

```text
世界层决定事实
表现层负责表达
规则层生成选项
纪事层回收经历
```

因此，所有重要文本、事件、线索、选择、纪事，都必须能追溯到世界状态对象。

---

## 2. 核心对象总览

世界层至少包含以下对象：

```text
WorldState
RegionState
LocationState
NPCState
FactionState
RelationshipState
ResourceState
WorldFact
Trace
Memory
LeadCandidate
LifePhase
ChronicleEntry
```

对象关系：

```text
WorldState
 ├─ RegionState
 │   ├─ LocationState
 │   ├─ ResourceState
 │   └─ Trace
 ├─ NPCState
 │   ├─ Memory
 │   └─ RelationshipState
 ├─ FactionState
 ├─ WorldFact
 ├─ LeadCandidate
 ├─ LifePhase
 └─ ChronicleEntry
```

---

## 3. WorldState

`WorldState` 是世界模拟层的根对象。

### 3.1 字段

```text
day: int
year: int
season: string
seed: int
regions: Dictionary
locations: Dictionary
npcs: Dictionary
factions: Dictionary
facts: Array[WorldFact]
traces: Array[Trace]
leads: Array[LeadCandidate]
chronicle_entries: Array[ChronicleEntry]
active_life_phase: LifePhase
```

### 3.2 职责

WorldState 负责保存：

```text
当前时间
所有地区
所有重要地点
所有已具体化 NPC
所有势力
已经发生过的事实
世界留下的痕迹
玩家可见线索
玩家人生阶段
可被纪事回收的记录
```

WorldState 不负责写文本。

---

## 4. RegionState

`RegionState` 表示一个地区。

Demo 阶段可用：

```text
湖湾镇周边
镜湖森林
北境边境
```

### 4.1 字段

```text
id: string
name: string
tags: Array[string]

food: float
order: float
war_tension: float
danger: float
scarcity: float
mystic: float

population: float
wealth: float
health: float
morale: float

owner_faction_id: string
active_factions: Array[string]
locations: Array[string]

recent_changes: Array[string]
```

### 4.2 慢变量

Demo 阶段最重要的慢变量：

```text
food
order
war_tension
```

其他变量可以存在，但不要抢核心。

### 4.3 地区标签

地区标签用于表达状态变化。

示例：

```text
shortage
unsafe_road
under_patrol
war_pressure
haunted
market_closed
food_price_rising
```

标签不是文本效果，而是状态事实。

---

## 5. LocationState

`LocationState` 表示地区内具体地点。

例如：

```text
老陈的店
湖湾镇集市
第七哨站
北墙
军医室
食堂
旧粮仓
```

### 5.1 字段

```text
id: string
name: string
region_id: string
type: string
tags: Array[string]
owner_faction_id: string
present_npcs: Array[string]
traces: Array[string]
state: Dictionary
```

### 5.2 示例

```text
id: chen_shop
name: 老陈的店
region_id: lake_town
type: shop
tags: [closed, debt_pressure]
state:
  food_stock: low
  debt_level: high
  door_open: false
```

表现层可以把它翻译成：

```text
老陈今天没有开店。
```

---

## 6. NPCState

`NPCState` 表示具体 NPC。

Chronicle 不模拟所有人。

NPC 分级：

```text
S级：核心 NPC，完整记忆、关系、长期目标
A级：重要 NPC，简化状态和少量记忆
B级：功能 NPC，职业、位置、基础状态
C级：群体实体，不具体化
```

### 6.1 字段

```text
id: string
name: string
tier: string
age: int
role: string
region_id: string
location_id: string
faction_id: string

health: float
hunger: float
fear: float
hope: float
loyalty: float
stress: float

needs: Dictionary
traits: Array[string]
memories: Array[string]
relationships: Dictionary
inventory: Array[string]
goals: Array[string]

status_tags: Array[string]
```

### 6.2 需求 needs

需求驱动 NPC 行为。

示例：

```text
needs:
  food: 80
  safety: 60
  money: 70
  medicine: 20
```

如果陈米 `food` 需求长期过高，而老陈店铺粮食不足，就可能产生偷粮行为。

### 6.3 记忆 memories

NPC 记忆不写散文，只记录事实引用。

```text
memories:
  fact_player_gave_food_to_chenmi
  fact_player_reported_chenmi
  fact_player_served_with_yilai_year_2
```

表现层需要时再翻译。

---

## 7. FactionState

`FactionState` 表示势力。

### 7.1 字段

```text
id: string
name: string
type: string
power: float
wealth: float
food: float
morale: float
hostility_to_player: float
relations: Dictionary
controlled_regions: Array[string]
goals: Array[string]
known_facts: Array[string]
tags: Array[string]
```

### 7.2 Demo 势力示例

```text
湖湾镇守卫
粮商网络
第七哨站
边境敌军
走私者
```

势力不是只提供任务，而是世界变化的行动者。

---

## 8. RelationshipState

关系不是单一好感度。

### 8.1 字段

```text
target_id: string
affection: float
trust: float
fear: float
debt: float
resentment: float
familiarity: float
last_interaction_day: int
tags: Array[string]
```

### 8.2 示例

玩家帮助陈米后：

```text
陈米.trust +20
陈米.debt +10
老陈.trust +8
粮商.resentment +5
守卫.familiarity +2
```

关系必须能影响未来选项和纪事。

---

## 9. ResourceState

资源可以属于地区、地点、势力或角色。

### 9.1 字段

```text
id: string
type: string
owner_id: string
amount: float
quality: float
tags: Array[string]
```

### 9.2 Demo 资源

```text
food
spoiled_grain
medicine
military_rations
old_dagger
hard_bread
bowstring
letter
```

物品如果具有叙事价值，应能进入纪事。

---

## 10. WorldFact

`WorldFact` 是已经真实发生的事实。

文本、线索、纪事都应引用事实。

### 10.1 字段

```text
id: string
day: int
type: string
actors: Array[string]
region_id: string
location_id: string
cause_fact_ids: Array[string]
effects: Dictionary
tags: Array[string]
importance: float
```

### 10.2 示例

```text
id: fact_chenmi_stole_spoiled_grain
type: theft
actors: [chenmi]
region_id: lake_town
location_id: abandoned_granary
cause_fact_ids:
  - fact_food_price_rising
  - fact_chen_family_debt_high
effects:
  chenmi.has_spoiled_grain = true
  old_chen.stress +10
tags:
  - food_crisis
  - child
  - moral_choice
importance: 0.8
```

如果没有 WorldFact，表现层不得生成重大文本。

---

## 11. Trace

`Trace` 是事实留下的可见痕迹。

玩家不是直接看到 WorldFact，而是看到 Trace。

### 11.1 字段

```text
id: string
fact_id: string
region_id: string
location_id: string
type: string
visibility: float
freshness: float
risk: float
description_tags: Array[string]
possible_interactions: Array[string]
```

### 11.2 示例

```text
type: closed_shop
description_tags:
  - wet_price_notice
  - locked_door
  - child_hiding_bag
possible_interactions:
  - ask_child
  - give_food
  - report_to_guard
  - ignore
```

Trace 对应玩家前台看到的“线索”或“场景痕迹”。

---

## 12. Memory

`Memory` 是 NPC、玩家或地点保存的过去。

### 12.1 字段

```text
id: string
owner_id: string
fact_id: string
emotional_weight: float
decay: float
tags: Array[string]
```

### 12.2 示例

```text
陈米记得玩家给过她食物
伊莱记得玩家救过他
第七哨站记得玩家服役五年
```

Memory 不一定每次出现，但必须能在未来影响行为。

---

## 13. LeadCandidate

`LeadCandidate` 是系统决定“值得展示给玩家”的候选线索。

它不是随机事件。

### 13.1 字段

```text
id: string
day: int
type: string
region_id: string
location_id: string
source_fact_id: string
source_trace_id: string
world_cause: string
urgency: float
freshness: float
risk: float
possible_actions: Array[string]
projected_consequences: Dictionary
```

### 13.2 规则

所有 LeadCandidate 必须来自：

```text
WorldFact
Trace
RegionState
NPCState
FactionState
```

禁止凭空随机生成。

---

## 14. LifePhase

`LifePhase` 表示玩家当前人生阶段。

### 14.1 字段

```text
id: string
mode: string
start_day: int
planned_duration_days: int
region_id: string
location_id: string
involved_npcs: Array[string]
repeated_rituals: Array[string]
phase_facts: Array[string]
phase_memories: Array[string]
status_changes: Array[string]
```

### 14.2 mode 示例

```text
wandering
settling
military_service
research
business
pursuit
retirement
```

Demo 阶段只做：

```text
settling
military_service
```

---

## 15. ChronicleEntry

`ChronicleEntry` 是纪事系统可回收的记录。

### 15.1 字段

```text
id: string
day: int
type: string
importance: float
fact_ids: Array[string]
npc_ids: Array[string]
location_ids: Array[string]
item_ids: Array[string]
tags: Array[string]
text_seed: Dictionary
```

### 15.2 示例

```text
type: farewell
fact_ids:
  - fact_player_served_five_years
  - fact_ron_gave_old_dagger
  - fact_roll_call_without_player
npc_ids:
  - ron
  - yilai
  - mata
location_ids:
  - seventh_outpost
item_ids:
  - old_dagger
tags:
  - military_service
  - farewell
  - absence
  - old_item
```

纪事文本只能回收 ChronicleEntry 中真实存在的信息。

---

## 16. 数据层禁止事项

1. 禁止重大事实只存在于文本中。
2. 禁止线索没有来源事实。
3. 禁止纪事引用没有发生过的事。
4. 禁止 AI 或模板创造世界事实。
5. 禁止玩家选项只改文本，不改状态。
6. 禁止 NPC 行为没有需求或状态来源。
7. 禁止长期模式只做奖励结算。
8. 禁止用事件池代替 WorldFact / Trace / LeadCandidate。

---

## 17. Demo 最小实现顺序

建议实现顺序：

```text
RegionState
↓
NPCState
↓
WorldFact
↓
Trace
↓
LeadCandidate
↓
Action Resolver
↓
Memory
↓
LifePhase
↓
ChronicleEntry
```

不要一开始就实现完整经济、完整战斗、完整装备。

---

## 18. 一句话原则

Chronicle 的世界状态层必须能回答：

> 这件事为什么发生？
> 谁做了它？
> 它留下了什么痕迹？
> 玩家为什么能看见？
> 玩家做了什么？
> 世界因此哪里变了？
> 多年后谁还记得？

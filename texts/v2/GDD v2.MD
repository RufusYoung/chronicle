太好了，先把思路拉满、落到一份真正“能交给程序/美术/编剧落地”的 GDD v2。下面这版在你的 v1 基础上，按“规则最小 + 数据最富 + 因果可追溯 + 可扩平台”的方向重排与细化：把**系统如何说话**（I/O）、**数据如何长肉**（Schema）、**引擎如何推进**（算法/流程）、**内容如何生产**（编剧指引）写清楚，最后配上线性→图式地图、事件链路、平衡与验收标准、短期里程碑。

---

# 《冒险纪事 / Chronicle》GDD v2（可执行版）

## 0. 设计基线（Non-Negotiables）

* **玩家幻想**：在一个会自己呼吸的世界里，作为一个“脆弱但可成长的个体”，经历一段独一无二、可被记录的旅行。
* **世界观气质**：50% 震撼/瑰丽/轻松 + 50% 黑暗/隐秘/危险（《来自深渊》《芙莉莲》调性）。
* **方法论**：少数通用规则 × 富含标签的世界事实 → 涌现式叙事（不靠长剧情脚本）。
* **产出形态**：文字冒险为主（RichText + 选项），像素化 UI 支撑氛围与反馈。
* **记录**：全过程生成“纪事（Chronicle）”，结局导出可读档。

---

## 1. 核心循环（Player Core Loop）

```
目的地选择/原地探索
→ 时间推进（昼夜/季节/年份；体力/理智/饥饿 等资源结算）
→ 事件分发（环境/生物/势力/内心），可触发战斗/交互/睡眠/采集/旅行
→ 结果写回（flags/marks/物品/关系/世界态势）
→ 纪事增量更新（事实与风格化语句）
→ 新的决策点（含选项/自动继续）
```

---

## 2. 世界系统（World System）

### 2.1 时间轴

* 粒度：小时（h）→ 天（d）→ 季（s）→ 年（y）
* **Tick**：每“推进动作”至少 +1h；某些系统（旅行/睡眠/制作）按固定小时数推进。
* **昼夜/季节影响**：事件权重、气候、可达性、疾病几率、梦境频率。

### 2.2 世界事实（Facts）

* **事实五类**：地理（region/edge）、生态（flora/fauna/weather）、社会（faction/关系）、历史（遗迹/传说/纪年）、个人（marks/inventory/关系）。
* **事实形态**：`{id, tags[], props{...}, counters{}, last_updated, provenance}`

  * `tags[]` 是规则对事实“读”的主要入口（如 `["forest","sacred","fog","mirrorlake"]`）。
  * `counters` 用于“因果强度/累计值”（如“在雾中迷路 3/5 次”）。

### 2.3 地图与连接（Graph Map）

* **节点**：地区（Region）/ 子地点（Sublocation）
* **边**：`edge{from,to,terrain,toll,hostility,base_hours}`
* **旅行耗时**：`base_hours * terrain_mult * weather_mult * load_mult * condition_mult`
* **非线性解锁**：边具备 `requires[]`（flag/mark/reputation/装备），支持世界随时代变化**重连**（封路、开路、临时捷径）。

---

## 3. 角色与资源（Character & Survival）

### 3.1 属性与状态

* **基础属性**：力、敏、体、智、感、魅（6 维）
* **生存状态**：生命（HP，非战斗为持久）、理智（SAN）、体温/疾病、饥饿、负重、睡眠积累。
* **成长机制**：**印记（Mark）**驱动成长（非刷数值）：

  * 例：`[深林静思] ×3 → 感+1`；`[长途负重] ×5 → 体+1`
* **疲惫曲线**（保持 v1 的阶梯与体质修正，数值归整到小时/百分比两个单位系）。

### 3.2 装备与改造（轻内核）

* **双词条**：战斗词条 / 探索词条（如“抗寒”“夜视”“追踪”）
* **损耗**：以“状态”控制（完好/磨损/破损），状态影响词条效果。
* **改造上限**：`limit = 体质*5 + 稳定修正`，超限进入“风险池”（幻觉/畸变/副作用）。

---

## 4. 战斗系统（Auto-Resolve）

* **触发**：事件脚本/探索遭遇/势力冲突。
* **临时战斗生命**：战斗结束重置（借鉴 v1）。
* **求解**：`DPS = f(属性, 词条, 天气地形, 对手模板)`；
  **战败**不一定死亡→可能负伤/感染/被俘/失物；**胜利**产出印记/战利品/态势变化。
* **记叙**：战斗细节以“要点拼句”生成（不做长剧本）。

---

## 5. 涌现叙事引擎（Emergent Narrative Engine, ENE）

> 核心目标：**少数通用规则** + **标签丰富的数据** → 事件“自然”发生，**有因果链**、**可回溯**、**可分支**。

### 5.1 事件模型（Event DSL）

```json
{
  "id": "ev.silence.enter",
  "tags": ["starter","forest","silence"],
  "weight": 1.2,
  "pre": [ {"any_tag": ["forest","mirrorlake"]},
           {"time_in": ["dawn","dusk"]},
           {"flag_absent": "banished_by_forest"} ],
  "effects": [ {"set_flag":"in_silence"},
               {"mark_add":"silent_steps", "inc":1},
               {"write_fact": {"k":"last_enter_silence","v":"now"}} ],
  "spawns": [
     {"when":[{"roll_lt":0.4}],"add":["fauna.owl_whisper"]},
     {"when":[{"weather_in":["fog"]}],"add":["hazard.soft_mire"]}
  ],
  "choices":[
     {"id":"listen","text":"静听风与枝叶的心声",
      "effects":[{"counter_add":"listen_wind", "inc":1}],
      "goto":"ev.silence.answer_or_reject"},
     {"id":"speak","text":"开口呼唤（冒犯沉默）",
      "effects":[{"set_flag":"angered_forest"}],
      "goto":"ev.silence.forest_reject"}
  ],
  "next":[
     {"id":"ev.silence.deepen","weight":1.0,
      "req":[{"counter_gte":{"k":"listen_wind","v":2}}]},
     {"id":"ev.common.foraging","weight":0.4}
  ]
}
```

**说明（最小通用子句）**

* `pre[]`：前置判定（时间/天气/标签/flag/mark/counter/reputation…）。
* `effects[]`：写回世界事实（flag/mark/counter/inventory/reputation/fact…）。
* `spawns[]`：内容注入（把“生物/植物/危害”贴到当前快照中，参与后续因果）。
* `choices[]`：本事件内分支（本地因果）。
* `next[]`：概率“延链”，支持 `req[]`（链上因果继续）。

> **关键**：事件不写长剧情，只**写条件与副作用**；文本由 **模板 + 事实**拼装。

### 5.2 选择与推进（Choice Gate）

* 当 `choices[]` 非空 → **暂停自动推进**，等待玩家选择；
* `apply_choice()`：先执行 `effects` → 评估 `goto`/`travel`/`spawn_event` → 写回因果；
* 选项执行后**立即发一个“后继事件”**（`goto` 或 `next` 筛选），避免“空白”。

### 5.3 事件来源优先级

1. **链后继（next）** ＞ 2) **场景种子（starter）** ＞ 3) **全球池（权重+标签匹配）**
   并带去重与冷却（同类事件短期不重复）。

### 5.4 因果存储（Causality Store）

* `flags{}`, `marks[]`, `counters{}`, `facts{}`（含时间戳）
* **规则只读这些容器**；**所有事件/系统只写这些容器**。
* 纪事系统读**差分**（变化 → 句段）。

---

## 6. 数据规范（Schemas for Content）

### 6.1 通用池（/data/common）

* `weather.json / flora.json / creatures.json / hazards.json / traits.json / loot.json / resources.json`
* 统一字段：

```
{id, name, tags[], weight, desc, props{...}, text_templates[], conds[], effects[]}
```

* **编剧指引**：

  * 每条 `tags[]` ≥ 5 个（生态/地形/光照/季节/神秘/势力…）。
  * `text_templates[]` 写“可插值句”，如：
    `"雾像是从{flora.root}里渗出，{fauna.call}在枝叶间回响。"`

### 6.2 地区（/data/regions/**/region.json）

```
{
 "id":"region.mirrorlake.belt",
 "name":"镜湖森林带",
 "tags":["forest","mirrorlake","north_central","sacred"],
 "pools": {
   "weather":[{"ref":"common:weather:fog_mirrorlake","weight":1.4}, ...],
   "flora":[...],
   "fauna":[...],
   "hazards":[...],
   "events":[{"ref":"region:event:ev.silence.enter"}, ...]
 },
 "sublocations":[...],
 "edges":[ {"to":"region.silence.forest","base_hours":3,"requires":["in_silence"]} ]
}
```

### 6.3 事件（/data/regions/**/events.json）

采用 **5.1 的 DSL**；编剧每写一条“事实/生物/植物”，就想一条“会被哪个事件读取”的 `tags/conds/effects`。

---

## 7. UI/UX（玩家可见反馈）

### 7.1 文本区

* **分三栏**：主叙述（RichText，分页）、**世界提示**（小灰行：时间/天气/温度/状态）、**纪事摘录**（重要事实短句）。
* **选项区**：只在 `choices` 存在时显示；选后**立即刷新**下一事件文本。
* **回看**：页签式翻页；自动在临界字符数落盘（v1 已有）。

### 7.2 氛围反馈

* 天气/昼夜/季节 → UI 调色、边角粒子（雾/雪/萤火）、环境音。

---

## 8. 平衡与反复（Balancing & Anti-Degeneracy）

* **权重上限**：同类事件 `effective_weight ∈ [0.2, 3.0]`，避免“一招鲜”。
* **冷却**：同 ID 冷却 N 小时；同类 tag 冷却更短（如 `["foraging"]` 2h）。
* **新鲜度优先**：最近未见/未体验的内容获得 `novelty_boost`。
* **安全阈**：饥饿/寒冷/疾病 → 进入“缓冲事件池”（给予补救/求生机会，但有代价）。
* **死亡是结果**：不硬保；但允许“代价换生”。

---

## 9. 纪事系统（Legacy Chronicle）

* **输入**：事实差分（flags/marks/counters/inventory/关系/大战/旅行）。
* **风格器**：按角色“风格（Style）”“地区气质”“季节”选择句型库。
* **输出**：章节化文本（按季/关键事件分页）；存 `user://chronicles/{seed}/{run}.md`。
* **标题生成**：`《{风格称号}·{角色名}的编年》`，副标题为“时代语”。

---

## 10. 生成器/算法要点（给程序）

### 10.1 事件选择伪代码

```pseudo
function produce_snapshot(ctx):
  flush_spawns()            # 先把上一事件注入的 flora/fauna/hazards 合并
  if awaiting_choice: return EMPTY

  seed = pick_chain_next()  # 基于 last_event.next + req
  if !seed: seed = pick_starter_or_global() # 启链/补链

  apply_effects(seed.effects)
  cache_choices(filter(seed.choices, pre_ok))
  awaiting_choice = has_choices()

  return assemble_text(seed, injected, world_facts)
```

### 10.2 选项执行

```pseudo
function apply_choice(id):
  c = find_choice_by_id(last_event, id)
  apply_effects(c.effects)
  if c.travel_to_region: return {type:"travel", ...}
  if c.goto_event:       return emit_event(c.goto_event)
  return emit_chain_next_or_global()
```

### 10.3 文本组装器（Template + Facts）

* 输入：`{event.text_templates[], weather, flora[], fauna[], subloc, marksΔ, flagsΔ}`
* 规则：优先用事件自身模板；不足用地区模板；仍不足 fallback 用通用模板（优先级：事件 > 地区 > 通用）。

---

## 11. 内容生产（给编剧/数值）

### 11.1 写作准则

* **不写故事，写物理/生物/社会事实**；让引擎自己“讲故事”。
* 每条内容至少回答：**是什么**、**可被谁读取**（tags）、**作用/代价**（effects）。
* 避免封闭式剧情；**多用 `mark/counter` 形成可升级的“因果链”。**

### 11.2 最小可玩的地区包（镜湖森林带 ↔ 沉默森林）

* **Starter**：3 条（清晨雾、镜湖倒影、无口入林）。
* **关键链**：

  * “沉默之礼”（多次“聆听”→得到“沉默徽记”→可安全穿行）
  * “逆礼之惩”（开口>2 次 → 森林驱逐 flag → 边封锁 3 天）
* **生态注入**：3×flora、3×fauna、2×hazard 通过 `spawns` 注入后续文本。
* **旅行**：edge 解锁条件 `in_silence` 或 `持徽记`；天气恶劣时边成本 ×1.5。

---

## 12. 验收标准（Definition of Done, 1st Playable）

* 30 分钟游玩中：

  1. 至少出现 3 条**可解释的因果链**（同一线的 next 或 counter 晋级）。
  2. **非线性旅行**成功（镜湖森林带 ↔ 沉默森林双向）。
  3. 纪事导出含 10+ 条关键事实；读上去**像故事**。
  4. 无红错；黄错仅限未用参数/Editor 警告。

---

## 13. 里程碑（Milestones, 4 周迭代）

**W1：因果闭环 α**

* 接口：`spawns`、`counters`、`novelty_boost`、同类冷却；
* 两地事件各 ≥8 条（含 2 条链式“成长印记”）。

**W2：文本组装 β**

* 模板占位规范与地区/通用回退；
* UI 小灰提示（世界时间/天气/状态）。

**W3：地图图式化 & 旅行平衡**

* edge 解锁/封锁；天气/负重对耗时影响；
* 旅行页“预计耗时/资源消耗”预告。

**W4：纪事体验 & 软上线**

* 纪事导出 + 首页“上一次纪事”入口；
* 打包一套“沉默之礼/逆礼之惩/误闯迷雾”链路展示。

---

## 14. 风险与对策

* **内容稀疏** → 抽空：加“生态注入”与“通用模板”作缓冲；
* **链条断裂** → 诊断：为每次选择/事件写“因果痕迹”到调试面板；
* **过难生存** → 安全池：低资源时强行注入“补给但有代价”的事件；
* **文本单调** → 模板分层（事件/地区/通用）+ 形容词/比喻词库（按气质挑选）；
* **性能** → 事实读写 O(1)，选择筛选限制集合大小（按 tag 倒排索引）。

---

### 你现在就能做的两件事（无改代码成本）

1. **补数据**：给镜湖与沉默两地各加 ≥8 事件；每条补足 `tags/pre/effects/choices/next/spawns`。
2. **标注目的**：为每条内容写一句“这条事实会被哪类规则读取？”（强迫自己只写可被系统利用的事实）。

等你点头，我们再把这份 v2 的“事件 DSL + 纪事模板 + 旅行耗时公式”三处翻成**具体 JSON 样例与最小实现**（逐文件、一改一测、带前后对比）——这样既不打断你当前结构，又把“因果链 + 非线性地图 + 纪事”三条主脉跑顺。

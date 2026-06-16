# Living Surface 规格

## 1. 目的

LivingSurface 是 Chronicle 的世界表面层。它把已经发生的 `WorldFact`、`Trace`、`Memory`、`NarratableState`、NPC 状态和地点状态翻译成开发者可读的“今日局面”。

LivingSurface 不是事件池，不决定事实，不调用 AI，不替代世界模拟层。它只帮助开发者看见：今天湖湾镇是什么样，谁在哪里，哪些痕迹还在，当前局面来自哪些事实。

## 2. 与 WorldFact / Trace / Memory 的关系

`WorldFact` 是已经发生的事实，LivingSurface 只能引用它，不能创建它。

`Trace` 是事实留下的可见痕迹，LivingSurface 优先用它生成可见细节。没有对应 `Trace` 时，不得写出具体痕迹。

`Memory` 是人物或地点保存的回声，LivingSurface 可以把它显示为记忆摘要，但不能用记忆反推新的事实。

## 3. 与 NarratableState 的关系

如果某天存在 `NarratableState`，LivingSurface 优先用它生成主卡。主卡必须保留：

- `source_fact_ids`
- `trace_ids`
- `memory_ids`
- `narratable_state_ids`

`NarratableState` 仍是投影结果，不是事实来源本身。LivingSurface 不会反向修改它。

## 4. LivingSurfaceCard 数据结构

标准卡片字段：

```gdscript
{
    "card_id": String,
    "seed": int,
    "day": int,
    "title": String,
    "subtitle": String,
    "location_id": String,
    "location_name": String,

    "scene_summary": String,
    "visible_details": Array,
    "people_present": Array,
    "location_state_lines": Array,
    "trace_lines": Array,
    "memory_echo_lines": Array,
    "cause_lines": Array,
    "quality_lines": Array,

    "source_fact_ids": Array,
    "trace_ids": Array,
    "memory_ids": Array,
    "narratable_state_ids": Array,
    "state_keys": Array,

    "tone_tags": Array,
    "severity": String,
    "card_type": String
}
```

每张卡至少必须有 `source_fact_ids` 或 `trace_ids`。`state_keys` 用于说明卡片读取了哪些人物或地点状态。

## 5. 生成规则

优先级：

1. 当日 `NarratableState`
2. 当日关键 `WorldFact`
3. 有近三日事实或痕迹支撑的状态延续

每天最多展示 1 张主卡和 2 张附属卡。卡片按严重度排序：`bad_outcome`、`critical`、`recovery`、`tense`、`calm`。

如果没有新增事实、没有痕迹、也没有近三日来源支撑，即使人物数值很高，也不得凭空生成重大场面。

## 6. 模板约束

模板只做结构化事实到短句的映射。它不能随机生成剧情，也不能引入没有来源的细节。

示例约束：

- 只有存在 `spoiled_grain_bag` 或相关取粮事实时，才可写发霉麦子。
- 只有存在 `guard_locked_abandoned_granary` 或封条痕迹时，才可写粮仓封条。
- 未知 fact type 不报错，显示通用句并保留 fact type。

## 7. UI 只读边界

Viewer 只消费 ViewModel 输出的 `Dictionary / Array`。UI 不得：

- 创建 `WorldFact`
- 创建 `Trace`
- 创建 `Memory`
- 创建 `NarratableState`
- 调用 `resolve_action()`
- 修改 `WorldSimState`

## 8. 禁止事项

禁止把 LivingSurface 当成事件池。

禁止 LivingSurface 决定事实。

禁止 LivingSurface 调用 AI 或大模型。

禁止 LivingSurface 替代 `WorldFact / Trace / Memory`。

禁止没有事实来源就写重要场景。

禁止为了鲜活感删除 `source_fact_ids / trace_ids / state_keys`。

## 9. 湖湾镇示例

取粮卡：

```text
老陈的铺子今天没有正常开门。
陈米抱着一只旧布袋，袋口露出灰白色的发霉麦粒。
她看见有人靠近时，把布袋往身后挪了一下。

来源：chen_mi_took_spoiled_grain，spoiled_grain_bag
```

封仓卡：

```text
废弃粮仓门上多了一道守卫封条。
封条前有几行小脚印，脚印又折回镇里。

来源：guard_locked_abandoned_granary，small_footprints_near_guard_seal
```

倒下卡：

```text
陈米倒在老陈铺子的门槛边。
她的饥饿已经进入极高区间，健康也在下降。

来源：chen_mi_collapsed_from_hunger，child_collapsed_at_shop_step
```

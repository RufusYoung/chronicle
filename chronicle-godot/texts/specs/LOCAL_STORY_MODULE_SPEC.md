# LocalStoryModule 规格

## 1. 目的

`LocalStoryModule` 用于把一个有限地点中的人物、资源、压力和因果演化整理成可复用接口。

它解决的是局部模拟的组织方式，不负责文学文本，也不等于事件池。新地点应实现同一组接口，而不是复制湖湾镇脚本后继续硬编码。

## 2. 为什么不能全地图全 NPC 精细模拟

全地图逐日精细模拟会同时扩大状态量、因果检查、调试成本和历史审计成本。当前阶段只对与局部故事有关的地点、NPC 和压力字段进行细粒度推进，其余世界仍由宏观模拟负责。

模块边界让局部精度可以按需增加，也让每个地点能独立进行多 seed 回归。

## 3. 模块边界

一个模块可以：

- 初始化局部状态和偏置。
- 推进已有状态中的局部因果。
- 生成 `WorldFact`、`Trace`、`Memory` 和 `NarratableState`。
- 根据可叙述状态生成 `ActionCandidate`。
- 解析外部行为并写回状态。
- 输出 `HistorySignature` 和 `QualityAudit`。

一个模块不可以：

- 充当剧情事件池。
- 直接写死剧情结局。
- 让模块 ID 或 profile ID 决定结果。
- 绕过世界状态直接向 UI 写事实。
- 负责正式 UI 或文学表达。

## 4. RegionSimProfile

`RegionSimProfile` 描述一次局部模拟的初始条件：

```gdscript
{
    "profile_id": String,
    "seed": int,
    "region_id": String,
    "module_id": String,
    "macro_pressure": Dictionary,
    "resources": Dictionary,
    "social_roles": Dictionary,
    "npc_bias": Dictionary,
    "location_bias": Dictionary,
    "external_pressure": Dictionary,
    "quality_targets": Dictionary
}
```

profile 可以包装旧 profile，供渐进迁移使用。它不能创建 `WorldFact`，也不能包含 `outcome_class`。seed 只产生初始条件差异，事实必须由后续状态变化和规则共同产生。

## 5. LocalStoryModule 接口

模块至少实现：

```gdscript
func get_module_id() -> String
func get_module_version() -> String
func get_region_id() -> String
func get_location_ids() -> Array
func get_required_state_keys() -> Array
func initialize_module_state(state: Variant, profile: Dictionary = {}) -> void
func tick_module(state: Variant) -> Array
func build_narratable_states(state: Variant) -> Array
func build_action_candidates(
    state: Variant,
    actor_state: Dictionary,
    narratable_state_id: String
) -> Array
func resolve_action(
    state: Variant,
    actor_state: Dictionary,
    action_id: String,
    narratable_state_id: String
) -> Dictionary
func build_history_signature(state: Variant) -> Dictionary
func audit_quality(
    state: Variant,
    signature: Dictionary = {}
) -> Dictionary
func describe_module() -> Dictionary
```

接口是普通 GDScript 约定。现有系统可以通过 wrapper 接入，不要求立即改造为继承体系。

## 6. LocalStoryPipeline

`LocalStoryPipeline` 只负责标准调用顺序：

1. 可选地用 profile 初始化模块状态。
2. 每日调用一次 `module.tick_module(state)`。
3. 比较 tick 前后的集合，记录新事实、痕迹、记忆和可叙述状态 ID。
4. 调用模块质量审计，返回当日 `quality_flags`。
5. 批量结束后生成历史签名、审计结果、复现性和汇总统计。

管线不得包含地点名、NPC 名或湖湾镇专用分支。

## 7. WorldFact / Trace / Memory / NarratableState 约束

- `WorldFact` 必须来自状态条件和规则触发。
- 后续事实应保留 `cause_fact_ids`。
- `Trace` 必须指向来源事实。
- `Memory` 必须指向来源事实，并有明确持有者。
- `NarratableState` 只能投影已存在的世界状态，不得反向创造前置事实。
- UI 只消费投影结果，不决定事实是否发生。

## 8. ActionCandidate 约束

候选行为必须来自一个尚未锁定的 `NarratableState`，并保留来源事实、来源痕迹、可见条件、需求和风险。候选行为不是事实，只有 `resolve_action()` 成功后才能写回状态。

## 9. HistorySignature 约束

历史签名用于多 seed 比较和复现检查。它应由已发生事实、发生日、最终状态、痕迹、记忆和分支闭合信息构成。

签名分类是对事实组合的总结，不能反过来控制模拟。

## 10. QualityAudit 约束

`HistoryQualityAudit` 是统一审计结果契约，至少稳定提供：

```gdscript
{
    "quality_flags": Array,
    "dangling_major_fact": bool,
    "impossible_shop_state": bool,
    "unresolved_extreme_hunger": bool,
    "contradiction_flags": Array,
    "notes": Array
}
```

具体模块可以增加字段，但通用管线只依赖稳定字段。

## 11. 湖湾镇模块示例

`lake_town_food_crisis_module` 是第一个模块样板。它没有重写湖湾镇逻辑，而是包装：

- `lake_town_food_chain`
- `lake_town_reaction_system`
- `lake_town_recovery_system`
- `lake_town_branch_closure_system`
- `lake_town_hunger_closure_system`
- `micro_action_resolver`
- `lake_town_history_variation_runner`
- `lake_town_history_quality_auditor`

每日推进继续委托 `WorldSimulator.advance_one_day()`，因此原有宏观模拟、湖湾镇五段 tick 和投影顺序保持不变。

## 12. 第二地点实现时必须遵守的规则

- 新建独立模块 ID、region ID、地点列表和 profile。
- 使用相同接口和通用管线。
- 只读取自己声明的局部状态，跨模块影响通过世界事实或共享宏观状态传递。
- 增加固定 seed、批量 seed、行为解析和质量审计测试。
- 不复制湖湾镇 NPC 名、事实类型或结局分类作为模板内容。
- 在接 UI 前先完成无头回归。

## 13. 禁止事项

- 禁止把局部故事模块做成事件池接口。
- 禁止让 seed 直接决定事实或结局。
- 禁止让 UI 直接创建世界事实。
- 禁止用模块 ID、profile ID 或地点 ID 选择剧情结局。
- 禁止为了抽象而重写已稳定的局部系统。
- 禁止在没有质量审计和复现测试的情况下接入第二地点。

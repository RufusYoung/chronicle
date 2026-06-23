# 2026-06-23 Snapshot Transaction Resolver + Effect Template Prototype 报告

## 1. 本次目标

本次目标是把事务解析从“主要读取初始 `SimContext`”推进为“读取当前 `SimSnapshot`”，并新增最小 effect template 机制。

本次目标不是给某条行动硬写结果，而是建立：

```text
Effect Atom
↓
Effect Template
↓
TransactionResolver
↓
TransactionResult
↓
TransactionWorldWriter
↓
Stores
```

本次未接 UI。
本次未实现完整世界 Tick。
本次未实现完整传闻传播。
本次未实现 AI 文本。
本次未实现湖湾镇完整闭环。
本次未实现第七哨站长期项目。
本次未把世界对象做成 Godot Node。
本次未把世界状态写入 Godot 场景树。

## 2. Raw Effect Templates

新增：

```text
chronicle-godot/data/sim/raw/effect_templates/basic_effect_templates.json
```

当前包含六个模板：

```text
give_food_help_effect
inquiry_concealed_item_effect
discipline_report_effect
discipline_conceal_effect
read_object_effect
inspect_trace_effect
```

每个模板由 effect atoms 组成：

```text
facts
state_changes
relationship_changes
memories
traces
rumors
narrative
```

模板中允许使用变量：

```text
{actor_id}
{target_id}
{target_display_name}
{location_id}
{rule_id}
{action_id}
{fixture_id}
{superior_id}
{superior_display_name}
```

模板不写地点特判，也不写人物特判。

## 3. EffectTemplateResolver

新增：

```text
chronicle-godot/scripts/sim/transaction/effect_template_resolver.gd
```

核心接口：

```text
load_effect_templates(path)
get_template(template_id)
resolve_template(template_id, candidate, snapshot)
```

`EffectTemplateResolver` 负责：

```text
1. 加载 raw effect template JSON。
2. 从 ActionCandidate + SimSnapshot 绑定变量。
3. 将模板里的 facts / state_changes / relationships / memories / traces / rumors / narrative 解析为 TransactionResult。
```

其中：

```text
superior_id
```

不是通过 `recruit_elai` 或 `outpost_kitchen` 特判获得，而是通过 snapshot 中可见实体 tags 查找 `captain` / `superior`。

`operation: decrease_tier` 会被 resolver 转成 StateStore 能处理的 `degrade` 写回。

## 4. TransactionResolver Snapshot 输入

修改：

```text
chronicle-godot/scripts/sim/transaction/transaction_resolver.gd
```

`resolve_action(candidate, context_or_snapshot)` 现在可以接受：

```text
SimContext
SimSnapshot
```

当前 rule 到 template 的映射：

```text
give_food_to_hungry_person -> give_food_help_effect
ask_about_concealed_item -> inquiry_concealed_item_effect
report_discipline_violation_to_superior -> discipline_report_effect
conceal_discipline_violation_once -> discipline_conceal_effect
read_visible_readable_object -> read_object_effect
inspect_visible_trace -> inspect_trace_effect
```

旧测试继续使用 `SimContext` 也能通过。
新流程中 `SimRunner` 已经把 step snapshot 传给 `TransactionResolver`。

## 5. ask_about_concealed_item 通用事务模板

`ask_about_concealed_item` 现在不再是空事务。

它通过：

```text
inquiry_concealed_item_effect
```

生成：

```text
Fact:
actor_asked_about_concealed_item

Relationship:
target -> actor fear +5

Memory:
target being_questioned_about_hidden_item

Narrative:
对方意识到你注意到了他藏着的东西。
```

这不是伊莱专属逻辑。
这不是第七哨站专属逻辑。
这不是地点按钮表。

任何符合 `ask_about_concealed_item` 行动规则的可见人物，都可以使用这套 `inquiry_concealed_item_effect` 模板。

本模板不生成 rumor seed。询问隐藏物本身不一定会传播。

## 6. SimRunner 改造

修改：

```text
chronicle-godot/scripts/sim/core/sim_runner.gd
```

现在每一步执行使用同一个 step snapshot：

```text
step_snapshot = SimSnapshotBuilder.build_snapshot(context, stores)
candidates = ActionAffordanceSystem.generate_candidates(step_snapshot, rules)
candidate = select candidate
result = TransactionResolver.resolve_action(candidate, step_snapshot)
TransactionWorldWriter.apply_result(result, stores)
```

WorldLog entry 新增：

```text
resolver_context_source: SimSnapshot
```

用于确认事务解析已经读取 snapshot，而不是只读取初始 context。

## 7. 测试结果

新增测试：

```text
chronicle-godot/tests/sim/snapshot_transaction_effect_template_test.gd
```

测试结果：

```text
[V5 SNAPSHOT TRANSACTION EFFECT TEMPLATE RESULT] PASS
```

覆盖内容：

```text
1. 能加载 basic_effect_templates.json。
2. EffectTemplateResolver 能解析 inquiry_concealed_item_effect。
3. TransactionResolver 能接受 SimSnapshot。
4. ask_about_concealed_item 基于 snapshot 产生 actor_asked_about_concealed_item。
5. ask_about_concealed_item 产生 being_questioned_about_hidden_item memory。
6. ask_about_concealed_item 产生 target -> player fear +5。
7. give_food_to_hungry_person 基于 snapshot 仍产生 hunger 降级。
8. report_discipline_violation_to_superior 基于 snapshot 仍产生 trace / rumor / narrative。
9. SimRunner 执行 conceal sequence 时，第一步不再是无事务写回。
10. SimRunner WorldLog 中 conceal sequence 第一步包含 actor_asked_about_concealed_item。
11. WorldLog entry 的 resolver_context_source 为 SimSnapshot。
```

同时回归通过：

```text
[V5 RAW RULE PROTOTYPE RESULT] PASS
[V5 TRANSACTION STATE MEMORY RESULT] PASS
[V5 RELATIONSHIP TRACE RUMOR NARRATIVE RESULT] PASS
[V5 SIM RUNNER WORLD LOG RESULT] PASS
[V5 SIM SNAPSHOT CANDIDATE CONTEXT RESULT] PASS
```

## 8. Sim Core 独立规则执行情况

本次仍保持 Sim Core 独立：

```text
effect template 是 raw 数据。
EffectTemplateResolver 只生成 TransactionResult。
TransactionWorldWriter 仍负责写 Stores。
SimRunner 使用 SimSnapshot 作为当前世界读取视图。
Godot 场景树不拥有世界状态。
```

本次没有接 UI。
本次没有让 UI 控件保存世界状态。
本次没有让 `_process()` 驱动世界推进。
本次没有让按钮直接修改实体状态。
本次没有把 fixture entities 实例化成 Godot Node。
本次没有让 Narrative 文本反向决定事实。

## 9. 未修改保护文件确认

本次未修改：

```text
chronicle-godot/scenes/ui/story_player.gd
chronicle-godot/scripts/gen/world_generation_v03.gd
chronicle-godot/scenes/ui/mainui.tscn
chronicle-godot/project.godot
chronicle-godot/素材包/
```

本次也未修改：

```text
chronicle-godot/scripts/rebuild/
chronicle-godot/scenes/rebuild/
chronicle-godot/data/rebuild/
```

## 10. 未完成内容

本次未完成：

```text
未接 UI。
未实现完整世界 Tick。
未实现完整传闻传播。
未实现 AI 文本。
未实现湖湾镇完整闭环。
未实现第七哨站长期项目。
未把世界对象做成 Godot Node。
未把世界状态写入 Godot 场景树。
```

技术上仍未完成：

```text
effect template DSL 仍然很小，只覆盖当前事务 atoms。
rule -> effect template 的映射仍在 TransactionResolver 中。
operation 目前只实现了 decrease_tier。
没有实现条件 effect、概率 effect、分支 effect。
没有实现完整物品系统，actor.food_count 仍是 StateStore 数值变化。
Narrative 仍是确定性模板文本，不是 AI 文本。
```

## 11. 下一步建议

下一步建议：

1. 把 rule -> effect template 映射逐步移入 raw rule，减少 resolver 内部映射表。
2. 为 effect template 增加 `conditions`，例如只有 witnessed 才生成 rumor seed。
3. 扩展 state operation，例如 `increase_tier`、`set_value`、`clamp_delta`。
4. 让 item / inventory 系统接管 `food_count`，不要长期把它挂在 player state 上。
5. 继续保持 UI 只读取 Sim Core 输出，不让 UI 持有世界状态。

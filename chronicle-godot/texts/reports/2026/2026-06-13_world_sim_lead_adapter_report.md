# world_sim 线索适配层报告

## 1. 本次目标

建立一个独立表现层适配器，将 world_sim 已经生成的 `LeadCandidate` 转换为 v0.3 可识别的线索字典。

本任务不生成新的世界事实，不生成新的 `LeadCandidate`，不扩写事件池，不接 UI，也不修改当前 Demo 运行逻辑。

## 2. 新增文件

- `scripts/sim/world_sim_lead_adapter.gd`
- `tests/world_sim_lead_adapter_test.gd`
- `texts/reports/2026/2026-06-13_world_sim_lead_adapter_report.md`

同时更新：

- `tests/README.md`
- `texts/README.md`
- `PROJECT_STRUCTURE.md`

未修改的保护文件：

- `scenes/ui/story_player.gd`
- `scripts/gen/world_generation_v03.gd`
- `project.godot`
- `素材包/`

## 3. 适配层接口

适配器提供：

```gdscript
adapt_lead_candidate(candidate: Dictionary) -> Dictionary
adapt_lead_candidates(candidates: Array) -> Array
map_lead_type(type_id: String) -> String
map_direction(candidate: Dictionary) -> String
map_stage(candidate: Dictionary) -> int
map_freshness(candidate: Dictionary) -> float
map_risk(candidate: Dictionary) -> float
map_title(candidate: Dictionary) -> String
map_source(candidate: Dictionary) -> String
map_action_hints(candidate: Dictionary) -> Array
```

输出同时包含规范字段和 v0.3 兼容字段。

规范字段使用中文四类线索和 0–1 数值。兼容字段包括：

- `lead_id`
- `lead_type`
- `target_dir_or_place`
- `freshness_percent`
- `risk_hint`

当前 v0.3 内部使用英文 `lead_type` 和 0–100 新鲜度。后续真正接入时，应把 `freshness_percent` 写入 v0.3 运行对象的 `freshness` 字段；本阶段不修改现有运行逻辑。

## 4. 类型映射规则

直接映射：

| world_sim | 规范类型 | v0.3 `lead_type` |
| --- | --- | --- |
| `smoke` | 烟柱 | `smoke` |
| `tracks` | 足迹 | `footprint` |
| `rumor` | 传闻 | `rumor` |
| `river` | 河流 | `river` |

间接映射：

| world_sim | 规范类型 | v0.3 `lead_type` |
| --- | --- | --- |
| `apparition` | 传闻 | `rumor` |
| `checkpoint` | 足迹 | `footprint` |
| `caravan` | 烟柱 | `smoke` |

没有新增 UI 类型。

## 5. 数值映射规则

`freshness` 和 `risk` 在适配结果中统一为 0–1：

- 原值在 0–1 时直接限制范围。
- 原值大于 1 时按百分制除以 100。
- 缺失 `freshness` 时使用 0.8。
- 缺失 `risk` 时使用 0.5。

阶段映射：

- `urgency < 0.35`：stage 1
- `0.35 <= urgency < 0.7`：stage 2
- `urgency >= 0.7`：stage 3

没有 `urgency` 时，根据风险和新鲜度推断。

方向优先读取候选已有字段，否则按地区稳定映射：

- `mirror_lake_forest`：西北
- `border_town`：东南
- `old_ruins`：北方

## 6. 行动提示映射规则

适配器将 world_sim 行动 ID 转换为短中文行动提示，例如：

- `investigate`：调查
- `protect`：护送
- `observe`：观察
- `interrupt`：打断
- `hunt`：狩猎
- `set_trap`：设陷
- `warn_travelers`：警告旅人

当前 world_sim 使用的其他行动也已覆盖。未知行动会记录 warning，并回退为“谨慎查看”，不会导致适配中断。

## 7. world_cause 与 related_fact_id 保留方式

适配结果直接复制：

```text
world_cause
related_fact_id
source_region_id
source_faction_id
origin = world_sim
```

如果输入缺少 `world_cause` 或 `related_fact_id`，单条适配失败并返回空字典，不会为它补造因果。

测试还会比较适配前后的 `world_facts` 和 `lead_candidates` 数量，确认适配器没有生成任何世界事实或候选线索。

## 8. 测试结果

测试环境：

- 固定种子：`20260613`
- Godot：4.6.3 stable
- 模拟长度：30 天
- 执行方式：无 UI

基线结果：

- 适配前 `LeadCandidate`：40
- 适配后 v0.3 线索字典：40
- 传闻：15
- 河流：3
- 烟柱：13
- 足迹：9

测试通过：

- 必需字段完整
- 类型只属于 v0.3 四类线索
- 新鲜度和风险范围合法
- 每条线索至少一个行动提示
- 所有线索保留 `world_cause`
- 所有线索保留 `related_fact_id`
- 同 seed 结果可复现
- 适配过程不增加世界事实
- 适配过程不增加候选线索

最终输出：

```text
[WORLD SIM LEAD ADAPTER RESULT] PASS
```

## 9. 无玩家干预适配样例

以下样例来自无干预 A 组。

1. 烟柱：远处商队烟迹，东南。原因 `scarcity_high_and_smuggler_raid`，行动为调查、护送、劫掠、放任。
2. 传闻：关于旧遗迹异象的传闻，北方。原因 `cult_ritual_and_mystic_pressure`，行动为观察、打断、跟随、报告。
3. 足迹：道旁新设的盘查痕迹，东南。原因 `warden_security_response`，行动为配合盘查、询问、绕过关卡、举报走私。
4. 足迹：林中迁徙足迹，西北。原因 `beast_migration`，行动为狩猎、跟随、设陷、警告旅人。
5. 传闻：镇上的低声传闻，东南。原因 `smuggler_information_market`，行动为核实、购买情报、散播消息、报告。

每条样例都保留对应的世界事实 ID。

## 10. 第 3 天测试注入后的适配差异

B 组在第 3 天执行测试注入：

```gdscript
help_faction(state, "wardens", "border_town")
```

30 天后：

- 无干预 A 组适配线索：40
- 测试注入 B 组适配线索：39
- 两组适配线索签名不同
- A 组商队烟柱类线索比 B 组多 1 条

签名包含线索 ID、类型、方向、世界原因、关联事实和新鲜度。差异来自 world_sim 后续状态变化，适配器本身没有改变世界。

## 11. 当前局限

- 当前输入接口使用 `Dictionary`，测试负责把 `LeadCandidate` 对象展开为字典。
- 地区方向是临时稳定映射，不代表正式地图坐标。
- 标题与描述是短模板，只覆盖当前七类 world_sim 线索及其原因。
- 适配结果尚未注入 v0.3 的 `leads` 数组。
- 当前没有处理适配线索完成后的 `resolve_lead()` 回写桥接。

## 12. 下一步建议

下一阶段可以新增独立桥接器和无头集成测试：

1. 将适配结果复制到一个隔离的 v0.3 世界对象实例。
2. 把 `freshness_percent` 转换为 v0.3 的 0–100 `freshness`。
3. 验证 v0.3 推荐行动能够读取四类线索。
4. 处理线索完成后，把 `related_fact_id` 和结果提交给 `resolve_lead()`。
5. 集成测试稳定前，继续保持 `story_player.gd` 和 UI 不变。

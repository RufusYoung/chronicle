# 2026-07-20 World Time Surface 报告

## 1. 本次目标

完成 Chronicle 纵向切片第 3 个里程碑：

> 玩家不直接选择世界结果，只推进时间；世界根据已经存在的状态、延迟后果和 Tick 规则自行结算，并把变化重新投影到地点现场。

本次使用一次可控的“等待一小时”验证该链路。

这不是后台实时运行，也不是完整日程系统。

## 2. SimSession 时间接口

`V5SimSession` 新增：

```text
advance_time(hours, trigger_key, metadata)
advance_world(tick_event, elapsed_hours_delta)
get_time_summary()
```

Session 现在持续持有：

- 当前天数。
- 当前小时。
- 从局面启动后经过的小时数。
- 已执行的世界 Tick 数。
- 与玩家行动共享的持续 WorldLog。

时间推进链路：

```text
SimSession.advance_time()
↓
合法 TickEvent
↓
WorldTickAdapter
↓
ConsequenceTriggerSystem / DueTriggerSystem
↓
TransactionWorldWriter
↓
原有 Stores
↓
Session WorldLog
↓
新 Snapshot 与行动候选
```

非法 Tick 不推进时钟。

玩家行动数 `action_count` 与世界 Tick 数 `world_tick_count` 分开记录。

## 3. Fixture 初始延迟后果

`lake_town_food_crisis_fixture.json` 新增：

- 初始时间：第 1 天 10:00。
- 隐藏现场实体：半掩的门板。
- 一条 `after_short_wait` 延迟后果。

该后果在 fixture 中明确声明：

```text
old_chen_shop_closes_after_wait
```

开始时：

- 门板不可见。
- 延迟后果状态为 `pending`。
- 老陈铺子的新增收铺压力为 0。

等待一小时后：

- 时钟从 10:00 前进到 11:00。
- 门板变为可见。
- 涨价告示状态变为再次改价。
- 老陈铺子新增粮食短缺压力。
- 写入“老陈铺子提前收门”事实。
- 延迟后果变为 `triggered`。
- 对应 Tick 进入持续 WorldLog。

第二次等待时，时钟继续前进到 12:00，但一次性后果不会重复触发。

## 4. 延迟后果模板

新增：

```text
lake_town_shop_closes_after_wait_effect
```

模板产生：

- 1 条结构化事实。
- 2 项可见状态变化。
- 1 项地点压力。
- 1 项延迟后果状态更新。
- 1 段基于这些变化的现场叙事。

`ConsequenceTriggerSystem` 现在会把延迟后果的自定义字段作为模板绑定传入。

因此不同 fixture 可以声明：

- 哪个现场实体发生变化。
- 哪个对象被影响。
- 使用哪个专属后果模板。

不需要在 TickAdapter 中为湖湾镇编写地点分支。

## 5. 地点界面

动态地点场景新增：

- 日期与小时显示。
- “等待一小时”按钮。
- 世界 Tick 反馈。
- 新增压力展示。
- 时间后果形成的玩家可读事实。
- 等待记录。

等待后，玩家在同一画面看到：

```text
第 1 天 10:00
↓
等待一小时
↓
第 1 天 11:00
↓
半掩的门板出现
涨价告示再次改高
铺子提前收门
粮食压力继续上升
```

界面没有直接设置门板、告示、压力或事实。

## 6. 玩家行动与世界变化的边界

“等待一小时”是玩家真实点击的时间操作。

但玩家没有选择：

- 老陈是否收铺。
- 告示是否再次涨价。
- 门板是否出现。
- 粮食压力增加多少。

这些结果来自 fixture 中已经存在的延迟后果，并经过 Tick、后果模板和 Store 写回。

这使“等待”不再是一段固定文案，也不是 UI 层伪造的事件。

## 7. 新增测试

新增：

```text
chronicle-godot/tests/sim/live_world_time_session_test.gd
chronicle-godot/tests/rebuild/v5_world_time_surface_test.gd
```

核心测试覆盖 14 项：

- 从 fixture 载入时间。
- 从 fixture 载入初始延迟后果。
- Tick 前隐藏现场细节。
- `advance_time()` 通过 WorldTickAdapter。
- Session 时钟推进。
- 可见实体和告示状态变化。
- 压力与事实写回。
- Tick 合并进持续 WorldLog。
- 一次性后果不重复触发。
- 非法 Tick 不推进时钟。
- 行动与 Tick 分开统计。
- SimRunner 保持兼容。
- 重载局面重置时钟与后果。

界面测试覆盖 10 项：

- 初始时钟与隐藏状态。
- 等待按钮和普通行动同时存在。
- 点击后时钟、现场与压力刷新。
- 玩家看到世界变化叙事。
- 事实进入认知栏。
- 等待进入历史。
- 核心区分玩家行动和世界 Tick。
- 新快照继续生成普通行动。
- 重复等待不复制后果。
- 重载恢复初始局面。

## 8. 回归结果

Godot 版本：

```text
4.5.1.stable
```

以下验证通过：

- 18 个 `tests/sim` 测试脚本。
- 2 个动态地点界面测试脚本。
- 项目级无界面编辑器载入。
- 1280×720 Vulkan 实际渲染。

新增结果：

```text
[V5 LIVE WORLD TIME SESSION RESULT] PASS
[V5 WORLD TIME SURFACE RESULT] PASS
```

全部既有 v5 模拟测试继续通过。

## 9. 边界确认

本次：

- 未修改 `project.godot`。
- 未替换正式主场景。
- 未让 UI 直接修改世界 Store。
- 未加入随机事件池。
- 未加入后台实时线程。
- 未实现 NPC 完整日程。
- 未实现多地点同时 Tick。
- 未实现旅行。
- 未实现昼夜画面变化。
- 未接入生成式 AI。

## 10. 创作方向验收

本次第一次在玩家画面证明：

- 时间是世界状态的一部分。
- 延迟后果可以跨越玩家行动边界。
- 玩家只推进时间，不直接指定结果。
- 世界变化会留下现场细节、压力、事实和日志。
- 一次性后果不会因为重复等待而反复生成。

这仍然只是短时间和单地点验证。

它尚未证明：

- 玩家离开后地点继续变化。
- 多个地点按不同粒度推进。
- 旅行消耗时间与资源。
- 玩家返回旧地时能看到长期变化。
- 多年尺度上的成长、老去、重逢和缺席。

## 11. 下一步

下一里程碑进入多地点与旅行：

```text
老陈铺子
↓
选择目的地
↓
旅行时间与资源消耗
↓
沿途 Tick
↓
到达新地点
↓
旧地点保留已经发生的变化
```

第一版应只连接两个地点，并确保离开老陈铺子再返回时，门板、告示、压力和事实仍然存在。

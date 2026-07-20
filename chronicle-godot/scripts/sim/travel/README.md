# Travel System

## 职责

Travel 把已经存在的地点连接成需要时间和资源的实际旅程。

路线不是静态地图按钮。它可以依据玩家已经确认的事实决定是否出现，并依据当前
时间与资源决定此刻是否能够出发。

## 当前契约

基础字段：

- `route_id`
- `from_location_id`
- `to_location_id`
- `hours`
- `food_cost`
- `trigger_key`
- `time_key`
- `narrative_title`
- `narrative`

可选的发现条件：

- `required_fact_type`
- `required_fact_target_id`

条件不满足时，路线完全隐藏，避免界面提前泄露未知地点。`SimSession.travel()`
会再次验证这些条件，因此直接调用 route ID 也不能绕过世界事实。

可选的出发时间窗：

- `available_hour_start`
- `available_hour_end`
- `access_hint`

时间窗采用起点包含、终点不包含的小时范围。例如 `6` 到 `18` 表示
`06:00 <= 当前小时 < 18:00`。跨越午夜的范围也受支持。

时间窗不满足时，路线仍可显示，但状态为不可出发，让玩家知道地点已经发现、
只是当前时机不对。执行时会再次复核，不会消耗时间或写入日志。

## 北埠旧档房

北埠路线要求玩家先确认：

```text
actor_found_public_granary_archive_reference
target = old_chen_public_granary_tax_deed
```

满足后，老陈铺子会出现前往北埠旧档房的摆渡路线。摆渡只在 06:00 至 18:00
开船，耗时 2 小时，不消耗食物。零食物成本是当前纵向切片的明确内容约束，
不是系统自动补给；此前往返废弃粮仓已经耗尽玩家携带的两份食物。

返程路线没有白天限制，避免玩家被锁死在档房。

## 边界

Travel 不负责：

- 创造路线所需的事实。
- 把未知地点直接加入玩家地图。
- 自动购买或补充资源。
- 结算地点内部的调查与危险。
- 把时间窗当成动态天气或潮汐模拟。

路线成功后仍通过 `TravelResolver` 产生旅行事实、资源变化和叙事，再由统一事务
写回。世界 Tick 在旅途中继续推进。

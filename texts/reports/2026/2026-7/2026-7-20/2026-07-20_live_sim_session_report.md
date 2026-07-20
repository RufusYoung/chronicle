# 2026-07-20 Live SimSession 报告

## 1. 本次目标

把原本只能执行预写测试序列的 v5 模拟核心，整理为能够被未来 UI 持续驱动的运行会话。

本次不接 UI，不实现旅行、时间推进、判定、物品或纪事系统。

## 2. 新增 SimSession

新增：

```text
chronicle-godot/scripts/sim/core/sim_session.gd
```

`V5SimSession` 持续持有：

- SimContext
- Raw Action Rules
- 全部现有 Stores
- SimWorldLog
- SimSnapshotBuilder
- ActionAffordanceSystem
- TransactionResolver
- TransactionWorldWriter

主要接口：

```text
start_from_fixture_path()
start_from_fixture_data()
get_snapshot()
get_action_candidates()
get_action_options()
execute_action()
execute_selection()
get_world_log_entries()
get_store_summary()
get_store_snapshots()
build_result_summary()
```

## 3. 玩家行动链路

```text
UI 可读 Action Option
↓
action_id
↓
重新构建 SimSnapshot
↓
重新生成当前候选
↓
确认 action_id 仍然有效
↓
TransactionResolver
↓
TransactionWorldWriter
↓
同一批 Stores
↓
WorldLog
↓
下一次 Snapshot 与候选
```

已经失效的候选返回：

```text
success = false
error = candidate_not_found
```

失效候选不执行事务，也不写入 WorldLog。

## 4. SimRunner 调整

`V5SimRunner` 现在作为测试场景适配器复用 `V5SimSession`。

原有 fixture + scenario 测试入口保持不变，但 Runner 不再自行创建和管理另一套 Context、Stores、Snapshot 与 WorldLog 生命周期。

为了兼容两项直接调用旧私有日志函数的历史测试，Runner 保留 `_build_world_log_entry()` 薄代理，实际构造逻辑仍由 SimSession 提供。

## 5. 新增测试

新增：

```text
chronicle-godot/tests/sim/live_sim_session_test.gd
```

覆盖：

- 从 fixture 启动持久 Session。
- 输出 UI 可读行动字典。
- 按 action_id 执行玩家行动。
- 连续行动写回同一批 Store。
- 状态变化后刷新行动候选。
- 拒绝已经失效的 action_id。
- candidate_only 行动可以被合法记录。
- 新快照读取事实、记忆与关系。
- WorldLog 持续记录行动。
- Store 保持纯数据对象，不进入 Godot 场景树。
- 原 SimRunner 通过同一 SimSession 保持兼容。

测试结果：

```text
[V5 LIVE SIM SESSION RESULT] PASS
```

## 6. 回归结果

以下测试通过：

```text
[V5 SIM RUNNER WORLD LOG RESULT] PASS
[V5 SIM SNAPSHOT CANDIDATE CONTEXT RESULT] PASS
[V5 RAW RULE PROTOTYPE RESULT] PASS
[V5 TRANSACTION STATE MEMORY RESULT] PASS
[V5 RELATIONSHIP TRACE RUMOR NARRATIVE RESULT] PASS
[V5 SNAPSHOT TRANSACTION EFFECT TEMPLATE RESULT] PASS
[V5 RAW RULE EFFECT BINDING RESULT] PASS
[V5 TRANSACTION CONTRACT CLEANUP RESULT] PASS
[V5 CANDIDATE EFFECT TEMPLATE BATCH1 RESULT] PASS
[V5 DOMAIN PRESSURE DEFERRED FOUNDATION RESULT] PASS
[V5 CONSEQUENCE TRIGGER SETTLEMENT RESULT] PASS
[V5 MINI WORLD TICK ADAPTER RESULT] PASS
[V5 TICK EVENT SCHEMA SCOPED RESULT] PASS
[V5 OBLIGATION EXCHANGE DUE TRIGGER RESULT] PASS
[V5 DUE RESOLUTION POLICY RESULT] PASS
[V5 SIM ARCHITECTURE SKELETON RESULT] PASS
```

## 7. 边界确认

本次：

- 未修改 `project.godot`。
- 未修改正式主场景。
- 未修改旧 `story_player.gd`。
- 未接入 `world_generation_v03.gd`。
- 未把 Store 或世界实体做成 Godot Node。
- 未实现完整世界 Tick。
- 未实现旅行、战斗、物品和纪事。
- 未接入 AI 文本。

## 8. 下一步

下一步应建立 `SimSession -> 地点局面 ViewModel -> v5 UI` 的最小连接。

第一版只展示：

- 当前地点与可见人物。
- 当前痕迹与地区压力。
- `get_action_options()` 返回的行动按钮。
- `execute_action()` 返回的即时叙事和状态变化。

这一步完成后，玩家将第一次通过真实 UI 驱动 v5 模拟核心。

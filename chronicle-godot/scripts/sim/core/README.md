# Core System

## 职责

提供世界模拟层的基础上下文、注册表、持久运行会话和共享入口。

## 管理的数据

模拟上下文、世界标识、当前行动者、当前地点、Raw 定义索引、系统注册信息、Store 生命周期和世界日志。

## 输入

Raw 定义、fixture 数据、正式世界实例和测试构造数据。

## 输出

可传递给各系统的上下文对象、定义查询入口、当前快照、行动候选、行动执行结果和运行摘要。

## SimSession

`sim_session.gd` 是前台游戏、无头测试和未来存档系统共用的持久运行入口。

核心链路：

```text
fixture + raw rules
↓
SimSession 持有 Context / Stores / WorldLog
↓
SimSnapshotBuilder 构建当前快照
↓
ActionAffordanceSystem 生成当前候选
↓
玩家按 action_id 选择行动
↓
TransactionResolver 结算
↓
TransactionWorldWriter 写回同一批 Stores
↓
刷新 Snapshot 与候选
```

`SimSession` 每次执行前都会重新生成候选。已经因状态变化而失效的旧按钮不能继续写回世界。

`SimRunner` 现在是脚本场景测试适配器，内部复用 `SimSession`，不再维护第二套模拟生命周期。

## 不负责什么

Core 不定义具体地点内容，不绘制 UI，不实现旅行、战斗或纪事文本。

## 与其他系统的关系

其他系统可以读取 Core 提供的上下文、快照和注册表，但具体规则应保留在各自系统中。

## 当前状态

已完成最小持久 `SimSession`：

- 可以从 fixture 启动一个运行中的世界切片。
- 可以持续列出当前行动候选。
- 可以按 `action_id` 或 `rule_id + target_id` 执行行动。
- 可以把事实、状态、关系、记忆、痕迹、传闻和后果持续写入同一批 Store。
- 可以拒绝已失效候选。
- 可以输出 WorldLog、Store snapshot 和运行摘要。
- 可以导出包含 Store 真值、世界时间、运行游标和 Definition manifest 的 SaveEnvelope seed。

当前 rebuild UI、旅行和世界时间已接入 SimSession。SaveEnvelope seed 只用于确认序列化边界与 JSON 往返，还没有正式保存、载入、迁移、RNG 恢复和候选一致性恢复。

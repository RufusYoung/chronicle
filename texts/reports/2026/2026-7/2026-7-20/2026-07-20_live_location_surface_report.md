# 2026-07-20 Live Location Surface 报告

## 1. 本次目标

把上一阶段的持久 `SimSession` 接到一个玩家能够实际操作的 Godot 地点局面。

本次只验证：

- 玩家能看见当前世界快照。
- 玩家能点击由世界状态生成的行动。
- 行动能经过真实事务链写回同一个世界。
- 玩家能在现场看到叙事、状态、关系、事实和后续选项的变化。

本次不替换正式入口，不实现旅行、时间推进、战斗、物品或完整纪事。

## 2. 新增动态地点界面

新增独立场景：

```text
chronicle-godot/scenes/rebuild/v5_live_location_viewer.tscn
```

场景包含：

- 当前地点与现场描述。
- 玩家身份、食物和感知。
- 地区与机构压力。
- 当前可见人物、物件和痕迹。
- 已确认事实。
- 最近行动历史。
- 事务结算后的即时反馈。
- 由当前行动候选动态生成的按钮。

场景使用独立暗色文字冒险布局，没有修改 `project.godot` 或正式主场景。

## 3. ViewModel 投影层

新增：

```text
chronicle-godot/scripts/rebuild/v5_live_location_view_model.gd
```

该层只负责把结构化模拟数据翻译为玩家可读信息：

```text
SimSession
↓
SimSnapshot
↓
地点 / 人物 / 物件 / 压力 / 认知
↓
玩家可读 ViewData
↓
Godot Control
```

玩家点击按钮时：

```text
action_id
↓
SimSession.execute_action()
↓
TransactionResolver
↓
TransactionWorldWriter
↓
原有 Stores 与 WorldLog
↓
重新生成 Snapshot 与行动候选
↓
刷新地点局面
```

UI 不直接修改人物饥饿、玩家食物、关系或事实。

## 4. 湖湾镇现场内容

在原有 `lake_town_food_crisis_fixture.json` 中补充了纯展示描述：

- 老陈铺子的气味、存粮和门外议论。
- 陈米的外观与不安。
- 发霉麦子袋。
- 涨价告示。
- 灰白粮粉。

这些文字不创建新的世界事实，只表现 fixture 已有地点、实体、可见性和状态。

## 5. 已完成的玩家闭环

初始局面中，玩家可以看见：

- 陈米处于严重饥饿状态。
- 玩家携带 2 份食物。
- 涨价告示可以阅读。
- 灰白粮粉可以检查。
- 湖湾镇承受较高粮食压力。

点击“给陈米食物”后：

- 玩家食物从 2 变为 1。
- 陈米饥饿从 `high` 变为 `medium`。
- 陈米对玩家的感激、信任和畏惧发生变化。
- 事实与记忆写入原有 Store。
- 结算叙事出现在现场反馈区。
- “给陈米食物”不再满足候选条件，因此按钮消失。

重复调用已经失效的行动时：

- 返回 `candidate_not_found`。
- UI 显示“局面已经变化”。
- 不写入新的 WorldLog。

阅读告示和检查粮粉后，对应事实会进入玩家可读的“已经确认的事”，不会显示内部 `fact_type`、`effect_template_id` 或候选调试信息。

## 6. 新增测试

新增：

```text
chronicle-godot/tests/rebuild/v5_live_location_viewer_test.gd
```

覆盖 13 项：

- 独立场景加载。
- fixture 数据投影。
- 可见人物、物件和痕迹。
- 地区压力翻译。
- 动态行动按钮。
- 按钮到 SimSession 的真实连接。
- 状态与关系即时反馈。
- 过期按钮消失。
- 过期 action_id 拒绝执行。
- 连续调查形成玩家认知。
- 连续行动历史。
- 内部模拟标识不泄漏到 UI。
- 重新载入初始局面。

测试结果：

```text
[V5 LIVE LOCATION VIEWER RESULT] PASS
```

## 7. 回归结果

Godot 版本：

```text
4.5.1.stable
```

项目级无界面编辑器载入通过。

新增场景测试、`live_sim_session_test.gd` 与现有 16 项 v5 模拟测试全部通过，共验证 18 个测试脚本：

```text
[V5 LIVE LOCATION VIEWER RESULT] PASS
[V5 LIVE SIM SESSION RESULT] PASS
[V5 CANDIDATE EFFECT TEMPLATE BATCH1 RESULT] PASS
[V5 CONSEQUENCE TRIGGER SETTLEMENT RESULT] PASS
[V5 DOMAIN PRESSURE DEFERRED FOUNDATION RESULT] PASS
[V5 DUE RESOLUTION POLICY RESULT] PASS
[V5 MINI WORLD TICK ADAPTER RESULT] PASS
[V5 OBLIGATION EXCHANGE DUE TRIGGER RESULT] PASS
[V5 RAW RULE EFFECT BINDING RESULT] PASS
[V5 RAW RULE PROTOTYPE RESULT] PASS
[V5 RELATIONSHIP TRACE RUMOR NARRATIVE RESULT] PASS
[V5 SIM ARCHITECTURE SKELETON RESULT] PASS
[V5 SIM RUNNER WORLD LOG RESULT] PASS
[V5 SIM SNAPSHOT CANDIDATE CONTEXT RESULT] PASS
[V5 SNAPSHOT TRANSACTION EFFECT TEMPLATE RESULT] PASS
[V5 TICK EVENT SCHEMA SCOPED RESULT] PASS
[V5 TRANSACTION CONTRACT CLEANUP RESULT] PASS
[V5 TRANSACTION STATE MEMORY RESULT] PASS
```

## 8. 创作方向验收

本次第一次在实际游戏现场证明了：

- 世界状态能够产生玩家选项。
- 玩家行动能够改变持续世界。
- 改变会影响后续可用行动。
- 玩家可以通过界面理解结果，而不是阅读调试报告。
- 表现文字来自已确认的结构化状态和事务结果。

但本次还没有证明：

- 世界在玩家不参与时继续变化。
- 旅行具有风景、资源和风险。
- 未知地点具有独特规则。
- 时间推进会形成重逢、老去、错过或缺席。
- 一次经历能在多年后被关系、物品和纪事回收。

因此这不是完整纵向切片，只是第一个面向玩家的真实局面闭环。

## 9. 边界确认

本次：

- 未修改 `project.godot`。
- 未修改正式主场景。
- 未修改旧 `v5_location_foundation_viewer`。
- 未修改 SimSession、事务解析器或 Store。
- 未让 UI 直接决定世界事实。
- 未接入生成式 AI。
- 未把测试结果伪装成玩家输入。

## 10. 下一步

下一里程碑应让世界第一次在玩家不操作时发生变化：

```text
SimSession
↓
advance_world(tick_event)
↓
WorldTickAdapter
↓
到期义务 / 延迟后果 / 地区压力
↓
新 Snapshot
↓
地点局面出现可见变化
```

第一版只需增加一个可控的短时间推进，并让玩家离开或等待后重新看到老陈铺子的变化。这样可以开始验证《Chronicle》最关键的第二件事：世界不是只在玩家按按钮时才存在。

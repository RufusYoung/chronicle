# Chronicle 物品实例合同实施报告

日期：2026-08-13

分支：`exp/v5-item-instance-contract`

对应计划：阶段 5.5，步骤 2C

## 1. 本轮结果

本轮把物品从“剧情脚本附带的一段字典”升级为可校验、可追溯的世界实例：

- 6 个 ItemDef 进入严格 Registry，包括四件现有调查物、旅行口粮和蜡封冬斗篷。
- `ItemStore` 只保存 `item_instance_id`、`item_def_id` 与 `holder`，不再保存 `item_id`、`owner_id` 或库存数组的第二真值。
- entity、location、container、escrow 与 destroyed 五类 holder 均有边界校验。
- transfer、consume、split_stack 与 durability 变化均要求引用已经存在的 Fact，并把来源写入物品历史。
- 湖湾镇粮仓发现物已接入新合同；旧 UI 和玩法仍能通过 Snapshot 兼容投影读取 `item_id`、`owner_id` 和 `inventory_item_ids`。

结果没有增加新的剧情长度，但降低了后续装备、商店、口粮消耗和遗物历史继续使用临时字段的风险。物品现在可以真正改变持有者、数量与状态，而不只是显示在剧情文本里。

## 2. Definition 与实例边界

ItemDef 负责稳定定义：

- 物品类别、标签、质量和基础价值；
- 是否可堆叠及最大堆叠；
- 可装备槽、能力和耐久上限；
- 静态 modifiers。

ItemInstance 负责运行时事实：

- 当前 holder 与 quantity；
- condition、custom tags、provenance 与 history；
- 创建和最后更新时间。

Registry 会拒绝负质量、负价值、非法堆叠上限、非堆叠多数量以及非法耐久定义。ItemStore 会拒绝未知 Definition、悬空 Entity/Location/Container、容器自包含、越界耐久和无事实来源的运行时创建。

初始 fixture 只能通过 `load_initial_items()` 的迁移入口载入。公开 `create_item()` 即使伪造 `source_kind: test_fixture`，也不能绕过 Fact 校验。

## 3. 唯一真值与兼容读取

物品归属只由以下字段决定：

```json
{
  "holder": {"kind": "entity", "id": "player"}
}
```

`lake_town_food_crisis_fixture.json` 已删除玩家的 `inventory_item_ids`。StateStore 和 Transaction Writer 会拒绝或跳过对该字段的写入，SnapshotBuilder 每次按 ItemStore holder 查询生成兼容数组。

现有调查、归还遗物和 UI 仍可读取旧别名，但这些值只存在于读取投影中，不会回写 Store。归还遗物测试的注入夹具也已改为直接使用规范 holder，避免测试本身制造双重真值。

## 4. 操作语义

- `transfer`：原子替换 holder，并记录旧 holder、新 holder 与来源 Fact。
- `consume`：扣减 quantity；数量归零后转为 destroyed，保留审计历史且不能再次转移。
- `split_stack`：保留总数量，为新实例分配合法 holder，并在两个实例上记录关联历史。
- `adjust_durability`：只允许带耐久定义的物品在 `0..maximum_durability` 内变化。
- `append_history`：只接受引用已存在 Fact 的历史记录。

单个 ItemStore 操作先完整校验后再落地，非法操作不会产生物品半写。

## 5. 自动化验证

新增 `item_instance_contract_test.gd`，共 15 项合同断言，覆盖：

- ItemDef 注册与非法定义拒绝；
- 未知 Definition、悬空 holder、非堆叠多数量和伪造 fixture 来源拒绝；
- 事实支持的创建、转移、消耗、拆分与耐久变化；
- holder 唯一真值和 Snapshot 库存派生；
- destroyed 终态、容器循环防护与真实粮仓发现流程；
- StateStore 拒绝伪造 `inventory_item_ids`。

测试环境：Godot 4.6.3，Windows，headless。

结果：

- ItemInstance 合同测试：`15 / 15` 通过。
- 粮仓、雾盐旧井、北码头、归还遗物与角色特征定向回归：通过。
- 全项目测试：`60 / 60` 个测试脚本通过。
- `git diff --check`：通过。

## 6. 尚未完成

本轮没有把旅行系统的 `food_count` 迁移为实际口粮堆叠，也没有实现堆叠合并、EquipmentLoadout、MarketStockView 或 SaveEnvelope。

另一个已确认风险是 Transaction Writer 仍按 Store 顺序写入，没有整笔事务预检与回滚。ItemStore 能拒绝非法物品操作，但若调用方构造了非法的跨 Store 事务，同笔 Fact 可能已经先写入。当前真实玩法只生成经过测试的合法物品操作，因此没有出现回归；这个限制不能延续到物品与装备联合写入。

## 7. 下一步

进入步骤 2D：实现 EquipmentLoadout，并先为物品与装备联合变化增加整笔预检。转移、销毁或完全损坏已装备物品时，事务必须同步解除装备或整体拒绝，不能留下悬空装备引用。

步骤 2E 使用最小合同 fixture 把 `food_count` 迁移为可堆叠旅行口粮，并验证旅行消耗、库存投影与往返数据一致。

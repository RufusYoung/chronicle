# Chronicle 装备位合同实施报告

日期：2026-08-13

分支：`exp/v5-equipment-loadout-contract`

对应计划：阶段 5.5，步骤 2D

## 1. 本轮结果

本轮建立了装备位与物品实例之间的可执行合同：

- body outer、main hand 与 utility 三个 EquipmentSlotDef 进入严格 Registry。
- 新增 `EquipmentLoadoutStore`，只保存角色装备位对 ItemInstance 的引用。
- ItemDef 声明的装备位必须存在，装备物必须具有 `equip` 能力并满足槽位标签约束。
- 装备、卸装会引用真实 Fact，并把历史写回 ItemInstance。
- Transaction Writer 在写入任何 Fact 前，先在复制的 ItemStore 与 EquipmentLoadoutStore 上模拟整笔变化。
- 第七哨站玩家获得一件真实蜡封冬斗篷，拥有独立耐久、来源与 body outer 装备引用。

结果没有增加新的剧情分支，但修复了装备接入前的结构风险。以后物品被转移、完全损坏或销毁时，系统不能继续留下指向它的装备位引用。

## 2. 唯一真值

物品状态仍只属于 ItemStore：

- holder、quantity、condition、provenance 与 history；
- ItemDef 的标签、能力、可装备位与 modifiers。

EquipmentLoadoutStore 只保存：

```json
{
  "entity_id": "player",
  "slots": {
    "slot.body_outer": "item_instance.seventh_outpost.player_winter_cloak",
    "slot.main_hand": null,
    "slot.utility": null
  },
  "updated_tick": 0
}
```

“已装备”没有成为新的 holder kind。冬斗篷仍由玩家实体持有，装备位只引用它。

## 3. 引用校验

EquipmentLoadoutStore 会拒绝：

- 不存在的角色、装备位或物品实例；
- 不由装备者持有的物品；
- ItemDef 未允许的槽位；
- 没有 `equip` 能力或标签不匹配的物品；
- 完全损坏的物品；
- 同一实例重复占用多个槽位；
- 互斥组冲突；
- 没有来源 Fact 的装备或卸装操作。

初始 fixture 通过同一引用完整性校验，不能用临时字段绕过 Store。

## 4. 联合事务预检

本轮为 ItemStore 与 EquipmentLoadoutStore 增加了联合预检：

```text
复制现有 Fact
-> 加入本次候选 Fact
-> 在复制 ItemStore 上模拟全部 item_changes
-> 在复制 EquipmentLoadoutStore 上模拟全部 equipment_changes
-> 校验最终装备引用
-> 全部合法后才写入真实 Store
```

自动化反例证明：

- 转移已装备物品但不同时卸装时，Fact、holder 与 Loadout 均不变化。
- 将已装备物品耐久降为 0 但不同时卸装时，Fact 与耐久均不变化。
- 同笔事务包含 `equipment_clear` 时，转移或完全损坏可以合法落地。

这解决了物品与装备之间的半写问题，但还不是全 Store 通用事务回滚。State、Relationship、Memory 等域的统一预检仍属于步骤 3。

## 5. 只读投影

Snapshot 新增：

- `get_equipment_loadout(entity_id)`；
- `get_equipped_item(entity_id, slot_id)`；
- `get_inventory_view(owner_entity_id)`；
- `get_market_stock_view(seller_entity_id)`。

InventoryView 按 holder 生成物品 ID 与总质量，不进入 Store。MarketStockView 只列出卖方实际持有且具备 `trade` 能力的物品，并明确返回 `quote_status: unquoted`。本轮没有实现动态报价、货币结算或交易锁定。

## 6. 真实玩法接入

第七哨站第一冬 fixture 新增：

- `item_instance.seventh_outpost.player_winter_cloak`；
- 耐久 `76 / 100`；
- 来源标签 `issued_by_seventh_outpost`；
- body outer 装备引用。

原有七日生活项目仍可完整运行。当前冬斗篷 modifier 尚未进入巡雾行动公式，因此它已经是可追溯装备实例，但还没有改变风险结算；这属于步骤 3 的通用 Modifier 接入。

## 7. 自动化验证

新增 `equipment_loadout_contract_test.gd`，共 15 项断言，覆盖：

- EquipmentSlotDef 注册与非法定义拒绝；
- ItemDef 未知槽位拒绝；
- 同一冬衣定义的两个独立实例；
- Fact 支持的装备、卸装与物品历史；
- 错误槽位和无事实写入拒绝；
- 转移、完全损坏与卸装的联合事务；
- 第七哨站真实冬斗篷、InventoryView 与 MarketStockView；
- Store、Snapshot 与 Context 的所有权边界。

测试环境：Godot 4.6.3，Windows，headless。

结果：

- 装备合同测试：`15 / 15` 通过。
- ItemInstance、角色特征与第七哨站定向回归：通过。
- 全项目测试：`61 / 61` 个测试脚本通过。
- JSON 解析与 `git diff --check`：通过。

## 8. 尚未完成

- 冬斗篷 modifier 尚未影响行动资格、风险或结果解释。
- main hand 与 utility 只有 Definition，没有真实装备实例接入。
- MarketStockView 没有动态价格、货币、报价过期与交易事务。
- 旅行仍使用 `food_count`，尚未消耗实际口粮堆叠。
- 跨所有 Store 的统一事务失败协议尚未实现。

## 9. 下一步

进入步骤 2E：建立最小合同 fixture，把旅行口粮从 `food_count` 迁移为可堆叠 ItemInstance，并加入第二名角色的独立冬衣实例与商人真实商品堆叠，为 SaveEnvelope 往返测试准备完整数据。

步骤 3 再接通用 Requirement、Modifier 与 Effect，使冬斗篷、伤势、技艺和印记共同影响同一条行动规则并提供玩家可读解释。

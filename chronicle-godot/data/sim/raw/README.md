# Raw 定义数据

## 职责

`raw/` 保存对象定义、状态字段、标签、材料、地点原型、事实类型和规则定义。

Raw 是定义层，不是世界实例。

## 不负责什么

Raw 不保存当前某个世界中已经发生的事实。

Raw 不保存玩家存档。

Raw 不保存地点专属按钮表。

## 当前说明

湖湾镇和第七哨站可以引用 Raw 定义，但它们自身在当前阶段属于 fixture。

## 当前状态

阶段 5.5 步骤 2A 已启用第一批正式定义：

- `state_defs/basic_state_defs.json` 提供带稳定 ID 和版本号的基础 StateDef。
- `object_defs/basic_object_defs.json` 提供带稳定 ID、所有者类型和默认标签的 ObjectDef。
- `SimRegistry` 在 Session 启动前执行严格注册，拒绝重复 ID、缺失版本及不合法 schema。
- `character_feature_defs/basic_character_feature_defs.json` 提供 TalentDef、TraitDef、MarkDef 和 SkillDef，并约束事实来源、阶段与等级阈值。

- `item_defs/basic_item_defs.json` 提供 ItemDef 的堆叠、质量、能力、耐久与装备位合同；fixture 只引用稳定 `item_def_id`。
- `equipment_slot_defs/basic_equipment_slot_defs.json` 提供 body outer、main hand 与 utility 三个最小 EquipmentSlotDef。

`EquipmentLoadoutStore` 只保存角色装备位对 ItemInstance 的引用；Inventory 与 MarketStock 继续由 holder 查询派生，不进入可写 Store。

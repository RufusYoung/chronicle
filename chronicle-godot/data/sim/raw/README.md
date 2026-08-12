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

天赋、特质、印记、技艺、物品模板和装备位定义将在后续步骤分别接入，不能继续塞进 fixture 临时字段。

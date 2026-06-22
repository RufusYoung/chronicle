# Chronicle v5 世界模拟数据

## 定位

`data/sim/` 保存世界模拟层使用的数据。

它与 `data/rebuild/` 分开：`data/rebuild/` 服务当前前台原型，`data/sim/` 服务后续 Raw / Rule、fixture 和正式世界实例。

## 子目录

- `raw/`：定义层和规则层数据，不是具体世界存档。
- `fixtures/`：用于测试的世界切片。
- `worlds/`：正式生成或保存的世界实例。

## 当前约束

湖湾镇和第七哨站在当前阶段应作为 fixture 看待。

它们不是主 GDD，也不是永久地点按钮表。

## 当前状态

骨架阶段，暂未实现正式数据。

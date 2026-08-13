# Fixture 测试切片

## 职责

`fixtures/` 保存用于测试系统组合的最小世界切片。

示例：

- 湖湾镇粮食压力切片。
- 第七哨站军纪与配给切片。
- 核心系统最小合同切片。

## 不负责什么

Fixture 不是正式世界存档。

Fixture 不是主 GDD。

Fixture 不应退化为永久地点按钮表。

## 当前说明

当前阶段的湖湾镇和第七哨站都应作为 fixture，而不是正式扩展地点。

## 当前状态

`lake_town_food_crisis_fixture.json` 和 `seventh_outpost_ration_fixture.json` 已接入当前可玩纵向切片。

`core_system_contract_fixture.json` 只用于跨 Store 合同验证，包含两件独立冬衣、玩家与商人的口粮堆叠、装备位、伤势、印记和技艺样本。它不是新剧情地点，也不是正式存档；后续 SaveEnvelope 保存与载入测试会继续复用这份最小数据。

# Settlement Resource System

本目录管理生成聚落的长期资源库存。

## ResourceStockStore

每项库存保存：

- `stock_id`、原始资源或交通来源 `source_id`；
- 所属聚落、所在生产地点、服务产业和设施实体；
- `capacity`、`current`、`recovery_per_hour` 与 `operating_floor`；
- 当前 `status`、来源事实、最后一次变化和累计变化次数。

所有消耗、恢复和外部调整都通过 `TransactionResult.resource_changes` 进入统一 Writer。透支或越界会在预检阶段拒绝整笔事务，不能留下已经生产物品但没有消耗资源的半写状态。

## SettlementResourceSystem

每个世界小时按固定顺序执行：

1. 未满库存按自身可靠性恢复；
2. 居民生计读取绑定库存并尝试生产；
3. 实际水位重新计算设施开工状态；
4. 粮食压力、资源负担和迁离倾向写回地区状态；
5. 跌破或重新越过开工线时形成事实、压力记录和聚落纪事。

资源库存是世界真值，地点界面只读取 Snapshot 投影，不维护第二份 UI 数值。

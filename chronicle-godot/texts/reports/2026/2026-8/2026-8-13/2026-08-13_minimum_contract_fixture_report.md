# Chronicle 最小合同夹具与口粮迁移报告

日期：2026-08-13

分支：`exp/v5-minimum-contract-fixture`

对应计划：阶段 5.5，步骤 2E

## 1. 本轮结果

本轮完成了步骤 2E。最直接的变化是，旅行食物不再是一个可以和库存分离的整数：

- 湖湾镇与第七哨站的起始口粮已成为真实 `ItemInstance` 堆叠。
- 赠粮、旅行和雾盐旧井远征补给全部通过事务消耗或创建真实口粮。
- `food_count` 不再存入 StateStore，只由玩家当前持有的 `item.travel_ration` 数量聚合。
- UI 会显示“旅行口粮 ×数量”，行动反馈会说明食物具体增加或减少多少。

这让资源消耗、库存、交易候选、来源历史和未来存档开始共享同一份物品真值。结果比上一轮更接近可扩展游戏系统，但没有新增剧情长度。

## 2. 确定性口粮消耗

新增 `V5ItemConsumptionPlanner`。它按 `item_instance_id` 的稳定顺序查找行动者持有的指定 ItemDef，并可以让一次消费跨越多个堆叠。

每个消费变化会保留：

```text
item_instance_id
item_def_id
quantity
source_fact_ids
```

耗尽的堆叠不会直接消失，而是进入 `destroyed` holder，并继续保留来源与历史。若总量不足，联合事务预检会拒绝整笔 Item/Equipment 写入。

## 3. 真实玩法迁移

湖湾镇初始提供 3 份旅行口粮。给陈米一份食物后，陈米的饥饿状态与关系照常变化，同时 ItemStore 中的口粮降为 2 份。废弃粮仓与北岸路线继续消耗同一批实际物品。

雾盐旧井远征准备会创建：

- 4 份有独立来源的旅行口粮；
- 1 件蜡布防盐面罩。

这两个结果都进入 ItemStore，重复点击已经失效的准备选项不会复制补给。

## 4. 最小合同 fixture

新增 `core_system_contract_fixture.json`，在一个不扩写剧情的最小世界中同时放入：

- 玩家与霍克各自持有的一件冬衣，同 ItemDef 但耐久、来源和历史不同；
- 两人的 body outer 装备引用；
- 玩家 6 份可拆分口粮；
- 商人塞拉持有的 12 份实际商品口粮；
- 一项可恢复伤势 TraitInstance；
- 同一雾盐 MarkDef 的两个独立实例；
- 一项有事实来源的侦察 SkillProgress。

该 fixture 验证多个系统能共享稳定 Entity、Fact、Item 和 Definition 引用，不是新地点内容，也不是独立玩法演示。

## 5. SaveEnvelope seed

SimSession 新增 `build_save_envelope_seed()`，当前导出：

- schema 版本、世界 ID、fixture ID、当前位置与世界时间；
- Session 运行游标；
- 所有 Store 快照；
- 排序稳定的 Definition manifest。

自动化测试验证了 JSON 编码、解码后的语义等价、重复导出的确定性，以及物品历史、装备引用、印记和技艺来源事实的完整性。物品保存记录不包含 `item_id`、`owner_id`、能力、价值等 UI 兼容投影；InventoryView 和 MarketStockView 也没有进入保存数据，它们仍由 Store 真值即时派生。

该输出只是 SaveEnvelope seed。它还不能从磁盘载入并恢复 Session，也不包含迁移注册表、完整 RNG 状态和载入后的行动候选一致性校验，因此步骤 4 尚未完成。

## 6. 自动化验证

新增 `minimum_contract_fixture_test.gd`，共 13 项断言，覆盖：

- Definition 与 Store 启动合同；
- 独立冬衣与装备引用；
- 口粮聚合、拆分、跨堆叠消费和耗尽历史；
- 商人真实库存投影；
- Trait、Mark 与 Skill 来源；
- SaveEnvelope seed 的 JSON 往返、确定顺序与引用完整性；
- 不保存 Inventory 和 MarketStock 派生投影。

测试环境：Godot 4.6.3，Windows，headless。

结果：

- 10 项迁移相关定向回归全部通过。
- 最小合同夹具 13 项断言全部通过。
- 全项目 `63 / 63` 个测试脚本通过。
- `git diff --check` 通过。

## 7. 尚未完成

- 通用 Requirement、Modifier 与 Effect 尚未让冬衣、伤势、技艺和印记共同影响行动。
- Transaction Writer 还没有覆盖全部 Store 的原子失败协议。
- MarketStockView 仍不提供动态价格、货币结算、交易锁定和报价过期。
- SaveEnvelope seed 尚不能执行正式保存、载入和版本迁移。
- 最小 fixture 尚未包含成功交易与过期报价反例，这两项需要步骤 3 的统一效果与后续经济事务支持。

## 8. 下一步

进入步骤 3。先选择一条现有巡雾或调查行动，让属性、冬衣、可恢复伤势、侦察技艺和雾盐印记通过统一 Requirement/Modifier 协议共同改变资格或风险，并在 UI 中逐项解释来源。

同轮把当前 Item/Equipment 联合预检扩展为全 Store 统一失败协议。完成后再进入步骤 4，将本轮 SaveEnvelope seed 发展为可保存、可载入、可迁移且恢复候选一致的正式存档。

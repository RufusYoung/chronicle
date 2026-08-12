# Chronicle 角色特征合同实施报告

日期：2026-08-12

分支：`exp/v5-character-feature-contract`

对应计划：阶段 5.5，步骤 2B

## 1. 本轮完成了什么

本轮建立了角色成长数据的第一层可执行合同：

- Raw Definition 新增 TalentDef、TraitDef、MarkDef、SkillDef 四类严格注册。
- 新增 `CharacterFeatureStore`，保存天赋指派、特质实例、印记实例和技艺进度。
- 新增只读 `CharacterProgress`，从 StateStore 读取六项属性，从角色特征 Store 读取四类实例 ID。
- Transaction Writer 先写入 FactStore，再由规范事实驱动角色特征变化。
- `injury` 和 `mist_salt_echo` 已从 StateStore 移出；旧 UI 继续通过 Snapshot 兼容投影读取，不再形成第二真值。
- 真实挑战伤势会创建 TraitInstance，雾盐旧井事实会创建 MarkInstance，第一冬巡雾职责会增长 `skill.scouting`。

## 2. Definition 合同

Registry 当前共加载 40 个 Definition，其中本轮新增：

- 1 个 TalentDef：`talent.night_adapted_eyes`。
- 3 个 TraitDef：扭伤、档案木刺伤、雾盐灼伤。
- 1 个 MarkDef：`mark.mist_salt_echo`。
- 1 个 SkillDef：`skill.scouting`。

严格校验覆盖稳定 ID、版本、阶段顺序、终止阶段、事实类型、进度阈值、rank 阈值和练习规则。非法 Definition 不会进入 Registry。

## 3. 唯一真值与写入链

六项基础属性仍由 StateStore 保存。角色特征实例只由 CharacterFeatureStore 保存，CharacterProgress 不允许独立写入。

运行时写入顺序为：

```text
TransactionResult.facts_added
-> FactStore 去重并保存规范事实
-> CharacterFeatureStore 按 fact_id 回读规范事实
-> 创建 Trait、累计 Mark 或累计 Skill XP
-> SnapshotBuilder 生成 CharacterProgress 与旧字段兼容投影
```

角色特征 Store 不信任调用方随附的同 ID payload。载入实例时也会重新校验事实是否存在、是否属于该角色、事实类型是否被 Definition 接受，以及事件累计值是否与规则一致。

## 4. 现有玩法迁移结果

### 4.1 伤势

粮仓、北埠档案房和雾盐旧井的挑战失败仍产生原有伤势反馈，但运行时真值已经是 TraitInstance。StateStore 会拒绝直接写入 `injury`。

### 4.2 雾盐回响

雾盐回响已经是 `mark.mist_salt_echo` 的 MarkInstance。阶段由事实进度与阈值推导，StateStore 会拒绝直接写入 `mist_salt_echo`。旧界面读取的 `faint` 来自 Snapshot 投影。

### 4.3 侦察技艺

第一冬连续七天执行 `patrol_fog_line` 会产生七条真实职责完成事实，最终形成：

```text
skill.scouting
practice_xp = 56
rank = 1
source_fact_ids = 7 条
```

不匹配侦察规则的职责不会增加经验，同一事实不会重复结算。

## 5. 自动化保护

新增 `character_feature_contract_test.gd`，共 20 项断言，覆盖：

- 四类 Definition 注册和非法 Definition 拒绝。
- 天赋受控来源与重复拥有拒绝。
- Trait 来源事实、事实去重与单实例规则。
- Mark 的规范事实、阶段推导、事件去重和伪造 payload 拒绝。
- Skill 的练习事实、XP、rank、去重和伪造 XP 拒绝。
- Session、Snapshot、CharacterProgress 与 StateStore 所有权边界。
- 真实粮仓挑战失败生成可追溯伤势 Trait。

原有雾盐测试新增 Trait、Mark 及旧字段非真值断言；第一冬测试新增七日侦察成长断言。

测试环境：Godot 4.6.3，Windows，headless。

结果：

- 角色特征合同测试：`20 / 20` 通过。
- 粮仓、雾盐旧井、第一冬定向回归：全部通过。
- 全项目测试：`60 / 60` 通过。
- `git diff --check`：通过。

全项目测试重生成的历史观察输出已还原，没有纳入本轮提交。

## 6. 尚未完成

本轮没有把 Definition 中的 Modifier 接入行动公式，也没有实现通用 Requirement、Modifier 与 Effect 系统。因此“天赋或伤势已存在”目前不等于“它已经影响所有行动结算”。

以下工作仍属于后续步骤：

- Trait 恢复与阶段推进命令。
- 天赋授予、移除及角色创建接线。
- UI 中的天赋、特质、印记和技艺详情页。
- ItemInstance、EquipmentLoadout、InventoryView 和 MarketStockView 合同。
- SaveEnvelope、存档迁移与往返一致性。

## 7. 下一步

进入步骤 2C：扩展 ItemStore 的 holder、quantity、transfer、consume 与 durability，并让库存从物品 owner 查询生成，删除 `inventory_item_ids` 双写。不得在这一步提前扩写第二年剧情。

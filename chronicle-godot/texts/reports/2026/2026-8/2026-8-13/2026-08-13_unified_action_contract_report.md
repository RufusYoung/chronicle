# Chronicle 统一行动合同报告

日期：2026-08-13

分支：`exp/v5-unified-action-contract`

对应计划：阶段 5.5，步骤 3

## 1. 本轮结果

步骤 3 已完成。项目不再由玩家行动、NPC 决策和生活项目分别解释条件与效果：

- Requirement 统一判断属性、状态、天赋、特质、印记阶段、技艺、物品、装备、关系、事实、记忆、压力、环境标签和世界时间。
- Modifier 按稳定顺序计算基础值、加法、乘法和边界，并保留来源与玩家可读解释。
- NPC 与生活项目 Effect 先转换为显式 `TransactionResult`，再交给 Writer。
- Writer 会在全部 Store 的预演副本中执行整笔结果；任何后置写入失败，前面的 Fact、状态和关系也不会落地。

玩家能直接看到本轮改善。“巡查雾线”现在显示组合资格、基础风险、最终风险和每项修正来源，不再只依赖一个感知门槛。

## 2. 真实行动接入

“巡查雾线”使用以下合同：

```text
资格：感知至少 8，或侦察至少 1 级
基础风险：6
行动标签：fog_patrol、foot_patrol、mist_salt_exposure
```

第一批参与风险计算的实际系统为：

- 上蜡冬衣：严寒环境风险 `-2`。
- 扭伤的脚踝：徒步巡查风险 `+2`。
- 雾盐回响：相似异常环境风险 `+1`。
- 侦察 1 级及以上：雾线巡查风险 `-1`。

初始第一冬角色穿着冬衣，因此巡查风险从 `6` 降为 `4`。专项测试注入可追溯的伤势、印记和三次巡查练习后，感知降到 `7` 仍可由 1 级侦察满足资格；四项修正共同得到最终风险 `6`。这些数值不是 UI 自行拼接，均来自 Definition、Instance、装备 Loadout 和 Snapshot。

## 3. 共享 Requirement

新增 `V5ActionContractResolver`。当前共享调用方包括：

- `ActionAffordanceSystem` 的玩家行动候选；
- `NpcDecisionSystem` 的资格条件与 utility factor；
- `LifeProjectController` 的职责资格和 `available_if`；
- 每日条件结算；
- 生活项目完成条件。

旧格式仍可读取，但只作为兼容输入：

- `player_min` 转换为 attribute Requirement；
- NPC 的 `source / equals / not_equals / in / min / max` 转换为通用条件；
- 生活项目的 `entity_id / key / min / max` 转换为 state Requirement。

行动候选暂时保留扁平 `player_requirements` 供旧主界面读取，完整组合结构放在 `extra.requirement_groups`。这避免界面回归，同时为后续逐步移除旧字段留下明确路径。

## 4. 共享 Modifier 与解释

Modifier 来源会从角色当前天赋、活动特质、活动印记、技艺进度和已装备物品中收集。每项已应用修正保留：

```text
modifier_id
source_kind
source_id
source_label
target
operation
value
before
after
reason
```

第七哨站职责界面会显示 `风险 6 → 4`；行动完成后的反馈会继续列出“上蜡冬衣 -2 风险”及原因。组合 Requirement 失败时会同时说明各条路径，单条件仍保持“智慧不足：需要 9，当前 8”这类紧凑文案。

## 5. Effect 与原子 Writer

新增 `V5EffectProtocolResolver`，第一批支持：

- state set、add、degrade；
- fact、memory、relationship、pressure；
- trace、rumor、chronicle、investigation；
- item、equipment；
- obligation、exchange、deferred consequence。

“巡查雾线”、罗恩高压加岗、低补给士气结算和 NPC 粮食交易已经使用原生 Requirement 或 operations 样本。闻简的离岗觅食、求助、购买、返回生活链继续保持原行为，但其 Effect 现在由共享解析器处理。

`V5TransactionWorldWriter` 不再只预检 Item 与 Equipment。它会：

1. 校验每类结果所需 Store 是否存在。
2. 克隆全部 Store 脚本状态。
3. 把克隆间的 Entity、Fact、Item 等引用重连到预演图。
4. 在预演图中执行全部变化并检查装备引用完整性。
5. 只有全部成功才把预演后的 Store 数据提交到正式世界。

专项反例故意先增加 Fact 和疲劳，再更新一个不存在的义务。结果整笔事务被拒绝，Fact 与疲劳均保持原值。

## 6. 自动化验证

新增 `unified_action_contract_test.gd`，7 项断言覆盖：

- 组合 Requirement；
- 冬衣、伤势、印记与技艺共同修正同一行动；
- 修正来源与解释；
- 后置 Store 失败时整笔事务不落地；
- 显式 Effect operations 推进真实值勤。

测试环境：Godot 4.6.3，Windows，headless。

结果：

- `tests/sim`：`34 / 34` 个脚本通过。
- `tests/rebuild`：`16 / 16` 个脚本通过。
- 全项目：`64 / 64` 个测试脚本通过。
- 闻简 14 步 NPC 生活链、七日第一冬、装备完整性和旧属性界面均通过回归。
- 测试输出无 `SCRIPT ERROR`。

## 7. 改善与限制

本轮改善的是系统协作方式和行动可解释性。装备、伤势、印记和技艺终于会改变玩家实际可做的事与风险，NPC 和生活结算也不再维护平行条件解释器。

本轮没有增加新的剧情长度，也没有完成完整数值平衡。当前 `action.risk` 已能统一计算和展示，但第一冬还没有让风险进一步驱动随机检定、伤势概率或收益档位；这应在后续系统接入中完成，不能把“风险可计算”误报为完整挑战系统。

另外尚未完成：

- 正式保存、载入和版本迁移；
- NPC Modifier 对 utility 或行动风险的全面应用；
- 所有旧数据改写为原生 Requirement 与 operations；
- 完整市场报价、货币与交易锁定；
- 阶段成长候选和长期服役内容。

## 8. 下一步

进入步骤 4。把现有 SaveEnvelope seed 扩展为可恢复的正式存档：实现载入、schema 迁移注册、引用校验、失败报告，并验证湖湾镇进入第七哨站后保存再载入时，人物、关系、物品、装备、伤势、印记、技艺、世界时间和行动候选完全一致。

# Transaction System

## 职责

处理玩家、NPC 或世界系统行动后的世界写回。

## 管理的数据

事务结果、实体生命周期、状态变化、事实记录、关系变化、记忆生成、痕迹生成、物品变化、地区变化和传闻种子。

## 输入

ActionCandidate、执行者、目标、当前世界状态、规则结果和随机判定。

## 输出

TransactionResult，以及可交给各系统写入的结构化变化。

## 不负责什么

不负责生成候选行动，不负责最终纪事输出，不负责 UI 展示。

## 与其他系统的关系

Action 和世界系统提供候选，Fact 记录客观事实，Entity、State、Relationship、Memory、Trace、Rumor 承接写回。

## 当前状态

已实现结构化 TransactionResult 与统一 Writer，支持 Entity、Fact、State、Relationship、Memory、Trace、Rumor、Pressure、Obligation、Exchange、Item、ResourceStock、Equipment、CharacterFeature、Chronicle、Investigation 和 DeferredConsequence 等写入。

ItemStore 与 EquipmentLoadoutStore 会在真实写入前联合模拟最终状态。旅行和行动效果可按物品定义规划多个口粮堆叠的确定性消耗。

Writer 会克隆本次涉及的所有 Store 完成预检，再一次性提交。任一资源透支、物品、装备或状态校验失败时，同笔事务的事实、状态、关系和其他 Store 均不留下半写。

## 实体生命周期合同

`TransactionResult.entity_changes` 支持三种操作：

- `create`：提交完整实体定义。初始状态和关系可以在同一事务中写入。
- `update`：只允许修改展示名、描述、目标、运行响应和需求信号等可变静态字段。ID、类型和标签属于身份合同，不能在运行期改写。
- `retire`：写入 `lifecycle_status = retired`、退役事实、日期和原因，不物理删除实体。

每项实体变化必须声明至少一个已经存在或由同事务新增的 `source_fact_ids`。退役操作还必须把 `retired_fact_id` 放入来源事实列表。Writer 先在克隆 Store 中应用实体变化，再验证同事务事实、状态、关系、资源和其他变化；任一后续写入失败时，新实体、事实和引用一起回滚。

退役采用软退役，因为 Fact、Relationship、Chronicle 和存档历史仍可能引用该实体。运行系统和当前界面负责忽略退役实体，历史读取仍能解析原 ID。区域与玩家实体受保护，不能通过通用退役操作撤销。

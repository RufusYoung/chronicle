# Transaction System

## 职责

处理玩家或 NPC 行动后的世界写回。

## 管理的数据

事务结果、状态变化、事实记录、关系变化、记忆生成、痕迹生成、物品变化、地区变化和传闻种子。

## 输入

ActionCandidate、执行者、目标、当前世界状态、规则结果和随机判定。

## 输出

TransactionResult，以及可交给各系统写入的结构化变化。

## 不负责什么

不负责生成候选行动，不负责最终纪事输出，不负责 UI 展示。

## 与其他系统的关系

Action 提供候选，Fact 记录客观事实，State、Relationship、Memory、Trace、Rumor 承接写回。

## 当前状态

已实现结构化 TransactionResult 与统一 Writer，支持 Fact、State、Relationship、Memory、Trace、Rumor、Pressure、Obligation、Exchange、Item、ResourceStock、Equipment、CharacterFeature、Chronicle、Investigation 和 DeferredConsequence 等写入。

ItemStore 与 EquipmentLoadoutStore 会在真实写入前联合模拟最终状态。旅行和行动效果可按物品定义规划多个口粮堆叠的确定性消耗。

Writer 会克隆本次涉及的所有 Store 完成预检，再一次性提交。任一资源透支、物品、装备或状态校验失败时，同笔事务的事实、状态、关系和其他 Store 均不留下半写。

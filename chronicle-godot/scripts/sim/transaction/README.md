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

骨架阶段，暂未实现正式逻辑。

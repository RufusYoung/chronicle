# Narrative Surface System

## 职责

把结构化状态翻译成玩家可读短文本。

## 管理的数据

地点叙述、行动结果文本、阶段摘要、人物反应、传闻描述和纪事段落素材。

## 输入

地点状态、可见对象、ActionCandidate、Transaction 结果、Fact、Memory、Rumor、Trace 和 Life Project 节点。

## 输出

前台可读文本和可交给 UI 展示的数据片段。

## 不负责什么

不负责决定事实，不负责推进世界，不负责创造不存在的人物、物品或关系。

## 与其他系统的关系

Narrative Surface 读取各系统输出，把事实和状态翻译成文本，但不反向决定世界状态。

## 当前状态

骨架阶段，暂未实现正式逻辑。

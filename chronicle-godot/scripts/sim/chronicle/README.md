# Chronicle Output System

## 职责

把已经发生的一生与时代事实整理成个人纪事和世界纪事。

Chronicle 不创造事件。它只读取 Fact、Memory、Relationship、Item
History、Rumor 和地区变化，把可追溯材料组织成可阅读条目。

## 当前实现

当前纵向切片已经包含：

- `V5ChronicleStore`：保存结构化纪事条目，按条目或主体读取。
- `V5ChronicleEntryBuilder`：从旅行、检定、发现物、人物识别和地方史事实
  构造个人纪事。
- `TransactionResult.chronicle_entries_added`：让纪事与事实、状态、关系、
  记忆和物品履历经过同一次事务写回。
- `SimSnapshot.chronicle_entries`：把已生成纪事投影到玩家界面。

第一条正式纪事是“被认出的验粮铜牌”。它只在以下因果链完整时生成：

```text
前往废弃粮仓
→ 完成危险检定
→ 发现并持有验粮铜牌
→ 返回老陈铺子
→ 陈米依据铜牌来源认出旧公仓
→ 写入地方史线索
→ 生成个人纪事
```

每条纪事保留：

- 来源事实 ID 与类型。
- 来源物品 ID。
- 来源记忆 ID。
- 分句级 `claims` 证据引用。
- 发生日期、小时和地点。

## 边界

Chronicle 不负责：

- 生成不存在的世界事件。
- 替代 FactStore 或 WorldLog。
- 直接修改人物关系、状态或物品。
- 在 UI 中临时拼出没有存储来源的故事。
- 使用生成式文本覆盖结构化事实。

如果旅行、检定、发现物或人物识别中的必要来源缺失，
`V5ChronicleEntryBuilder` 会拒绝生成条目。

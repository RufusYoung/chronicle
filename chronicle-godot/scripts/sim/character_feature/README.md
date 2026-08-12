# Character Feature System

## 职责

保存角色拥有的天赋指派、特质实例、印记实例和技艺进度。

## 唯一真值

- 六项基础属性继续由 `StateStore` 保存。
- `CharacterFeatureStore` 保存四类角色特征运行实例。
- `CharacterProgress` 只从两个 Store 聚合读取，不允许独立写入。

## 来源约束

Trait、Mark 和 Skill 的运行时变化必须引用已经写入 `FactStore` 的事实。同一事实不能为同一印记或技艺重复贡献。Mark 的阶段与 Skill 的 rank 都由 Raw Definition 阈值推导。

从 fixture 或存档载入记录时，Store 还会重新校验事实类型、事实拥有者、事件增量和 Definition 规则，不信任外部提供的 `stage_id`、`rank` 或累计值。

## 不负责什么

不负责生成剧情文本，不负责决定 UI 布局，不把临时生活项目指标直接伪装成永久技艺。Definition 中的 Modifier 目前只保存合同数据，尚未接入通用 Requirement、Modifier 与 Effect 结算。

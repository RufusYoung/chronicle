# Chronicle 开发路线图

## Milestone 0：项目清理

目标：确认当前 Demo 边界，归档旧副本与损坏代码，建立文档和架构决策体系。

状态：执行中，详见 `milestone_0_project_cleanup.md`。

## Milestone 1：world_sim_mvp

目标：建立可以脱离玩家选择自行推进的最小世界模拟层。

状态：第一阶段核心已完成，无 UI Runner 已通过两组 30 天对比验收；尚未接入当前 Demo。

范围：

- 单个镜湖种子世界
- 地区状态
- 少量势力状态
- 资源与生态变化
- 固定时间步进
- 状态变化生成传闻与线索
- 玩家行为写回世界

详见 `milestone_1_world_sim_mvp.md`。

## Milestone 2：当前 Demo 接入

目标：保留现有线索与 MicroSession 体验，将其数据来源替换为世界模拟投影。

## Milestone 3：内容扩展与验证

目标：在模拟闭环稳定后，再扩展地区、事件、角色成长、装备、生物和关系网络。

# Chronicle v5.1 世界模拟系统架构

## 1. 文档定位

本文件是 Chronicle v5.1 的世界模拟系统架构文档。

它不替代 GDD。
它不替代 UI Flow。
它不替代 Raw / Rule 系统规格。
它也不是某个地点的剧情设计文档。

它负责回答：

```text
Chronicle 的世界到底由哪些层级组成？
每一层管理什么数据？
系统之间如何交互？
Raw / Rule 层在整个架构中处于什么位置？
后续新增地点、人物、物品、装备、职业、关系、事件时，应该往哪个系统里加？
```

Chronicle 的目标不是制作大量手写事件，也不是给每个地点手写按钮。

Chronicle 的目标是：

```text
先定义世界的基本构成单位。
再定义这些单位如何组合。
再定义组合体之间如何互相影响。
最后让世界在玩家介入或不介入时，都能持续产生事实、记忆、关系、传闻和故事。
```

---

## 2. 当前问题

当前 v5.1 已经有了一个可运行的地点局面主界面原型。

该原型证明了：

```text
顶部导航可以存在。
左侧角色状态可以存在。
中央地点局面可以存在。
右侧地区状态、线索、地点可以存在。
底部行动选项可以存在。
线索行动卡可以存在。
生涯面板占位可以存在。
```

但这只是前台承载面。

如果继续沿当前方式直接扩展内容，很容易变成：

```text
湖湾镇写一批按钮。
第七哨站写一批按钮。
王都图书馆写一批按钮。
医馆写一批按钮。
矿村写一批按钮。
```

这不是涌现式世界模拟。

真正需要建立的是：

```text
基础对象
+
状态字段
+
关系结构
+
制度约束
+
地点组织
+
系统规则
+
行动生成
+
事实写回
+
记忆、传闻、纪事承接
```

只有这些层级拆清楚，Raw / Rule 原型才不会变成一堆散乱 if 条件。

---

## 3. 总体比喻：细胞、组织、器官、系统、世界

Chronicle 的世界可以按五层理解：

```text
细胞层
组织层
器官层
系统层
世界层
```

这不是文学比喻，而是工程分层。

### 3.1 细胞层

细胞是最小可组合单位。

包括：

```text
年龄
饥饿
恐惧
信任
怨恨
债务
材质
湿度
锋利度
腐败度
所有权
可见性
可读性
危险度
新鲜度
标签
词条
事实类型
关系轴
时间戳
```

细胞本身不构成故事。

例如：

```text
hunger = high
fear = medium
material = spoiled_grain
ownership = old_chen_family
visibility = visible
trust = low
```

这些只是原子状态。

### 3.2 组织层

组织是由一组细胞组合成的具体对象。

包括：

```text
一个人
一件物品
一条痕迹
一段关系
一个记忆
一份告示
一把剑
一袋粮食
一处门缝
一本账册
一条传闻
```

例如“陈米”是组织：

```text
Person:
- 年龄：child
- 饥饿：high
- 恐惧：medium
- 关系：old_chen 的女儿
- 行为：hiding_food
- 携带物：old_bag
```

“灰白粮粉”也是组织：

```text
Trace:
- 类型：powder_trace
- 材料：spoiled_grain
- 可见性：visible
- 新鲜度：recent
- 来源暗示：abandoned_granary
```

### 3.3 器官层

器官是多个组织组合起来形成的局部生活结构。

包括：

```text
地点
家庭
店铺
商队
小队
职业路线
市场
哨站
装备组
地方制度
地牢
药铺
图书馆
```

例如“老陈铺子”不是一个按钮集合，而是一个器官：

```text
老陈铺子：
- 老陈
- 陈米
- 涨价告示
- 旧布袋
- 灰白粮粉
- 店铺门
- 邻里关系
- 粮价压力
- 守卫注意
```

“第七哨站厨房”也是器官：

```text
第七哨站厨房：
- 厨子玛塔
- 新兵伊莱
- 缺失口粮记录
- 储物柜
- 泥脚印
- 配给制度
- 队长罗恩的军纪压力
- 今夜雾线巡逻
```

### 3.4 系统层

系统管理某一类规则和数据流。

包括：

```text
实体系统
状态系统
关系系统
物品系统
地点系统
地区系统
组织 / 制度系统
经济 / 资源压力系统
行动生成系统
事务写回系统
事实系统
记忆系统
传闻系统
长期项目系统
叙事表面系统
纪事系统
世界推进系统
```

系统不是内容本身，而是管理内容如何运行。

### 3.5 世界层

世界层是所有系统运行后的整体结果。

世界不需要玩家存在也能推进。

它会持续产生：

```text
事实
死亡
迁徙
债务
关系变化
传闻
店铺兴衰
军纪处分
市场波动
疾病传播
家族沉浮
地点荒废
职业路线变化
时代记忆
```

玩家只是其中一个实体。

---

## 4. 核心设计原则

### 4.1 先有深度，再有广度

当前阶段不追求十个地区、五十个职业、一百个地点。

当前阶段追求：

```text
一个地点能否有深度。
一个人物能否由多个系统共同塑造。
一个选择能否同时影响关系、状态、事实、传闻和纪事。
一个规则能否在不同生活领域中复用或分化。
```

广度应该在系统稳定后增加。

### 4.2 不按地点写按钮

地点不应该保存最终按钮表。

错误方式：

```text
老陈铺子：
- 走近陈米
- 给她食物
- 查看涨价告示
- 举报她
```

正确方式：

```text
老陈铺子包含：
- 饥饿人物
- 隐藏物品
- 可读告示
- 可检查痕迹
- 粮食压力
- 守卫注意
- 街坊目光
```

行动由规则生成。

### 4.3 不按人物写专属逻辑

错误方式：

```text
if entity_id == "chen_mi":
    add_action("给她食物")
```

正确方式：

```text
if entity.type == person
and entity.hunger >= high
and player has food:
    generate "给 {entity.name} 食物"
```

但仅有这种基础规则还不够。
不同领域必须有不同制度和生活结构，否则会变成换壳。

### 4.4 通用规则不等于所有场景同质化

湖湾镇和第七哨站不能只是：

```text
饥饿孩子
饥饿新兵
```

它们应该来自不同系统压力。

湖湾镇的核心压力：

```text
民间粮食危机
家庭债务
儿童恐惧
地方街坊关系
守卫介入
市场价格
```

第七哨站的核心压力：

```text
军纪
配给制度
小队关系
上级命令
值岗责任
边境威胁
口粮短缺
战时纪律
```

所以行动生成必须由：

```text
基础规则
+
领域规则包
+
局面规则包
```

共同完成。

---

## 5. 系统总表

Chronicle v5.1 的世界模拟至少拆成以下系统：

```text
1. Entity System             实体系统
2. State / Need System       状态与需求系统
3. Trait / Tag System        特质与标签系统
4. Relationship System       关系系统
5. Memory System             记忆系统
6. Item / Material System    物品与材质系统
7. Equipment System          装备系统
8. Location System           地点系统
9. Region System             地区系统
10. Institution System       组织与制度系统
11. Economy / Pressure System 经济与压力系统
12. Action Affordance System 行动候选系统
13. Transaction System       行动事务系统
14. Fact / History System    事实与历史系统
15. Trace System             痕迹系统
16. Rumor System             传闻系统
17. Life Project System      长期项目系统
18. World Tick System        世界推进系统
19. Narrative Surface System 叙事表面系统
20. Chronicle Output System  纪事输出系统
```

这些系统不是一次性全部实现。
但必须先明确边界。

---

## 6. Entity System：实体系统

### 6.1 职责

实体系统管理世界中“谁”和“什么”存在。

实体包括：

```text
人
动物
怪物
物品
地点对象
组织
势力
商队
小队
店铺
家庭
装备
痕迹
传闻载体
```

### 6.2 输入

```text
Raw Definition
出生 / 创建规则
世界生成结果
行动事务
长期项目结算
世界推进事件
```

### 6.3 输出

```text
Active Instance
实体查询
实体生命周期
实体所属关系
实体位置
实体可见性
```

### 6.4 原则

实体系统不决定行动。
实体系统只告诉其他系统：

```text
当前有哪些对象存在。
它们在哪里。
它们是什么类型。
它们有什么组件。
它们是否可见。
```

---

## 7. State / Need System：状态与需求系统

### 7.1 职责

状态系统管理实体的数值、状况和需求。

包括：

```text
生命
健康
精力
理智
饥饿
伤势
恐惧
疲劳
疾病
年龄
疼痛
寒冷
饥荒压力
忠诚
腐败度
新鲜度
湿度
损坏度
```

### 7.2 输入

```text
时间推进
行动事务
物品效果
地点环境
地区压力
长期项目
疾病 / 伤势规则
```

### 7.3 输出

```text
状态变化
需求压力
行为倾向
行动条件
叙事素材
结算素材
```

### 7.4 原则

状态不是 UI 文本。

错误：

```text
文本里说她饿，所以 hunger = high。
```

正确：

```text
hunger = high，所以文本可以写她饥饿。
```

---

## 8. Trait / Tag System：特质与标签系统

### 8.1 职责

标签和特质用于给对象、人物、地点、规则提供可匹配语义。

包括：

```text
food
spoiled
readable
inspectable
military
market
child
soldier
merchant
forbidden
public
private
dangerous
trace
memory_weight_high
```

### 8.2 输入

```text
Raw Definition
行动结果
阶段结算
身份系统
装备历史
地点原型
```

### 8.3 输出

```text
规则匹配条件
叙事修饰
行动候选
传闻传播条件
纪事筛选权重
```

### 8.4 原则

标签要可复用。

错误：

```text
tag: chen_mi_scene
```

正确：

```text
tag: hungry_child
tag: concealed_food
tag: local_family_crisis
```

---

## 9. Relationship System：关系系统

### 9.1 职责

关系系统管理实体之间的长期关系和短期态度。

关系不是单一好感度。

建议关系轴：

```text
信任
恐惧
感激
怨恨
债务
熟悉
亲近
羞愧
利用意图
误解
忠诚
服从
竞争
保护欲
```

### 9.2 输入

```text
共同经历
行动事务
事实
记忆
组织关系
血缘
职业关系
债务
冲突
帮助
背叛
```

### 9.3 输出

```text
NPC 行为倾向
行动候选条件
传闻传播倾向
长期项目节点
叙事文本素材
纪事权重
```

### 9.4 示例

玩家给陈米食物：

```text
陈米 gratitude_to_player +1
陈米 fear_to_player -1
陈米 memory: received_food_help
```

玩家举报陈米：

```text
陈米 fear_to_player +1
老陈 shame +1
守卫 attention_to_player +1
街坊 rumor_seed +1
```

---

## 10. Memory System：记忆系统

### 10.1 职责

记忆系统管理某个实体如何主观记住事实。

Fact 是客观发生。
Memory 是某人怎么记住。

### 10.2 输入

```text
事实
情绪权重
关系
身份
地点
创伤
帮助
背叛
长期项目节点
```

### 10.3 输出

```text
后续态度
对话素材
传闻源头
长期回声
个人纪事素材
阶段结算素材
```

### 10.4 原则

记忆可以失真，但事实不能失真。

纪事中可以写：

```text
世人说他收买了老陈一家。
```

但不能把没有发生过的事情写成事实。

---

## 11. Item / Material System：物品与材质系统

### 11.1 职责

管理物品、材料、食物、工具、货物、书籍、药物、普通道具。

物品不是简单背包图标。

物品应包含：

```text
材质
用途
所有权
价值
腐败度
耐久
可食用性
可交易性
危险性
文化意义
历史记录
```

### 11.2 输入

```text
Raw ItemDef
MaterialDef
制作规则
腐败规则
交易规则
行动事务
世界生成
```

### 11.3 输出

```text
行动条件
经济影响
装备构成
食物效果
痕迹生成
传记素材
```

### 11.4 示例

发霉麦子：

```text
Item:
- type: food
- material: grain
- spoiled: high
- edible: dangerous
- value: low
- hunger_restore: low
- health_risk: medium
- linked_region_pressure: food_crisis
```

---

## 12. Equipment System：装备系统

### 12.1 职责

装备系统管理装备作为战斗工具、身份象征和历史物件的三重性质。

装备应包含：

```text
类型
材质
基础数值
耐久
契合度
词条
历史
修理记录
杀敌记录
所有者
传承状态
```

### 12.2 输入

```text
Item / Material System
战斗事务
修理事务
赠送事务
长期项目
传闻
遗产系统
```

### 12.3 输出

```text
战斗修正
身份识别
传闻素材
纪事素材
遗产物
赝品条件
```

### 12.4 原则

装备不是单纯数值。

一把旧短刀可以因为事实记录变成：

```text
第七哨站防守中使用过的旧短刀
```

这类历史应由 Fact / History System 支撑。

---

## 13. Location System：地点系统

### 13.1 职责

地点系统管理局部空间和可激活对象。

地点包括：

```text
城镇
街道
店铺
仓库
哨站
厨房
市场
码头
图书馆
医馆
矿洞
森林
遗迹
```

### 13.2 输入

```text
PlaceDef
地区状态
实体位置
行动事务
世界推进
传闻
长期项目
```

### 13.3 输出

```text
当前地点上下文
可见实体
可见物品
可见痕迹
地点标签
风险
子地点
行动候选上下文
叙事表面素材
```

### 13.4 原则

地点不是按钮容器。
地点是对象、状态、痕迹、人物、风险、社会关系的汇合点。

---

## 14. Region System：地区系统

### 14.1 职责

地区系统管理比地点更大的状态。

地区包括：

```text
湖湾镇地区
北境边境
王都
南部湿地
商路
岛屿
山谷
```

地区状态包括：

```text
粮食压力
治安
商路
疾病
战争压力
物价
人心
天气倾向
势力控制
传闻密度
```

### 14.2 输入

```text
经济系统
世界推进
地点事件
商队流动
战争
疾病
玩家行动
```

### 14.3 输出

```text
地点初始状态
行动候选条件
传闻传播
长期项目背景
世界纪事素材
```

### 14.4 示例

```text
粮食：紧张。
老陈铺子已经两天没开门，市场上的干粮涨了一次价。
```

这不是纯文本，而应来自：

```text
region.food_pressure = high
market.grain_price_trend = rising
old_chen_shop.open_state = closed
```

---

## 15. Institution System：组织与制度系统

### 15.1 职责

制度系统管理社会规则、权力结构和角色义务。

包括：

```text
家庭
军队
小队
商会
教团
学院
地方守卫
贵族家族
工坊
黑市
债务关系
法律
军纪
行会规矩
```

### 15.2 输入

```text
组织定义
实体身份
关系
地点
事实
行动事务
长期项目
地区状态
```

### 15.3 输出

```text
行为限制
行动候选
后果规则
惩罚规则
身份变化
组织记忆
传闻传播
```

### 15.4 示例：第七哨站

第七哨站的选择不能来自“饥饿新兵”这个单一状态。

它必须来自制度组合：

```text
chain_of_command = active
discipline_level = strict
ration_pressure = high
fog_patrol_tonight = true
ron_is_captain = true
elai_is_recruit = true
player_is_squadmate = true
```

因此能生成：

```text
向队长罗恩报告
替伊莱隐瞒一次
让伊莱今晚替你站岗作为交换
找厨子玛塔确认分发记录
把事情压到巡逻结束后再处理
```

这些不是陈米换壳。

---

## 16. Economy / Pressure System：经济与压力系统

### 16.1 职责

经济系统不一定要模拟完整市场价格，但要管理资源压力和物价趋势。

包括：

```text
粮食压力
药品压力
武器短缺
口粮短缺
债务压力
贸易中断
物价趋势
供需关系
```

### 16.2 输入

```text
地区状态
商路状态
库存
消耗
灾害
战争
玩家交易
NPC 行动
```

### 16.3 输出

```text
价格变化
地区状态
NPC 行为压力
偷窃 / 走私 / 饥饿风险
行动候选
传闻素材
```

### 16.4 示例

湖湾镇粮食压力高，会影响：

```text
老陈铺子关门
陈米饥饿
市场涨价
守卫夜巡
街坊压抑
废弃粮仓被关注
```

---

## 17. Action Affordance System：行动候选系统

### 17.1 职责

行动候选系统负责生成玩家当前可以做什么。

它读取：

```text
当前地点
可见实体
可见痕迹
玩家状态
物品
关系
制度
地区压力
已知线索
当前长期项目
```

输出：

```text
ActionCandidate[]
```

### 17.2 它不负责什么

它不负责直接改变世界。
它不负责写叙事文本。
它不负责决定长期结局。

它只回答：

```text
现在可以做什么？
```

### 17.3 行动来源

行动由三类规则共同生成：

```text
基础规则
领域规则包
局面规则包
```

基础规则：

```text
交谈
阅读
检查
给物品
离开
进入
等待
```

领域规则包：

```text
food_crisis
military_discipline
market_trade
archive_research
medicine_treatment
crafting_workshop
```

局面规则包：

```text
陈米藏着发霉麦子
伊莱疑似私藏口粮
图书馆禁书被调包
医馆药柜失窃
```

局面规则包不是手写按钮，而是为当前切片提供状态和约束。

---

## 18. Transaction System：行动事务系统

### 18.1 职责

事务系统负责处理玩家或 NPC 行动后的世界写回。

行动候选只是“可以做什么”。
事务系统处理“做了以后发生什么”。

### 18.2 输入

```text
ActionCandidate
执行者
目标
当前世界状态
规则结果
随机判定
```

### 18.3 输出

```text
状态变化
事实记录
关系变化
记忆生成
痕迹生成
物品变化
地区状态变化
传闻种子
叙事结果
```

### 18.4 原则

任何重要行动都不应该只改 UI 文本。

它至少应写入：

```text
Fact
```

否则后续系统无法读取。

---

## 19. Fact / History System：事实与历史系统

### 19.1 职责

事实系统管理客观发生过的事情。

事实是 Chronicle 的骨架。

包括：

```text
玩家给陈米食物
陈米拿过发霉麦子
老陈关店
玩家举报陈米
伊莱私藏口粮
玩家向罗恩报告
第七哨站发生处分
旧短刀参与防守
```

### 19.2 输入

```text
行动事务
世界推进
长期项目
战斗
交易
死亡
出生
迁徙
```

### 19.3 输出

```text
记忆
关系变化
传闻
纪事素材
地区历史
世界历史
```

### 19.4 原则

事实不写文学文本。
事实写结构化记录。

---

## 20. Trace System：痕迹系统

### 20.1 职责

痕迹系统管理世界中可见或可发现的后果。

包括：

```text
粮粉
脚印
血迹
损坏门锁
旧伤
告示
气味
破损装备
废弃营火
翻动过的账本
```

### 20.2 输入

```text
事实
行动事务
物品状态
环境
时间流逝
```

### 20.3 输出

```text
可检查对象
线索
传闻种子
行动候选
叙事细节
```

---

## 21. Rumor System：传闻系统

### 21.1 职责

传闻系统管理事实和记忆在社会中的传播与失真。

### 21.2 输入

```text
事实
记忆
见证者
地点人流
商路
酒馆
组织网络
人物名声
```

### 21.3 输出

```text
新线索
误解
名声
地区舆论
第二角色可听到的前角色传闻
纪事中的世人评价
```

### 21.4 原则

传闻可以失真。
事实不能失真。

传记可以写：

```text
有人说他收买了老陈一家。
```

但事实层不能写成：

```text
他确实收买了老陈一家。
```

除非事实真的发生。

---

## 22. Life Project System：长期项目系统

### 22.1 职责

长期项目系统管理跨日、跨月、跨年的人生阶段。

包括：

```text
服役
定居
营生
求知
追寻
漂泊
学徒
照顾某人
隐居恢复
```

### 22.2 输入

```text
角色状态
地点
组织
制度
关系
地区状态
线索
玩家选择
世界推进
```

### 22.3 输出

```text
年度节点
阶段摘要
状态变化
关系变化
事实
记忆
特质
伤势
技能成长
人生阶段结算
纪事素材
```

### 22.4 原则

长期项目不是跳过时间。

例如第七哨站服役五年应包含：

```text
年度摘要
固定人物
重复仪式
关键节点
中途退出机会
世界背景变化
阶段结算
离别文本
```

---

## 23. World Tick System：世界推进系统

### 23.1 职责

世界推进系统负责在玩家行动之间推动世界变化。

包括：

```text
每日推进
半日推进
月度推进
年度推进
长期项目推进
玩家失控期间推进
角色死亡后推进
第二角色出生前推进
```

### 23.2 输入

```text
时间
地区状态
实体需求
经济压力
组织目标
当前事实
长期项目
随机种子
```

### 23.3 输出

```text
新事实
状态变化
NPC 行动
地点变化
传闻传播
地区趋势
死亡 / 出生 / 迁徙
```

### 23.4 原则

世界推进不能只围绕玩家。

玩家不在湖湾镇时，湖湾镇仍然可以变化。
玩家疯癫十年时，世界仍然继续推进。
前角色死亡后，世界仍然继续推进。

---

## 24. Narrative Surface System：叙事表面系统

### 24.1 职责

叙事表面系统负责把结构化状态翻译成玩家可读短文本。

它读取：

```text
地点状态
可见对象
ActionCandidate
Transaction 结果
Fact
Memory
Rumor
Trace
LifeProject 节点
```

输出：

```text
地点叙述
行动结果文本
阶段摘要
人物反应
传闻描述
纪事段落素材
```

### 24.2 原则

叙事层不决定事实。

错误：

```text
AI 写到陈米死了，所以陈米状态改为死亡。
```

正确：

```text
陈米死亡事实已经存在，所以叙事层写陈米死亡。
```

---

## 25. Chronicle Output System：纪事输出系统

### 25.1 职责

纪事系统负责把一生整理成文学化个人纪事。

它读取：

```text
事实
长期项目
关系
记忆
伤势
装备历史
传闻
地区变化
死亡事件
```

输出：

```text
个人传记
时代纪事
角色归档
世界归档
```

### 25.2 原则

个人纪事不能把假传闻写成事实。
但可以写世人如何误解这个人。

---

## 26. Raw / Rule 层的位置

Raw / Rule 不是独立世界系统的全部。

它是：

```text
定义层
匹配层
连接层
```

它服务于所有系统。

### 26.1 Raw 负责定义

```text
对象类型
状态字段
标签
材料
人物类型
地点原型
规则定义
事实类型
记忆规则
传闻规则
```

### 26.2 Rule 负责匹配

```text
什么状态会生成什么行动
什么行动会产生什么事务
什么事实会触发什么记忆
什么记忆会产生什么传闻
什么地区压力会影响什么 NPC 行为
```

### 26.3 Raw / Rule 不负责所有内容

Raw / Rule 不应该变成一个巨大的杂物箱。

例如：

```text
关系变化归 Relationship System
记忆归 Memory System
物品腐败归 Item / Material System
长期项目归 Life Project System
纪事归 Chronicle Output System
```

Raw / Rule 只提供定义和规则框架。

---

## 27. 跨系统交互方式

系统之间不应互相随意改数据。

推荐交互方式：

```text
ActionCandidate
↓
ActionTransaction
↓
Fact
↓
State / Relationship / Memory / Trace / Rumor / Narrative
```

### 27.1 例子：给陈米食物

```text
ActionCandidate:
给陈米食物

Transaction:
玩家消耗食物
陈米饥饿下降

Fact:
player_gave_food_to_chen_mi

Relationship:
陈米感激上升
陈米恐惧下降

Memory:
陈米记得玩家给过食物

Rumor:
若被旁人看见，可能生成传闻

Narrative:
陈米接过食物，抱紧旧布袋的手松了一点。
```

### 27.2 例子：向罗恩报告伊莱私藏口粮

```text
ActionCandidate:
向队长罗恩报告伊莱私藏口粮

Transaction:
罗恩获得事实
伊莱风险上升
玩家与伊莱关系变化
军纪流程启动

Fact:
player_reported_elai_ration_violation_to_ron

Institution:
第七哨站军纪处理流程推进

Relationship:
伊莱怨恨或恐惧上升
罗恩信任玩家可能上升

Memory:
伊莱记得玩家报告了他
罗恩记得玩家维护军纪

Rumor:
小队内部可能流传玩家告密

Narrative:
罗恩没有立刻说话，只把那页口粮记录折了起来。
```

这个例子说明第七哨站不是陈米换壳。
它需要 Institution System 参与。

---

## 28. 湖湾镇如何映射到系统

湖湾镇不是一个事件卡。

它至少涉及：

```text
Region System:
湖湾镇地区，粮食压力高，商路受阻，治安紧张

Location System:
老陈铺子、市场、码头、守卫所、废弃粮仓

Entity System:
老陈、陈米、玛婶、刘账房、守卫、买粮人群

Item / Material System:
干粮、发霉麦子、旧布袋、涨价告示

Trace System:
灰白粮粉、关店痕迹、潮湿霉味

Relationship System:
老陈与陈米父女关系
老陈与刘账房债务关系
陈米对玩家恐惧 / 感激
街坊对老陈家的看法

Economy / Pressure System:
粮价上涨、商队迟到、家庭粮食不足

Institution System:
地方守卫、市场秩序、债务规则

Action System:
给食物、询问、举报、查看痕迹、打听粮价

Fact System:
陈米拿过发霉麦子
玩家是否帮助
玩家是否举报

Memory / Rumor:
陈米记住玩家
街坊可能传言
守卫可能记录
```

---

## 29. 第七哨站如何映射到系统

第七哨站不是“另一个饥饿人物场景”。

它至少涉及：

```text
Region System:
北境边境，补给紧张，边境威胁存在

Location System:
第七哨站、厨房、哨墙、雾线巡逻路线、军医室、储物间

Entity System:
队长罗恩、新兵伊莱、厨子玛塔、军医赛拉、老兵霍克、玩家

Item / Material System:
口粮、口粮记录、军靴、巡逻灯、旧短刀、军徽

Trace System:
泥脚印、缺失记录、被翻动的储物柜、湿斗篷

Relationship System:
队长 / 新兵 / 战友 / 厨子 / 军医关系
玩家与伊莱信任
玩家与罗恩纪律关系

Institution System:
军纪、值岗责任、配给制度、上下级命令、处分制度

Economy / Pressure System:
口粮短缺、补给延迟、巡逻压力

Action System:
核对记录、私下询问、向上级报告、替人隐瞒、要求归还口粮、用值岗交换

Fact System:
伊莱是否私藏口粮
玩家是否报告
玛塔是否知情
罗恩是否处分

Memory / Rumor:
伊莱记住玩家是否帮他
小队流传玩家是否告密
罗恩记住玩家是否守纪律
```

第七哨站的行动必须来自制度和职责，而不是只来自饥饿状态。

---

## 30. 开发顺序调整

当前阶段不应继续扩地点内容。

推荐顺序：

```text
阶段 1：地点局面主界面原型
阶段 1.1：UI 小修
阶段 1.2：世界模拟系统架构整理
阶段 1.3：项目目录与系统骨架整理
阶段 1.4：Raw / Rule 原型
阶段 1.5：湖湾镇 + 第七哨站双场景 fixture 测试
阶段 2：湖湾镇最小状态闭环
阶段 3：第七哨站长期项目原型
```

也就是说，Raw / Rule 原型要服务于系统架构，而不是抢在系统架构之前。

---

## 31. 推荐项目目录

后续建议逐步整理为：

```text
chronicle-godot/data/sim/raw/
chronicle-godot/data/sim/fixtures/
chronicle-godot/data/sim/worlds/

chronicle-godot/scripts/sim/core/
chronicle-godot/scripts/sim/entity/
chronicle-godot/scripts/sim/state/
chronicle-godot/scripts/sim/relationship/
chronicle-godot/scripts/sim/item/
chronicle-godot/scripts/sim/location/
chronicle-godot/scripts/sim/institution/
chronicle-godot/scripts/sim/economy/
chronicle-godot/scripts/sim/action/
chronicle-godot/scripts/sim/fact/
chronicle-godot/scripts/sim/memory/
chronicle-godot/scripts/sim/rumor/
chronicle-godot/scripts/sim/narrative/
chronicle-godot/scripts/sim/chronicle/

chronicle-godot/tests/sim/
```

当前 `scripts/rebuild/` 可以保留作为 v5 原型目录。
等 `scripts/sim/` 骨架稳定后，再逐步迁移可复用内容。

---

## 32. 对 Codex 的后续要求

Codex 后续不应直接接到主界面继续加功能。

下一步 Codex 任务应是：

```text
整理项目系统骨架。
新增 sim 目录。
建立各系统 README 或空骨架脚本。
不迁移复杂逻辑。
不新增玩法内容。
不扩展湖湾镇按钮。
```

然后再实现 Raw / Rule 原型。

---

## 33. 成功标准

这套架构成功的标志不是文档变厚。

成功标志是：

```text
新增一个状态字段时，知道归哪个系统管理。
新增一个对象时，知道它是 Raw Definition 还是 Active Instance。
新增一个地点时，不需要手写按钮表。
新增一个规则时，可以知道它属于基础规则、领域规则，还是局面规则。
玩家行动后，结果能写入 Fact。
Fact 能驱动 Relationship、Memory、Rumor、Narrative、Chronicle。
第七哨站和湖湾镇能产生不同选择结构，而不是换皮。
```

---

## 34. 当前下一步

保存本文件后，下一步不应直接做 Raw / Rule 原型。

下一步应该写每日执行指令：

```text
2026-06-22.2 指令：v5 世界模拟系统骨架整理
```

该指令应要求 Codex：

```text
1. 阅读本架构文档。
2. 不改旧主界面。
3. 不新增玩法内容。
4. 新建 sim 系统目录。
5. 为各系统建立 README 或最小脚本骨架。
6. 标明每个系统职责、输入、输出。
7. 保留当前 rebuild 原型。
8. 写报告。
```

完成系统骨架整理后，再进入：

```text
Raw Object + Rule Prototype
```

---

## 35. 一句话总结

Chronicle 的世界不是由地点按钮堆出来的。

它应该由：

```text
细胞：状态、数值、标签、事实
组织：人物、物品、痕迹、关系、记忆
器官：地点、家庭、店铺、小队、商队、装备组
系统：经济、关系、行动、事实、传闻、长期项目、纪事
世界：所有系统持续运行后的历史
```

共同构成。

玩家看到的选择，只是这个人体表面浮现出的神经反应。
真正重要的是身体内部的结构、血液循环和系统联动。

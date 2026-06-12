# 世界引擎改造报告（本轮）

## 目标
本轮按你的 5 个任务做了“世界自运转 + 因果链 + 回响穿透 + 系统互联 + 框架整合”的落地改造，核心代码集中在：
- `scripts/gen/world_generation.gd`

## 1) 世界自运转机制（资源/势力/生态/地区）

### 新增世界状态容器
- `world_regions`: 区域级动态状态（食物/木材/水源/植物/动物/污染/危险/冲突/神秘/控制势力/邻接）
- `world_factions`: 势力级动态状态（力量/经济/攻击性/合法性/关系网/控制区）
- `world_news_queue`: 世界态势新闻队列
- `world_reaction_queue`: 世界反应事件队列（可自动弹出决策）
- `world_reaction_tickets`: 世界反应事件上下文

### 初始化
- 新增 `_ensure_world_sim_init()`：
  - 从 `region_index.json` 读取区域
  - 推断区域标签与邻接
  - 初始化区域资源/生态/冲突状态
  - 初始化势力基础盘面并重建领土
- 在 `bootstrap()` 中接入世界状态初始化。

### 时间推进驱动自运转
- 在 `_survival_tick()` 每小时迭代中接入 `_world_tick_hour()`。
- `_world_tick_hour()` 内部：
  - 每 2h：`_world_evolve_regions()`（资源增减、生态修复/衰退、污染/危险/冲突演化）
  - 每 6h：`_world_evolve_factions()`（经济/力量/合法性/攻击性变化、关系漂移、摩擦升级）
  - 每 6h：`_world_maybe_queue_reactions()`（自动生成世界态势抉择）
  - 持续：`_world_sync_global_arc()`（将世界态势回写全局 Arc）

## 2) 世界状态与玩家决策因果链

### 玩家行动写入世界长期状态
- 新增 `_world_apply_player_action()`，并在系统行动中接入：
  - `sys.forage / sys.hunt / sys.rest / sys.meditate / sys.trade / sys.push / sys.scout / sys.leverage / sys.reroute / sys.deep_echo / sys.travel`
- 效果示例：
  - 采集会降低区域生态储备并提高污染
  - 狩猎会改变动物与危险结构
  - 交易/施压会改变势力经济与关系
  - 深回响会提高神秘涨潮压力

### 模块与线程结果写入世界
- 新增 `_world_apply_module_outcome()`：
  - 局势模块成功/失败不再只改文本与计数器，会改区域资源/冲突/势力关系。
- 新增 `_world_apply_thread_outcome()`：
  - 线程收束/失败会改变区域冲突、生态、神秘、势力关系。

## 3) 回响系统穿透增强

### 从“文本回响”到“状态回响”
- 回响不仅写 `echo_log`，还会：
  - 触发区域状态变化（冲突、危险、资源、神秘）
  - 改变势力关系
  - 推动世界反应事件队列

### 新世界反应事件系统（自动弹出）
- 新增 `_maybe_offer_world_reaction_choice()`：自动弹出世界态势抉择（无需手动翻按钮）。
- 新增 `_apply_world_reaction_action()`：处理世界抉择并应用：
  - 玩家资源成本（金币/口粮/理智）
  - 区域状态 delta
  - 势力属性 delta
  - 势力关系 delta
  - 线索计数变化
- 支持事件类型：资源紧缩、生态恶化、边境升温、神秘涨潮等。

## 4) 系统间深度交互

### 交互链条
- 区域资源与生态 -> 影响势力经济与攻击性
- 势力关系恶化 -> 触发边境摩擦与区域冲突升高
- 区域冲突/污染/危险 -> 反向恶化资源与生态
- 聚合世界态势 -> 回写 `global_arc`（danger/war/scarcity/order/mystic）
- `global_arc` 与区域态势共同影响：
  - 局势模块权重（`_module_weight`）
  - 全局事件触发（`_run_global_state_event`）
  - 张力推进（`_current_tension`）

## 5) 与现有框架整合

### 主循环接线
- `produce_snapshot()` 中新增：
  - 世界反应抉择优先弹出
  - 世界新闻弹出（非纯文本空转）

### 系统动作接线
- `apply_system_choice()` 新增 `sys.world.*` 路由，处理世界反应选择。

### 效果系统扩展
- `_apply_effects()` 新增支持：
  - `world_region_delta`
  - `world_faction_delta`
  - `world_relation_add`

### UI可见性增强（不改布局）
- `get_feedback_panel()` 增加世界态势摘要（当前辖区、域压、资源/生态/冲突摘要）。
- `get_player_panel()` 增加世界字段（控制势力、区域冲突/危险/资源）。

## 关键结果
- 世界现在可在无玩家干预时持续演化（资源/生态/势力/冲突）。
- 玩家选择可改变长期世界结构，不再只影响短文本。
- 回响可穿透到世界状态并在未来形成新抉择。
- 事件生成权重受到世界状态驱动，减少“回到起点”感。

## 仍需后续迭代（客观）
- 当前势力与区域数量受现有数据规模限制，复杂战争格局深度仍有限。
- 世界反应模板已可用，但文案与分支数量还可继续扩充。
- 还未做自动化回归测试（需在 Godot 运行环境内跑完整体验回放）。

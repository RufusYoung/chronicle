# Chronicle 核心系统最小 Schema 草案 v5.1

日期：2026-08-12

状态：阶段 5.5 步骤 1 草案，供步骤 2 实现

关联审计：`CHRONICLE_CORE_SYSTEM_CONTRACT_AUDIT_v5.1.md`

## 1. 目的与约束

本文件定义足以支撑湖湾镇、第一冬、存档和后续阶段结算的最小数据合同。它不是完整数值设计，也不要求现在制作完整天赋树、技能树、装备库或动态市场。

所有 schema 遵守以下约束：

1. Raw Definition 与 World Instance 分离。
2. 每个运行实例拥有稳定且唯一的实例 ID。
3. 跨系统只通过稳定 ID 引用，不复制对方数据。
4. 所有运行变化都通过 `TransactionResult` 提交。
5. 所有持久变化必须有 `source_fact_ids` 或系统来源。
6. Snapshot、Inventory、MarketStock、角色面板都是只读投影。
7. UI 只提交行动或选择，不直接修改 Store。
8. 本草案中的 JSON 是规范示例，不是可直接载入的完整内容。

## 2. 命名和版本规则

### 2.1 ID 类别

| 字段 | 作用 | 示例 |
| --- | --- | --- |
| `*_def_id` | 引用不可变 Raw Definition | `skill.scouting` |
| `*_instance_id` | 引用某个世界中的运行实例 | `item.w1.000042` |
| `entity_id` | 世界实体身份 | `player`、`captain_ron` |
| `fact_id` | 已发生事实身份 | `fact.w1.000918` |
| `transaction_id` | 一次原子事务身份 | `tx.w1.000311` |
| `world_id` | 世界或存档谱系身份 | `world.516.a` |

ID 一经进入正式存档不得复用。显示名、标签和语言文本变化不得改变 ID。

### 2.2 Schema 版本

顶层存档使用整数 `schema_version`。当前实现目标从 `1` 开始。

Definition 可以单独拥有整数 `definition_version`，用于内容迁移与兼容检查。

运行实例不各自保存 schema 版本；它们由所属 SaveEnvelope 统一解释。只有需要独立迁移的外部资源才增加版本字段。

### 2.3 时间引用

统一使用：

```json
{
  "day": 12,
  "hour": 18,
  "tick": 402
}
```

`tick` 是同一世界中的单调递增序号，用于排序同一小时内发生的事务。需要完整时间的实例优先引用生成它的 `fact_id`，避免在每个系统复制时间文本。

## 3. Definition 层

### 3.1 通用 Definition 头

```json
{
  "def_id": "trait.twisted_ankle",
  "definition_version": 1,
  "display_name_key": "trait.twisted_ankle.name",
  "description_key": "trait.twisted_ankle.description",
  "tags": ["physical", "injury", "temporary"]
}
```

正式定义中的文学文本使用本地化 key 或专门叙事模板，不让底层规则依赖显示文本。

### 3.2 StateDef

```json
{
  "state_def_id": "state.character.perception",
  "key": "perception",
  "owner_kinds": ["character"],
  "value_type": "int",
  "default": 5,
  "minimum": 0,
  "maximum": 20,
  "allowed_operations": ["set", "add"],
  "persistence": "save",
  "ui_visibility": "summary"
}
```

`StateDef` 必须定义：

- 哪类实体可以拥有该字段；
- 值类型与范围；
- 允许的写入操作；
- 是否进入存档；
- 是否允许进入玩家可见解释。

### 3.3 TalentDef

```json
{
  "talent_def_id": "talent.night_adapted_eyes",
  "definition_version": 1,
  "display_name_key": "talent.night_adapted_eyes.name",
  "tags": ["innate", "perception", "night"],
  "granted_affordance_tags": ["observe_in_dim_light"],
  "modifiers": [
    {
      "modifier_id": "night_observation_risk",
      "target": "action.risk",
      "operation": "add",
      "value": -1,
      "when": [{"kind": "context_tag", "tag": "dim_light"}]
    }
  ]
}
```

TalentDef 不包含拥有者。它只说明天赋的规则含义。

### 3.4 TraitDef

```json
{
  "trait_def_id": "trait.twisted_ankle",
  "definition_version": 1,
  "display_name_key": "trait.twisted_ankle.name",
  "tags": ["physical", "injury", "recoverable"],
  "stage_order": ["fresh", "recovering", "healed"],
  "modifiers": [
    {
      "modifier_id": "long_travel_risk",
      "target": "action.risk",
      "operation": "add",
      "value": 2,
      "when": [{"kind": "action_tag", "tag": "long_travel"}]
    }
  ],
  "terminal_stages": ["healed"]
}
```

### 3.5 MarkDef

```json
{
  "mark_def_id": "mark.mist_salt_echo",
  "definition_version": 1,
  "display_name_key": "mark.mist_salt_echo.name",
  "tags": ["experience", "anomaly", "persistent"],
  "stages": [
    {"stage_id": "faint", "threshold": 1},
    {"stage_id": "resonant", "threshold": 4}
  ],
  "accepted_fact_types": [
    "actor_acquired_mist_salt_echo",
    "actor_endured_mist_salt_resonance"
  ],
  "modifiers": [],
  "granted_affordance_tags": ["recognize_mist_salt_resonance"]
}
```

印记阶段由进度和事实推导，不能由 UI 直接设置。

### 3.6 SkillDef

```json
{
  "skill_def_id": "skill.scouting",
  "definition_version": 1,
  "display_name_key": "skill.scouting.name",
  "tags": ["fieldcraft", "observation"],
  "rank_thresholds": [0, 20, 60, 140, 300],
  "accepted_practice_fact_types": [
    "actor_completed_patrol",
    "actor_inspected_trace",
    "actor_learned_from_failed_search"
  ]
}
```

### 3.7 ItemDef

```json
{
  "item_def_id": "item.waxed_winter_cloak",
  "definition_version": 1,
  "display_name_key": "item.waxed_winter_cloak.name",
  "item_kind": "equipment",
  "tags": ["clothing", "winter", "water_resistant"],
  "stackable": false,
  "max_stack": 1,
  "base_mass": 2.4,
  "equip_slots": ["body_outer"],
  "capabilities": ["equip", "trade", "repair"],
  "durability": {"maximum": 100},
  "modifiers": [
    {
      "modifier_id": "cold_exposure_risk",
      "target": "action.risk",
      "operation": "add",
      "value": -2,
      "when": [{"kind": "context_tag", "tag": "freezing"}]
    }
  ],
  "base_value": 24
}
```

### 3.8 EquipmentSlotDef

```json
{
  "slot_def_id": "slot.body_outer",
  "definition_version": 1,
  "display_name_key": "slot.body_outer.name",
  "accepts_item_tags_any": ["clothing", "armor_outer"],
  "exclusive_group": "body_outer"
}
```

## 4. 角色运行实例

### 4.1 CharacterProgress 只读投影

`CharacterProgress` 不是独立可写 Store。它是角色状态和角色特征 Store 的聚合读取面：

```json
{
  "entity_id": "player",
  "attributes": {
    "strength": 7,
    "dexterity": 8,
    "wisdom": 9,
    "charisma": 6,
    "constitution": 8,
    "perception": 10
  },
  "talent_assignment_ids": ["talent_assignment.w1.0001"],
  "trait_instance_ids": ["trait_instance.w1.0042"],
  "mark_instance_ids": ["mark_instance.w1.0007"],
  "skill_progress_ids": ["skill_progress.w1.player.scouting"]
}
```

来源：

- `attributes` 从 `StateStore` 读取；
- 其余数组从角色特征 Store 按 `owner_entity_id` 查询。

### 4.2 TalentAssignment

```json
{
  "talent_assignment_id": "talent_assignment.w1.0001",
  "talent_def_id": "talent.night_adapted_eyes",
  "owner_entity_id": "player",
  "status": "active",
  "source_kind": "character_creation",
  "source_fact_ids": [],
  "assigned_tick": 0
}
```

约束：

- 同一角色默认不能重复拥有同一个 TalentDef。
- 游戏中授予或移除天赋必须由明确系统权限和事实支持。
- 普通阶段奖励不得直接创建天赋。

### 4.3 TraitInstance

```json
{
  "trait_instance_id": "trait_instance.w1.0042",
  "trait_def_id": "trait.twisted_ankle",
  "owner_entity_id": "player",
  "stage_id": "fresh",
  "severity": 2,
  "status": "active",
  "source_fact_ids": ["fact.w1.000918"],
  "created_tick": 281,
  "updated_tick": 281,
  "recovery_progress": 0
}
```

约束：

- `source_fact_ids` 至少一个，除非来源是角色生成或存档迁移。
- 是否允许同定义多实例由 TraitDef 指定；伤势通常允许不同部位多实例。
- `status = resolved` 后保留实例或写入历史事实，不能无痕删除。

### 4.4 MarkInstance

```json
{
  "mark_instance_id": "mark_instance.w1.0007",
  "mark_def_id": "mark.mist_salt_echo",
  "owner_entity_id": "player",
  "progress": 1,
  "stage_id": "faint",
  "status": "active",
  "source_fact_ids": ["fact.w1.000932"],
  "progress_events": [
    {"fact_id": "fact.w1.000932", "delta": 1}
  ],
  "created_tick": 296,
  "updated_tick": 296
}
```

约束：

- 每次进度变化必须引用一个被 MarkDef 接受的事实。
- `stage_id` 由 progress 与 MarkDef 阈值计算，Store 不接受任意阶段写入。
- 同一事实不能为同一印记重复贡献进度。

### 4.5 SkillProgress

```json
{
  "skill_progress_id": "skill_progress.w1.player.scouting",
  "skill_def_id": "skill.scouting",
  "owner_entity_id": "player",
  "practice_xp": 27,
  "rank": 1,
  "source_fact_ids": ["fact.w1.001003", "fact.w1.001026"],
  "practice_events": [
    {"fact_id": "fact.w1.001003", "xp": 8},
    {"fact_id": "fact.w1.001026", "xp": 5}
  ],
  "updated_tick": 348
}
```

约束：

- rank 由 SkillDef 阈值推导，不单独自由写入。
- 每个事实对同一技艺最多结算一次。
- 训练、实战、失败复盘可以使用不同 xp 规则，但都必须来自事实。

## 5. 物品、库存与装备

### 5.1 HolderRef

物品位置使用一个统一引用：

```json
{
  "kind": "entity",
  "id": "player"
}
```

允许的最小 kind：

- `entity`：角色、商人或机构持有；
- `location`：放置在地点；
- `container`：位于另一个物品实例内；
- `escrow`：交易预留，不能同时使用；
- `destroyed`：已消耗或销毁，只保留审计信息。

“已装备”不是 holder kind。装备物仍由角色持有，装备位通过 `EquipmentLoadout` 引用该实例。

### 5.2 ItemInstance

```json
{
  "item_instance_id": "item.w1.000042",
  "item_def_id": "item.waxed_winter_cloak",
  "holder": {"kind": "entity", "id": "player"},
  "quantity": 1,
  "condition": {
    "durability": 83,
    "maximum_durability": 100,
    "quality": "serviceable"
  },
  "custom_tags": ["issued_by_seventh_outpost"],
  "provenance": {
    "created_by_fact_id": "fact.w1.000104",
    "parent_item_instance_ids": [],
    "original_owner_entity_id": "seventh_outpost"
  },
  "history": [
    {
      "event_id": "item_event.w1.000073",
      "event_type": "transferred",
      "fact_id": "fact.w1.000104",
      "transaction_id": "tx.w1.000038"
    }
  ],
  "created_tick": 18,
  "updated_tick": 18
}
```

约束：

- `quantity >= 1`，除非 holder 为 `destroyed`。
- 非堆叠物品 `quantity` 永远为 1。
- 有独立耐久、词条、来源或历史的物品不能合并堆叠。
- holder 改变必须同时写入历史并生成事实。
- ItemStore 拒绝引用不存在的 Definition、Entity、Location 或 Container。

### 5.3 堆叠拆分与合并

消耗或转移部分数量时使用显式操作：

```json
{
  "operation": "split_stack",
  "item_instance_id": "item.w1.ration_stack.1",
  "quantity": 2,
  "new_item_instance_id": "item.w1.ration_stack.9",
  "new_holder": {"kind": "entity", "id": "player"},
  "source_fact_ids": ["fact.w1.trade.77"]
}
```

合并只允许：

- `item_def_id` 相同；
- condition 与 custom tags 兼容；
- 没有需要独立保存的历史；
- 合并后不超过 `max_stack`。

### 5.4 EquipmentLoadout

```json
{
  "entity_id": "player",
  "slots": {
    "body_outer": "item.w1.000042",
    "main_hand": "item.w1.000057",
    "utility": null
  },
  "updated_tick": 351
}
```

约束：

- 每个 slot 必须存在于 EquipmentSlotDef。
- 被引用物品必须由该角色持有。
- ItemDef 必须允许该 slot。
- 同一物品不能占用互斥槽，除非 Definition 明确声明多槽占用。
- 转移、销毁或完全损坏已装备物品时，事务必须同时解除装备。

### 5.5 InventoryView

```json
{
  "owner_entity_id": "player",
  "item_instance_ids": ["item.w1.000042", "item.w1.ration_stack.9"],
  "total_mass": 4.8
}
```

这是按 holder 查询的只读结果，不进入存档，不接受修改操作。

## 6. 市场与交易

### 6.1 MarketPolicy

商人或商店实体可以引用一个定义化政策：

```json
{
  "market_policy_id": "market_policy.lake_town_grain_shop",
  "seller_entity_id": "old_chen",
  "accepted_currency_item_def_ids": ["item.copper_coin"],
  "sellable_item_tags_any": ["food", "grain"],
  "buyable_item_tags_any": ["food", "grain", "container"],
  "base_markup": 0.15,
  "pressure_bindings": [
    {
      "pressure_type": "food_pressure",
      "price_factor_per_point": 0.04
    }
  ]
}
```

Policy 是定义或稳定配置，不保存当前商品数量。

### 6.2 MarketStockView

```json
{
  "seller_entity_id": "old_chen",
  "offers": [
    {
      "item_instance_id": "item.w1.grain_stack.4",
      "available_quantity": 6,
      "unit_price": {
        "currency_item_def_id": "item.copper_coin",
        "quantity": 3
      },
      "price_explanation": [
        {"source": "base_value", "delta": 0},
        {"source": "pressure.food_pressure", "factor": 1.2},
        {"source": "relationship.trust", "factor": 0.95}
      ]
    }
  ]
}
```

该视图每次从实际物品、MarketPolicy、PressureStore、关系、制度和时间生成，不进入存档。

### 6.3 TradeIntent

```json
{
  "buyer_entity_id": "player",
  "seller_entity_id": "old_chen",
  "item_instance_id": "item.w1.grain_stack.4",
  "quantity": 2,
  "quoted_unit_price": {
    "currency_item_def_id": "item.copper_coin",
    "quantity": 3
  }
}
```

Resolver 必须在执行时重新验证库存、价格、营业状态和买方支付能力。过期报价不能直接落地。

一次成功交易至少原子写入：

- 商品实例的拆分或 holder 变化；
- 货币实例的拆分或 holder 变化；
- 交易事实；
- 必要的关系、压力、Exchange 或 Obligation 变化；
- 双方可见的结果解释。

## 7. 通用 Requirement、Modifier 与 Effect

### 7.1 Requirement

```json
{
  "requirement_id": "req.scouting_or_perception",
  "mode": "any",
  "conditions": [
    {
      "kind": "attribute",
      "subject": "actor",
      "key": "perception",
      "operator": "gte",
      "value": 10
    },
    {
      "kind": "skill_rank",
      "subject": "actor",
      "skill_def_id": "skill.scouting",
      "operator": "gte",
      "value": 1
    }
  ],
  "visibility": "always_explain"
}
```

第一批必须支持的 condition kind：

- `attribute`
- `state`
- `talent`
- `trait`
- `mark_stage`
- `skill_rank`
- `item_owned`
- `item_equipped`
- `relationship_axis`
- `fact_exists`
- `memory_exists`
- `pressure`
- `context_tag`
- `world_time`

Requirement 只判断资格，不直接修改结果。

### 7.2 Modifier

```json
{
  "modifier_id": "mod.winter_cloak_patrol_risk",
  "source_ref": {
    "kind": "item_instance",
    "id": "item.w1.000042"
  },
  "target": "action.risk",
  "operation": "add",
  "value": -2,
  "when": [
    {"kind": "action_tag", "tag": "cold_exposure"}
  ],
  "explain_key": "modifier.winter_cloak_reduces_cold_risk"
}
```

统一执行顺序：

1. `set_base`
2. `add`
3. `multiply`
4. `clamp`
5. 领域最终取整

同阶段修正按稳定 `modifier_id` 排序，避免存档载入后结果漂移。

### 7.3 Effect

```json
{
  "effect_id": "effect.consume_ration",
  "operation": "item_consume",
  "target": {"kind": "owned_item_by_tag", "owner": "actor", "tag": "ration"},
  "quantity": 1,
  "fact_template_id": "fact.actor_consumed_ration"
}
```

第一批 effect operation：

- `state_set`
- `state_add`
- `fact_add`
- `memory_add`
- `relationship_add`
- `pressure_add`
- `trait_add`
- `trait_advance`
- `mark_progress_add`
- `skill_practice_add`
- `item_create`
- `item_transfer`
- `item_consume`
- `item_condition_add`
- `item_history_add`
- `equipment_set`
- `equipment_clear`
- `obligation_add`
- `exchange_add`
- `deferred_add`

所有 Effect 先解析为 TransactionResult 中的显式 change，再统一预检和写入。

## 8. TransactionResult v2 草案

```json
{
  "transaction_id": "tx.w1.000311",
  "transaction_schema_version": 2,
  "actor_entity_id": "player",
  "source_action_id": "repair_east_wall",
  "contract_status": "resolved",
  "facts_added": [],
  "state_changes": [],
  "relationship_changes": [],
  "memories_added": [],
  "traces_added": [],
  "rumors_added": [],
  "pressure_changes": [],
  "trait_changes": [],
  "mark_changes": [],
  "skill_changes": [],
  "item_changes": [],
  "equipment_changes": [],
  "obligation_changes": [],
  "exchange_changes": [],
  "deferred_changes": [],
  "chronicle_entries_added": [],
  "narrative_result": {}
}
```

清理规则：

- 删除 `facts`、`memories`、`traces`、`rumors` 别名。
- 删除未接入 writer 的 `region_changes`，地区变化改用实体 `state_changes`。
- 所有 change 必须有 operation、目标和来源。
- 写入前验证全部 Definition、Instance、Entity、Fact 和 Slot 引用。
- 任何一项无效则整笔事务失败，Store 不发生变化。

## 9. SaveEnvelope v1

```json
{
  "schema_version": 1,
  "save_id": "save.2026-08-12.001",
  "world_id": "world.516.a",
  "build_id": "chronicle-v5.5-contract-1",
  "created_at_utc": "2026-08-12T10:00:00Z",
  "saved_at_utc": "2026-08-12T12:30:00Z",
  "source_kind": "player_save",
  "world_time": {"day": 12, "hour": 18, "tick": 402},
  "rng_states": {},
  "session": {
    "actor_entity_id": "player",
    "current_location_id": "outpost_courtyard",
    "active_life_project_id": "life_project.seventh_outpost_first_winter",
    "life_project_runtime": {
      "current_day": 5,
      "status": "active"
    }
  },
  "stores": {
    "entities": {},
    "states": {},
    "facts": {},
    "memories": {},
    "relationships": {},
    "traces": {},
    "rumors": {},
    "pressures": {},
    "obligations": {},
    "exchanges": {},
    "deferred_consequences": {},
    "character_features": {},
    "items": {},
    "equipment_loadouts": {},
    "chronicle_entries": {},
    "investigation_leads": {}
  },
  "definition_manifest": {
    "content_pack_id": "chronicle.base",
    "content_pack_version": 1,
    "required_definition_ids": []
  },
  "integrity": {
    "payload_hash": "sha256-placeholder"
  }
}
```

### 9.1 进入存档

- 世界和会话身份；
- 世界时间与所有影响确定性的 RNG 状态；
- 当前地点和长期项目 runtime；
- 所有运行 Store；
- Definition 清单与内容包版本；
- schema 版本和完整性摘要。

### 9.2 不进入存档

- Snapshot；
- 当前行动候选；
- InventoryView；
- MarketStockView；
- UI 展开状态、滚动位置和临时提示；
- 测试 runner 的断言状态；
- 可由事实和 Store 重建的摘要缓存。

### 9.3 测试注入隔离

`source_kind` 允许：

- `player_save`
- `test_fixture`
- `migration_fixture`

正式 UI 只加载 `player_save`。测试 fixture 可以缺少某些生产元数据，但必须通过同一引用校验，不能被误写成玩家存档。

## 10. 引用完整性

载入或提交事务时至少验证：

1. 所有 Definition 引用存在且 kind 正确。
2. 所有 Entity、Item、Fact、Location 和 Slot 引用存在。
3. holder 为 container 时不存在循环包含。
4. 已装备物品由装备者持有且槽位兼容。
5. Mark 和 Skill 的来源事实类型被对应 Definition 接受。
6. Memory 引用的事实存在，或明确标记为误传、想象或错误记忆。
7. Chronicle 引用的事实、关系、物品和人物存在。
8. 事务不会让堆叠数量、耐久、健康或定义范围越界。
9. 所有稳定 ID 唯一。
10. schema 迁移完成后不得残留未知必需字段。

## 11. 迁移顺序

步骤 2 实现时按以下顺序迁移，减少一次性改动：

1. 实现 Definition 注册、ID 与 schema 校验。
2. 将 EntityStore 接入 SimSession，并让实体身份与可变状态分别只由 EntityStore 和 StateStore 持有。
3. 为现有 Store 明确序列化边界；正式 `to_save_data()` 与 `load_save_data()` 在步骤 4 接入。
4. 引入角色特征 Store 和只读 CharacterProgress 投影。
5. 把 `mist_salt_echo` 迁成 MarkInstance，把一个伤势迁成 TraitInstance。
6. 扩展 ItemStore 的 holder、quantity、transfer、consume 与 durability。
7. 将 `inventory_item_ids` 读取改为 owner 查询，并删除双写。
8. 引入 EquipmentStore 和三个最小槽位。
9. 生成 InventoryView 与 MarketStockView，不保存它们。
10. 接入通用 Requirement、Modifier 与 Effect。
11. 实现 SaveEnvelope、迁移注册表和往返一致性测试。

## 12. 最小验收 fixture

步骤 2 至 4 应共同维护一个小型合同 fixture，至少包含：

- 两名角色拥有同一个冬衣 ItemDef 的不同实例；
- 两件冬衣耐久、来源和历史不同；
- 一份可拆分的口粮堆叠；
- 一项可恢复伤势 TraitInstance；
- 同一个雾盐 MarkDef 由不同事实集合形成的两个实例样例；
- 一项侦察 SkillProgress；
- 三个装备位；
- 一个商人持有的真实商品堆叠；
- 一笔成功交易与一笔因报价过期而失败的交易；
- 保存、载入后完全相同的行动候选与修正解释。

验收不依赖新增地点剧情。优先复用湖湾镇和第七哨站第一冬。

## 13. 尚未在本草案裁定的内容

以下内容需要更多玩法证据，暂不进入最小实现：

- 装备随机词条生成算法；
- 完整负重与体积模拟；
- 多币种汇率；
- 拍卖、远期合约和复杂金融；
- 技艺专精树；
- 天赋遗传与重塑；
- 印记冲突和融合；
- 完整战斗伤害公式；
- 大规模市场供需模拟。

这些功能以后必须扩展现有 Definition、Instance、Requirement、Modifier、Effect 和 SaveEnvelope，不得另起平行底层。

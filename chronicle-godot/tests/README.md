# Tests

`project_cleanup_smoke.gd` 是项目清理后的无头冒烟测试。

它会加载当前主场景，并验证：

- 主界面能够实例化
- 继续按钮可用
- 行动选择能够进入多阶段流程
- 重新开始能够创建新世界实例
- 新旅程能够创建新世界实例

运行示例：

```powershell
godot_console --headless --path . --script res://tests/project_cleanup_smoke.gd
```

`world_sim_lead_adapter_test.gd` 会运行两组固定种子的 30 天模拟，验证：

- `LeadCandidate` 可稳定适配为 v0.3 四类线索字典
- 世界原因和关联事实不会丢失
- 同 seed 结果可复现
- 第 3 天测试注入会改变后续适配线索签名
- 适配过程不会创建世界事实或新候选线索

运行示例：

```powershell
godot_console --headless --path . --script res://tests/world_sim_lead_adapter_test.gd
```

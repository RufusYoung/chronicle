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

# AI 后台游玩接口 v1

更新于 2026-09-05。入口为本地、单进程、单调用方的调试与代理游玩接口，不监听网络端口，不需要屏幕、鼠标、Godot 编辑器或在线模型服务。AI 根据每次返回的观察选择下一步，游戏规则仍由正式 Godot 会话执行。

## 开始使用

环境为 Godot 4.6.3 与 Python 3。Windows 默认查找已安装的 `Godot_v4.6.3-stable_win64_console.exe`；其他路径可以设置 `CHRONICLE_GODOT` 环境变量或传 `ChronicleClient(godot=...)`。本轮已验证 Windows；其他平台分支尚未实机验收。

从 Godot 子项目目录运行 Python，在 `tools` 路径导入客户端：

```python
import sys
sys.path.insert(0, "tools")
from agent_play import ChronicleClient

with ChronicleClient() as game:
    result = game.request("start", mode="play", scenario="echo_realm", seed=81001)
    print(result["observation"])
    choices = [row for row in result["choices"] if row["enabled"]]
    # An AI should choose using the returned cost, hint, tradeoff and current situation.
    choice = next(row for row in choices if row["kind"] == "wait")
    result = game.request("act", choice_id=choice["choice_id"])
    print(result["receipt"], result["observation"]["feedback"])
    game.request("save", slot="my_run", overwrite=True)
```

也可运行 `python tools/agent_play.py`，向它的标准输入逐行发送 JSON。客户端自动补入协议版本、请求编号、会话身份与当前修订号，标准输出逐行返回 JSON。输入 EOF 会关闭它拥有的 Godot 进程。

H1 已增加发布包入口，直接启动 `Chronicle.exe --headless -- --agent-stdio`，使用同一帧协议和控制权限。Python 调用 `ChronicleClient(godot=r"C:\code\game\chronicle\builds\h1-windows\Chronicle.exe", packaged=True)`，或 CLI 加 `--packaged --godot <exe>`；不会传入源码目录，不要求安装 Godot。发布包由 bootstrap 分派到同一个 stdio driver，不用编辑器的 `--script` 启动参数代替包内入口。

```jsonl
{"command":"start","mode":"world","scenario":"echo_realm","seed":81001}
{"command":"advance","hours":24}
{"command":"inspect","kind":"facts","offset":0,"limit":20}
{"command":"save","slot":"day_one"}
{"command":"observe"}
```

项目内 GDScript 可以直接 `preload("res://scripts/agent/agent_game_session.gd").new()`，读取 `hello()` 后调用 `handle(request)`。直接持有 GDScript 对象的同进程开发代码天然可以绕过公开约定，它不构成沙箱；需要检验代理是否遵守权限时使用进程协议，不给代理内部对象或任意文件编辑权。

## 两种模式

| 模式 | 可做的事 | 禁止与边界 |
| --- | --- | --- |
| `world` | 启动 `echo_realm` 或 `generated_network`、读时间与网络摘要、按页查事实/人物/物品/资源/承诺/交换、推进 1 至 24 小时、存读档 | 不提供角色行动，不接收状态改写。观察明确为 `omniscient_debug`，不得用这种信息冒充玩家已知。现有世界仍含被动旅人实体。 |
| `play` | 启动 `echo_realm`、`generated_network`、`lake_town` 或 `first_winter`；取得正式 ViewModel 同源内容与候选，执行行动、旅行、挑战、战斗、调查、回应、职责、成长、交易和旧生涯转换 | 不能全知查询、直接推进任意时长、指定骰点或注入 effects。等待也是候选动作，战斗中不提供等待。各场景只提供实际已有的功能。 |

`echo_realm` 是正式 UI 新世界默认入口，使用原设定回音港周边的两个生成小聚落。`region_map.canon` 是公开的历史地理背景，不是远方实时观察；世界模式在 `observation.canon` 返回同一背景。旧三镇保留 `generated_network`，协议默认值也保留兼容性；请显式指定新场景。设定目录包含六界域和 17 个主要势力，不代表它们都在运行模拟。

`generated_network` 已同时接入正式世界原型 UI 与代码入口，二者共用地点 ViewModel 的开局和行动规则；仍未完成有目标、经济生活和危险旅途的玩家人生开局。`region_map` 仅公开区域拓扑、种子、聚落名称、地形标签、道路时间和当前位置，不泄露远处人物库存或目标。湖湾镇和第七哨站保留为旧回归切片；旧生涯转换仍启动新夹具并携带部分状态，不能把它写成连续世界已经完成。

## 命令合同

所有请求包含 `protocol: 1`、`command`、长度 1 至 96 的字符串 `request_id`。除 `observe/inspect` 外，还必须携带握手提供的 `session_id` 与整数 `expected_revision`。

| 命令 | 参数与结果 |
| --- | --- |
| `start` | `mode` 默认 world，`scenario` 默认 generated_network，`seed` 默认 81001，取 1 至 2147483647 的整数。替换当前会话；非法配置保留旧会话。 |
| `observe` | 返回当前正式观察与候选，不推进时间、不消费 RNG。不包含完整 Stores、原始事务历史或存档内容。现场对象按稳定 ID 排序，候选按 choice_id 排序，不代表推荐顺序。 |
| `act` | 只能传当前候选的 `choice_id`。`enabled=false` 不能执行；成长与生涯转换还要求 `confirm: true`。配给交易每次买 1 份，价格来自当前正式报价，不能自报低价。 |
| `advance` | 仅 world 模式，`hours` 为 1 至 24 的整数，以全局范围调用正式时间推进。无需角色行动也会结算已有世界机制。 |
| `inspect` | 仅 world 模式。`kind` 为 facts/entities/resources/items/obligations/exchanges；`offset` 默认 0，`limit` 默认 20、最大 100。事实流分页保持追加顺序；其他集合分页仅在同一修订号内稳定。 |
| `save` | `slot` 为 1 至 48 位 ASCII 字母、数字、下划线或连字符。默认拒绝覆盖，覆盖须显式 `overwrite: true`。 |
| `load` | 仅从当前模式与开局档案自己的命名空间读 `slot`。原生存档验证成功后替换会话，失败不清空当前进度。读取后仍使用递增修订号。 |

响应 `ok` 表示本次命令成功与否；成功操作返回新 `observation`、`choices` 和 `receipt`。`receipt.cause` 区分 `agent_action`、`world_advance`、session_start/save/load。这里的 code_agent 是控制入口来源，不表示真实 UI 输入，也不表示新增内置 LLM 人物。

底层旧 ViewModel 的部分日志仍以玩家实体和界面来源命名。审计必须连同 API receipt 使用，不能只凭旧日志的 `source` 字符串判断真人操作；本轮未全局迁移历史事实命名。

### 重复与失败

- 每次接受的执行都增加 `revision`，包括开局、存读档及已进入正式结算后失败的操作。合法候选必须与读取时修订号匹配。
- 最近 32 个非只读请求缓存完整请求指纹与收据。同编号、同内容返回旧收据并标记 `replayed=true`；同编号改内容被拒绝。缓存只在当前进程有效；跨进程握手不同，过期请求不得重放。
- 重放返回的是原时刻收据，不是当前世界。需要最新情况时调用 `observe`。客户端不会因为旧收据而回退自己的修订号。
- 协议拒绝在执行前发生，返回 `rejected_before_execution=true`，不扣资源、不耗时。进入正式结算后的失败可能已有部分效果，返回 `partial_commit_possible=true`。不能假定失败等于回滚。
- 客户端一次只允许一个调用方顺序使用。超时默认 120 秒，可以显式调大；超时关闭所属进程，不自动重试。不得把超时的动作带到新进程再执行一遍，结果需从明确存档重新确认。
- 不保证任意长单次世界推进快速完成。30 日世界的逐步响应问题仍归 H1/B1 性能诊断，不通过静默跳过结算解决。

### 存档

写入 `user://agent_play/<mode>/<scenario>/<slot>.json`，不覆盖正式 UI 的存档槽。以原生 SaveEnvelope 保存 Stores、绝对时间、随机状态及 life-project runtime，再补入 `agent_control` 的表面反馈和模式元数据，统一重算原生完整性摘要。先写同目录临时文件，再重命名替换；写入失败不替换已有槽。

本接口存档可被原生服务理解，但本轮没有为人类 UI 增加这些槽的选择器，也没有提供任意 UI 存档导入命令。并发进程写同一槽没有跨进程锁，调用方应使用独立槽名。

原生 SaveEnvelope 有意采用较短 JSON 小数表示，以兼容早期 Godot 的摘要往返规则。例如资源比例 `0.7678571428571429` 在磁盘中成为 `0.767857142857143`。世界存档与续跑按原生存档精度验收，不承诺每个浮点数逐位相同；只读请求和同源行动对照仍使用完整精度比较，不能用存档精度掩盖行动差异。

## 进程协议

底层启动命令：

```text
Godot_v4.6.3-stable_win64_console.exe --headless --path chronicle-godot --script res://scripts/agent/agent_stdio_runner.gd
```

客户端到 Godot 的每帧为 **8 个 ASCII 十进制长度字节 + 相应长度的 UTF-8 JSON**，最大 65536 字节。它不是原始 JSONL。Godot 的响应为 `CHRONICLE_AGENT_JSON`、一个制表符、单行 JSON 和换行；其他 stdout 行属于引擎诊断。首条协议响应为 hello。关闭 stdin 表示结束，完整 EOF 正常退出；长度错误或残帧退出码 2。非法 JSON 返回错误后可接下一帧。

Windows 管道逐字节输入测试发现 Godot 4.6.3 的缓冲读取会把短读仍返回为请求大小，未按实际读取量缩短。已对照 [Godot 4.6.3 Windows 源码](https://github.com/godotengine/godot/blob/4.6.3-stable/platform/windows/os_windows.cpp#L1963) 核实；runner 在 Windows 逐字节拼成有上限的请求，避免把填充字节当作完整帧。中文只在帧收齐后解码，底层不以换行判断请求边界。

## 验证入口

```text
Godot_v4.6.3-stable_win64_console.exe --headless --path chronicle-godot --script res://tests/agent/agent_game_session_test.gd
python chronicle-godot/tools/test_agent_play.py
python chronicle-godot/tools/agent_smoke_play.py --days 3 --output <evidence-directory>
```

最后一项是有界脚本策略与无角色行为世界演算，输出逐步 JSONL 及汇总，不声称是模型自由探索、人工 UI 长测、参赛录屏或涌现质量验收。后台覆盖不能取代 H4 的真实界面试玩。

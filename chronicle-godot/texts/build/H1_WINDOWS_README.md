# Chronicle 北境三镇世界原型

这是 H1 内部运行包，用于检查世界、存档、区域视图和资产打包。它还没有足够的玩家行动、危险出行、声音和内容来构成参赛 Demo，不应对外宣传为完成版本。

## 启动与操作

在同一目录保留 Chronicle.exe 和 Chronicle.pck，双击 Chronicle.exe。无需安装 Godot 或 Python。

- 「现场」选择行动或旅行，按钮注明时间与已知代价。
- 「区域」查看聚落与道路示意；连线来自当前世界，道路图并非按比例地形图。
- 「角色」看属性；「记录」查看完整结果与世界信息。
- 现场结果右上角的「查看完整结果」可以直接打开记录，再用「返回现场」继续选择。
- 「保存」写入当前整个世界，覆盖已有存档时需要确认。
- 「读档」恢复保存时的状态，未保存行动会丢失；下一次启动也会继续这份存档。
- 「新世界」可输入种子，已有存档不自动覆盖；相同种子生成相同初始区域。
- 结算期间请等待提示，按钮暂时禁用；不需要反复点击。
- Esc 或关闭窗口会询问退出方式，可取消、保存并退出或退出而不保存。结算进行中会先等待完成。

存档位于 `%APPDATA%\Godot\app_userdata\CHRONICLE_GODOT\world_demo\manual.json`。退出前请手动保存，本版本没有自动存档。若读档失败，原文件会保留，屏幕显示错误；不要马上覆盖旧存档。

后台控制使用 `Chronicle.exe --headless -- --agent-stdio`，与源码代理入口共用协议，不使用桌面控制。可从源码仓库的 `tools/agent_play.py` 导入 `ChronicleClient(godot=<Chronicle.exe 绝对路径>, packaged=True)`；Python 只是测试客户端，正常游戏不需要 Python。代理存档与 UI 存档分属独立目录，不能直接互相加载。

## 现有边界

世界中有生成的居民、设施、资源、道路和组织。人物的日常活动与跨镇运输已经存在，但持续经济、玩家工作与危险旅途仍在开发。初始公共空间有时无人，不代表世界中没有居民；目前尚缺能自然引导玩家接触这些生活的行动。

苇岸地点画面由内置 imagegen 生成，属于静态美术样例，不代表画中人数、天气、船只或货物已被逐一模拟。其他地点未制作画面，不拿同一张图充当不同城镇。

Godot 图标尚未替换；可执行文件没有数字签名。此构建仅完成开发机冒烟，不代表所有 Windows 电脑兼容。没有录制参赛视频，也没有提交作品。

## 工具与第三方资料

使用 Godot 4.6.3 与 Compatibility 渲染。引擎及随附库版权见 GODOT_COPYRIGHT.txt；思源宋体许可见 SOURCE_HAN_SERIF_LICENSE.txt；地点画来源见 ASSET_PROVENANCE.md。备用素材库未纳入此构建。

源码中的全部正式美术集中在 `chronicle-godot/art/`，含目录说明、来源记录和校验清单；`art/reference/` 仅供查找备用素材，不进入运行包。本次整理没有新增画面或音效。

打包依据：[Godot Windows 导出说明](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_windows.html)。

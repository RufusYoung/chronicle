# Life in Adventure 临时授权素材

用户于 2026-09-28 在本项目对话明确确认已经拥有所供安装包内美术、代码与执行文本的使用授权，并要求临时复用、发布前替换。这里记录的是用户确认，不声称已独立审查授权文件。

- 来源：StudioWheel / Life in Adventure 1.2.23，本地 `base.apk.1`。
- APK SHA256：`4e1a32ed5c6d261a5def62de2a26bb9b37af752775ba82f47e12b2b0ff8e36d8`。
- 方法：UnityPy 读取 `assets/bin/Data/data.unity3d` 中选定 Sprite，原图导出 PNG；未运行 APK，未提取广告、支付、分析服务。
- 逐文件原对象名、path_id、尺寸和 PNG 哈希：`art/catalog.json` 中本目录的条目。
- 文件名保持对象 ID，避免误认作 Chronicle 原创。画面仅作临时插图，不把原作人物或地点变成 Chronicle 正史。
- 替换清单：本目录所有 `sprite_*.png` 均为待替换项；发布检查必须显式报告剩余项。删除任一临时素材前，先替换引用并更新目录。
- 当前只复用像素美术。APK 中的文本数据并不等于恢复了完整事件解释器，尚未迁移可执行商业代码。

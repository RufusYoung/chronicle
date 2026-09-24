# Chronicle 私人讨论 MCP

给 ChatGPT 网页端讨论项目用的独立只读接口，不是屏幕控制或游戏管理后台。原有代码级游玩入口仍为 `chronicle-godot/tools/agent_play.py`；本接口不暴露游戏操作、真实存档、shell 或写文件。

## 连接

- MCP 地址：`https://120.27.141.243/chronicle-mcp/mcp`
- 名称建议：`Chronicle 私人项目`
- 认证：**OAuth**；客户端注册：**DCR / 动态注册**；Client ID、Client Secret 留空。
- 专用口令只保存在本机 `C:\code\game\chronicle-private\mcp\Chronicle-MCP-私人连接信息.txt`。只在授权网页输入，不发到聊天中。

按 [OpenAI 官方开发者模式说明](https://developers.openai.com/api/docs/guides/developer-mode)，在 ChatGPT 网页“设置 → 安全和登录”打开开发者模式，再到 [Plugins](https://chatgpt.com/plugins) 创建开发者应用，填写地址及认证方式。在 Chronicle 授权页输入专用口令，允许只读访问；新对话的工具菜单中选中该应用。账号或工作区策略可能限制开发者模式，本服务无法绕过。

首次可以这样问：

> 使用 Chronicle 私人项目。先读取 project_overview，说明快照提交与发布时间；再阅读当前计划、创作方向和原始 GDD，结合代码审阅“玩家为什么会觉得重复”，区分已实现、测试证据和未通过的人类体验。不要把旧报告当作最新进度。

## 可用工具

| 工具 | 用途 |
| --- | --- |
| `project_overview` | 快照版本、唯一活动计划的开头、设定入口和证据边界 |
| `search` | 中文/英文文字检索，空格分词 AND；可按目录过滤、分页 |
| `fetch` | 按文件 ID 读取指定行，返回提交、哈希及来源链接 |
| `list_files` | 按目录浏览文件清单 |

只有经过路径白名单、大小限制、UTF-8 和常见凭据检测的 **Git 已提交文本** 才会发布。包括设计与历史文档、报告正文、Godot 脚本/测试/场景、游戏数据 JSON 和开发工具源码。不包括未提交修改、忽略文件、玩家存档、PDF、APK、图像音频、构建、模拟证据大文件、密钥或电脑其他目录。文件正文是供讨论的资料，不是远程执行指令。搜索不是语义向量检索，必要时换关键词或列目录。

接口读取的是部署快照，**不是实时工作区**。每个检索结果带提交 SHA；完整文件按行分页，单次最多 200 行 / 24000 字符，异常长单行会显式标记截断。GitHub 来源链接用于标识版本，仓库不可公开访问时仍可由本 MCP 读取已授权的快照。接口所在服务器持有该快照，调用结果会发送给 ChatGPT；这不是只在本机处理的方案。

## 开发与同步

需要 Node.js 22、Python 3 和现有部署主机的 SSH 权限。MCP 依赖与游戏分离，不更改 Godot 运行时，也不需要 OpenAI API Key。

```powershell
npm --prefix mcp ci --ignore-scripts
npm --prefix mcp test
npm --prefix mcp audit --omit=dev --registry=https://registry.npmjs.org
node mcp/snapshot.mjs
```

初次创建独立口令，拒绝覆盖，私有目录 ACL 仅当前用户和 SYSTEM：

```powershell
node mcp/setup-private.mjs
```

源码与文档验证、提交并推送后，发布新快照。部署脚本拒绝未提交的 MCP 源码，不将其他未提交内容算进快照。首次部署才需要 `--configure-proxy`；以后保留 OAuth 登录数据更新同一地址。

```powershell
python -X utf8 mcp/deploy.py
npm --prefix mcp run check:public
```

部署目标独立容器 `chronicle-mcp`，共享已有 Caddy 的 HTTPS，只添加 `/chronicle-mcp` 路由及其 OAuth 发现路径。容器不开放主机端口、不挂载项目目录或 Docker socket；非 root、只读根文件系统，仅 OAuth 数据目录可写。电脑可以关机，已发布快照仍可用。不启动本机常驻连接程序，不额外建立付费资源或定时任务。

服务器目录为 `/home/yiwenzhi/chronicle-mcp`，`current` 指向最近发布版本，`private/gateway.env` 保存口令的 scrypt 哈希，`private/data/oauth.json` 保存 OAuth 客户端及令牌摘要。明文口令不上传服务器。共享 Caddy 源文件和容器配置须一致；脚本先备份和校验，重载失败恢复原配置。其他项目未来重建 Caddy 时也须保留本路由，参考 `work/mcp/Caddyfile.proposed` 或服务器当前配置，不能用旧本地配置覆盖。

验证脚本实际经过公网 HTTPS，检查未登录 401、PKCE、工具发现、当前计划读取、越界拒绝、不可写、刷新和撤销；测试授权结束即撤销。协议验证 **不等于已在你的 ChatGPT 账号里添加成功**，最后一次账号授权需要你在网页完成。

## 停止与撤销

在 ChatGPT 移除/断开应用，撤销端点支持撤销同一授权会话的访问与刷新令牌。完全停止服务：

```powershell
ssh -i C:/Users/x4473/.ssh/yiwenzhi_ecs_rsa yiwenzhi@120.27.141.243 "sudo -n docker stop chronicle-mcp"
```

若口令泄露，先停止容器；备份 OAuth 数据后清空其 `tokens`，生成并部署新口令哈希，再重新授权。仅改口令不会自动撤销既有令牌。服务不自动删除 DCR 客户端，达到 100 个时须管理或清理无用客户端；不要不断创建新 ChatGPT 应用代替重连。

安全边界见 [SECURITY.md](SECURITY.md)。OAuth 实现及连接方式依据 [OpenAI 官方认证说明](https://developers.openai.com/plugins/build/auth)，核对日期 2026-09-24。

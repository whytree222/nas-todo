# 验证记录

本工程目前是源码交付。不能把“有构建脚本 / CI 配置”理解为“已经构建成功”。

| 项目 | 本次状态 |
| --- | --- |
| 客户端 Flutter 静态分析 | 尚未完成；本地 Flutter/Dart 工具环境受限 |
| 客户端 Flutter 测试 | 尚未完成；本地 Flutter/Dart 工具环境受限 |
| Dart 语法解析 | Tree-sitter 对 10 个 Dart 文件解析通过；不等于类型检查或 Flutter 编译 |
| 原生平台静态资源 | 7 个 XML 文件与 Windows 应用清单解析通过；Gradle wrapper JAR 完整，Windows ICO 头有效；未编译 |
| Android APK 构建 | 未执行，没有可交付 APK |
| Windows 原生构建 | 未执行，没有可交付 Windows 二进制 |
| 服务端 Python HTTP / SQLite 测试 | Python 3.12.14 下 18 项全部通过 |
| PowerShell 构建脚本 | 语法解析通过；用模拟 Flutter 验证检查顺序和错误时停止，未执行真实构建 |
| GitHub Actions 配置 | YAML 解析与任务关系检查通过，未实际运行 GitHub CI |
| Docker 镜像构建 / DX4600 部署 | 未在真实 NAS 上验证 |
| 安卓与 Windows 实机同步 | 未验证 |
| NAS ZeroTier 待办端口 | 已检查 `10.59.218.68:8787`，连接被拒绝（WinError 10061），尚未获得 `/health` 响应 |
| 手机外网 ZeroTier 同步 | 未验证；三台设备已加入同一网络，待启动待办服务后验证 |

已写出 19 个客户端集成测试和 4 个界面测试。集成测试会启动隔离的真实 Python 后端，覆盖离线保存、双端同步、冲突、响应丢失后重试及继续编辑、备份恢复、完成状态竞态与实例身份校验。测试代码存在并不表示本次已通过这些客户端测试。

本地尝试运行 Flutter/Dart 工具时，观察到 Dart runtime 报错 `Platform.resolvedExecutable` 为 null（Dart 3.13.5 环境）。该错误发生在工具启动阶段，导致 `flutter analyze`、`flutter test` 和原生构建未能执行；本记录不把它判定为客户端源码已知缺陷。平台目录依据 Flutter stable 3.47.6 的官方模板提供，仍需在正常 SDK 环境实际验证。

2026-10-09 部署跟进：用户提供的 NAS 日志确认 `todo-init` 已完成数据目录初始化；`todo-sync` 曾因 NAS 上的 `server/app.py` 读权限不足而重启。另行提供的 v3 私有部署配置将同一后端代码放进启动命令，移除程序文件挂载；本地确认该命令能够启动并初始化 SQLite。用户随后反馈部署已好，但健康检查和实机同步仍待明确验证。已为这个完成初始化的项目提供单容器运行配置，移除一次性初始化服务，以免 NAS 将正常退出的初始化容器标为异常。私有部署配置包含实际密钥，不属于本源码工程或 GitHub 上传内容。

用户已选择在自己的 GitHub 私有仓库使用 Actions 构建客户端。工作流已固定版本并通过静态检查，实际云端测试和构建结果将在工作流完成后更新；准备完成不代表构建成功。

需要安装可用的 Flutter stable、Python 3.12+ 与对应安卓 / Windows 编译工具，完成 `scripts/build.ps1` 和 [部署说明](DEPLOY-DX4600.md) 中的验收步骤，再把该工程用于长期保存真实待办。

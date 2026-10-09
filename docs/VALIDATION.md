# 验证记录

2026-10-09，GitHub Actions 运行 [37900998859](https://github.com/whytree222/nas-todo/actions/runs/37900998859) 的三个任务全部成功。构建对应代码提交 `bc35fc387f926ffb9370369974961cb257a0ceb2`，使用 Flutter stable 3.47.6 / Dart 3.13.5 / Python 3.12；Windows 使用 windows-2022。

| 项目 | 结果 |
| --- | --- |
| 服务端 HTTP / SQLite 测试 | GitHub Ubuntu 中 18 项通过；此前本地 Python 3.12.14 中亦通过 |
| 客户端静态分析 | 安卓与 Windows 两个任务均 No issues found |
| 客户端测试 | 安卓与 Windows 两个任务各 23 项全部通过 |
| Android APK | flutter build apk --debug 成功，已上传测试 APK 产物 |
| Windows x64 | flutter build windows --release 成功，已上传完整程序目录产物 |
| NAS 初始化 | 用户日志确认 todo-init 完成 data 目录初始化 |
| NAS 程序挂载权限 | v3 配置移除 app.py 文件挂载，用户反馈部署已好；独立健康检查仍待设备确认 |
| 实机安全存储、双端和外网同步 | 尚未验证，需要按安装说明验收 |

客户端测试包含 19 项使用隔离真实 Python 后端的集成测试，以及 4 项界面测试，覆盖离线持久化、双端同步、冲突、响应丢失后重试、后续离线编辑、备份恢复、实例身份校验、完成状态竞态、窄屏/桌面布局及编辑期间收到更新后的覆盖确认。云端测试不访问真实 NAS，也不使用其密钥。

## 构建产物

- [安卓测试 APK ZIP](https://github.com/whytree222/nas-todo/actions/runs/37900998859/artifacts/11602068142)：79,834,623 字节；上传记录 SHA256 为 `45eafdcfe663706be4bc1ceb5760530beae3bed2b63102b11b34ab5856f61fa3`。
- [Windows 完整目录 ZIP](https://github.com/whytree222/nas-todo/actions/runs/37900998859/artifacts/11602218670)：12,484,942 字节；上传记录 SHA256 为 `89b55dfb5a6d760c52695a1a0cc1564ef1bfe2cdcfb03b8810f3c9587d9a9b53`。

Actions 产物需登录有权限的 GitHub 账号下载，保留至 2026-10-23。上述哈希对应原始 Actions ZIP，不是 Release 中重新打包后的文件。本机转存临时下载地址曾收到 HTTP 403；随后发布流程直接从 Actions 下载并完成了下述验包。

## 私有 Release

[发布运行 37904737671](https://github.com/whytree222/nas-todo/actions/runs/37904737671) 成功；[v0.1.0 Release](https://github.com/whytree222/nas-todo/releases/tag/v0.1.0) 已发布为测试版，仓库保持私有。标签指向上述实际构建代码提交。

发布流程确认原构建成功与代码提交一致，检查 APK ZIP 完整性、manifest、字节码和 Flutter 引擎，确认 Windows EXE / DLL 为 x64 且资源目录完整，再验证完整 ZIP、所有上传文件大小与 GitHub SHA256。没有在实机启动二进制。

- Android APK：160,591,403 字节；SHA256 `ca65e98c1f3c7b08a11bca0fad3442904c4af3fa168445f3dae577d49fadbdf1`。
- Windows 完整 ZIP：12,290,046 字节；SHA256 `c9e4c2efb47e9e346f81fe06e22b985bc5514e3c5f656866e3a707db5dbbd2fd`。
- Release 同时包含 INSTALL.md 与 SHA256SUMS.txt，作为固定安装入口。

Android 使用测试签名；长期使用前需要固定签名密钥以稳定覆盖更新。Windows 应解压完整目录运行，不能只复制 EXE。

## 已修复的问题与部署说明

工作流测试目录的 runner.temp 已移动到合法的步骤环境变量位置；两处代码规范问题已修正；离线保存只在配置 NAS 后创建同步定时器，解决了界面测试结束时遗留无效定时器的问题。上述修改后两端分析、测试和构建通过。

用户使用 DX4600、已有 ZeroTier 网络及 Compose 入口。包含实际密钥的私有部署配置单独交付，不属于源码仓库；最新后续运行配置移除已完成的 todo-init，继续沿用 NAS 原项目 data 目录。源码工程的 compose.yaml 是通用构建部署模板，不替代用户已经部署的私有配置。

本机运行下载的 Dart SDK 曾遇到 Platform.resolvedExecutable 为 null，无法完成本地 Flutter 验证；通过云端正常环境已完成客户端验证与编译，无需在本机重复排查来使用这些产物。

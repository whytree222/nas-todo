# 验证记录

## 当前 v0.4.0：毛玻璃与极简 Windows 组件

2026-10-10，[构建 38044970508](https://github.com/whytree222/nas-todo/actions/runs/38044970508) 全部成功，源提交 `6b03e886fc992a9890a88c59e613a7fb1f251c1f`。19 项后端测试、两端静态分析和各 33 项客户端测试、Android APK 与 Windows x64 原生编译通过。

服务端新增认证失败时完整错误响应的回归检查：发送错误响应后限量丢弃尚未读完的上传正文，避免 Windows 连接重置使错误响应丢失。拒绝的正文不解析、不写数据库。Windows 原有“密钥错误保留所有本地修改”集成测试通过。

Windows 原生检查覆盖玻璃表面合成、极简布局、无父窗口、直接勾选回调、四边收起后的标签留在工作区内和悬停展开；真实 Flutter 主界面关闭后隐藏且组件仍可见，重新打开主界面与关闭组件后主界面保留。离线队列与数据格式沿用原实现。

本机 Windows 11 实际运行与发布程序共用 widget_ui 代码的隔离预览，使用演示待办及自身创建的红蓝条纹背景，确认文字、图标和 BGRA 像素上下方向正确。激活窗口中细条纹被模糊，大红蓝色块透过带底色的材质显示，确认本机支持的 Acrylic 真实渲染；非激活状态显示带底色备用卡片，符合系统材质策略。这些视觉检查没有读取真实待办或连接 NAS，未验证所有 Windows 版本、显卡、壁纸、多显示器和 DPI 组合。

[发布 38045046146](https://github.com/whytree222/nas-todo/actions/runs/38045046146) 成功，[v0.4.0 私有 Release](https://github.com/whytree222/nas-todo/releases/tag/v0.4.0) 包含 APK、Windows 完整 ZIP（含 desktop-widget.cmd）、INSTALL.md 与 SHA256SUMS.txt。发布检查仓库私有、成功构建与源提交一致、APK 完整性、Windows x64 / DLL / 资源 / 独立启动器，并核对全部上传文件的大小与 SHA256。合成预览工具不包含在用户安装包中。

实际 DX4600、ZeroTier 外网和安卓 / Windows 双端同步仍需设备验收。窗口和主界面共用后台进程及原离线队列；没有系统 Widgets 面板扩展、开机自启或应用内自动更新。Android 仍为测试签名。

| v0.4.0 文件 | 字节数 | SHA256 |
| --- | --- | --- |
| nas-todo-windows-v0.4.0-x64.zip | 12,395,696 | `5a15ac81812da9e752528212dfb86bc814e8fa897236498b5368c9c5e50eea48` |
| nas-todo-android-v0.4.0-test.apk | 160,634,957 | `101dc82d1e19a7aafc54425cc2d5f201af21f03a7d29154e0d1b82aee5f2c7b4` |

## v0.3.0 历史版本：独立透明 Windows 组件

2026-10-09，[构建 37933330471](https://github.com/whytree222/nas-todo/actions/runs/37933330471) 全部成功，源提交 `429a769ec07c9632f587371f94abfca89aaf0c3f`。18 项后端测试、两端静态分析和各 33 项客户端测试、Android APK 与 Windows x64 原生编译通过。

Windows 发布程序实际运行两组原生检查：透明色键属性、无父窗口、直接勾选回调、四边收起后的标签留在工作区内、悬停展开；以及真实 Flutter 主界面关闭后隐藏且组件仍可见、重新打开主界面、关闭组件后主界面仍存在。离线保存测试验证重启保留、重复请求幂等、保存失败回滚与重试，并检查组件快照不包含备注和连接凭据。

[发布 37933601078](https://github.com/whytree222/nas-todo/actions/runs/37933601078) 成功，[v0.3.0 私有 Release](https://github.com/whytree222/nas-todo/releases/tag/v0.3.0) 包含 APK、Windows 完整 ZIP（含 desktop-widget.cmd）、INSTALL.md 与 SHA256SUMS.txt。发布检查仓库私有、成功构建与源提交一致、APK 完整性、Windows x64 / DLL / 资源 / 独立启动器，并核对全部上传文件的大小与 SHA256。

检查在 GitHub Windows runner 上运行，不替代使用者实际壁纸、多显示器、系统 DPI 和 ZeroTier / NAS 双端同步验收。窗口和主界面共用后台进程及原离线队列；无系统 Widgets 面板扩展、开机自启或应用内自动更新。Android 仍为测试签名。

| v0.3.0 文件 | 字节数 | SHA256 |
| --- | --- | --- |
| nas-todo-windows-v0.3.0-x64.zip | 12,383,966 | `49cdd63b9362b1b26f66d705da62ffd91391f040bd8068628dfec8337d531439` |
| nas-todo-android-v0.3.0-test.apk | 160,634,961 | `879fa6a4c65f8343df3e864353018b309a347da4cad6e1240b452577e9c311dd` |

## v0.2.0 历史版本：日历与桌面小组件

2026-10-09，[构建运行 37928118785](https://github.com/whytree222/nas-todo/actions/runs/37928118785) 全部成功，对应提交 `de89da34e3c6cd4d123a52c8ed50123a8109c073`。后端 18 项测试通过，两端各 31 项客户端测试与静态分析通过，Android Kotlin / XML / Flutter APK 及 Windows C++ / Flutter 原生程序编译成功。

新增 8 项测试覆盖日期分组与删除过滤、闰日跨月、选中日期新建、窄屏滚动和未安排选择保留、完成项删除线、桌面勾选及置顶入口、安卓操作重复投递、存储失败不确认、重启后完成状态保留及小组件快照排除备注与凭据。

[发布运行 37928801352](https://github.com/whytree222/nas-todo/actions/runs/37928801352) 成功，[v0.2.0 私有 Release](https://github.com/whytree222/nas-todo/releases/tag/v0.2.0) 包含：

| 安装文件 | 字节数 | SHA256 |
| --- | --- | --- |
| nas-todo-android-v0.2.0-test.apk | 160,634,213 | `9ab248584ddcdf6cb3aac602cafe6d23f24f639503901956ab3f2cf583065740` |
| nas-todo-windows-v0.2.0-x64.zip | 12,360,800 | `afd556038684a86a86fc6b0634f8b46570ae77b9a1d845d659e26d0505258172` |

发布时确认私有仓库、原构建成功及源提交一致；检查 APK ZIP、manifest、字节码与 Flutter 引擎，Windows x64 EXE / DLL、完整资源目录与 ZIP，再核对上传大小及 SHA256。没有在真实手机启动小组件或在真实 Windows 桌面验证拖动置顶。

Android 小组件勾选会唤起主应用，通过同一离线队列持久化，再确认原生动作。Windows 小窗与主界面使用同一个引擎和数据实例，重复启动复用窗口。NAS 后端、任务字段和本机 schema 均保持兼容。仍需实机检查：小组件添加 / 调整尺寸 / 勾选 / 跨日刷新，Windows 拖动 / 调整尺寸 / 置顶，以及勾选结果的双端同步。

Android 长期固定签名及应用内更新尚未配置，测试 APK 不能保证覆盖旧版。迁移前确认没有待上传修改；不要直接卸载含有离线内容的旧版。

## v0.1.0 历史记录

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

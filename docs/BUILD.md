# 构建安卓与 Windows 客户端

本工程提供独立应用源码。NAS 的 Docker 服务与客户端构建是两个步骤：Docker 不会直接生成 APK 或 Windows 程序。

## 环境准备

安装 Flutter **stable** 并把 `flutter` 加入 PATH。本工程平台文件依据 Flutter stable **3.47.6** 的官方模板生成，模板提交为 `5fc346839b5d0eef006ed8404392afb4dfae428d`；原生构建尚未验证。Dart 随 Flutter SDK 提供。客户端需要联网从 pub.dev 获取依赖；Android 构建还会下载 Gradle 与 Android 依赖。[Flutter 安装文档](https://docs.flutter.dev/install)

本工程的客户端集成测试会启动真实的本地 Python 同步服务，因此测试和构建脚本还要求 **Python 3.12 或更新版本**，默认运行 PATH 中的 `python`。如需指定解释器，在构建前设置 `$env:NAS_TODO_TEST_PYTHON = 'C:\你的Python目录\python.exe'`。测试临时数据库默认在 `client/build/test-state/`，可用 `NAS_TODO_TEST_TMP` 指定另一个可写目录；不会连接真实 NAS 或读取部署令牌。

安卓：安装 Android Studio、Android SDK Platform、Build-Tools、Command-line Tools 和 Platform-Tools；使用 Android Studio 自带的受支持 JDK。本工程 Gradle wrapper 使用 **9.3.1**，运行 Gradle 9 需要 Java 17 或更新的兼容 JVM，CI 模板使用 JDK 17。[Gradle 官方兼容说明](https://docs.gradle.org/current/userguide/compatibility.html)、[Android 的 JDK 兼容说明](https://developer.android.com/build/jdks)。以项目 Gradle 和 `flutter doctor -v` 检查结果为准，按提示安装项目要求的 NDK/CMake，并阅读、接受 Android SDK 协议：[Flutter 安卓环境说明](https://docs.flutter.dev/platform-integration/android/setup)。

```powershell
flutter doctor --android-licenses
flutter doctor -v
flutter devices
```

Windows：在 Windows 上安装 Visual Studio 2022 的 **Desktop development with C++ / 使用 C++ 的桌面开发** 工作负载及其默认组件，包括 MSVC、CMake 和 Windows SDK。Visual Studio Code 不能替代这些编译工具；再检查 `flutter doctor -v` 的 Windows 和 Visual Studio 条目。[Flutter Windows 环境说明](https://docs.flutter.dev/platform-integration/windows/setup)

## 本机检查与构建

在工程根目录 `nas-todo` 打开 PowerShell：

```powershell
.\scripts\build.ps1 -Target Check
.\scripts\build.ps1 -Target Android
.\scripts\build.ps1 -Target Windows
```

脚本执行依赖获取、静态检查和客户端测试，再构建所选平台；任一步失败都会停止。也可以直接运行：

```powershell
Set-Location client
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter build windows --release
```

Android 默认产物：`client/build/app/outputs/flutter-apk/app-debug.apk`。这是用调试签名的测试 APK，适合先安装验证。开启设备允许该文件来源安装的权限；或连接启用了 USB 调试的设备使用 `flutter install --debug`。

Windows 默认产物：`client/build/windows/x64/runner/Release/`。**请复制整个 Release 文件夹**，包括 DLL 和 `data/`，再运行其中的 `nas_todo.exe`。独立复制一个 EXE 会缺少依赖。目标电脑可能需要安装 Microsoft Visual C++ 运行库，见 [Flutter Windows 分发说明](https://docs.flutter.dev/deployment/windows)。

## 平台目录缺失时

正常工程已经包含 `client/android/` 和 `client/windows/`，构建脚本不会重新生成已有平台。如果你只拷贝了 Dart 源码，请先备份自定义文件，再在 `client` 内生成缺失的平台；不要加 `--overwrite`：

```powershell
flutter create --platforms=android,windows --project-name nas_todo --org cn.privatetodo .
```

生成后需要保留本工程安卓清单中的联网权限、私有网络 HTTP 设置和禁用系统备份设置，并保持现有 applicationId `cn.privatetodo.app`，否则连接行为或覆盖升级身份可能变化。这个补全命令不替代原工程的平台定制。

## 安装后第一次连接

1. 先在 NAS 按 [部署说明](DEPLOY-DX4600.md) 启动服务。
2. NAS、安卓和 Windows 已加入同一个 ZeroTier 网络，两端打开“连接设置”，输入 `http://NAS的ZeroTierIP:8787`（占位文字换成 NAS 的实际 Managed IP），以及自己的访问令牌。
3. 保存设置并手动同步；测试安卓新增、Windows 拉取、Windows 编辑、安卓拉取。
4. 手机切到移动网络、保持现有 ZeroTier 连接，并使用同一 NAS ZeroTier IP 验证外网同步；详见部署说明的 `/health` 和端口检查。

NAS URL 与令牌在运行时输入，不写入 APK、Windows 程序或仓库。使用 NAS ZeroTier 地址时，三台设备的现有 ZeroTier 网络连接需要可用。

## 长期使用的安卓签名

调试 APK 与 CI 的调试密钥只适合验证。长期使用前，按 [Flutter 安卓签名说明](https://docs.flutter.dev/deployment/android) 配置自己保存的签名密钥，再运行 `flutter build apk --release`，并提高 `pubspec.yaml` 的版本号。保管密钥和密码；不要把它们提交到仓库。

同一个 Android applicationId 的覆盖更新需要兼容签名。不同机器或不同 CI 运行可能生成不同调试密钥，安装时可能要求先卸载；卸载会清除本机待办。**先确认没有待上传内容并完成 NAS 备份，再卸载测试版本。** 使用固定的正式签名密钥后才适合稳定更新。

## 可选：手动 CI 构建

`.github/workflows/build.yml` 提供 GitHub Actions 流程，上传客户端、服务端代码或工作流到 main 分支时自动触发，也支持 `workflow_dispatch` 手动触发。将本工程根目录作为 GitHub 仓库根目录上传后，可以在 Actions 页面查看构建结果，分别下载测试 APK 和完整 Windows Release ZIP。流程使用 Flutter stable、JDK 17、依赖获取、静态检查和测试；只有通过后才构建、上传产物。

模板固定 Flutter stable 3.47.6；Windows 使用 windows-2022 环境。先在 Ubuntu 的 Python 3.12 环境运行服务端测试，通过后再启动安卓与 Windows 两个任务；两个任务也安装 Python 3.12 以运行真实服务集成测试，测试目录使用各任务的临时目录。成功生成的安装包产物保留 14 天，需及时下载保存。

这需要把源码交给 GitHub，并由其构建环境下载依赖；本次没有创建仓库、运行 CI 或上传源码。真实令牌、数据库、备份和签名材料不需要、也不应提交到 GitHub。长期发布需要另行配置固定安卓签名及 Windows 分发方式。

## 验证范围

**本次客户端源码尚未通过 `flutter analyze` 与 `flutter test`，两个平台构建也未执行。** 具体本地工具限制与服务端结果以 [验证记录](VALIDATION.md) 为准。

以后成功运行 `flutter analyze` 与 `flutter test`，代表源码静态检查和测试通过，不能替代安卓/Windows 编译、真实设备系统安全存储、两台设备之间以及 DX4600 外网连接的验证。完成部署后按部署说明执行双端、离线和冲突验收。

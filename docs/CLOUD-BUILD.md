# 云端编译与公开发布

运行 [38393229963](https://github.com/whytree222/nas-todo/actions/runs/38393229963) 全部成功，源提交 `0bf438eeb505c16613e9b96e56e3eccf6b7bf5a9`。v0.9.0安装包在 [Release](https://github.com/whytree222/nas-todo/releases/tag/v0.9.0)，见 [安装说明](RELEASE-v0.9.0.md)。安卓任务保存中文字体渲染的手机/桌面鼓励卡片预览，并执行Android15模拟器小组件测试。

当前仓库按使用者授权保持公开，源码和安装包可以公开下载，使用 Actions 编译。部署密钥和 NAS 数据不需要提供给 GitHub，客户端安装后再填写。

## 仓库与上传

1. 当前使用 `whytree222/nas-todo` 公开仓库；自行部署时也可在自己的账号下创建专用仓库，名称建议 `nas-todo`。
2. 勾选 Add a README file 初始化仓库，默认分支使用 main。
3. 将仓库链接交给当前对话，以便继续上传源码、运行测试和处理构建错误。已有仓库也可以使用，建议专用于此项目。
4. 工程根目录下的 `.github`、`client`、`server`、`docs` 等直接放在仓库根目录，不能再套一层 `nas-todo`。

只上传 `nas-todo-source.zip` 中的源码。不上传 `nas-todo-deploy*.zip`、各版私有部署 Compose、NAS data 目录或同步密钥。

## 构建流程

上传客户端、服务端源码或工作流到 main 分支后会自动启动构建；也可以手动执行 Actions → Build native test apps → Run workflow → main → Run workflow。工作流使用 Flutter stable 3.47.6、Python 3.12，安卓使用 JDK 17，Windows 使用 windows-2022。先运行后端测试，再分别执行客户端依赖获取、静态分析、测试和构建。失败的步骤需要修复后重新运行，不能跳过测试当作已验证产物。

以后构建的新产物可在运行页面的 Artifacts 下载；当前已验证版本优先从 Release 下载：

- nas-todo-android-test-apk：解压得到 app-debug.apk，安装到安卓。
- nas-todo-windows-full-release：解压整个文件夹，运行其中的 nas_todo.exe，保留旁边的 DLL 和 data 文件夹。

Actions 产物保留14天。各publish工作流固定已验证的对应版本；publish-v09.yml等待鼓励与小组件检查、两端编译成功后核对并发布安装包。APK仍为测试签名，长期覆盖升级需要固定签名。

## 首次同步验收

两端打开连接设置，输入 NAS 地址 `http://10.59.218.68:8787` 和 NAS 私有 Compose 中 `NAS_TODO_TOKEN` 的值。保持 ZeroTier 连接。

先测试安卓新增后 Windows 拉取，再测试 Windows 修改后安卓拉取。然后断网编辑并重新联网同步，最后让两端离线修改同一条待办，确认冲突选择能够正确保留所选版本。

安装包已经构建生成；仍需完成上述实机验收，才能确认两端在自己的 NAS 和 ZeroTier 环境中实际可用。

官方操作说明：https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow

Windows 可双击完整目录中的 desktop-widget.cmd 单独启动毛玻璃组件；表面显示待办和“…”菜单，其他操作从菜单打开。“设置 → 外观与主题”可选应用颜色，以及跟随应用或独立的小组件颜色。主界面关闭后组件继续工作，保留原离线队列、应用身份及数据目录。

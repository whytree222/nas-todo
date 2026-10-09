# 私有仓库云端编译

运行 [37900998859](https://github.com/whytree222/nas-todo/actions/runs/37900998859) 的后端、安卓和 Windows 任务已全部成功。可直接下载：[安卓测试 APK ZIP](https://github.com/whytree222/nas-todo/actions/runs/37900998859/artifacts/11602068142)、[Windows 完整程序 ZIP](https://github.com/whytree222/nas-todo/actions/runs/37900998859/artifacts/11602218670)。登录自己的 GitHub 账号后下载，产物保留至 2026-10-23。

源码通过自己的 GitHub 私有仓库交给 Actions 编译。部署密钥和 NAS 数据不需要提供给 GitHub，客户端安装后再填写。

## 仓库与上传

1. 登录 GitHub，在自己的账号下创建 Private 仓库，名称建议 `nas-todo`。
2. 勾选 Add a README file 初始化仓库，默认分支使用 main。
3. 将仓库链接交给当前对话，以便继续上传源码、运行测试和处理构建错误。已有私有仓库也可以使用，但须确认是专用于此项目的仓库。
4. 工程根目录下的 `.github`、`client`、`server`、`docs` 等直接放在仓库根目录，不能再套一层 `nas-todo`。

只上传 `nas-todo-source.zip` 中的源码。不上传 `nas-todo-deploy*.zip`、各版私有部署 Compose、NAS data 目录或同步密钥。

## 构建流程

上传客户端、服务端源码或工作流到 main 分支后会自动启动构建；也可以手动执行 Actions → Build native test apps → Run workflow → main → Run workflow。工作流使用 Flutter stable 3.47.6、Python 3.12，安卓使用 JDK 17，Windows 使用 windows-2022。先运行后端测试，再分别执行客户端依赖获取、静态分析、测试和构建。失败的步骤需要修复后重新运行，不能跳过测试当作已验证产物。

构建成功后在运行页面的 Artifacts 下载：

- nas-todo-android-test-apk：解压得到 app-debug.apk，安装到安卓。
- nas-todo-windows-full-release：解压整个文件夹，运行其中的 nas_todo.exe，保留旁边的 DLL 和 data 文件夹。

产物保留 14 天，请下载保存。当前 APK 使用测试签名；长期使用需固定自己的签名密钥，避免后续更新因签名变化而需要卸载应用。

## 首次同步验收

两端打开连接设置，输入 NAS 地址 `http://10.59.218.68:8787` 和 NAS 私有 Compose 中 `NAS_TODO_TOKEN` 的值。保持 ZeroTier 连接。

先测试安卓新增后 Windows 拉取，再测试 Windows 修改后安卓拉取。然后断网编辑并重新联网同步，最后让两端离线修改同一条待办，确认冲突选择能够正确保留所选版本。

安装包已经构建生成；仍需完成上述实机验收，才能确认两端在自己的 NAS 和 ZeroTier 环境中实际可用。

官方操作说明：https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow

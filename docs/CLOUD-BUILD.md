# 云端编译与公开发布

运行 [39374604219](https://github.com/whytree222/nas-todo/actions/runs/39374604219) 全部成功，源提交 `2a32912b853d268acff7adfb9270fdf8699bb23e`。v0.10.0安装包见 [Release](https://github.com/whytree222/nas-todo/releases/tag/v0.10.0) 与 [安装说明](RELEASE-v0.10.0.md)。

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

Actions 产物保留14天。各publish工作流固定已验证的对应版本；publish-v010.yml在两端检查与原生编译通过后核对安装包并发布。APK仍为测试签名。

## 新个人功能

- 智能清单、清单分组、标签筛选、搜索及快捷添加；Windows 多栏详情，安卓底部导航与抽屉。
- 子任务最多五层，展开、收起和独立完成；删除父待办后子任务提升到顶层。
- 标签可选择已有标签或输入新标签；按天、周、月重复，可设置间隔、执行日及每月日期。NAS 在完成并同步后生成下一次，重试和撤销后再次完成不会多生成。
- 按优先级看板及四象限，支持拖动和菜单移动。四象限以较高/紧急优先级判断重要，以今天及之前日期判断紧急；移出紧急象限清除已到期日期，重复待办改到明天，未来日期保留。
- 月、周、日、议程日历；完整展示当天待办，完成后保留划线；无日期待办可拖到目标日期。
- 习惯支持勾选或次数目标、每周计划日、撤销、近七天记录、月热力图与历史补记；习惯历史不受待办月底清理影响。

**新个人功能需要升级 NAS。** 在原 Docker 项目替换本聊天提供的私有运行配置，保留原令牌、端口、data 和数据库；先停止项目并备份整份 data。无需 todo-init。详见 [升级步骤](UPGRADE-v0.10.0.md)。升级后同步，“设置 → 个人功能同步”显示服务已连接。旧 NAS 仍可同步基础待办，个人信息保存在本机队列等待升级，不要卸载或降级含有未上传信息的应用。

本版依据使用者提供的静态功能报告组织信息，布局、图标和代码由本应用独立实现。按最新要求不提供番茄钟。

## 首次同步验收

两端打开连接设置，输入 NAS 地址 `http://10.59.218.68:8787` 和 NAS 私有 Compose 中 `NAS_TODO_TOKEN` 的值。保持 ZeroTier 连接。

先测试安卓新增后 Windows 拉取，再测试 Windows 修改后安卓拉取。然后断网编辑并重新联网同步，最后让两端离线修改同一条待办，确认冲突选择能够正确保留所选版本。

安装包已经构建生成；仍需完成上述实机验收，才能确认两端在自己的 NAS 和 ZeroTier 环境中实际可用。

官方操作说明：https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow

Windows 可双击完整目录中的 desktop-widget.cmd 单独启动毛玻璃组件；表面显示待办和“…”菜单，其他操作从菜单打开。“设置 → 外观与主题”可选应用颜色，以及跟随应用或独立的小组件颜色。主界面关闭后组件继续工作，保留原离线队列、应用身份及数据目录。

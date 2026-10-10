# 私有待办 · NAS Todo

给绿联 DX4600 使用的个人待办项目：安卓和 Windows 原生客户端共用 Flutter 源码，Docker 同步服务和 SQLite 主数据库放在自己的 NAS 上。

**[v0.4.0 私有测试版已发布](https://github.com/whytree222/nas-todo/releases/tag/v0.4.0)**，包含任务日历、安卓桌面小组件及 Windows 独立毛玻璃桌面组件，提供 APK 和 Windows 完整程序 ZIP。两端静态检查、各 33 项客户端测试和 19 项服务端测试通过。Windows 原生窗口、四边收起、悬停展开和主界面关闭检查通过；本机 Windows 11 合成背景预览确认 Acrylic 模糊、带底色的玻璃材质及文字图标正向显示。NAS 双端同步仍需设备验收。详见 [验证记录](docs/VALIDATION.md) 和 [安装说明](docs/RELEASE-v0.4.0.md)。

## 可以做什么

- 新建、编辑、完成和删除待办；清单分类、搜索、今天与已完成筛选。
- 截止日期、优先级和排序。
- 月历与每日待办：按日期查看任务，完成项保留并显示删除线，未安排日期的任务单独查看。
- 安卓桌面“今天”小组件：可调整大小，勾选时打开应用保存离线修改。
- Windows 独立毛玻璃桌面组件：运行 desktop-widget.cmd，关闭主界面后仍可使用；烟灰绿圆角卡片、清晰的圆形勾选图标，表面保留待办和“…”菜单。拖动、调整大小、贴四边收起和悬停展开，记住位置、置顶及贴边选项。
- 先保存本机，断网时照常编辑；联网后上传到 NAS，并拉取其他设备的修改。
- 手动同步、应用打开期间定时同步、回到前台时同步；显示待上传数量和同步结果。
- 两台设备同时修改同一条待办时显示冲突，由你选择本机或 NAS 版本。

这是一位使用者、一个共享访问令牌的第一版。暂未实现附件、多人权限和到期通知。手机应用退出后不保证后台同步；再次打开会尝试同步。

## 数据在哪里

```text
安卓客户端 ─ 本机离线副本 ─┐
                          ├─ 私有网络 / HTTPS ─ DX4600 Docker 服务 ─ SQLite 主库
Windows 客户端 ─ 本机副本 ─┘                              └─ NAS 备份
```

NAS 保存完成同步后的主库和备份。离线新增的内容在同步成功前只存在创建它的设备上；两台设备都必须保留本地副本才能离线使用。访问令牌放在客户端系统安全存储中，待办的本地副本使用应用数据目录保存，并没有单独进行内容加密。同步服务不使用待办 SaaS，也没有内置遥测。

NAS、安卓和 Windows 已经加入同一个 ZeroTier 网络，直接沿用现有网络。客户端填写 NAS 的 **ZeroTier Managed IP**，例如 `http://NAS的ZeroTierIP:8787`，待办主库仍保存在 NAS；Managed IP 可在现有网络的设备列表查看。[ZeroTier 官方说明](https://docs.zerotier.com/quickstart/)

## 从这里开始

1. 按 [DX4600 部署说明](docs/DEPLOY-DX4600.md) 把同步服务装到 NAS，生成自己的访问令牌。
2. 从 [Release](https://github.com/whytree222/nas-todo/releases/tag/v0.4.0) 下载安卓 APK 和 Windows 完整程序 ZIP；也可按 [客户端构建说明](docs/BUILD.md) 自行编译。
3. 在两台设备的“连接设置”中填写同一 NAS 地址和同一访问令牌。
4. 用 NAS 的 ZeroTier IP 验证 `/health` 和同步，再让手机切到移动网络测试；最后验证断网修改和双端冲突。

## 工程内容

| 目录 / 文件 | 用途 |
| --- | --- |
| `client/` | 安卓与 Windows Flutter 客户端 |
| `server/` | Python 标准库同步 API、数据库与测试 |
| `compose.yaml` | NAS 的 Docker Compose 配置 |
| `.env.example` | 部署配置模板，不含真实令牌 |
| `scripts/build.ps1` | Windows 本机检查及构建脚本 |
| `.github/workflows/build.yml` | main 分支代码更新或手动触发的 GitHub Actions 构建流程 |
| `.github/workflows/publish.yml` | 发布已验证的 v0.1.0 构建，保留私有仓库与测试版标记 |
| `.github/workflows/publish-v03.yml` | 等待已验证的 v0.3.0 两端构建成功，再发布私有测试版 |
| `.github/workflows/publish-v04.yml` | 等待已验证的 v0.4.0 两端构建成功，再发布私有毛玻璃组件测试版 |
| `docs/` | 部署、备份、恢复和客户端构建说明 |

源码已上传到使用者的 GitHub 私有仓库，并配置 Actions 构建；运行 38044970508 的全部任务成功。v0.4.0 安装包已发布到同一私有仓库的 Release，下载需登录有权限的账号。NAS 部署密钥、数据库和待办内容没有上传。

## 日常使用注意

先等应用显示同步成功，再卸载、清除应用数据或换设备；未上传修改可能随本地数据一起丢失。连接设置中的令牌相当于主库访问权限，妥善保存，不要把 `.env`、备份或客户端数据目录提交到公开仓库。

服务端通过版本号识别修改，不依赖手机与电脑时钟一致。已确认同步的数据定期用 SQLite 在线备份命令保存，具体步骤见部署说明。

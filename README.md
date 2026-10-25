# 私有待办 · NAS Todo

给绿联 DX4600 使用的个人待办项目：安卓和 Windows 原生客户端共用 Flutter 源码，Docker 同步服务和 SQLite 主数据库放在自己的 NAS 上。

**[v0.11.1 便捷启动与简约成就测试版已发布](https://github.com/whytree222/nas-todo/releases/tag/v0.11.1)**。每次启动默认打开今天，全部待办隐藏逾期；成就使用图标与进度条，规则收进弹窗。两端静态分析、Flutter测试和原生构建已通过。见 [安装说明](docs/RELEASE-v0.11.1.md) 与 [验证记录](docs/VALIDATION.md)。

## 可以做什么

- 每次启动显示今天，清除上次页面、清单、标签、优先级和滚动位置；全部待办隐藏逾期，原清单与已逾期入口保留。
- 成就用年度星星、12个月热力图及图标进度条呈现，详细规则可点击“规则说明”查看。
- 手机底栏为待办、日历、习惯、成就、设置；今天、已完成保留在智能清单。Windows非任务页面收起清单侧栏。
- 待办、子任务、标签、重复规则、已有清单选择、搜索、筛选、排序和按优先级看板保留。列表明确标题与日期、标签层级；每个勾选入口保持独立热区。
- 四象限作为可选视图，默认隐藏，在“设置 → 功能显示”开启；关闭只隐藏入口，不更改任务数据或规则。
- 手机底部任务编辑器可展开全屏，避让键盘；Windows大窗口在右侧编辑。离开未保存内容前提示，保留原同步冲突确认。
- 快速添加可选择清单、日期、优先级和已有标签；显示偏好在当前设备保存。月、周、日、议程日历保留，全部待办可达，完成划线，未安排卡片可拖入日期。
- 习惯支持勾选、次数目标、每周计划日、撤销、补记和月热力图。历史区域可展开，按日期保留以前的目标和计划。
- 成就每周分别考核待办完成率、习惯达标率，两个非空类别均≥80%才得星。每个习惯的每个计划日计1天，达到当天次数目标才达标；休息日不参与，实时分母不提前计未来习惯日。
- 黑白绿蓝主题、今日鼓励、安卓五种滑动组件、Windows独立毛玻璃与贴边隐藏、离线保存、NAS同步及冲突选择继续保留。

v0.11.1 仅更新客户端，已使用 v0.11.0 成就服务的 NAS 无需重新部署。尚未升级习惯成就服务时，先同步并停止原项目，备份整份data；在原compose中只替换todo-sync的整个command段，保留密钥、端口、用户和挂载，无需init。command-block.yaml不是完整compose，不能直接覆盖原文件。详见 [升级说明](docs/UPGRADE-v0.11.0.md)。已有习惯从NAS新规则启用当天开始计计划日，历史已结算成就不回算，习惯与打卡历史不参加待办月底清理。

本版依据使用者提供的静态前端报告组织界面，使用独立实现的组件和图标；保留现有功能，不添加时间线、番茄钟、附件、AI或协作模块。

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
2. 从 [Release](https://github.com/whytree222/nas-todo/releases/tag/v0.11.0) 下载安卓APK和完整WindowsZIP，并按 [习惯成就升级说明](docs/UPGRADE-v0.11.0.md) 更新原NAS项目。
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
| `.github/workflows/publish-v05.yml` | 发布已验证的 v0.5.0 主题颜色私有测试版 |
| `.github/workflows/publish-v06.yml` | 按使用者授权公开发布已验证的 v0.6.0 日历与拖动安排测试版 |
| `.github/workflows/publish-v061.yml` | 公开发布已验证的 v0.6.1 日历显示修复测试版 |
| `.github/workflows/publish-v062.yml` | 公开发布已验证的 v0.6.2 日历全部待办测试版 |
| `.github/workflows/publish-v07.yml` | 发布已验证的 v0.7.0 成就与匹配 NAS 服务升级包 |
| `.github/workflows/publish-v08.yml` | 发布通过原生滑动小组件检查的 v0.8.0 安装包 |
| `.github/workflows/publish-v09.yml` | 发布通过今日鼓励与紧急程度检查的 v0.9.0 安装包 |
| `.github/workflows/publish-v091.yml` | 发布通过已有分组选择检查的 v0.9.1 安装包 |
| `.github/workflows/publish-v010.yml` | 发布已验证的 v0.10.0 个人工作台与匹配 NAS 源码包 |
| `.github/workflows/publish-v011.yml` | 发布已验证的v0.11.0客户端和不含密钥的NAS程序升级片段 |
| `docs/` | 部署、备份、恢复和客户端构建说明 |

使用者已授权公开源码和安装包。构建40047037467全部成功，v0.11.0公开发布；原NAS密钥不在本地，使用者已明确同意按源码差异和敏感信息审计发布。源码包排除.env、数据库、备份和签名材料。

## 日常使用注意

先等应用显示同步成功，再卸载、清除应用数据或换设备；未上传修改可能随本地数据一起丢失。连接设置中的令牌相当于主库访问权限，妥善保存，不要把 `.env`、备份或客户端数据目录提交到公开仓库。

服务端通过版本号识别修改，不依赖手机与电脑时钟一致。已确认同步的数据定期用 SQLite 在线备份命令保存，具体步骤见部署说明。

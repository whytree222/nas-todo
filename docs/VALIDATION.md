# v0.13.0 编译预检完成，正式签名及发布待完成

- 验证源码：`e19962733c1de62511cc0fe63818bf97f863eed5`；[构建运行 40447504915](https://github.com/whytree222/nas-todo/actions/runs/40447504915) 全部成功。
- 后端45项测试和3项发布清单测试通过；Android 201项 Flutter 测试通过、1项平台跳过；Windows 202项通过。两端静态分析无问题。
- Android debug、无签名 release 编译通过；Android 15 模拟器12项原生测试通过，覆盖已有滑动组件、应用/版本/签名核对、私有文件与 FileProvider 范围。尚未生成或上传正式签名 APK。
- Windows x64 编译、实际PE产品与版本核对通过；独立更新器复制到临时目录后自检通过，覆盖SHA256、路径限制、文件占用失败回滚和无关文件保留。原有毛玻璃、贴边隐藏、主界面与独立组件生命周期检查继续通过。
- 更新模块测试覆盖固定仓库与重定向限制、流式哈希/长度、节流与稍后提醒、空间不足、下载取消、重启后Ready恢复、安装前篡改拒绝、重复安装拦截、真实ZIP解包及旧缓存清理。安装确认界面在320宽度测试通过，已人工查看两端合成更新预览。
- CI明确检测到 `HAS_RELEASE_SIGNING: false`；本次仅为编译预检，未生成 `nas-todo-android-release-apk` 产物，未创建v0.13.0 Release，也没有发布更新清单。等待四项仓库签名Secrets配置后重新构建，核对固定证书和实际包身份，再发布正式更新通道。
- 固定签名已在本机独立私有目录保存，私钥、密码与配置助手不属于源码ZIP。上传前已执行公开源差异审查和敏感信息扫描。用户NAS服务、数据库、挂载与同步密钥未改动，无需重部署。
- 本次自动测试不等同于真机安装器和用户电脑上跨版本覆盖安装验收；首次从旧debug签名迁移需先同步、备份，再按系统提示处理。

---

# v0.12.0 验证

- 测试源码：`7e0cd8b17a70ec0ec785947ba8930fe715d94d18`；[构建运行](https://github.com/whytree222/nas-todo/actions/runs/40423430609)。
- 后端45项测试、Android 178项 Flutter 测试（另1项平台跳过）、Windows 179项测试、两端静态分析及原生构建通过；安卓8项组件检查、Windows毛玻璃及独立窗口生命周期检查通过。
- 新增分类迁移验证：已完成/未完成、日期、标签、备注、父子关系、其他分类保留；一次持久化写入失败全量回滚，重启恢复；删除操作与真实NAS双客户端同步收敛。
- 周一至周日跨年边界、无日期待办延续、手机与桌面添加/选星期日、已有分类拖放改日期保留字段通过。查看了实际 Flutter 生成的手机/Windows周待办预览。
- 沿用现有 NAS API，服务器源码无变化；已有 v0.11.0 成就服务无需升级。未接触用户真实数据或密钥。
- [发布校验](https://github.com/whytree222/nas-todo/actions/runs/40424543381)验证测试源码标签、5项发布产物大小与 SHA256。上传前继续执行已授权的公开源差异审查及敏感信息扫描。

---

# v0.11.1 验证

- 源码提交：`8f076643af631f7b5e60b5dba9b9cee956fa3075`。
- [两端构建与测试](https://github.com/whytree222/nas-todo/actions/runs/40198117737)：45项后端测试；Android 170项 Flutter 测试通过、1项平台跳过，Windows 171项通过；两端静态分析和原生构建通过，安卓8项原生组件检查、Windows毛玻璃组件与进程生命周期检查通过。
- 新增验证：手机和电脑均忽略旧页面与筛选，重新启动显示今天；全部待办隐藏逾期但原清单可查，日期跨天筛选正确；320宽屏规则弹窗能打开、阅读和关闭。
- 查看了实际 Flutter 生成的手机与 Windows 成就页预览，未见遮挡或溢出；12个月历史颜色与跨年测试继续通过。
- 成就计算、NAS代码和数据协议没有变更；已运行 v0.11.0 服务无需重新部署。
- [发布与完整性校验](https://github.com/whytree222/nas-todo/actions/runs/40198862261)验证 tag、安装包及 SHA256；源码上传采用已获用户许可的公开基线差异审查及敏感信息扫描，未读取原 NAS 密钥。

---

# 验证记录

## 历史 v0.11.0：界面改版与习惯成就

[构建40047037467](https://github.com/whytree222/nas-todo/actions/runs/40047037467)成功，测试源提交`0aecedc24e30423ff497aa2d14b5d1a32501f0a6`。45项后端测试、两端静态分析、安卓166项/Windows167项Flutter测试和原生构建通过；安卓8项原生小组件检查通过。Windows毛玻璃及独立窗口生命周期检查通过；仅Windows执行的可见性测试在安卓跳过。

- 手机底栏为待办、日历、习惯、成就、设置；今天、已完成保留在智能清单。Windows非任务页面收起清单侧栏。
- 待办、子任务、标签、重复规则、已有清单选择、搜索、筛选、排序和按优先级看板保留。列表明确标题与日期、标签层级；每个勾选入口保持独立热区。
- 四象限作为可选视图，默认隐藏，在“设置 → 功能显示”开启；关闭只隐藏入口，不更改任务数据或规则。
- 手机底部任务编辑器可展开全屏，避让键盘；Windows大窗口在右侧编辑。离开未保存内容前提示，保留原同步冲突确认。
- 快速添加可选择清单、日期、优先级和已有标签；显示偏好在当前设备保存。月、周、日、议程日历保留，全部待办可达，完成划线，未安排卡片可拖入日期。
- 习惯支持勾选、次数目标、每周计划日、撤销、补记和月热力图。历史区域可展开，按日期保留以前的目标和计划。
- 成就每周分别考核待办完成率、习惯达标率，两个非空类别均≥80%才得星。每个习惯的每个计划日计1天，达到当天次数目标才达标；休息日不参与，实时分母不提前计未来习惯日。
- 黑白绿蓝主题、今日鼓励、安卓五种滑动组件、Windows独立毛玻璃与贴边隐藏、离线保存、NAS同步及冲突选择继续保留。

后端45项检查包含计划日边界、休息日与未来日期、次数目标只记一天、两类80%阈值不能互相抵消、计划目标变更和删除保留过去日期、断网计划历史、操作ID重试与重启、NAS激活日、旧客户端成就投影、月底归档与SQLite备份、晚到记录不重算历史。真实Dart双客户端与SQLite服务往返检查通过，真实HTTP双客户端检查验证习惯成就一致。

界面回归涵盖导航、已有清单、标签、日历滚动与拖动、主题、可选四象限、手机编辑器全屏和键盘、桌面内嵌编辑、草稿退出提示，以及习惯热力图在窄屏大字下可达。8张Flutter预览检查桌面、手机、看板、四象限、习惯、日历和两端编辑器。

[发布40047984328](https://github.com/whytree222/nas-todo/actions/runs/40047984328)成功，Release及标签、测试源提交、5个文件的大小和SHA256通过独立API复核。本版需要升级NAS结算服务。先同步并停止原项目，备份整份data；在原compose中只替换todo-sync的整个command段，保留密钥、端口、用户和挂载，无需init。command-block.yaml不是完整compose，不能直接覆盖原文件。详见 [升级说明](UPGRADE-v0.11.0.md)。已有习惯从NAS新规则启用当天开始计计划日，历史已结算成就不回算，习惯与打卡历史不参加待办月底清理。 实际NAS升级、真实安卓桌面手势、系统安全存储、多显示器和DPI仍需设备验收。

| 文件 | 字节数 | SHA256 |
|---|---:|---|
| `INSTALL.md` | 2754 | `abe7caf803edd6ec18109b794e013da20cc0e835a7203309a89aca436d1eebe7` |
| `SHA256SUMS.txt` | 370 | `1563be9d55580bab248b0b100541477c41a3b4f19258720c5a04ce5fbbc698f1` |
| `nas-todo-android-v0.11.0-test.apk` | 160919717 | `9fbfa1d563ebde5879989ca91177332288e7419f015be0f7927ee1dc82509cc4` |
| `nas-todo-server-v0.11.0.zip` | 69892 | `2a97e3b3abb68679bb0e163d1d43dd30e9826262ae0ba99b7107de0fec951a4d` |
| `nas-todo-windows-v0.11.0-x64.zip` | 12722645 | `70a36415c3290748adb89a0dbdcb1011aecbf6823d3e8ee9c7bb326f89da3a13` |

## v0.10.0 历史版本：个人工作台、任务扩展与习惯

[构建 39374604219](https://github.com/whytree222/nas-todo/actions/runs/39374604219) 成功，源提交 `2a32912b853d268acff7adfb9270fdf8699bb23e`。39项后端测试、两端静态分析、安卓159项/Windows160项Flutter测试及原生构建通过；安卓8项原生小组件检查通过。Windows 玻璃与窗口生命周期检查通过。Windows 可见性专用测试仅在 Windows 执行。

- 智能清单、清单分组、标签筛选、搜索及快捷添加；Windows 多栏详情，安卓底部导航与抽屉。
- 子任务最多五层，展开、收起和独立完成；删除父待办后子任务提升到顶层。
- 标签可选择已有标签或输入新标签；按天、周、月重复，可设置间隔、执行日及每月日期。NAS 在完成并同步后生成下一次，重试和撤销后再次完成不会多生成。
- 按优先级看板及四象限，支持拖动和菜单移动。四象限以较高/紧急优先级判断重要，以今天及之前日期判断紧急；移出紧急象限清除已到期日期，重复待办改到明天，未来日期保留。
- 月、周、日、议程日历；完整展示当天待办，完成后保留划线；无日期待办可拖到目标日期。
- 习惯支持勾选或次数目标、每周计划日、撤销、近七天记录、月热力图与历史补记；习惯历史不受待办月底清理影响。

同步验证覆盖旧六字段任务与新个人记录并存、原数据库迁移及备份恢复、子任务层级与循环校验、父任务删除及月底归档提升子任务、标签和重复规则保留、习惯计数与计划日、历史补记、两端冲突选择、掉线或丢失回复后幂等重试、队列持久化和旧 NAS 升级提示。重复任务由 NAS 去重生成，修改或取消规则期间暂缓生成；月末、闰月和每周执行日边界有回归检查。真实 Dart 双客户端与 SQLite 服务的标准输入输出往返检查也通过。

界面检查包括树状子任务与新建下一步、标签快捷添加、重复编辑器、习惯创建/撤销/次数目标/历史补记、手机320px大字体和日历全部任务可达。既有主题、今日鼓励、成就和桌面组件回归通过。

本版依据使用者提供的静态功能报告组织信息，布局、图标和代码由本应用独立实现。按最新要求不提供番茄钟。 新个人功能需要按 [升级说明](UPGRADE-v0.10.0.md) 更新 NAS，同一个数据库事务增加个人表，原任务和成就历史保留。

[发布 39375534659](https://github.com/whytree222/nas-todo/actions/runs/39375534659) 成功，[v0.10.0](https://github.com/whytree222/nas-todo/releases/tag/v0.10.0) 的五个资产均核对源提交、文件完整性、大小和 SHA256。真实手机桌面手势、系统安全存储、多显示器/DPI及实际 NAS/ZeroTier 双端同步仍需设备验收；没有声称已操作用户 NAS。APK仍是测试签名。

| 文件 | 字节数 | SHA256 |
|---|---:|---|
| `INSTALL.md` | 3514 | `f5360d51c58681e46b3b3eb5dd743044b810a2898b21d3b360104aedc3cce315` |
| `SHA256SUMS.txt` | 370 | `c0d28daba2a451a68ac1c7db846e127ee43fd81ce456ef407eb7b2c24059f422` |
| `nas-todo-android-v0.10.0-test.apk` | 160873657 | `333ebe7a9905ddee3fbdd30a13313b30e3f004a80e1983094ee57f11110d2d1d` |
| `nas-todo-server-v0.10.0.zip` | 17292 | `899df7a142dec9fb554e10bcdee293cba602bad6eb575c60e87ec9dd467e9b8e` |
| `nas-todo-windows-v0.10.0-x64.zip` | 12669547 | `4f3329c0fefddd637f45a0e244abb1441070eca36bb220994aa1701c250946b8` |

## v0.9.1 历史版本：已有分组选择

[构建 38681645447](https://github.com/whytree222/nas-todo/actions/runs/38681645447) 成功，源提交 `13fac04d35c0b2cbbbdae81969c6765c75d6f1fd`。24项后端测试、两端静态分析、安卓102项/Windows103项Flutter测试、AndroidAPK与Windowsx64编译、安卓8项原生小组件测试以及Windows玻璃与窗口生命周期检查通过。Windows可见性专用测试仅Windows执行。

新建/编辑保留手工输入框，右侧菜单展示全部已知清单，不按当前默认文本过滤。检查覆盖已有（含已完成）任务清单、默认收件箱、重复名称合并、初始/编辑清单、选择后保留标题/备注/日期/优先级、编辑期间新增的清单选项、手输新组保存，以及窄窗口中的长名称和滚动选择。分组仍沿用任务的list_name，没有新增NAS表或协议。

[发布 38682228465](https://github.com/whytree222/nas-todo/actions/runs/38682228465) 成功，[v0.9.1](https://github.com/whytree222/nas-todo/releases/tag/v0.9.1)提供APK、完整WindowsZIP、无密钥NAS源码包、INSTALL.md和SHA256SUMS.txt。核对源提交、文件完整性、图标字体、NAS源码一致、上传字节数及SHA256。现有NAS无需为本次改动再次部署；APK仍为测试签名。

| 文件 | 字节数 | SHA256 |
|---|---:|---|
| `INSTALL.md` | 1051 | `23f0313079715f2ec5ed5e0f05e0b4b216560aed0143ac35cdff0fcc881a82af` |
| `SHA256SUMS.txt` | 367 | `aee333d2f7219f321d0673fd4970859fac1f48698936df7ecfaa3f1ef3b42307` |
| `nas-todo-android-v0.9.1-test.apk` | 160731069 | `2bc9a5246cc31db5b84b1205be65bce7f121e5cc584df3e544558b002f829975` |
| `nas-todo-server-v0.9.1.zip` | 11072 | `65179e873f367537aeee586565264bb6368bc261c0775aa3cb9812438bed6194` |
| `nas-todo-windows-v0.9.1-x64.zip` | 12513877 | `eda4219e8327ffcd468aa7049e61da4cb906bfc77ac47e341e822f42597a81e4` |

## v0.9.0 历史版本：今日鼓励与安卓紧急程度

[构建 38393229963](https://github.com/whytree222/nas-todo/actions/runs/38393229963) 成功，源提交 `0bf438eeb505c16613e9b96e56e3eccf6b7bf5a9`。24项后端测试、两端静态分析、安卓97项/Windows98项Flutter测试及AndroidAPK/Windowsx64编译通过；Windows原生玻璃与独立窗口生命周期检查通过。Windows主窗可见性专用测试仅在Windows执行，安卓按平台跳过。

新增检查覆盖有日期的今日全部完成、跨清单统计、无日期/过去/未来/删除项排除、保存失败不误报、取消后重新完成的每日去重、日期切换、同步和改期不触发、本机去重记录重载、启动时小组件操作待展示、弹窗关闭与多尺寸/大字号/减少动态效果。中文字体渲染的手机及桌面预览用于视觉核对，均使用虚构数据。鼓励是每台设备本机记录，不改变NAS任务或历史成就。

Android15模拟器通过8项原生测试，延续30项列表的实际触摸滑动、五种样式、主题与删除线检查；增加五种小组件的三级优先级文本/不同颜色、黑白绿蓝适配检查。浏览与滑动不打开应用，勾选仍打开主应用保存。受控模拟器宿主检查没有覆盖所有品牌真实桌面。

[发布 38394358412](https://github.com/whytree222/nas-todo/actions/runs/38394358412) 成功，[v0.9.0](https://github.com/whytree222/nas-todo/releases/tag/v0.9.0)提供APK、完整WindowsZIP、无密钥NAS源码包、INSTALL.md和SHA256SUMS.txt。核对测试源提交、文件完整性、NAS源码一致及上传字节数与SHA256。已有v0.7.0 NAS服务不需再次部署；APK仍为测试签名。

| 文件 | 字节数 | SHA256 |
|---|---:|---|
| `INSTALL.md` | 1691 | `32ee8c39df828bae5f301563355dd3c9bc41eae38a3ff13ad89207b87c84727b` |
| `SHA256SUMS.txt` | 367 | `14d8d66e3b7d7424c97e447eb08e884efe215d9e2f338b7d93f38158aaa37692` |
| `nas-todo-android-v0.9.0-test.apk` | 160727493 | `7ddd9d227d61e92606327aaf9b0bd51985da3fbc38cbe847c63b6944c4569983` |
| `nas-todo-server-v0.9.0.zip` | 11072 | `f3ba9654599e4babdb505afd81a811cc297468b9f5556e87391a75c5b829f622` |
| `nas-todo-windows-v0.9.0-x64.zip` | 12509957 | `e49707dc48295cb976169d9af8a6ed688ce5d154ccea1e2e0d3b9ab8d9686664` |

## v0.8.0 历史版本：安卓滑动小组件

[构建 38351581078](https://github.com/whytree222/nas-todo/actions/runs/38351581078) 成功，源提交 `360c14120cfd6b2870b89b6485e8a9b36dbfb16c`。24项后端测试、两端静态分析、各80项Flutter测试及AndroidAPK/Windowsx64编译通过；Windows原生玻璃与独立窗口生命周期检查通过。

Android15模拟器执行6项AndroidJUnitRunner检查：所有列表/卡片工厂提供30条以上数据，样式筛选独立、稳定ID与工厂重建；七天跨年边界及无日期/删除项排除；四色主题、完成删除线及标题不绑定打开应用操作；坏缓存安全回退与重新读取；五个组件和受保护服务已注册、布局为原生ListView/StackView；受控测试窗口中实际触摸滑动移到后续任务，并可到最后一项，Flutter主界面没有被打开。模拟器检查使用独立演示数据和测试宿主，尚未验证所有品牌桌面或真实手机的手势。

旧今日组件保留原provider身份，列表改用新布局资源以重新创建视图。所有模式读取持久化的精简本机副本，不含备注、NAS地址和密钥；勾选仍通过主应用的持久保存队列，未实现关闭应用后的后台NAS同步。已有v0.7.0 NAS服务不需再次更新。

[发布 38352512923](https://github.com/whytree222/nas-todo/actions/runs/38352512923) 成功，[v0.8.0](https://github.com/whytree222/nas-todo/releases/tag/v0.8.0)提供APK、完整WindowsZIP、同版本命名的无密钥NAS源码包、INSTALL.md和SHA256SUMS.txt。核对测试提交、文件完整性、NAS源码一致、上传大小与SHA256。APK仍为测试签名。实现参考 [Android官方集合小组件说明](https://developer.android.com/develop/ui/views/appwidgets/collections)。

| 文件 | 字节数 | SHA256 |
|---|---:|---|
| `INSTALL.md` | 1758 | `7e89a4888b26ada0e00b569c8ffb98e4dabb70465d3bfd7c50cc6dcda6eb8aa4` |
| `SHA256SUMS.txt` | 367 | `77a07672b8642b2f98072f70e4a50ff687a0bbae9cac3543ac766c1052f47e69` |
| `nas-todo-android-v0.8.0-test.apk` | 160696168 | `9ed9c6f3fe9a7ba66c167e53ac673e5f82299f331d8e7824e0fabb24dee57fe7` |
| `nas-todo-server-v0.8.0.zip` | 11072 | `ec75ec6d65801aef156b5ef6a39f94325f68e104129777c7c090b582103a8878` |
| `nas-todo-windows-v0.8.0-x64.zip` | 12499309 | `553b98e84570d21bdea80af48b29a4ee7ceff900fa70533c29dd8a46d2eaeba7` |

## v0.7.0 历史版本：星星、年度热力图与 NAS 月底归档

[构建 38348563693](https://github.com/whytree222/nas-todo/actions/runs/38348563693) 成功，源提交 `e796a0ac5647424d87b9e1e0b75d0e6cb9f87616`。24项后端测试、两端静态分析、各 80 项客户端测试、安卓 APK 与 Windows x64 编译通过，原生小组件及独立窗口生命周期检查通过。

新增成就检查覆盖80%边界、月内短周、闰年、空月、未分类计分与清理豁免、含未完成任务的月末归档、事务失败回滚、重启及备份、跨年和晚到的离线待办。客户端检查覆盖离线缓存、保存失败重试、十二格颜色、多尺寸、年度自动切换及历史浏览。真实隔离 HTTP/SQLite 双端测试确认月底清理同步至两端、成就保留且未同步修改进入冲突而不丢失。测试没有连接使用者的 NAS。

[发布 38348845699](https://github.com/whytree222/nas-todo/actions/runs/38348845699) 成功，[v0.7.0](https://github.com/whytree222/nas-todo/releases/tag/v0.7.0) 包含 APK、完整 Windows ZIP、无密钥 NAS 服务升级包、INSTALL.md 和 SHA256SUMS.txt。核对源提交、APK与Windows完整性、NAS程序与已测试源码一致、所有上传字节数及SHA256。真实密钥和待办数据没有上传。

**现有 NAS 需更新服务才会执行自动结算；仅升级客户端不会清理任务。** 使用者已确认清理本月已安排且有分类的全部任务，包括未完成任务，保留无日期、收件箱和未分类。按北京时间首次启用当月起记录；月内星星预览，月底按 NAS 已收到的数据定格，历史不回改，清理前完整归档。月末离线修改与清理冲突时保留供选择，晚到的新任务保留供改期或手动处理。实际 NAS 部署、系统存储、真实双端及各设备显示仍需验收，安卓仍为测试签名。

| 文件 | 字节数 | SHA256 |
|---|---:|---|
| `INSTALL.md` | 1658 | `b99cfd2ab114b0ff23bed65097172b3b037a79054924a1494bcb692a60921617` |
| `SHA256SUMS.txt` | 367 | `fb823809c0b1dffdd6868e67cf9e156d20f34a403eb97005d7fe96c5be2828d6` |
| `nas-todo-android-v0.7.0-test.apk` | 160684594 | `91cc9ef331c617c14ec7aa5011f88bb4e2ee3886d3ff484de0c7dad12cb7bf42` |
| `nas-todo-server-v0.7.0.zip` | 11072 | `f2ac67d7e59b3a677c64b429107d5ae339c40cee754d5508478adc36e8b73db4` |
| `nas-todo-windows-v0.7.0-x64.zip` | 12499315 | `7d0c11cc3632cdff79d42e605e6881e6751af5510dce537838e9f992bea67cf0` |

## v0.6.2 历史版本：日历直接展开全部待办

[构建 38135799194](https://github.com/whytree222/nas-todo/actions/runs/38135799194) 全部成功，源提交 `9b3688547ed8ffd1f76121cb03813274aea01bd1`。19 项后端测试、两端静态分析、各 69 项客户端测试、Android APK 和 Windows x64 原生编译通过；Windows 小组件与主窗口生命周期检查通过。

取消日期格的预览数量限制，每周按任务最多的一天自动增高，直接展开当天全部待办。完成项保留原位置并划线；日期格中的“详情”可查看完整任务名称及编辑入口。七列适配窗口宽度；任务多时整张日历上下滚动，Windows 支持真实鼠标拖动与滚动条，安卓上下滑动。原有拖动安排和离线同步沿用，不需修改 NAS Compose。

新增三项回归测试：安卓和 Windows 完整应用页面中，当天十二条待办全部存在且最后一条可滚动到、可完成并保留删除线，删除项不出现；放大字体时八条待办全部位于日期格内且不溢出。更新原有日历详情与月末可达性检查，沿用完整应用多尺寸、四至六周月份、拖动安排、取消与保存失败检查。测试使用隔离数据，未连接真实 NAS。

[发布 38135894692](https://github.com/whytree222/nas-todo/actions/runs/38135894692) 成功，[v0.6.2 公开测试版](https://github.com/whytree222/nas-todo/releases/tag/v0.6.2) 提供 APK、完整 Windows ZIP、INSTALL.md 与 SHA256SUMS.txt。核对标签源提交、安装包完整性、字节数和 SHA256；源码和安装包按使用者授权公开，NAS 密钥、数据库和待办内容未上传。

安卓仍为测试签名。实际手机滑动手感、Windows 多显示器与 DPI、真实 NAS 和 ZeroTier 双端同步仍需设备验收。

| 文件 | 字节数 | SHA256 |
|---|---:|---|
| `INSTALL.md` | 1147 | `168db94418ca08990824d7071a0827f0d0dd986d666a15ceacde2d9e0c1b0824` |
| `SHA256SUMS.txt` | 274 | `25a8a37a4dbbf4bf88228a97133485397767b383adfc9cf0a8485a6669b13961` |
| `nas-todo-android-v0.6.2-test.apk` | 160664446 | `d1a7e0e69037021314bc8ef98e42dc75d4417e4288876cc5d39ee0b49ad433c6` |
| `nas-todo-windows-v0.6.2-x64.zip` | 12481338 | `0671b96e0b05e53a9c6312b426e232ee64d4046b4e9c368331183f61a7743268` |

## v0.6.1 历史版本：日历显示修复

[构建 38122913525](https://github.com/whytree222/nas-todo/actions/runs/38122913525) 全部成功，源提交 `730ecdbf83bd1cb28edc4786b81e1fad5abe8176`。19 项后端测试、两端静态分析、各 66 项客户端测试、Android APK 和 Windows x64 原生编译通过；Windows 小组件与主窗口生命周期检查通过。

日历按窗口宽度显示完整七列，按月份实际天数显示四至六周；按可用空间预览一至三条任务，完成项保留删除线，点击“+N 项”查看全天待办。高度不足时使用始终可见的垂直滚动条；Windows 支持鼠标拖动日历空白处，手机支持上下滑动。新建入口移到页头，未安排区域继续固定显示，原有拖动安排与离线同步沿用。

新增 10 项回归检查覆盖七列和实际周数、窄屏与较矮窗口、不同任务预览数量、鼠标手势滚动、短窗口及完整应用页面中的日历访问。结合原有完成划线、任务溢出、Windows 拖动安排、安卓长按拖动、取消与保存失败测试验证新布局。界面检查使用测试事件和隔离数据；没有读取使用者的 NAS 或宣称真实设备显示已验收。

[发布 38122967744](https://github.com/whytree222/nas-todo/actions/runs/38122967744) 成功，[v0.6.1 公开测试版](https://github.com/whytree222/nas-todo/releases/tag/v0.6.1) 提供 APK、完整 Windows ZIP、INSTALL.md 与 SHA256SUMS.txt。使用者已授权公开源码和安装包；核对仓库公开、标签源提交、安装包完整性、上传字节数与 SHA256。NAS 密钥、数据库和待办内容未上传。历史发布记录及原安装包校验值保留。

安卓 APK 仍为测试签名。实际手机滑动与拖动手感、Windows 多显示器及 DPI、真实 NAS 与 ZeroTier 双端同步和系统安全存储仍需设备验收；此次沿用后端数据格式，不需修改 NAS Compose。

| 文件 | 字节数 | SHA256 |
|---|---:|---|
| `INSTALL.md` | 1535 | `5d0dad486f8378272397129e78812019efe1281f1b828ecd37a799d05855922e` |
| `SHA256SUMS.txt` | 274 | `e1d9a1ed685b24161c1e52bb3a9bbdf354934d789c4562e8ef49169add4d7f6c` |
| `nas-todo-android-v0.6.1-test.apk` | 160663418 | `7c36a4f0ca26db06391596ce6218a329218d48b4a5e885c42472721f10a9b8cc` |
| `nas-todo-windows-v0.6.1-x64.zip` | 12476528 | `228aaac13cc27ba6b030268aa590135c1e2a4a9707c7937d4061d7e3407d8569` |

## v0.6.0 历史版本：日历待办与拖动安排

[构建 38121339641](https://github.com/whytree222/nas-todo/actions/runs/38121339641) 全部成功，源提交 `9da1d2dbcc5b29b4ed3bf49d4210fc9b006edcf2`。19 项后端测试、两端静态分析、各 56 项客户端测试、Android APK 和 Windows x64 原生编译通过；Windows 小组件与主窗口生命周期检查通过。

日期格显示待办名称，完成项保留删除线，点击“+N 项”查看全天待办。未安排卡片固定显示，Windows 支持鼠标拖动、安卓支持长按拖动；日期高亮与边缘滚动通过界面测试。

新增检查覆盖取消拖动、保存失败重试、重启后日期与离线队列保留、长标题和手机布局。通过真实测试 HTTP/SQLite 服务验证：拖动安排期间的同步保留最新任务内容、日期传播至另一客户端、已有日期的远端修改不会被旧拖动覆盖。测试使用隔离数据，未连接使用者的 NAS。

[发布 38121818488](https://github.com/whytree222/nas-todo/actions/runs/38121818488) 成功，[v0.6.0 公开测试版](https://github.com/whytree222/nas-todo/releases/tag/v0.6.0) 提供 APK、完整 Windows ZIP、INSTALL.md 与 SHA256SUMS.txt。使用者已明确授权公开源码和安装包；核对仓库公开、标签源提交、安装包完整性、上传字节数与 SHA256。NAS 密钥、数据库和待办内容未上传。历史版本的私有发布记录反映其发布时状态。

安卓 APK 仍为测试签名。实际手机拖动手感、真实 NAS 与 ZeroTier 双端同步、系统安全存储及桌面多显示器仍需设备验收；本次更新沿用后端数据格式，不需修改 NAS Compose。

| 文件 | 字节数 | SHA256 |
|---|---:|---|
| `INSTALL.md` | 1581 | `43ddf7581dabb7c7dd436e1ee1aabd637c6b760429bca556c7e1b9d23bc7b0ad` |
| `nas-todo-android-v0.6.0-test.apk` | 160660410 | `ee9f5153cb361f2c5f17df3b19df3469db93dd894256fcd9b0f5483440a3aaa4` |
| `nas-todo-windows-v0.6.0-x64.zip` | 12477740 | `89acacd0d434dadad1e3638b191862193d36d3a4f0f11764b1f5867e5649c597` |
| `SHA256SUMS.txt` | 274 | `275afb8a4e453c04b4716df1d2bb2f2e8d5e47e6244c8561e6364143a51342f5` |

<!-- v0.5.0-proof:start -->
## v0.5.0 历史版本：应用与小组件主题颜色

[构建 38109357722](https://github.com/whytree222/nas-todo/actions/runs/38109357722) 全部成功，源提交 `a4eb69a8263cf9da2481dfd7b7f38f16b8aeae11`。19 项后端测试、两端静态分析和各 44 项客户端测试、Android APK 与 Windows x64 原生编译通过。

应用新增黑、白、绿、蓝四种主题，小组件可跟随应用或独立选择同样四种颜色。选择保存在当前设备，手机与电脑可使用不同设置；NAS 任务数据、连接密钥、原离线队列和数据格式沿用原实现。

[发布 38109492505](https://github.com/whytree222/nas-todo/actions/runs/38109492505) 成功，[v0.5.0 私有 Release](https://github.com/whytree222/nas-todo/releases/tag/v0.5.0) 包含 APK、Windows 完整 ZIP（含 desktop-widget.cmd）、INSTALL.md 与 SHA256SUMS.txt。发布前核对成功构建与源提交，安装包仍为私有测试版。

本记录确认云端分析、测试、编译与发布。安卓四种小组件颜色的真实桌面显示，以及多显示器、DPI、DX4600、ZeroTier 外网和双端同步仍需设备验收。本机离屏配色检查见下方补充记录。

Android 仍为测试签名，不能保证覆盖旧版；更新前保留未同步内容。窗口共用原后台进程及离线队列，没有系统 Widgets 面板扩展、开机自启或应用内自动更新。
<!-- v0.5.0-proof:end -->

### v0.5.0 安装包校验

发布程序已核对上传后的字节数和 SHA256；对应已通过的源提交 `a4eb69a8263cf9da2481dfd7b7f38f16b8aeae11`。

| 文件 | 字节数 | SHA256 |
|---|---:|---|
| `INSTALL.md` | 1329 | `d5010e72700f8e531ba8e3117c7ae8f76c8e70754ca588336302039abb3842ec` |
| `nas-todo-android-v0.5.0-test.apk` | 160653598 | `9c6a06e06b2a6151011d084b134328bda82f21b117c1717288dd90fcdd9138e2` |
| `nas-todo-windows-v0.5.0-x64.zip` | 12430452 | `6a6f6dc2d7fe7507ece9f82d6ddb38696a5f45bfdfcedcbebcc572cc3523d279` |
| `SHA256SUMS.txt` | 274 | `877b55370c98f85b93187f940262a30778b16dabdbced2178f52d6730d5379e6` |

本机补充验证：同一小组件绘制器的黑、白、绿、蓝离屏配色、预乘透明度像素、启动前主题保留、运行切色重绘及 DWM 明暗属性通过。配色图已目视检查；这些检查与离屏图不等同于四种配色的真实桌面 Acrylic 截图或安卓实机验收。


## v0.4.0 历史版本：毛玻璃与极简 Windows 组件

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

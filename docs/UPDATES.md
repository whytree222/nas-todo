# 应用内更新

用户确认范围：安卓与 Windows 均实现运行时更新，现阶段仅使用 `whytree222/nas-todo` 的 GitHub Release，预留 Gitee。用户提供的文档描述的是另一个应用，预约服务、仓库名、版本号与私有配置不沿用。

Flutter `pubspec.yaml` 是唯一版本源。发布脚本从实际 APK/Windows ZIP 生成 `update.json`、`update-windows.json`，分别含 schema=1、versionCode/versionName/minSupportedVersionCode、publishedAt、apkUrls/zipUrls、大小、SHA256、说明及版本发布页。每个清单≤64KB，每个包≤100MiB；HTTPS、固定仓库、重定向白名单及最多5次跳转。临时下载 `.part`，精确字节数及流式SHA256通过才提交；后台/编辑/同步取消检查与下载，安装须再次由用户选择。自动检查24小时节流、失败1小时、提醒延后24小时；最低版本只提示。

Android 发布构建需要四项 Actions Secrets：`NAS_TODO_KEYSTORE_BASE64`、`NAS_TODO_STORE_PASSWORD`、`NAS_TODO_KEY_ALIAS`、`NAS_TODO_KEY_PASSWORD`。密钥文件只在CI临时目录解码，四项必须齐全，不能回退debug签名。公共证书指纹保存在 `client/android/release-cert.sha256`；CI使用apksigner核对单签名指纹，并核对应用ID、版本和文件哈希。缺少签名时仅做未签名编译预检，不上传可供安装的APK，不允许发布更新。debug构建不启用更新。包校验与系统安装使用文件受限的非导出FileProvider和系统未知来源授权，无静默安装权限。

Windows ZIP在应用私有更新目录校验后展开，拒绝路径穿越、链接、设备文件、备用数据流、重复路径及超量展开。独立 `nas_todo_updater.exe` 通过就绪/确认握手，等待已校验身份的父进程退出，重新校验文件清单后逐项备份和替换；失败按逆序恢复。只修改当前程序目录中更新包拥有的文件，其他文件与AppData中的离线数据、凭据均保留。不申请管理员提权。备份及失败结果保留在本机更新目录，下一次启动可查看提示。Windows包目前未作商业代码签名，不声称完成Authenticode校验；可信来源、包哈希、PE版本/产品身份与文件清单负责检查。

发布必须先有安装包再有清单：在新的GitHub草稿中上传并校验全部包，最后上传两份清单，完整校验后公开并设为latest。历史tag/Release不覆盖、不移动；该版本为正式通道，旧的测试版保留。未来接入Gitee时需使用NAS Todo专用仓库、匹配相同发布字节，并扩展固定仓库策略与测试。

首次从历史debug包迁移需要手动安装一次。旧签名无法恢复时，先确认离线修改已经同步或备份，再处理系统签名不兼容；本程序不会承诺或尝试绕过Android限制。真机系统安装器、厂商未知来源界面与特定磁盘权限，仍需实际设备验收。

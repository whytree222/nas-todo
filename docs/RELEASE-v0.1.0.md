私有待办的首个测试版，支持 Android 和 Windows 离线编辑、连接自己的 NAS 同步，以及冲突选择。

### 下载与安装

- Android：下载 `nas-todo-android-v0.1.0-test.apk`，直接安装。Android 7.0 及以上。这是测试签名；长期使用前需要固定自己的签名密钥。
- Windows x64：下载 `nas-todo-windows-v0.1.0-x64.zip`，完整解压后运行 `nas_todo.exe`。保留同目录的 DLL 和 `data` 文件夹。
- `SHA256SUMS.txt` 为文件校验值；`INSTALL.md` 为本说明的副本。不要下载下面自动生成的 Source code 来安装客户端。

### 连接与首次同步

1. 手机、电脑和 NAS 都连接原来的 ZeroTier 网络。
2. 在两个客户端的连接设置中填写自己 NAS 的服务地址（含端口），以及原 Compose 中 `NAS_TODO_TOKEN` 对应的同步密钥。
3. 保存并同步。安卓新增待办后在 Windows 同步，确认出现同一条待办；再反向修改验证。
4. 手机断网新增待办，关闭并重新打开确认保留，再联网同步到 Windows。

密钥需自行在客户端输入，安装包没有内置密钥。离线修改在上传成功前保存在当前设备；关闭应用后的后台同步目前不保证，重新打开会尝试同步。

### 验证范围

来自已成功完成的构建：https://github.com/whytree222/nas-todo/actions/runs/37900998859

源代码提交：`bc35fc387f926ffb9370369974961cb257a0ceb2`。18 项后端测试通过，两端各 23 项客户端测试通过，静态检查与两端编译成功。发布时检查 APK 压缩完整性、Windows x64 程序和资源目录、上传文件的 SHA256。真实设备安装与 NAS 双端同步仍需按上述步骤验证。

这是私有仓库中的预发布版本，下载需登录有权限的 GitHub 账号。

# 原生平台工程来源

`android/` 与 `windows/` 使用 Flutter 官方 stable 3.47.6 的应用模板：

- 仓库：<https://github.com/flutter/flutter>
- 提交：`5fc346839b5d0eef006ed8404392afb4dfae428d`
- 模板目录：`packages/flutter_tools/templates/app/android.tmpl`、`android-kotlin.tmpl`、`windows.tmpl`
- Gradle wrapper：官方 `flutter_infra_release/gradle-wrapper/fd5c1f2c013565a3bea56ada6df9d2b8e96d56aa/gradle-wrapper.tgz`，包含真实 wrapper JAR 与启动脚本。
- Windows 图标：Flutter 官方 `flutter_template_images` 5.0.0 图片包中 `templates/app/windows.tmpl/runner/resources/app_icon.ico` 的原始资源，为包含 10 个图像的真实 ICO 文件。
- 模板与图片包的 BSD 许可分别保留在 `FLUTTER_TEMPLATE_LICENSE.txt` 与 `FLUTTER_TEMPLATE_IMAGES_LICENSE.txt`。

应用的安卓标识为 `cn.privatetodo.app`。安卓清单加入 INTERNET 权限、禁用系统备份，并允许家庭局域网或私有 VPN 使用 HTTP；直接互联网访问请配置 HTTPS。最低安卓版本为 API 24。Windows 的中文窗口名为“私有待办”，开启 UTF-8 编译；程序文件名为 `nas_todo.exe`。

模板采用其原始 Gradle 9.3.1、Android Gradle Plugin 9.1.0、Kotlin 2.4.0 配置。安卓原型构建使用开发签名；安装后需要保留相同签名才能直接升级而保留本机数据。长期使用或分发前请设置个人 release keystore，并单独备份。

`flutter pub get` 和后续 `flutter build` 会生成平台插件注册文件、`android/local.properties`、Windows `flutter/ephemeral` 等与本机环境相关的文件。这些文件由 Flutter 管理。

本机 Dart 执行环境在 `Platform.resolvedExecutable` 处出错，所以这份工程目前完成了模板渲染与静态审查，尚未成功运行 Flutter 分析、界面测试或原生编译。请在可正常运行 Flutter 的开发环境中执行部署文档列出的分析、测试与构建命令。

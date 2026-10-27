> 最新版本：[v0.13.0](https://github.com/whytree222/nas-todo/releases/tag/v0.13.0)。本次只需更新客户端；v0.11.0 NAS 服务可继续使用。

# 云端编译与公开发布

[构建40047037467](https://github.com/whytree222/nas-todo/actions/runs/40047037467)全部成功，测试源提交`0aecedc24e30423ff497aa2d14b5d1a32501f0a6`。[v0.11.0 Release](https://github.com/whytree222/nas-todo/releases/tag/v0.11.0)提供安装包和升级说明。45项后端测试、两端静态分析、安卓166项/Windows167项Flutter测试和原生构建通过；安卓8项原生小组件检查通过。

仓库按使用者授权保持公开。当前改版上传前核对已公开源文件哈希、变更范围与敏感信息特征，源码包排除.env、数据库、备份、签名密钥和客户端私有配置；由于原NAS密钥不在本地，未声称完成实际密钥逐字比对，此检查方式已获使用者明确同意。

## 构建与下载

main的client/server/scripts或build.yml变化触发GitHub Actions，也可手动运行Build native test apps。固定Flutter3.47.6、Python3.12，Android使用JDK17，Windows使用windows-2022。后端通过后才运行两端分析、测试和构建。Actions产物保留14天，长期下载使用Release。

publish-v013.yml固定已通过的签名构建40461782486和源提交bddd6860c13589c0d2d7586b16a86b74a73f071a。发布前运行8项打包/签名脚本测试，核对APK固定证书、版本、完整Windows目录及NAS代码一致性；在草稿中校验安装包与更新清单后公开为latest。长期沿用四项Actions签名Secrets，禁止重新生成或公开私钥；机制见[UPDATES.md](UPDATES.md)。

## 升级与验收

v0.13.0 沿用现有NAS服务。若已使用 v0.11.0 成就服务，NAS 无需再次部署；仅当仍使用更旧的服务时，先同步并停止原项目，备份整份data，在原compose中替换todo-sync的整个command段，保留密钥、端口、用户和挂载，无需init。command-block.yaml不是完整compose，不能直接覆盖原文件。详见 [升级说明](UPGRADE-v0.11.0.md)。已有习惯从NAS新规则启用当天开始计计划日，历史已结算成就不回算，习惯与打卡历史不参加待办月底清理。

Windows首次解压整个ZIP并保留nas_todo_updater.exe、DLL和data，运行nas_todo.exe；desktop-widget.cmd单独启动毛玻璃组件。两端沿用原ZeroTier地址和访问令牌，验证新增、离线编辑、重启、习惯打卡撤销、双端冲突和新成就规则。真实设备和NAS部署未由云端测试代替。

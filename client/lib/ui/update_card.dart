import 'package:flutter/material.dart';

import '../update_controller.dart';

Future<void> showAppUpdateDialog(
  BuildContext context,
  UpdateController updates,
) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (context) => AnimatedBuilder(
    animation: updates,
    builder: (context, _) {
      if (!updates.allowed) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted && ModalRoute.of(context)?.isCurrent == true) {
            Navigator.pop(context);
          }
        });
      }
      return PopScope(
        canPop: updates.status != UpdateStatus.downloading,
        child: AlertDialog(
          title: const Text('应用更新'),
          scrollable: true,
          content: SizedBox(width: 480, child: UpdateCard(updates: updates)),
          actions: [
            TextButton(
              onPressed: updates.status == UpdateStatus.downloading
                  ? null
                  : () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    },
  ),
);

class UpdateCard extends StatelessWidget {
  const UpdateCard({super.key, required this.updates});
  final UpdateController updates;
  Future<void> _install(BuildContext context) async {
    final windows = updates.info.platform == 'windows';
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('安装更新？'),
        content: Text(
          windows
              ? '将关闭主程序和桌面组件，更新程序文件后自动启动。待办与 NAS 配置保留；替换失败会恢复旧文件。'
              : '系统安装器会再次确认覆盖安装。应用无法静默安装，请保留现有数据。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('继续安装'),
          ),
        ],
      ),
    );
    if (agreed == true) await updates.install();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: updates,
    builder: (context, _) {
      final colors = Theme.of(context).colorScheme;
      final manifest = updates.manifest;
      final status = switch (updates.status) {
        UpdateStatus.unavailable => '此构建未启用应用内更新',
        UpdateStatus.idle => '可手动检查新版本',
        UpdateStatus.checking => '正在检查更新…',
        UpdateStatus.upToDate => '当前已是最新版本',
        UpdateStatus.available => '发现新版本 ${manifest!.versionName}',
        UpdateStatus.downloading =>
          '正在下载 ${(updates.downloaded / manifest!.size * 100).round()}%',
        UpdateStatus.ready =>
          updates.info.platform == 'android'
              ? '安装包已通过大小、SHA-256、版本与签名校验'
              : '安装包已通过 SHA-256、路径、程序标识和版本校验',
        UpdateStatus.failed => '更新未完成',
      };
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.system_update_alt_rounded, color: colors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '应用更新',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '当前版本 ${updates.info.versionName} · ${updates.info.platform == 'android' ? 'Android' : 'Windows'}',
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Text(status, key: const ValueKey('update-status')),
          if (!updates.allowed)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('请先结束编辑或同步，并保持应用在前台。'),
            ),
          if (updates.requiredUpdate)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('建议尽快更新，当前版本仍可继续使用。'),
            ),
          if (manifest != null) ...[
            const SizedBox(height: 10),
            Text('${(manifest.size / 1024 / 1024).toStringAsFixed(1)} MB'),
            if (manifest.notes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(manifest.notes),
              ),
          ],
          if (updates.status == UpdateStatus.downloading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(
                value: manifest == null
                    ? null
                    : updates.downloaded / manifest.size,
              ),
            ),
          if (updates.message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                updates.message!,
                key: const ValueKey('update-message'),
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (updates.active)
                OutlinedButton(
                  onPressed: updates.cancel,
                  child: const Text('取消'),
                ),
              if (!updates.active &&
                  updates.status != UpdateStatus.unavailable &&
                  updates.status != UpdateStatus.ready)
                OutlinedButton(
                  key: const ValueKey('update-check'),
                  onPressed: updates.allowed ? () => updates.check() : null,
                  child: const Text('检查更新'),
                ),
              if (!updates.active &&
                  manifest != null &&
                  updates.status != UpdateStatus.ready)
                FilledButton(
                  key: const ValueKey('update-download'),
                  onPressed: updates.allowed ? updates.download : null,
                  child: const Text('下载更新'),
                ),
              if (updates.status == UpdateStatus.ready)
                FilledButton(
                  key: const ValueKey('update-install'),
                  onPressed: updates.allowed ? () => _install(context) : null,
                  child: const Text('安装更新'),
                ),
              if (updates.hasUpdate && !updates.active)
                TextButton(onPressed: updates.later, child: const Text('稍后提醒')),
              if (manifest != null && !updates.active)
                TextButton(
                  onPressed: updates.openPage,
                  child: const Text('发布页'),
                ),
            ],
          ),
        ],
      );
    },
  );
}

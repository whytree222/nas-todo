import 'package:flutter/material.dart';

import '../app_controller.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _url;
  late final TextEditingController _token;
  bool _obscureToken = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: widget.controller.serverUrl);
    _token = TextEditingController(text: widget.controller.token);
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final saved = await widget.controller.setConnection(_url.text, _token.text);
    if (saved) await widget.controller.sync();
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved && widget.controller.error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('NAS 连接已保存，同步完成。')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final controller = widget.controller;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SettingsCard(
            title: '连接你的 NAS',
            icon: Icons.dns_outlined,
            children: [
              Text(
                '填写 DX4600 中待办服务的地址。安卓和 Windows 使用相同地址与令牌，即可共享数据。',
                style: TextStyle(color: colors.onSurfaceVariant, height: 1.7),
              ),
              const SizedBox(height: 22),
              TextField(
                key: const ValueKey('nas-url'),
                controller: _url,
                enabled: !_saving && !controller.busy,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'NAS 服务地址',
                  hintText: 'http://192.168.1.10:8787',
                  prefixIcon: Icon(Icons.link_rounded),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('nas-token'),
                controller: _token,
                enabled: !_saving && !controller.busy,
                obscureText: _obscureToken,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: '访问令牌',
                  hintText: '部署 Docker 服务时设置的令牌',
                  prefixIcon: const Icon(Icons.key_rounded),
                  suffixIcon: IconButton(
                    tooltip: _obscureToken ? '显示令牌' : '隐藏令牌',
                    onPressed: () => setState(() => _obscureToken = !_obscureToken),
                    icon: Icon(_obscureToken ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _saving || controller.busy ? null : _save,
                  icon: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.sync_rounded, size: 20),
                  label: Text(_saving ? '正在连接' : '保存并同步'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _SettingsCard(
            title: '同步状态',
            icon: Icons.sync_rounded,
            children: [
              _StatusRow(label: '服务地址', value: controller.isConfigured ? controller.serverUrl : '尚未设置'),
              _StatusRow(label: '待上传修改', value: '${controller.pendingCount} 项'),
              _StatusRow(label: '需要处理的冲突', value: '${controller.conflicts.length} 项'),
              _StatusRow(label: '上次成功同步', value: formatSyncTime(controller.lastSyncedAt)),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: controller.busy || !controller.isConfigured ? null : controller.sync,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(controller.syncing ? '正在同步' : '立即同步'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _SettingsCard(
            title: '离线与外网使用',
            icon: Icons.shield_outlined,
            children: [
              _InfoLine(
                icon: Icons.edit_off_outlined,
                title: '离线也能继续',
                text: '修改先保存到本机。连接可用时自动同步，应用恢复到前台也会尝试同步。',
              ),
              const SizedBox(height: 18),
              _InfoLine(
                icon: Icons.vpn_lock_outlined,
                title: '通过私有 VPN 访问 NAS',
                text: 'HTTP 地址适合家庭局域网或 Tailscale 等私有 VPN。直接从互联网访问服务时，请使用 HTTPS。',
              ),
              const SizedBox(height: 18),
              _InfoLine(
                icon: Icons.storage_outlined,
                title: '主库在 NAS，本机保留副本',
                text: '令牌保存在系统安全存储中。更换连接地址不会清空本机待办或待上传修改；服务身份不同会停止同步并提示。',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String formatSyncTime(DateTime? date) {
  if (date == null) return '尚未同步';
  final local = date.toLocal();
  return '${local.year}年${local.month}月${local.day}日 '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.title, required this.icon, required this.children});
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 22, color: colors.primary),
              const SizedBox(width: 12),
              Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
          Expanded(child: SelectableText(value, style: const TextStyle(fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.title, required this.text});
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: colors.onSurfaceVariant, size: 20),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 5),
              Text(text, style: TextStyle(color: colors.onSurfaceVariant, height: 1.7)),
            ],
          ),
        ),
      ],
    );
  }
}

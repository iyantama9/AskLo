import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/admin_service.dart';
import 'admin_dialog.dart';
import 'admin_shell.dart';

class RouterConfigScreen extends StatefulWidget {
  const RouterConfigScreen({super.key});

  @override
  State<RouterConfigScreen> createState() => _RouterConfigScreenState();
}

class _RouterConfigScreenState extends State<RouterConfigScreen> {
  List<dynamic> _configs = [];
  bool _isSyncing = false;
  bool _isTesting = false;
  String? _error;
  late AdminService _adminService;

  @override
  void initState() {
    super.initState();
    _adminService = AdminService(ApiService().token ?? '');
    _loadConfigs();
  }

  Future<void> _loadConfigs() async {
    _error = null;
    try {
      final configs = await _adminService.getRouterConfigs();
      if (mounted) setState(() => _configs = configs);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _syncModels() async {
    setState(() => _isSyncing = true);
    try {
      final result = await _adminService.syncModelsFromRouter();
      if (!mounted) return;
      final count = result['count'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Sync $count model dari router'),
          backgroundColor: Colors.green[700],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Gagal sync model: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _testConnection(int id, String name) async {
    setState(() => _isTesting = true);
    try {
      final result = await _adminService.testRouterConnection(id);
      if (!mounted) return;
      final success = result['success'] == true;
      final duration = result['duration_ms'];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              success
                  ? '✅ $name connection ok (${duration}ms)'
                  : '❌ $name connection gagal'),
          backgroundColor: success
              ? Colors.green[700]
              : Theme.of(context).colorScheme.error,
        ),
      );
      await _loadConfigs();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Test gagal: $e'),
            backgroundColor: Theme.of(context).colorScheme.error),
      );
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  Future<void> _toggleActive(dynamic config) async {
    final active = config['is_active'] == true;
    try {
      await _adminService.updateRouterConfig(config['id'], {
        'is_active': !active,
      });
      await _loadConfigs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(active
                ? 'Router dinonaktifkan'
                : 'Router diaktifkan sebagai router aktif'),
            backgroundColor: Colors.green[700],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: $e'),
              backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
  }

  Future<void> _deleteConfig(int id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Router'),
        content: Text('Yakin ingin menghapus router "$name"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Hapus')),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _adminService.deleteRouterConfig(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Router "$name" dihapus'),
          backgroundColor: Colors.green[700],
        ),
      );
      await _loadConfigs();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal hapus: $e'),
              backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
  }

  void _showConfigDialog({Map<String, dynamic>? config}) {
    final nameController = TextEditingController(text: config?['name'] ?? '');
    final urlController =
        TextEditingController(text: config?['base_url'] ?? '');
    final keyController = TextEditingController(
        text: config?['api_key'] != null ? config!['api_key'] : '');
    final timeoutController =
        TextEditingController(text: (config?['timeout_ms'] ?? 30000).toString());
    final retriesController =
        TextEditingController(text: (config?['max_retries'] ?? 3).toString());

    bool showKey = config == null;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final theme = Theme.of(dialogCtx);

          void doSave() async {
            final name = nameController.text.trim();
            final baseUrl = urlController.text.trim();
            final apiKey = keyController.text.trim();

            if (name.isEmpty || baseUrl.isEmpty) {
              ScaffoldMessenger.of(dialogCtx).showSnackBar(
                const SnackBar(
                    content: Text('⚠️ Name dan Base URL wajib diisi')),
              );
              return;
            }

            final updateBody = <String, dynamic>{
              'name': name,
              'base_url': baseUrl,
              'timeout_ms': int.tryParse(timeoutController.text) ?? 30000,
              'max_retries': int.tryParse(retriesController.text) ?? 3,
            };
            if (apiKey.isNotEmpty) {
              updateBody['api_key'] = apiKey;
            } else if (config == null) {
              ScaffoldMessenger.of(dialogCtx).showSnackBar(
                const SnackBar(content: Text('⚠️ API Key wajib diisi')),
              );
              return;
            }

            Navigator.pop(dialogCtx);
            try {
              if (config != null) {
                await _adminService.updateRouterConfig(config['id'], updateBody);
              } else {
                await _adminService.createRouterConfig(updateBody);
              }
              await _loadConfigs();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(config == null
                        ? '✅ Router ditambahkan'
                        : '✅ Router diupdate'),
                    backgroundColor: Colors.green[700],
                  ),
                );
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Gagal: $e'),
                    backgroundColor: theme.colorScheme.error,
                  ),
                );
              }
            }
          }

          Widget formBody() => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  darkField(
                    controller: nameController,
                    label: 'Name',
                    icon: Icons.router,
                    hint: 'mis. Iyan Router',
                  ),
                  const SizedBox(height: 12),
                  darkField(
                    controller: urlController,
                    label: 'Base URL',
                    icon: Icons.link,
                    hint: 'https://routers.iyantama.tech',
                  ),
                  const SizedBox(height: 12),
                  darkField(
                    controller: keyController,
                    label: 'API Key',
                    icon: Icons.key,
                    obscure: !showKey,
                    hint: config != null
                        ? 'Isi untuk ganti, kosongkan jika tetap'
                        : null,
                    suffix: IconButton(
                      icon: Icon(showKey ? Icons.visibility : Icons.visibility_off,
                          size: 18, color: AdminUi.muted),
                      onPressed: () => setDialogState(() => showKey = !showKey),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: darkField(
                          controller: timeoutController,
                          label: 'Timeout (ms)',
                          icon: Icons.timer,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: darkField(
                          controller: retriesController,
                          label: 'Max Retries',
                          icon: Icons.replay,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                ],
              );

          return AdminModal(
            title: config == null ? 'Tambah Router' : 'Edit Router',
            subtitle: config == null
                ? 'Konfigurasi endpoint LLM router'
                : config['name']?.toString(),
            child: SingleChildScrollView(child: formBody()),
            actions: [
              ...modalActions(
                onCancel: () => Navigator.pop(dialogCtx),
                onConfirm: doSave,
                cancelLabel: 'Batal',
                confirmLabel: config == null ? 'Simpan' : 'Simpan Perubahan',
              ),
            ],
            width: 500,
          );
        },
      ),
    );
  }

  Widget _buildHeaderActions() {
    final isNarrow = MediaQuery.sizeOf(context).width < 640;
    if (isNarrow) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(icon: const Icon(Icons.refresh, size: 20), tooltip: 'Refresh', onPressed: _loadConfigs),
          IconButton(icon: _isSyncing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync, size: 20), tooltip: 'Sync Models', onPressed: _isSyncing ? null : _syncModels),
          IconButton(icon: const Icon(Icons.add, size: 20), tooltip: 'Tambah Router', onPressed: () => _showConfigDialog()),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(icon: const Icon(Icons.refresh, size: 20), tooltip: 'Refresh', onPressed: _loadConfigs),
        const SizedBox(width: 6),
        FilledButton.tonalIcon(
          onPressed: _isSyncing ? null : _syncModels,
          icon: _isSyncing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync, size: 18),
          label: Text(_isSyncing ? 'Syncing…' : 'Sync Models'),
        ),
        const SizedBox(width: 6),
        FilledButton.icon(onPressed: () => _showConfigDialog(), icon: const Icon(Icons.add), label: const Text('Add Router')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textMuted = const Color(0xFF8B8CA0);
    final surface = const Color(0xFF141520);
    final border = const Color(0xFF262738);

    return AdminShell(
      section: 'router',
      onSectionSelected: AdminSectionController.select,
      title: 'Router',
      subtitle: 'Kelola router LLM dan koneksi',
      headerActions: _buildHeaderActions(),
      body: _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline,
                      size: 48, color: theme.colorScheme.error),
                  const SizedBox(height: 16),
                  Text('Gagal memuat data: $_error',
                      style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 16),
                  FilledButton(
                      onPressed: _loadConfigs,
                      child: const Text('Coba Lagi')),
                ],
              ),
            )
          : _buildConfigList(surface, border, textMuted),
    );
  }

  Widget _buildConfigList(
      Color surface, Color border, Color textMuted) {
    final theme = Theme.of(context);

    if (_configs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.router, size: 48, color: textMuted),
            const SizedBox(height: 16),
            Text(
              'Belum ada router yang dikonfigurasi',
              style: TextStyle(color: textMuted, fontSize: 15),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _showConfigDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Add First Router'),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 700;
        final pad = isNarrow ? 16.0 : 24.0;
        return ListView.builder(
          padding: EdgeInsets.all(pad),
          itemCount: _configs.length,
          itemBuilder: (context, index) {
            final config = _configs[index];
            final active = config['is_active'] == true;
            final lastTest = config['last_test_status'];
            final name = config['name']?.toString() ?? '';
            final url = config['base_url']?.toString() ?? '';
            final cfgId = config['id'];

            if (isNarrow) {
              return Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: surface,
                  border: Border.all(color: border),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name,
                                  style: theme.textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text(url,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      fontFamily: 'monospace',
                                      color: theme.colorScheme.onSurfaceVariant),
                                  overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                        Switch(
                          value: active,
                          onChanged: (_) => _toggleActive(config),
                        ),
                      ],
                    ),
                    if (active) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('AKTIF',
                            style: TextStyle(
                                color: Colors.green,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        _buildInfoChip('Timeout', '${config['timeout_ms'] ?? 30000}ms', Icons.timer),
                        _buildInfoChip('Retries', '${config['max_retries'] ?? 3}', Icons.replay),
                        if (lastTest != null) _buildStatusChip(lastTest),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _isTesting ? null : () => _testConnection(cfgId, name),
                          icon: _isTesting ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_arrow, size: 16),
                          label: const Text('Test'),
                        ),
                        const Spacer(),
                        IconButton(icon: const Icon(Icons.edit), tooltip: 'Edit', onPressed: () => _showConfigDialog(config: config)),
                        IconButton(icon: Icon(Icons.delete_outline, color: theme.colorScheme.error), tooltip: 'Delete', onPressed: () => _deleteConfig(cfgId, name)),
                      ],
                    ),
                  ],
                ),
              );
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: surface,
                border: Border.all(color: border),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(name,
                                    style: theme.textTheme.titleLarge
                                        ?.copyWith(fontWeight: FontWeight.bold)),
                                const SizedBox(width: 12),
                                if (active)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text('AKTIF',
                                        style: TextStyle(
                                            color: Colors.green,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.5)),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(url,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                    fontFamily: 'monospace',
                                    color: theme.colorScheme.onSurfaceVariant),
                                overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _isTesting ? null : () => _testConnection(cfgId, name),
                        icon: _isTesting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_arrow, size: 18),
                        label: const Text('Test'),
                      ),
                      const SizedBox(width: 8),
                      IconButton(icon: const Icon(Icons.edit), tooltip: 'Edit', onPressed: () => _showConfigDialog(config: config)),
                      IconButton(icon: Icon(Icons.delete_outline, color: theme.colorScheme.error), tooltip: 'Delete', onPressed: () => _deleteConfig(cfgId, name)),
                      const SizedBox(width: 8),
                      Switch(value: active, onChanged: (_) => _toggleActive(config)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _buildInfoChip('Timeout', '${config['timeout_ms'] ?? 30000}ms', Icons.timer),
                      const SizedBox(width: 12),
                      _buildInfoChip('Max Retries', '${config['max_retries'] ?? 3}', Icons.replay),
                      if (lastTest != null) ...[
                        const SizedBox(width: 12),
                        _buildStatusChip(lastTest),
                      ],
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildInfoChip(String label, String value, IconData icon) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0C14),
        border: Border.all(color: const Color(0xFF262738)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            '$label: $value',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color color;
    String label;
    switch (status) {
      case 'success':
        color = Colors.green;
        label = 'Last test: OK';
        break;
      case 'failed':
        color = Colors.orange;
        label = 'Last test: Gagal';
        break;
      case 'error':
        color = Colors.red;
        label = 'Last test: Error';
        break;
      default:
        color = Colors.grey;
        label = 'Last test: $status';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

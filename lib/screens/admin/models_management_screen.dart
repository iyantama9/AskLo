import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../services/admin_service.dart';
import '../../services/api_service.dart';
import 'admin_dialog.dart';
import 'admin_shell.dart';

class ModelsManagementScreen extends StatefulWidget {
  const ModelsManagementScreen({super.key});

  @override
  State<ModelsManagementScreen> createState() =>
      _ModelsManagementScreenState();
}

class _ModelsManagementScreenState extends State<ModelsManagementScreen> {
  List<dynamic> _models = [];
  bool _isSyncing = false;
  bool _isReordering = false;
  String? _error;
  String _search = '';
  String _providerFilter = '';
  String _featureFilter = '';
  bool _showDisabledOnly = false;
  int _page = 0;
  static const int _perPage = 8;
  late AdminService _adminService;

  @override
  void initState() {
    super.initState();
    _adminService = AdminService(ApiService().token ?? '');
    _loadModels();
  }

  Future<void> _loadModels() async {
    _error = null;
    try {
      final models = await _adminService.getModels();
      if (mounted) setState(() => _models = models);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
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
          content: Text('✅ Catalog updated: $count model aktif dari router'),
          backgroundColor: Colors.green[700],
        ),
      );
      await _loadModels();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Gagal sync: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _toggleModel(dynamic model) async {
    final id = model['id'].toString();
    final index = _models.indexWhere((m) => m['id'] == id);
    if (index == -1) return;
    final oldEnabled = _models[index]['enabled'] == true;

    setState(() {
      _models = List.from(_models);
      _models[index] = {..._models[index], 'enabled': !oldEnabled};
    });

    try {
      await _adminService.toggleModel(id);
      await _loadModels();
    } catch (e) {
      await _loadModels();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _deleteModel(dynamic model) async {
    final id = model['id'].toString();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Model'),
        content:
            Text('Yakin hapus "$id"? Model dari router akan kembali ke metadata default.'),
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
      await _adminService.deleteModel(id);
      await _loadModels();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Model dihapus'),
            backgroundColor: Colors.green[700],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  List<dynamic> get _providers {
    final set = <String>{};
    for (final m in _models) {
      final p = m['owned_by']?.toString() ?? '';
      if (p.isNotEmpty) set.add(p);
    }
    return set.toList()..sort();
  }

  static const List<(String, String)> _featureOptions = [
    ('', 'Semua Fitur'),
    ('image', 'Image Gen'),
    ('vision', 'Vision'),
    ('reasoning', 'Reasoning'),
    ('browse', 'Browse'),
  ];

  List<dynamic> get _visibleModels {
    final query = _search.toLowerCase();
    return _models.where((m) {
      final id = m['id']?.toString().toLowerCase() ?? '';
      final name = m['display_name']?.toString().toLowerCase() ?? '';
      final matchesSearch =
          query.isEmpty || id.contains(query) || name.contains(query);
      final matchesProvider =
          _providerFilter.isEmpty || m['owned_by'] == _providerFilter;
      final matchesFeature = _featureFilter.isEmpty ||
          (m['supports_${_featureFilter}'] == true ||
              m['supports_image_generation'] == true &&
                  _featureFilter == 'image');
      final matchesEnabled =
          !_showDisabledOnly || m['enabled'] != true;
      return matchesSearch && matchesProvider && matchesFeature && matchesEnabled;
    }).toList();
  }

  int get _pageCount => _visibleModels.isEmpty ? 1 : (_visibleModels.length / _perPage).ceil();

  /// The slice of [_visibleModels] for the current page.
  List<dynamic> get _pagedModels {
    final visible = _visibleModels;
    if (_page >= _pageCount) return visible; // keep last valid page
    final start = _page * _perPage;
    final end = (start + _perPage) > visible.length ? visible.length : start + _perPage;
    return visible.sublist(start, end);
  }



  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textMuted = const Color(0xFF8B8CA0);

    return AdminShell(
      section: 'models',
      onSectionSelected: AdminSectionController.select,
      title: 'Models',
      subtitle: 'Kelola model dan provider yang tersedia',
      headerActions: _buildHeaderActions(),
      body: _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline,
                      size: 48, color: theme.colorScheme.error),
                  const SizedBox(height: 16),
                  Text(_error!, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 16),
                  FilledButton(
                      onPressed: _loadModels, child: const Text('Coba Lagi')),
                ],
              ),
            )
          : Column(
              children: [
                _buildFilters(theme, textMuted),
                Expanded(child: _buildModelsList(theme, textMuted)),
              ],
            ),
    );
  }

  /// Header actions that adapt to screen width: full buttons on wide
  /// screens, compact icon-only buttons on narrow (mobile) so they never
  /// overflow the header.
  Widget _buildHeaderActions() {
    final isNarrow = MediaQuery.sizeOf(context).width < 640;

    if (isNarrow) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: 'Refresh',
            onPressed: _loadModels,
          ),
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync, size: 20),
            tooltip: 'Sync dari Router',
            onPressed: _isSyncing ? null : _syncModels,
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 20),
            tooltip: 'Tambah Model',
            onPressed: () => _showModelDialog(),
          ),
          IconButton(
            icon: const Icon(Icons.sort, size: 20),
            tooltip: 'Urutkan Model',
            onPressed: _showReorderDialog,
          ),
          IconButton(
            icon: const Icon(Icons.palette, size: 20),
            tooltip: 'Logo Provider',
            onPressed: _showProviderLogosDialog,
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.refresh, size: 20),
          tooltip: 'Refresh',
          onPressed: _loadModels,
        ),
        const SizedBox(width: 6),
        OutlinedButton.icon(
          onPressed: _isReordering ? null : _showReorderDialog,
          icon: _isReordering
              ? const SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.sort, size: 16),
          label: Text(_isReordering ? 'Menyimpan…' : 'Urutan'),
        ),
        const SizedBox(width: 6),
        FilledButton.tonalIcon(
          onPressed: _isSyncing ? null : _syncModels,
          icon: _isSyncing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.sync, size: 18),
          label: Text(_isSyncing ? 'Syncing…' : 'Sync dari Router'),
        ),
        const SizedBox(width: 6),
        FilledButton.icon(
          onPressed: () => _showModelDialog(),
          icon: const Icon(Icons.add),
          label: const Text('Tambah Model'),
        ),
      ],
    );
  }

  // ── Reorder dialog: move models up/down, then persist to backend ─────────
  Future<void> _showProviderLogosDialog() async {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final muted = cs.onSurfaceVariant;
    final onSurf = cs.onSurface;

    bool busy = false;
    List<dynamic> logos = [];
    List<dynamic> providers = _providers;

    try {
      logos = await _adminService.getProviderLogos();
    } catch (_) {}
    if (!mounted) return;

    final logoMap = <String, String?>{};
    for (final l in logos) {
      final prov = l['provider']?.toString();
      if (prov != null) {
        logoMap[prov] = l['logo_url']?.toString();
      }
    }

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        final dTheme = Theme.of(dialogCtx);
        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> pickAndUpload(String provider) async {
              setState(() => busy = true);
              try {
                final result = await FilePicker.platform.pickFiles(
                  dialogTitle: 'Pilih logo untuk $provider',
                  type: FileType.image,
                  withData: true,
                );
                final file = result?.files.single;
                if (file != null) {
                  final bytes = file.bytes ??
                      await File(file.path ?? '').readAsBytes();
                  final b64 =
                      'data:image/png;base64,${base64.encode(bytes)}';
                  await _adminService.uploadProviderLogo(provider, b64);
                  logoMap[provider] = await _resolveLogoUrl(provider);
                  ScaffoldMessenger.of(dialogCtx).showSnackBar(
                    SnackBar(content: Text('✅ Logo $provider diunggah')),
                  );
                }
              } catch (e) {
                ScaffoldMessenger.of(dialogCtx).showSnackBar(
                  SnackBar(content: Text('Gagal: $e')),
                );
              } finally {
                setState(() => busy = false);
              }
            }

            return Dialog(
              backgroundColor: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: muted.withValues(alpha: 0.2)),
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.palette, size: 18, color: cs.primary),
                          const SizedBox(width: 10),
                          Text(
                            'Logo Provider',
                            style: dTheme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.pop(dialogCtx),
                            icon: const Icon(Icons.close, size: 20),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Upload logo brand untuk tiap provider. Logo muncul di dropdown model (main page & settings).',
                        style: TextStyle(color: muted, fontSize: 12.5),
                      ),
                      const SizedBox(height: 14),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight:
                              MediaQuery.sizeOf(dialogCtx).height * 0.55),
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            for (final p in providers)
                              Container(
                                margin:
                                    const EdgeInsets.symmetric(vertical: 4),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerHighest
                                      .withValues(alpha: 0.35),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    // current logo preview
                                    if (logoMap[p] != null)
                                      Padding(
                                        padding: const EdgeInsets.only(right: 10),
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          child: Image.network(
                                            logoMap[p]!,
                                            width: 32,
                                            height: 32,
                                            fit: BoxFit.contain,
                                            errorBuilder: (_, __, ___) =>
                                                SizedBox(width: 32, height: 32),
                                          ),
                                        ),
                                      )
                                    else
                                      Padding(
                                        padding: const EdgeInsets.only(right: 10),
                                        child: Container(
                                          width: 32,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            color: cs.primary
                                                .withValues(alpha: 0.12),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          alignment: Alignment.center,
                                          child: Icon(
                                            Icons.image_outlined,
                                            size: 16,
                                            color: muted,
                                          ),
                                        ),
                                      ),
                                    Expanded(
                                      child: Text(
                                        p,
                                        style: TextStyle(
                                            color: onSurf,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed:
                                          busy ? null : () => pickAndUpload(p),
                                      child: Text(
                                        logoMap[p] != null
                                            ? 'Ganti'
                                            : 'Upload',
                                        style: TextStyle(
                                            color: cs.primary,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    if (logoMap[p] != null)
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        onPressed: busy
                                            ? null
                                            : () async {
                                                setState(() => busy = true);
                                                try {
                                                  await _adminService
                                                      .deleteProviderLogo(p);
                                                  logoMap.remove(p);
                                                } catch (e) {
                                                  ScaffoldMessenger.of(dialogCtx)
                                                      .showSnackBar(
                                                    SnackBar(
                                                        content:
                                                            Text('Gagal: $e')),
                                                  );
                                                } finally {
                                                  setState(
                                                      () => busy = false);
                                                }
                                              },
                                        icon: Icon(
                                            Icons.delete_outline,
                                            size: 16,
                                            color: Colors.red),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          onPressed: () => Navigator.pop(dialogCtx),
                          child: const Text('Selesai'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Best-effort resolve of a provider's current logo URL for the dialog.
  Future<String?> _resolveLogoUrl(String provider) async {
    try {
      final logos = await _adminService.getProviderLogos();
      for (final l in logos) {
        if (l['provider'] == provider) return l['logo_url']?.toString();
      }
    } catch (_) {}
    return null;
  }

  Future<void> _showReorderDialog() async {
    // Start from the live catalog order (already sorted by sort_order/display).
    final order = _models
        .where((m) => m['enabled'] != false)
        .map((m) => m['id'].toString())
        .toList();
    if (order.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Min. 2 model untuk mengurutkan')),
      );
      return;
    }

    var busy = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final cs = theme.colorScheme;
        final onSurf = cs.onSurface;
        final muted = cs.onSurfaceVariant;
        final accent = cs.primary;
        final surface = cs.surface;

        String labelFor(String id) {
          for (final m in _models) {
            if (m['id'].toString() == id) {
              final dn = m['display_name']?.toString();
              if (dn != null && dn.isNotEmpty) return dn;
            }
          }
          return id;
        }

        moveAt(int i, int delta) {
          final j = i + delta;
          if (j < 0 || j >= order.length) return;
          final t = order[i];
          order[i] = order[j];
          order[j] = t;
        }

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Container(
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: muted.withValues(alpha: 0.2)),
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.sort_rounded, size: 18, color: accent),
                          const SizedBox(width: 10),
                          Text('Urutan Model di Halaman Utama',
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800)),
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            icon: const Icon(Icons.close, size: 20),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Geser ke atas/bawah, lalu Simpan. Model teratas muncul paling awal di picker.',
                        style: TextStyle(color: muted, fontSize: 12.5),
                      ),
                      const SizedBox(height: 14),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.5),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: order.length,
                          itemBuilder: (context, i) {
                            final id = order[i];
                            return Container(
                              margin: const EdgeInsets.symmetric(vertical: 3),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest
                                    .withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Text('${i + 1}',
                                      style: TextStyle(
                                          color: accent,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      labelFor(id),
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: onSurf, fontSize: 13.5),
                                    ),
                                  ),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    icon: Icon(Icons.arrow_upward,
                                        size: 16,
                                        color: i == 0 ? muted : onSurf),
                                    onPressed: i == 0
                                        ? null
                                        : () {
                                            moveAt(i, -1);
                                            setDialogState(() {});
                                          },
                                  ),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    icon: Icon(Icons.arrow_downward,
                                        size: 16,
                                        color: i == order.length - 1 ? muted : onSurf),
                                    onPressed: i == order.length - 1
                                        ? null
                                        : () {
                                            moveAt(i, 1);
                                            setDialogState(() {});
                                          },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text('Batal'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: busy ? null : () async {
                              setDialogState(() => busy = true);
                              final ids = List<String>.from(order);
                              Navigator.pop(dialogContext);
                              setState(() => _isReordering = true);
                              try {
                                await _adminService.reorderModels(ids);
                                await _loadModels();
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('✅ Urutan model disimpan')),
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Gagal: $e')),
                                  );
                                }
                              } finally {
                                if (mounted) setState(() => _isReordering = false);
                              }
                            },
                            child: const Text('Simpan Urutan'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFilters(ThemeData theme, Color textMuted) {
    final surface = const Color(0xFF141520);
    final border = const Color(0xFF262738);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 560;
        return Container(
          margin: EdgeInsets.fromLTRB(isNarrow ? 16 : 28, 0, isNarrow ? 16 : 28, 16),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: surface,
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: isNarrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _filterSearch(theme, textMuted),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _modernDropdown(
                            icon: Icons.layers,
                            current: _providerFilter,
                            placeholder: 'Semua Provider',
                            options: [
                              ('', 'Semua Provider'),
                              ..._providers.map((p) => (p, p)),
                            ],
                            onSelected: (v) {
                              setState(() => _providerFilter = v ?? '');
                              _page = 0;
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _modernDropdown(
                            icon: Icons.category,
                            current: _featureFilter,
                            placeholder: 'Semua Fitur',
                            options: _featureOptions,
                            onSelected: (v) {
                              setState(() => _featureFilter = v ?? '');
                              _page = 0;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _pillToggle(
                          label: 'Nonaktif',
                          value: _showDisabledOnly,
                          onChanged: (v) => setState(() {
                            _showDisabledOnly = v;
                            _page = 0;
                          }),
                        ),
                        const Spacer(),
                        Text(
                          '${_visibleModels.length} / ${_models.length}',
                          style: TextStyle(color: textMuted, fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    _filterSearch(theme, textMuted),
                    const SizedBox(width: 12),
                    _modernDropdown(
                      icon: Icons.layers,
                      current: _providerFilter,
                      placeholder: 'Semua Provider',
                      options: [
                        ('', 'Semua Provider'),
                        ..._providers.map((p) => (p, p)),
                      ],
                      onSelected: (v) {
                        setState(() => _providerFilter = v ?? '');
                        _page = 0;
                      },
                    ),
                    const SizedBox(width: 10),
                    _modernDropdown(
                      icon: Icons.category,
                      current: _featureFilter,
                      placeholder: 'Semua Fitur',
                      options: _featureOptions,
                      onSelected: (v) {
                        setState(() => _featureFilter = v ?? '');
                        _page = 0;
                      },
                    ),
                    const SizedBox(width: 10),
                    _pillToggle(
                      label: 'Nonaktif',
                      value: _showDisabledOnly,
                      onChanged: (v) => setState(() {
                        _showDisabledOnly = v;
                        _page = 0;
                      }),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${_visibleModels.length} / ${_models.length}',
                      style: TextStyle(color: textMuted, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
        );
      },
    );
  }

  /// The search field, extracted so it can be used full-width on mobile.
  Widget _filterSearch(ThemeData theme, Color textMuted) {
    return TextField(
      onChanged: (v) {
        setState(() => _search = v);
        _page = 0;
      },
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Cari model...',
        hintStyle: TextStyle(color: textMuted, fontSize: 14),
        prefixIcon: Icon(Icons.search, color: textMuted, size: 18),
        filled: false,
        fillColor: Colors.transparent,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        contentPadding: EdgeInsets.zero,
      ),
    );
  }

  /// Compact pill-style toggle with an inline label, matching the modern
  /// dropdown look (rounded, subtle border, no heavy box-in-box).
  Widget _pillToggle({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final textMuted = const Color(0xFF8B8CA0);
    final border = const Color(0xFF262738);
    final accent = const Color(0xFFA78BFA);
    return Container(
      decoration: BoxDecoration(
        color: value ? const Color(0xFF1F1B3A) : const Color(0xFF0B0C14),
        border: Border.all(color: value ? accent : border),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: accent,
            activeTrackColor: accent.withValues(alpha: 0.4),
            inactiveThumbColor: textMuted,
            inactiveTrackColor: const Color(0xFF141520),
          ),
          Text(label, style: TextStyle(color: value ? accent : textMuted, fontSize: 12)),
        ],
      ),
    );
  }

  /// Modern dropdown: a bordered pill trigger + a rounded overlay menu with
  /// checkmark on the selected option. Replaces the default [DropdownButton]
  /// which looks dated on the web target.
  Widget _modernDropdown({
    required IconData icon,
    required String current,
    required String placeholder,
    required List<(String, String)> options,
    required ValueChanged<String?> onSelected,
  }) {
    final textMuted = const Color(0xFF8B8CA0);
    final border = const Color(0xFF262738);
    final accent = const Color(0xFFA78BFA);
    final currentLabel = options
            .firstWhere((o) => o.$1 == current, orElse: () => ('', placeholder))
        .$2;

    return PopupMenuButton<String>(
      tooltip: null,
      padding: EdgeInsets.zero,
      offset: const Offset(0, 30),
      color: const Color(0xFF141520),
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: border),
      ),
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final opt in options)
          PopupMenuItem<String>(
            value: opt.$1,
            height: 40,
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  child: opt.$1 == current
                      ? Icon(Icons.check, size: 16, color: accent)
                      : const SizedBox.shrink(),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    opt.$2,
                    style: TextStyle(
                      color: opt.$1 == current ? Colors.white : Colors.white.withValues(alpha: 0.75),
                      fontSize: 14,
                      fontWeight: opt.$1 == current ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        width: 168,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0B0C14),
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                currentLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
            Icon(Icons.keyboard_arrow_down, size: 18, color: textMuted),
          ],
        ),
      ),
    );
  }

  Widget _buildModelsList(ThemeData theme, Color textMuted) {
    final surface = const Color(0xFF141520);
    final border = const Color(0xFF262738);
    final accent = const Color(0xFFA78BFA);
    final visible = _visibleModels;
    final pageModels = _pagedModels;

    if (visible.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 48, color: textMuted),
            const SizedBox(height: 16),
            Text('Tidak ada model cocok dengan filter',
                style: theme.textTheme.bodyLarge?.copyWith(color: textMuted)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _syncModels,
              icon: const Icon(Icons.sync),
              label: const Text('Sync dari Router'),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 700;
        final padH = isNarrow ? 16.0 : 28.0;
        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: padH),
                child: Container(
                  decoration: BoxDecoration(
                    color: surface,
                    border: Border.all(color: border),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: isNarrow
                      ? Column(
                          children: [
                            for (final m in pageModels)
                              _buildMobileModelCard(theme, m, textMuted, accent),
                          ],
                        )
                      : Column(
                          children: [
                            _buildHeaderRow(theme, textMuted, accent),
                            ...pageModels.map(
                                (m) => _buildModelRow(theme, m, textMuted, accent)),
                          ],
                        ),
                ),
              ),
            ),
            // Pager
            if (_pageCount > 1)
              Container(
                padding: EdgeInsets.symmetric(horizontal: padH, vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _pagerButton(Icons.chevron_left, _page > 0, () {
                      setState(() => _page--);
                    }, textMuted),
                    const SizedBox(width: 14),
                    Text(
                      'Halam ${_page + 1} / $_pageCount',
                      style: TextStyle(color: textMuted, fontSize: 13),
                    ),
                    const SizedBox(width: 14),
                    _pagerButton(Icons.chevron_right, _page < _pageCount - 1, () {
                      setState(() => _page++);
                    }, textMuted),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  /// Stacked, mobile-first card used on narrow screens where the 5-column
  /// table would overflow.
  Widget _buildMobileModelCard(
      ThemeData theme, dynamic model, Color textMuted, Color accent) {
    final id = model['id']?.toString() ?? '';
    final provider = model['owned_by']?.toString() ?? '—';
    final enabled = model['enabled'] == true;
    final source = model['source']?.toString() ?? 'db';
    final features = _modelFeatures(model);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1018),
        border: Border.all(color: const Color(0xFF1E2030)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  border: Border.all(color: accent.withValues(alpha: 0.35)),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(Icons.hexagon, color: accent, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(id,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'monospace'),
                        overflow: TextOverflow.ellipsis),
                    Text(
                        source == 'router'
                            ? 'Router'
                            : source == 'router+db'
                                ? 'Router + DB'
                                : 'Override DB',
                        style: TextStyle(color: textMuted, fontSize: 11)),
                  ],
                ),
              ),
              Switch(
                value: enabled,
                onChanged: (_) => _toggleModel(model),
                activeThumbColor: accent,
                activeTrackColor: accent.withValues(alpha: 0.35),
                inactiveThumbColor: textMuted,
                inactiveTrackColor: const Color(0xFF262738),
              ),
            ],
          ),
          if (features.isNotEmpty || provider.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.layers, size: 15, color: textMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(provider,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: features.map((f) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF262738).withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: const Color(0xFF262738)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_featureIcon(f), size: 12, color: textMuted),
                    const SizedBox(width: 4),
                    Text(f, style: TextStyle(color: textMuted, fontSize: 11.5)),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _iconActionButton(
                Icons.edit_outlined,
                textMuted,
                () => _showModelDialog(existing: model),
                tooltip: 'Edit',
              ),
              const SizedBox(width: 6),
              _iconActionButton(
                Icons.delete_outline,
                const Color(0xFFDC2626),
                () => _deleteModel(model),
                tooltip: 'Hapus',
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<String> _modelFeatures(dynamic model) {
    final features = <String>[];
    if (model['supports_reasoning'] == true) features.add('Reasoning');
    if (model['supports_vision'] == true) features.add('Vision');
    if (model['supports_browse'] == true) features.add('Browse');
    if (model['supports_image_generation'] == true) features.add('Image');
    return features;
  }

  Widget _pagerButton(IconData icon, bool enabled, VoidCallback onTap, Color muted) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: enabled ? const Color(0xFF141520) : Colors.transparent,
            border: Border.all(color: enabled ? const Color(0xFF262738) : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: enabled ? Colors.white : muted.withValues(alpha: 0.35)),
        ),
      ),
    );
  }

  Widget _buildHeaderRow(ThemeData theme, Color textMuted, Color accent) {
    Widget col(String label, {int flex = 1}) {
      return Expanded(
        flex: flex,
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                  color: textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4),
            ),
            const SizedBox(width: 4),
            Icon(Icons.swap_vert, size: 13, color: textMuted),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF1E2030))),
      ),
      child: Row(
        children: [
          col('Model', flex: 3),
          col('Provider', flex: 2),
          col('Fitur', flex: 2),
          col('Status', flex: 1),
          Expanded(child: Text('Aksi', style: TextStyle(color: textMuted, fontSize: 13, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Widget _buildModelRow(
      ThemeData theme, dynamic model, Color textMuted, Color accent) {
    final id = model['id']?.toString() ?? '';
    final provider = model['owned_by']?.toString() ?? '—';
    final enabled = model['enabled'] == true;
    final source = model['source']?.toString() ?? 'db';

    final features = <String>[];
    if (model['supports_reasoning'] == true) features.add('Reasoning');
    if (model['supports_vision'] == true) features.add('Vision');
    if (model['supports_browse'] == true) features.add('Browse');
    if (model['supports_image_generation'] == true) features.add('Image');

    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF1E2030))),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.1),
                      border: Border.all(
                          color: accent.withValues(alpha: 0.35), width: 1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.hexagon, color: accent, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          id,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              fontFamily: 'monospace'),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          source == 'router'
                              ? 'Router'
                              : source == 'router+db'
                                  ? 'Router + DB'
                                  : 'Override DB',
                          style:
                              TextStyle(color: textMuted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: const Color(0xFF262738).withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.layers,
                        color: textMuted, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    provider,
                    style:
                        const TextStyle(color: Colors.white, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: features.map((f) {
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF262738)
                          .withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(7),
                      border:
                          Border.all(color: const Color(0xFF262738)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_featureIcon(f),
                            size: 13, color: textMuted),
                        const SizedBox(width: 5),
                        Text(f,
                            style:
                                TextStyle(color: textMuted, fontSize: 12)),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Center(
              child: Switch(
                value: enabled,
                onChanged: (_) => _toggleModel(model),
                activeColor: accent,
                activeTrackColor: accent.withValues(alpha: 0.35),
                inactiveThumbColor: textMuted,
                inactiveTrackColor: const Color(0xFF262738),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _iconActionButton(
                    Icons.edit_outlined,
                    textMuted,
                    () => _showModelDialog(existing: model),
                    tooltip: 'Edit',
                  ),
                  const SizedBox(width: 6),
                  _iconActionButton(
                    Icons.delete_outline,
                    const Color(0xFFDC2626),
                    () => _deleteModel(model),
                    tooltip: 'Hapus',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _featureIcon(String f) {
    switch (f) {
      case 'Image':
        return Icons.image;
      case 'Vision':
        return Icons.visibility_outlined;
      case 'Reasoning':
        return Icons.psychology_outlined;
      case 'Browse':
        return Icons.public_outlined;
      default:
        return Icons.circle_outlined;
    }
  }

  Widget _iconActionButton(IconData icon, Color color, VoidCallback onTap,
      {required String tooltip}) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E2030),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF262738)),
            ),
            child: Icon(icon, color: color, size: 17),
          ),
        ),
      ),
    );
  }

  void _showModelDialog({dynamic existing}) {
    final idController =
        TextEditingController(text: existing?['id']?.toString() ?? '');
    final nameController =
        TextEditingController(text: existing?['display_name'] ?? '');
    final providerController =
        TextEditingController(text: existing?['owned_by'] ?? '');

    bool supportsReasoning = existing?['supports_reasoning'] == true;
    bool supportsVision = existing?['supports_vision'] == true;
    bool supportsImageGen = existing?['supports_image_generation'] == true;
    bool supportsBrowse = existing?['supports_browse'] == true;
    String costTier = existing?['cost_tier']?.toString() ?? 'standard';
    bool enabled = existing?['enabled'] != false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final theme = Theme.of(dialogCtx);
          Widget content() => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  darkField(
                    controller: idController,
                    label: 'Model ID',
                    icon: Icons.tag,
                    enabled: existing == null,
                    hint: existing == null ? 'mis. wz/gemini-3.8-flash' : null,
                  ),
                  const SizedBox(height: 12),
                  darkField(
                    controller: nameController,
                    label: 'Display Name',
                    icon: Icons.title,
                    hint: 'Label yang tampil ke user',
                  ),
                  const SizedBox(height: 12),
                  darkField(
                    controller: providerController,
                    label: 'Kategori / Provider',
                    icon: Icons.category,
                    hint: 'mis. Alibaba, QwenChain, OpenAI',
                  ),
                  const SizedBox(height: 20),
                  // Capability toggles — modern pill chips, not default checkboxes
                  const _SectionLabel('Fitur'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      pillToggleRow(
                        label: 'Reasoning',
                        icon: Icons.psychology_outlined,
                        value: supportsReasoning,
                        onChanged: (v) => setDialogState(() => supportsReasoning = v),
                      ),
                      pillToggleRow(
                        label: 'Vision',
                        icon: Icons.visibility_outlined,
                        value: supportsVision,
                        onChanged: (v) => setDialogState(() => supportsVision = v),
                      ),
                      pillToggleRow(
                        label: 'Image Gen',
                        icon: Icons.image_outlined,
                        value: supportsImageGen,
                        onChanged: (v) => setDialogState(() => supportsImageGen = v),
                      ),
                      pillToggleRow(
                        label: 'Browse',
                        icon: Icons.public_outlined,
                        value: supportsBrowse,
                        onChanged: (v) => setDialogState(() => supportsBrowse = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Cost tier + enabled, side by side
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _SectionLabel('Cost Tier'),
                            const SizedBox(height: 8),
                            _segmented(
                              value: costTier,
                              options: const [
                                ('standard', 'Standard'),
                                ('premium', 'Premium'),
                                ('image', 'Image'),
                              ],
                              onChanged: (v) => setDialogState(() => costTier = v),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _SectionLabel('Status'),
                            const SizedBox(height: 8),
                            pillToggleRow(
                              label: enabled ? 'Aktif' : 'Nonaktif',
                              icon: enabled ? Icons.check_circle_outline : Icons.remove_circle_outline,
                              value: enabled,
                              onChanged: (v) => setDialogState(() => enabled = v),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              );

          void doSave() async {
            Navigator.pop(dialogCtx);
            final body = <String, dynamic>{
              'id': idController.text.trim(),
              'display_name': nameController.text.trim(),
              'owned_by': providerController.text.trim(),
              'supports_reasoning': supportsReasoning,
              'supports_vision': supportsVision,
              'supports_image_generation': supportsImageGen,
              'supports_browse': supportsBrowse,
              'cost_tier': costTier,
              'enabled': enabled,
            };
            try {
              if (existing == null) {
                await _adminService.createModel(body);
              } else {
                await _adminService.updateModel(existing['id'].toString(), body);
              }
              await _loadModels();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(existing == null
                        ? '✅ Model ditambahkan'
                        : '✅ Model diupdate'),
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

          return AdminModal(
            title: existing == null ? 'Tambah Model' : 'Edit Model',
            subtitle: existing == null
                ? 'Definisikan model baru yang tersedia'
                : '${existing['id']}',
            child: SingleChildScrollView(child: content()),
            actions: [
              ...modalActions(
                onCancel: () => Navigator.pop(dialogCtx),
                onConfirm: doSave,
                confirmLabel: existing == null ? 'Simpan' : 'Update',
                busy: false,
              ),
            ],
            width: 520,
          );
        },
      ),
    );
  }

  /// Modern rounded segmented control (single-line chips) for cost tier.
  Widget _segmented({
    required String value,
    required List<(String, String)> options,
    required ValueChanged<String> onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onChanged(options[i].$1),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: value == options[i].$1
                      ? const Color(0xFF1F1B3A)
                      : AdminUi.field,
                  border: Border.all(
                      color: value == options[i].$1 ? AdminUi.accent : AdminUi.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  options[i].$2,
                  style: TextStyle(
                    color: value == options[i].$1 ? Colors.white : AdminUi.muted,
                    fontSize: 13,
                    fontWeight: value == options[i].$1 ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A small section label used above dialog field groups.
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
          color: AdminUi.muted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8),
    );
  }
}

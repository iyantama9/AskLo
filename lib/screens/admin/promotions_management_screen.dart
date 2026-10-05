import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/admin_service.dart';
import 'admin_shell.dart';

class PromotionsManagementScreen extends StatefulWidget {
  const PromotionsManagementScreen({super.key});

  @override
  State<PromotionsManagementScreen> createState() =>
      _PromotionsManagementScreenState();
}

class _PromotionsManagementScreenState
    extends State<PromotionsManagementScreen> {
  List<dynamic> _promotions = [];
  bool _isLoading = true;
  String? _error;
  late AdminService _adminService;

  @override
  void initState() {
    super.initState();
    _adminService = AdminService(ApiService().token ?? '');
    _loadPromotions();
  }

  Future<void> _loadPromotions() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final promos = await _adminService.getPromotions();
      setState(() {
        _promotions = promos;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Widget _buildHeaderActions() {
    final isNarrow = MediaQuery.sizeOf(context).width < 640;
    if (isNarrow) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(icon: const Icon(Icons.refresh, size: 20), tooltip: 'Refresh', onPressed: _loadPromotions),
          IconButton(icon: const Icon(Icons.add, size: 20), tooltip: 'Create Promo', onPressed: () => _showPromoDialog()),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(icon: const Icon(Icons.refresh, size: 20), tooltip: 'Refresh', onPressed: _loadPromotions),
        const SizedBox(width: 8),
        FilledButton.icon(onPressed: () => _showPromoDialog(), icon: const Icon(Icons.add), label: const Text('Create')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AdminShell(
      section: 'promotions',
      onSectionSelected: AdminSectionController.select,
      title: 'Promotions',
      subtitle: 'Kelola promosi dan kuota',
      headerActions: _buildHeaderActions(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error, size: 48, color: theme.colorScheme.error),
                      const SizedBox(height: 16),
                      Text('Error: $_error'),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _loadPromotions,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _promotions.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.local_offer,
                              size: 48, color: theme.colorScheme.outline),
                          const SizedBox(height: 16),
                          const Text('No promotions found'),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () => _showPromoDialog(),
                            icon: const Icon(Icons.add),
                            label: const Text('Create First Promo'),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(24),
                      itemCount: _promotions.length,
                      itemBuilder: (context, index) =>
                          _buildPromoCard(_promotions[index]),
                    ),
    );
  }

  Widget _buildPromoCard(Map<String, dynamic> promo) {
    final theme = Theme.of(context);
    final startDate = DateTime.parse(promo['start_date']);
    final endDate = DateTime.parse(promo['end_date']);
    final now = DateTime.now();
    final isActive = promo['is_active'] == true;
    final isCurrent = now.isAfter(startDate) && now.isBefore(endDate);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 560;
            final titleRow = Row(
              children: [
                Flexible(
                  child: Text(
                    promo['name']?.toString() ?? '',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                if (isActive && isCurrent)
                  const Chip(
                    label: Text('Active'),
                    backgroundColor: Color(0xFF1F4D2E),
                    labelStyle: TextStyle(color: Colors.greenAccent),
                  ),
              ],
            );

            final metaItems = <Widget>[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_today,
                      size: 16, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text('${_fmtDate(startDate)} → ${_fmtDate(endDate)}',
                      style: theme.textTheme.bodySmall),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.people,
                      size: 16, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text('${promo['user_count'] ?? 0} users',
                      style: theme.textTheme.bodySmall),
                ],
              ),
              if (promo['unlimited_quota'] == true)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.all_inclusive,
                        size: 16, color: Colors.purple.shade700),
                    const SizedBox(width: 4),
                    Text('Unlimited',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.purple.shade700)),
                  ],
                ),
            ];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          titleRow,
                          if (promo['description'] != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              promo['description']?.toString() ?? '',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => _showPromoDialog(promo: promo),
                      tooltip: 'Edit',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (isNarrow)
                  Wrap(spacing: 14, runSpacing: 8, children: metaItems)
                else
                  Row(children: [
                    ...[
                      for (var i = 0; i < metaItems.length; i++)
                        ...[
                          if (i > 0) const SizedBox(width: 16),
                          metaItems[i],
                        ],
                    ],
                  ]),
              ],
            );
          },
        ),
      ),
    );
  }

  String _fmtDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  void _showPromoDialog({Map<String, dynamic>? promo}) {
    final nameCtrl = TextEditingController(text: promo?['name']);
    final descCtrl = TextEditingController(text: promo?['description']);
    DateTime? startDate =
        promo != null ? DateTime.parse(promo['start_date']) : null;
    DateTime? endDate =
        promo != null ? DateTime.parse(promo['end_date']) : null;
    bool unlimited = promo?['unlimited_quota'] ?? true;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(promo == null ? 'Create Promotion' : 'Edit Promotion'),
          content: SizedBox(
            width: 450,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: startDate ?? DateTime.now(),
                            firstDate: DateTime.now(),
                            lastDate:
                                DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) {
                            setDialogState(() => startDate = picked);
                          }
                        },
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(
                          startDate == null
                              ? 'Start Date'
                              : _fmtDate(startDate!),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate:
                                endDate ?? DateTime.now().add(const Duration(days: 7)),
                            firstDate: startDate ?? DateTime.now(),
                            lastDate:
                                DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) {
                            setDialogState(() => endDate = picked);
                          }
                        },
                        icon: const Icon(Icons.event, size: 16),
                        label: Text(
                          endDate == null ? 'End Date' : _fmtDate(endDate!),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  title: const Text('Unlimited Quota'),
                  subtitle: const Text('No daily limits during promo'),
                  value: unlimited,
                  onChanged: (v) {
                    setDialogState(() => unlimited = v ?? true);
                  },
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (nameCtrl.text.isEmpty ||
                    startDate == null ||
                    endDate == null) {
                  return;
                }
                Navigator.pop(dialogContext);
                try {
                  final data = {
                    'name': nameCtrl.text,
                    'description':
                        descCtrl.text.isEmpty ? null : descCtrl.text,
                    'start_date': startDate!.toIso8601String(),
                    'end_date': endDate!.toIso8601String(),
                    'unlimited_quota': unlimited,
                  };
                  if (promo == null) {
                    await _adminService.createPromotion(data);
                  } else {
                    await _adminService.updatePromotion(promo['id'], data);
                  }
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(promo == null
                            ? 'Promotion created'
                            : 'Promotion updated'),
                        backgroundColor: Colors.green[700],
                      ),
                    );
                    _loadPromotions();
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed: $e'),
                        backgroundColor:
                            Theme.of(context).colorScheme.error,
                      ),
                    );
                  }
                }
              },
              child: Text(promo == null ? 'Create' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}

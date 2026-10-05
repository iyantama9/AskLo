import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/admin_service.dart';
import 'admin_shell.dart';

class UsersManagementScreen extends StatefulWidget {
  const UsersManagementScreen({super.key});

  @override
  State<UsersManagementScreen> createState() => _UsersManagementScreenState();
}

class _UsersManagementScreenState extends State<UsersManagementScreen> {
  List<dynamic> _users = [];
  bool _isLoading = true;
  String? _error;
  late AdminService _adminService;

  int _currentPage = 1;
  int _totalPages = 1;
  String _searchQuery = '';
  String _roleFilter = '';

  @override
  void initState() {
    super.initState();
    _adminService = AdminService(ApiService().token ?? '');
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await _adminService.getUsers(
        page: _currentPage,
        search: _searchQuery,
        role: _roleFilter,
      );

      setState(() {
        _users = response['users'] as List<dynamic>;
        final pagination = response['pagination'];
        _totalPages = pagination['pages'];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AdminShell(
      section: 'users',
      onSectionSelected: AdminSectionController.select,
      title: 'Users',
      subtitle: 'Kelola pengguna dan peran',
      headerActions: IconButton(
        icon: const Icon(Icons.refresh),
        onPressed: _loadUsers,
        tooltip: 'Refresh',
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error, size: 48, color: theme.colorScheme.error),
                      const SizedBox(height: 16),
                      Text('Error: $_error', style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 16),
                      FilledButton(onPressed: _loadUsers, child: const Text('Coba Lagi')),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Compact filter bar
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      child: LayoutBuilder(
                        builder: (context, c) {
                          final isNarrow = c.maxWidth < 560;
                          final searchField = TextField(
                            decoration: InputDecoration(
                              hintText: 'Cari username...',
                              prefixIcon: const Icon(Icons.search, size: 20),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              filled: true,
                              fillColor: theme.colorScheme.surface,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                            ),
                            onChanged: (v) {
                              setState(() {
                                _searchQuery = v;
                                _currentPage = 1;
                              });
                              _loadUsers();
                            },
                          );
                          final roleField = SizedBox(
                            width: isNarrow ? double.infinity : 140,
                            child: DropdownMenu<String>(
                              label: const Text('Role', style: TextStyle(fontSize: 13)),
                              initialSelection: _roleFilter.isEmpty ? null : _roleFilter,
                              dropdownMenuEntries: const [
                                DropdownMenuEntry(value: '', label: 'Semua'),
                                DropdownMenuEntry(value: 'user', label: 'User'),
                                DropdownMenuEntry(value: 'admin', label: 'Admin'),
                              ],
                              menuHeight: 120,
                              onSelected: (v) {
                                setState(() {
                                  _roleFilter = v ?? '';
                                  _currentPage = 1;
                                });
                                _loadUsers();
                              },
                            ),
                          );
                          return isNarrow
                              ? Column(
                                  children: [
                                    searchField,
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(child: roleField),
                                        const SizedBox(width: 10),
                                        Text('${_users.length} user',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                                      ],
                                    ),
                                  ],
                                )
                              : Row(
                                  children: [
                                    Expanded(child: searchField),
                                    const SizedBox(width: 12),
                                    roleField,
                                    const SizedBox(width: 12),
                                    Text('${_users.length} user',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                                  ],
                                );
                        },
                      ),
                    ),
                    // Table
                    Expanded(
                      child: _buildUsersTable(theme),
                    ),
                    // Pagination inline
                    if (_users.isNotEmpty && _totalPages > 1)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.chevron_left, size: 20),
                              onPressed: _currentPage > 1
                                  ? () {
                                      setState(() => _currentPage--);
                                      _loadUsers();
                                    }
                                  : null,
                              visualDensity: VisualDensity.compact,
                            ),
                            Text(
                              'Hal $_currentPage / $_totalPages',
                              style:
                                  theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.chevron_right, size: 20),
                              onPressed: _currentPage < _totalPages
                                  ? () {
                                      setState(() => _currentPage++);
                                      _loadUsers();
                                    }
                                  : null,
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
    );
  }

  Widget _buildUsersTable(ThemeData theme) {
    if (_users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_off, size: 44, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text('Tidak ada user',
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 720;
        final pad = isNarrow ? 16.0 : 24.0;
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          child: SingleChildScrollView(
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border.all(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(12),
              ),
              child: isNarrow
                  ? Column(
                      children: [
                        for (final user in _users)
                          _buildMobileUserCard(user),
                      ],
                    )
                  : Column(
                      children: [
                        _buildUsersHeader(theme),
                        ..._users.map((user) => _buildUserRow(user)),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildUsersHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          _th('Username', 2.2),
          _th('Role', 1.2),
          _th('Chats', 0.8),
          _th('Promo', 0.8),
          _th('Gabung', 1.5),
          _th('Aksi', 0.8, align: TextAlign.right),
        ],
      ),
    );
  }

  Widget _buildMobileUserCard(dynamic user) {
    final theme = Theme.of(context);
    final username = user['username']?.toString() ?? '';
    final isAdmin = user['role'] == 'admin';
    final createdAt = DateTime.tryParse(user['created_at']?.toString() ?? '') ?? DateTime.now();
    final lastLogin = user['last_login_at'] != null
        ? DateTime.tryParse(user['last_login_at'].toString())
        : null;
    final chatCount = int.tryParse('${user['chat_count']}') ?? 0;
    final activePromos = int.tryParse('${user['active_promotions']}') ?? 0;

    return Container(
      margin: const EdgeInsets.all(14),
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(username,
                        style:
                            theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    if (lastLogin != null)
                      Text('Last: ${_formatRelativeTime(lastLogin)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: isAdmin
                      ? Colors.purple.withValues(alpha: 0.15)
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  (user['role'] ?? 'user').toString().toUpperCase(),
                  style: TextStyle(
                      color: isAdmin ? Colors.purple : null,
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _userStat('Chats', '$chatCount'),
              ),
              Expanded(
                child: _userStat('Promo', '$activePromos'),
              ),
              Expanded(
                child: _userStat('Gabung', _formatDate(createdAt)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                icon: const Icon(Icons.visibility, size: 18),
                onPressed: () => _showUserDetails(user),
                tooltip: 'Detail',
                visualDensity: VisualDensity.compact,
                iconSize: 18,
              ),
              PopupMenuButton(
                icon: const Icon(Icons.more_vert, size: 18),
                iconSize: 18,
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'assign_promo', child: Text('Assign Promo')),
                  const PopupMenuItem(value: 'change_role', child: Text('Change Role')),
                ],
                onSelected: (value) {
                  switch (value) {
                    case 'assign_promo':
                      _showAssignPromoDialog(user);
                      break;
                    case 'change_role':
                      _showChangeRoleDialog(user);
                      break;
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _userStat(String label, String value) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(value, style: theme.textTheme.bodyMedium),
      ],
    );
  }

  Widget _th(String label, double flex, {TextAlign align = TextAlign.left}) {
    final theme = Theme.of(context);
    return Expanded(
      flex: (flex * 10).round(),
      child: Text(
        label.toUpperCase(),
        textAlign: align,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildUserRow(dynamic user) {
    final theme = Theme.of(context);
    final isAdmin = user['role'] == 'admin';
    final createdAt = DateTime.parse(user['created_at']);
    final lastLogin = user['last_login_at'] != null
        ? DateTime.parse(user['last_login_at'])
        : null;
    final chatCount = int.tryParse('${user['chat_count']}') ?? 0;
    final activePromos = int.tryParse('${user['active_promotions']}') ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: Row(
        children: [
          // Username (flex 22)
          Expanded(
            flex: 22,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user['username'] ?? '',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w500)),
                if (lastLogin != null)
                  Text(
                    'Last login: ${_formatRelativeTime(lastLogin)}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 12),
                  ),
              ],
            ),
          ),
          // Role (flex 12)
          Expanded(
            flex: 12,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: isAdmin
                        ? Colors.purple.withValues(alpha: 0.15)
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    (user['role'] ?? 'user').toUpperCase(),
                    style: TextStyle(
                      color: isAdmin ? Colors.purple : null,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Chats (flex 8)
          Expanded(
            flex: 8,
            child: Text(
              '$chatCount',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          // Promo (flex 8)
          Expanded(
            flex: 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$activePromos',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                if (activePromos > 0) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.local_offer,
                      size: 14, color: Colors.green.shade700),
                ],
              ],
            ),
          ),
          // Gabung (flex 15)
          Expanded(
            flex: 15,
            child: Text(
              _formatDate(createdAt),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          // Aksi (flex 8)
          Expanded(
            flex: 8,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.visibility, size: 18),
                  onPressed: () => _showUserDetails(user),
                  tooltip: 'Detail',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                ),
                PopupMenuButton(
                  icon: const Icon(Icons.more_vert, size: 18),
                  iconSize: 18,
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'assign_promo',
                      child: Text('Assign Promo',
                          style: TextStyle(fontSize: 14)),
                    ),
                    const PopupMenuItem(
                      value: 'change_role',
                      child: Text('Change Role',
                          style: TextStyle(fontSize: 14)),
                    ),
                  ],
                  onSelected: (value) {
                    switch (value) {
                      case 'assign_promo':
                        _showAssignPromoDialog(user);
                        break;
                      case 'change_role':
                        _showChangeRoleDialog(user);
                        break;
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatRelativeTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return _formatDate(date);
  }

  void _showUserDetails(Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('User Details: ${user['username']}'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('ID', '${user['id']}'),
              _buildDetailRow('Role', user['role']),
              _buildDetailRow('Total Chats', '${user['chat_count']}'),
              _buildDetailRow('Active Promotions', '${user['active_promotions']}'),
              _buildDetailRow('Joined', _formatDate(DateTime.parse(user['created_at']))),
              if (user['last_login_at'] != null)
                _buildDetailRow(
                  'Last Login',
                  _formatDate(DateTime.parse(user['last_login_at'])),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  void _showAssignPromoDialog(Map<String, dynamic> user) {
    List<dynamic> _promos = [];
    bool _loadingPromos = true;
    int? _selectedPromoId;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Load promotions on first build
          if (_loadingPromos) {
            _adminService.getPromotions().then((promos) {
              setDialogState(() {
                _promos = promos;
                _loadingPromos = false;
              });
            }).catchError((e) {
              setDialogState(() => _loadingPromos = false);
            });
          }

          return AlertDialog(
            title: Text('Assign Promotion to ${user['username']}'),
            content: SizedBox(
              width: 400,
              child: _loadingPromos
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : _promos.isEmpty
                      ? const Text('No promotions available')
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: _promos.map<Widget>((promo) {
                            return RadioListTile<int>(
                              title: Text(promo['name']),
                              subtitle: Text(
                                promo['description'] ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              value: promo['id'],
                              groupValue: _selectedPromoId,
                              onChanged: (value) {
                                setDialogState(() => _selectedPromoId = value);
                              },
                            );
                          }).toList(),
                        ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: _selectedPromoId == null
                    ? null
                    : () async {
                        Navigator.pop(dialogContext);
                        try {
                          await _adminService.assignPromotion(
                            _selectedPromoId!,
                            [user['id']],
                          );
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Promotion assigned to ${user['username']}',
                                ),
                                backgroundColor: Colors.green[700],
                              ),
                            );
                            _loadUsers();
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
                child: const Text('Assign'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showChangeRoleDialog(Map<String, dynamic> user) {
    String selectedRole = user['role'];

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Change Role: ${user['username']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Current role: ${user['role']}'),
              const SizedBox(height: 16),
              const Text('Change to:'),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'user', label: Text('User')),
                  ButtonSegment(value: 'admin', label: Text('Admin')),
                ],
                selected: {selectedRole},
                onSelectionChanged: (Set<String> selection) {
                  setDialogState(() => selectedRole = selection.first);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selectedRole == user['role']
                  ? null
                  : () async {
                      Navigator.pop(dialogContext);
                      try {
                        await _adminService.changeUserRole(
                          user['id'],
                          selectedRole,
                        );
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${user['username']} role changed to $selectedRole',
                              ),
                              backgroundColor: Colors.green[700],
                            ),
                          );
                          _loadUsers();
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
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

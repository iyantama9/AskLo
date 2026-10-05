import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ChatSidebar extends StatefulWidget {
  final List<Map<String, dynamic>> chats;
  final int? selectedChatId;
  final ValueChanged<int> onChatSelected;
  final VoidCallback onNewChat;
  final Function(int, String) onRenameChat;
  final ValueChanged<int> onDeleteChat;
  final VoidCallback onLogout;
  final String username;
  final String? avatarUrl;
  final VoidCallback? onEditProfile;

  const ChatSidebar({
    super.key,
    required this.chats,
    required this.selectedChatId,
    required this.onChatSelected,
    required this.onNewChat,
    required this.onRenameChat,
    required this.onDeleteChat,
    required this.onLogout,
    required this.username,
    this.avatarUrl,
    this.onEditProfile,
  });

  @override
  State<ChatSidebar> createState() => _ChatSidebarState();
}

class _ChatSidebarState extends State<ChatSidebar> {
  int? _editingId;
  final _editController = TextEditingController();
  final _searchController = TextEditingController();
  String _searchQuery = '';
  List<Map<String, dynamic>>? _searchResults;
  bool _isSearching = false;

  @override
  void dispose() {
    _editController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) async {
    setState(() => _searchQuery = query);
    if (query.trim().length >= 3) {
      setState(() => _isSearching = true);
      try {
        final results = await ApiService().searchChats(query.trim());
        if (mounted) {
          setState(() {
            _searchResults = results;
            _isSearching = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isSearching = false);
      }
    } else {
      setState(() => _searchResults = null);
    }
  }

  void _startEditing(int chatId, String currentTitle) {
    setState(() {
      _editingId = chatId;
      _editController.text = currentTitle;
    });
  }

  void _submitEdit(int chatId) {
    final newTitle = _editController.text.trim();
    if (newTitle.isNotEmpty) {
      widget.onRenameChat(chatId, newTitle);
    }
    setState(() => _editingId = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      color: theme.brightness == Brightness.dark
          ? const Color(0xFF121218)
          : const Color(0xFFF5F3FF),
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: widget.onNewChat,
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: const Text('New Chat'),
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Search chats...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged('');
                          },
                        )
                      : null,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: theme.colorScheme.outline.withValues(alpha: 0.2),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: theme.colorScheme.outline.withValues(alpha: 0.2),
                    ),
                  ),
                  filled: true,
                  fillColor: theme.colorScheme.surface,
                ),
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 4),
            // Chat list
            Expanded(
              child: Builder(
                builder: (context) {
                  // Apply filter
                  final displayChats =
                      _searchQuery.isNotEmpty && _searchResults != null
                      ? _searchResults!
                      : _searchQuery.isNotEmpty
                      ? widget.chats.where((c) {
                          final title = (c['title'] ?? '')
                              .toString()
                              .toLowerCase();
                          return title.contains(_searchQuery.toLowerCase());
                        }).toList()
                      : widget.chats;

                  if (_isSearching) {
                    return const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    );
                  }

                  if (displayChats.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _searchQuery.isNotEmpty
                              ? 'No results found'
                              : 'No chats yet.\nTap "New Chat" to start!',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    itemCount: displayChats.length,
                    itemBuilder: (context, index) {
                      final chat = displayChats[index];
                      final chatId = chat['id'] as int;
                      final isSelected = chatId == widget.selectedChatId;
                      final isEditing = _editingId == chatId;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            onTap: () => widget.onChatSelected(chatId),
                            borderRadius: BorderRadius.circular(12),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? theme.colorScheme.primary.withValues(
                                        alpha: 0.15,
                                      )
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.chat_bubble_outline_rounded,
                                    size: 16,
                                    color: isSelected
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: isEditing
                                        ? TextField(
                                            controller: _editController,
                                            autofocus: true,
                                            style: theme.textTheme.bodySmall,
                                            decoration: const InputDecoration(
                                              isDense: true,
                                              contentPadding:
                                                  EdgeInsets.symmetric(
                                                    vertical: 4,
                                                  ),
                                              border: InputBorder.none,
                                            ),
                                            onSubmitted: (_) =>
                                                _submitEdit(chatId),
                                          )
                                        : Text(
                                            chat['title'] ?? 'New Chat',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  fontWeight: isSelected
                                                      ? FontWeight.w600
                                                      : FontWeight.w400,
                                                  color: isSelected
                                                      ? theme
                                                            .colorScheme
                                                            .primary
                                                      : theme
                                                            .colorScheme
                                                            .onSurface,
                                                ),
                                          ),
                                  ),
                                  if (isSelected && !isEditing)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        InkWell(
                                          onTap: () => _startEditing(
                                            chatId,
                                            chat['title'] ?? '',
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.all(4),
                                            child: Icon(
                                              Icons.edit_rounded,
                                              size: 14,
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                        InkWell(
                                          onTap: () =>
                                              widget.onDeleteChat(chatId),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.all(4),
                                            child: Icon(
                                              Icons.delete_outline_rounded,
                                              size: 14,
                                              color: Colors.red.withValues(
                                                alpha: 0.7,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            // User info + logout
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: theme.colorScheme.outline.withValues(alpha: 0.2),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: theme.colorScheme.primary,
                        backgroundImage:
                            (widget.avatarUrl != null &&
                                widget.avatarUrl!.isNotEmpty)
                                ? NetworkImage(widget.avatarUrl!)
                                : null,
                        child: (widget.avatarUrl != null &&
                                widget.avatarUrl!.isNotEmpty)
                            ? null
                            : Text(
                                widget.username[0].toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                      if (widget.onEditProfile != null)
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Material(
                            color: theme.colorScheme.surface,
                            shape: CircleBorder(),
                            shadowColor:
                                theme.colorScheme.shadow.withValues(alpha: 0.4),
                            elevation: 2,
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: widget.onEditProfile,
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: Icon(
                                  Icons.edit_rounded,
                                  size: 10,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.username,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onLogout,
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    tooltip: 'Logout',
                    iconSize: 18,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

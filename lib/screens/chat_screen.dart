import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../helpers/clipboard_paste.dart';
import '../core/constants.dart';
import '../main.dart';
import '../models/artifact_model.dart';
import '../models/message_model.dart';
import '../services/api_service.dart';
import '../services/chat_service.dart';
import '../widgets/artifact_viewer.dart';
import '../widgets/chat_input.dart';
import '../widgets/chat_sidebar.dart';
import '../widgets/message_bubble.dart';
import '../widgets/model_selector.dart';
import '../widgets/profile_editor_dialog.dart';
import '../widgets/welcome_view.dart';
import 'playground_screen.dart' deferred as playground;

class _RetryPayload {
  final String content;
  final List<PendingFile> files;
  final Set<ChatTool> tools;

  const _RetryPayload({
    required this.content,
    required this.files,
    required this.tools,
  });
}

class ChatScreen extends StatefulWidget {
  final VoidCallback onLogout;
  const ChatScreen({super.key, required this.onLogout});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final ApiService _api = ApiService();
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> _chats = [];
  List<ChatMessage> _messages = [];
  List<ModelInfo> _models = [];
  int? _selectedChatId;
  String? _currentModel;
  bool _isLoading = false;
  bool _isSubmittingFeedback = false;
  bool _sidebarOpen = true;
  _RetryPayload? _lastRetryPayload;
  final Map<String, _RetryPayload> _retryPayloads = {};
  String? _usageWarning;
  List<ArtifactSummary> _artifacts = [];
  ChatArtifact? _activeArtifact;
  bool _artifactPanelOpen = false;
  // Only animate the LATEST 2 messages (user + assistant)
  final Map<String, AnimationController> _animControllers = {};

  // Streamed tokens flow through this notifier so only the active bubble
  // rebuilds during streaming; the rest of the screen stays untouched.
  final ValueNotifier<String> _streamingText = ValueNotifier<String>('');
  String? _streamingMessageId;

  // File attachments (up to 5)
  List<PendingFile> _pendingFiles = [];

  // Active tools
  final Set<ChatTool> _activeTools = {};

  // Profile (nickname + avatar)
  String? _profileDisplayName;
  String? _profileAvatarUrl;

  // Reasoning toggle for models that expose a separate thinking id.
  bool _reasoningEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadModelCatalog();
    _loadChats();
    _loadUsage();
    _loadProfile();
    // Setup web clipboard paste listener for images
    setupWebPasteListener(_onImagePasted);
  }

  Future<void> _loadProfile() async {
    if (!_api.isLoggedIn) return;
    try {
      final data = await _api.getProfile();
      if (!mounted) return;
      final user = data['user'] as Map?;
      setState(() {
        _profileDisplayName = user?['display_name']?.toString() ?? _api.username;
        _profileAvatarUrl = user?['avatar_url']?.toString();
      });
    } catch (_) {}
  }

  Future<void> _openProfileEditor() async {
    if (!_api.isLoggedIn) return;
    final currentName = _profileDisplayName ?? _api.username ?? '';
    await ProfileEditorDialog.show(
      context,
      displayName: currentName,
      avatarUrl: _profileAvatarUrl,
      onChanged: (_) {},
    );
    if (!mounted) return;
    await _loadProfile();
  }

  Future<void> _loadModelCatalog() async {
    final catalog = await ApiService().getModelCatalog();
    final models = catalog.models.map(ModelInfo.fromJson).toList();
    if (!mounted) return;
    setState(() {
      _models = models;
      // Preserve the in-use model when it is still served; otherwise fall back
      // to the admin-configured default (or the first available model).
      _currentModel = _models.any((m) => m.id == _currentModel)
          ? _currentModel
          : catalog.defaultModel ?? (_models.isEmpty ? null : _models.first.id);
    });
  }

  Future<void> _loadUsage() async {
    if (!_api.isLoggedIn) return;
    try {
      final data = await _api.getUsage();
      final usage = List<Map<String, dynamic>>.from(data['usage'] as List);
      final nearLimit = usage.where((item) {
        final percent = (item['percent'] as num?)?.toDouble() ?? 0;
        return percent >= 0.8;
      }).toList();
      if (!mounted) return;
      setState(() {
        _usageWarning = nearLimit.isEmpty
            ? null
            : 'Quota hampir habis: ${nearLimit.map((e) => e['kind']).join(', ')}';
      });
    } catch (_) {}
  }

  void _showErrorSnack(String message) {
    if (!mounted) return;
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: theme.colorScheme.errorContainer,
          elevation: 10,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: theme.colorScheme.error.withValues(alpha: 0.24),
            ),
          ),
          content: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: theme.colorScheme.onErrorContainer,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 4),
        ),
      );
  }

  String _formatError(String message, {String? code, String? requestId}) {
    final cleanCode = code?.trim();
    final cleanRequestId = requestId?.trim();
    final buffer = StringBuffer(message.trim());
    if (cleanCode != null && cleanCode.isNotEmpty) {
      buffer.write('\n\nKode: $cleanCode');
    }
    if (cleanRequestId != null && cleanRequestId.isNotEmpty) {
      buffer.write('\nID bantuan: $cleanRequestId');
    }
    return buffer.toString();
  }

  void _showSuccessSnack(String message) {
    if (!mounted) return;
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: theme.colorScheme.primaryContainer,
          elevation: 10,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: theme.colorScheme.primary.withValues(alpha: 0.24),
            ),
          ),
          content: Row(
            children: [
              Icon(
                Icons.check_circle_outline_rounded,
                color: theme.colorScheme.onPrimaryContainer,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 3),
        ),
      );
  }

  Future<void> _showFeedbackDialog() async {
    final controller = TextEditingController();
    var canSubmit = false;

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          final theme = Theme.of(dialogContext);
          return StatefulBuilder(
            builder: (context, setDialogState) {
              Future<void> submit() async {
                final content = controller.text.trim();
                if (content.isEmpty || _isSubmittingFeedback) return;

                setState(() => _isSubmittingFeedback = true);
                setDialogState(() {});
                try {
                  await _api.submitFeedback(
                    content,
                    chatId: _selectedChatId,
                    model: _currentModel,
                  );
                  if (!mounted || !dialogContext.mounted) return;
                  Navigator.of(dialogContext).pop();
                  _showSuccessSnack(
                    'Terima kasih, kritik dan saran berhasil dikirim.',
                  );
                } catch (e) {
                  if (!mounted) return;
                  final apiError = e is ApiException ? e : null;
                  _showErrorSnack(
                    apiError?.supportMessage ??
                        'Gagal mengirim kritik dan saran. Coba lagi.',
                  );
                } finally {
                  if (mounted) {
                    setState(() => _isSubmittingFeedback = false);
                    if (dialogContext.mounted) setDialogState(() {});
                  }
                }
              }

              final isDark = theme.brightness == Brightness.dark;
              final surface = isDark
                  ? const Color(0xFF191925)
                  : theme.colorScheme.surface;
              final fieldColor = isDark
                  ? const Color(0xFF24243A)
                  : theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.55,
                    );
              final outlineColor = theme.colorScheme.outline.withValues(
                alpha: isDark ? 0.18 : 0.55,
              );

              return Dialog(
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                backgroundColor: Colors.transparent,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: outlineColor),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.28),
                          blurRadius: 34,
                          offset: const Offset(0, 18),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Kritik dan Saran',
                                      style: theme.textTheme.titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -0.3,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Bantu AskLo jadi lebih enak dipakai.',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                            fontWeight: FontWeight.w500,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: _isSubmittingFeedback
                                    ? null
                                    : () => Navigator.of(dialogContext).pop(),
                                icon: const Icon(Icons.close_rounded, size: 20),
                                tooltip: 'Tutup',
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),
                          TextField(
                            controller: controller,
                            autofocus: true,
                            minLines: 5,
                            maxLines: 7,
                            maxLength: 2000,
                            textInputAction: TextInputAction.newline,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              height: 1.45,
                              fontWeight: FontWeight.w500,
                            ),
                            decoration: InputDecoration(
                              hintText:
                                  'Tulis kritik, saran, bug, atau ide fitur di sini...',
                              alignLabelWithHint: true,
                              filled: true,
                              fillColor: fieldColor,
                              contentPadding: const EdgeInsets.fromLTRB(
                                18,
                                18,
                                18,
                                12,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(22),
                                borderSide: BorderSide(color: outlineColor),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(22),
                                borderSide: BorderSide(color: outlineColor),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(22),
                                borderSide: BorderSide(
                                  color: theme.colorScheme.primary,
                                  width: 1.6,
                                ),
                              ),
                              counterStyle: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            onChanged: (value) {
                              final nextCanSubmit = value.trim().isNotEmpty;
                              if (nextCanSubmit != canSubmit) {
                                setDialogState(() => canSubmit = nextCanSubmit);
                              }
                            },
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Masukan kamu akan tersimpan bersama chat aktif jika ada.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              TextButton(
                                onPressed: _isSubmittingFeedback
                                    ? null
                                    : () => Navigator.of(dialogContext).pop(),
                                child: const Text('Batal'),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.icon(
                                onPressed: canSubmit && !_isSubmittingFeedback
                                    ? submit
                                    : null,
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                icon: _isSubmittingFeedback
                                    ? SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: theme.colorScheme.onPrimary,
                                        ),
                                      )
                                    : const Icon(Icons.send_rounded, size: 18),
                                label: Text(
                                  _isSubmittingFeedback
                                      ? 'Mengirim...'
                                      : 'Kirim',
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
      );
    } finally {
      controller.dispose();
      if (mounted && _isSubmittingFeedback) {
        setState(() => _isSubmittingFeedback = false);
      }
    }
  }

  MessageAttachment _attachmentFromPending(PendingFile file) {
    return MessageAttachment(
      url: file.url,
      name: file.name,
      contentType: file.contentType,
      sizeBytes: file.sizeBytes,
      previewBytes: file.previewBytes,
    );
  }

  ArtifactSummary? _artifactFromApi(Map<String, dynamic> message) {
    final raw = message['artifact'];
    if (raw is Map) {
      return ArtifactSummary.fromJson(Map<String, dynamic>.from(raw));
    }
    return null;
  }

  Future<void> _loadChatArtifacts(int chatId) async {
    try {
      final artifacts = await _api.getChatArtifacts(chatId);
      if (!mounted) return;
      setState(() => _artifacts = artifacts);
    } catch (_) {}
  }

  Future<void> _openArtifact(String artifactId) async {
    try {
      final artifact = await _api.getArtifact(artifactId);
      if (!mounted) return;
      final isMobile =
          MediaQuery.sizeOf(context).width < AppConstants.sidebarBreakpoint;
      if (isMobile) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => Scaffold(
              body: SafeArea(
                child: ArtifactViewer(
                  artifact: artifact,
                  onClose: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
        );
        return;
      }
      setState(() {
        _activeArtifact = artifact;
        _artifactPanelOpen = true;
        if (!_artifacts.any((item) => item.id == artifact.id)) {
          _artifacts = [artifact, ..._artifacts];
        }
      });
    } catch (e) {
      _showErrorSnack('Gagal membuka artifact: $e');
    }
  }

  void _closeArtifactPanel() {
    setState(() => _artifactPanelOpen = false);
  }

  List<MessageAttachment> _attachmentsFromApi(Map<String, dynamic> message) {
    final rawUrls = message['file_urls'];
    final rawNames = message['file_names'];
    final urls = rawUrls is List
        ? rawUrls.map((value) => value.toString()).toList()
        : <String>[
            if ((message['file_url']?.toString() ?? '').isNotEmpty)
              message['file_url'].toString(),
          ];
    final names = rawNames is List
        ? rawNames.map((value) => value.toString()).toList()
        : <String>[
            if ((message['file_name']?.toString() ?? '').isNotEmpty)
              message['file_name'].toString(),
          ];

    final attachments = <MessageAttachment>[];
    for (var i = 0; i < urls.length; i++) {
      final url = urls[i];
      final name = i < names.length ? names[i] : 'Lampiran ${i + 1}';
      if (url.isEmpty || name.isEmpty) continue;
      attachments.add(MessageAttachment(url: url, name: name));
    }
    return attachments;
  }

  bool _looksLikeImageRequest(String text, List<PendingFile> files) {
    final lower = text.toLowerCase();
    final createVerb = RegExp(
      r'\b(buat|buatkan|bikin|generate|desain|draw|create)\b',
      caseSensitive: false,
    ).hasMatch(lower);
    final imageNoun = RegExp(
      r'\b(gambar|image|foto|poster|ilustrasi|logo)\b',
      caseSensitive: false,
    ).hasMatch(lower);
    final editVerb = RegExp(
      r'\b(edit|ubah|ganti|replace|jadikan|pakai|baju|warna|background|hapus|tambahkan)\b',
      caseSensitive: false,
    ).hasMatch(lower);
    return (createVerb && imageNoun) ||
        (files.any((file) => file.isImage) && editVerb);
  }

  Future<void> _onImagePasted(Uint8List bytes, String mimeType) async {
    if (_isLoading) return;

    if (_pendingFiles.length >= ChatInput.maxFiles) {
      _showErrorSnack('Maksimal ${ChatInput.maxFiles} file per pesan');
      return;
    }

    if (bytes.length > AppConstants.maxFileSize) {
      _showErrorSnack('Gambar terlalu besar (maks 1MB)');
      return;
    }

    // Pasted images can be analyzed by vision models or auto-routed by the
    // backend to Qwen Image Edit when the prompt is an edit/generation request.
    final ext = mimeType.split('/').last;
    final fileName = 'pasted_${DateTime.now().millisecondsSinceEpoch}.$ext';

    setState(() {
      _pendingFiles.add(
        PendingFile(
          url: '',
          name: fileName,
          previewBytes: bytes,
          contentType: mimeType,
          sizeBytes: bytes.length,
        ),
      );
    });

    try {
      final result = await _api.uploadFile(bytes, fileName, mimeType);
      if (!mounted) return;

      final uploadedFile = PendingFile(
        url: result['key'] ?? result['url'] ?? '',
        name: result['file_name'] ?? result['name'] ?? fileName,
        previewBytes: bytes,
        contentType: mimeType,
        sizeBytes: bytes.length,
      );

      setState(() {
        final index = _pendingFiles.indexWhere(
          (file) => file.name == fileName && file.url.isEmpty,
        );
        if (index != -1) {
          _pendingFiles[index] = uploadedFile;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pendingFiles.removeWhere(
          (file) => file.name == fileName && file.url.isEmpty,
        );
      });
      _showErrorSnack('Upload gambar gagal: $e');
    }
  }

  @override
  void dispose() {
    disposeWebPasteListener();
    _scrollController.dispose();
    for (final c in _animControllers.values) {
      c.dispose();
    }
    _streamingText.dispose();
    super.dispose();
  }

  Future<void> _loadChats() async {
    try {
      final chats = await _api.getChats();
      if (mounted) setState(() => _chats = chats);
    } catch (_) {}
  }

  Future<void> _loadMessages(int chatId) async {
    _cleanupAnimControllers();

    try {
      final msgs = await _api.getMessages(chatId);
      if (mounted) {
        await _loadChatArtifacts(chatId);
        setState(() {
          _messages = msgs
              .map(
                (m) => ChatMessage(
                  id: m['id'].toString(),
                  role: m['role'] == 'user'
                      ? MessageRole.user
                      : MessageRole.assistant,
                  content: m['content'] ?? '',
                  timestamp:
                      DateTime.tryParse(m['created_at'] ?? '') ??
                      DateTime.now(),
                  attachments: _attachmentsFromApi(m),
                  artifact: _artifactFromApi(m),
                ),
              )
              .toList();
        });
        _scrollToBottom();
      }
    } catch (_) {}
  }

  void _cleanupAnimControllers() {
    for (final c in _animControllers.values) {
      c.dispose();
    }
    _animControllers.clear();
  }

  AnimationController _createAnimController() {
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    controller.forward();
    return controller;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Pin the view to the newest streamed content, but only when the user is
  /// already near the bottom so manual scrolling is never hijacked.
  void _followStream() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (position.maxScrollExtent - position.pixels < 160) {
        _scrollController.jumpTo(position.maxScrollExtent);
      }
    });
  }

  // Reasoning pairs are derived from the live catalog: any model whose id ends
  // in "-thinking" is the thinking twin of the same id without that suffix,
  // when that base model is also served. No static model ids are assumed.
  String _thinkingIdFor(String model) =>
      model.endsWith('-thinking') ? model : '$model-thinking';

  bool _catalogServes(String modelId) => _models.any((m) => m.id == modelId);

  String _baseReasoningModel(String model) {
    if (model.endsWith('-thinking') &&
        _catalogServes(model.substring(0, model.length - '-thinking'.length))) {
      return model.substring(0, model.length - '-thinking'.length);
    }
    return model;
  }

  String? _thinkingModelFor(String model) {
    final base = _baseReasoningModel(model);
    final thinking = _thinkingIdFor(base);
    if (thinking == base) return null;
    return _catalogServes(thinking) ? thinking : null;
  }

  bool _isThinkingModel(String model) {
    return _catalogServes(model) &&
        _catalogServes(_baseReasoningModel(model));
  }

  bool _supportsReasoningModel(String model) {
    final base = _baseReasoningModel(model);
    final thinking = _thinkingModelFor(model);
    if (thinking == null) return false;
    return _catalogServes(base) && _catalogServes(thinking);
  }

  Future<void> _selectChat(int chatId) async {
    setState(() {
      _selectedChatId = chatId;
      _artifactPanelOpen = false;
      _activeArtifact = null;
    });
    await _loadMessages(chatId);

    // Sync reasoning toggle based on loaded model
    final chat = _chats.firstWhere((c) => c['id'] == chatId);
    final model = chat['model'] as String? ?? _currentModel;
    setState(() {
      _currentModel = model;
      _reasoningEnabled = model != null && _isThinkingModel(model);
      if (_reasoningEnabled) {
        _activeTools.add(ChatTool.reasoning);
      } else {
        _activeTools.remove(ChatTool.reasoning);
      }
    });

    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _createNewChat() async {
    try {
      final chat = await _api.createChat(model: _currentModel);
      await _loadChats();
      await _selectChat(chat['id']);
    } catch (_) {}
  }

  Future<void> _renameChat(int chatId, String newTitle) async {
    try {
      await _api.renameChat(chatId, newTitle);
      await _loadChats();
    } catch (_) {}
  }

  Future<void> _deleteChat(int chatId) async {
    try {
      await _api.deleteChat(chatId);
      if (_selectedChatId == chatId) {
        setState(() {
          _selectedChatId = null;
          _messages.clear();
          _artifacts = [];
          _activeArtifact = null;
          _artifactPanelOpen = false;
        });
      }
      await _loadChats();
    } catch (_) {}
  }

  void _retryMessage(String messageId) {
    final payload = _retryPayloads[messageId] ?? _lastRetryPayload;
    if (payload == null || _isLoading) return;

    setState(() {
      final errorIndex = _messages.indexWhere((m) => m.id == messageId);
      if (errorIndex != -1) {
        _messages.removeAt(errorIndex);
        if (errorIndex > 0 &&
            _messages[errorIndex - 1].role == MessageRole.user) {
          _messages.removeAt(errorIndex - 1);
        }
        _retryPayloads.remove(messageId);
      } else {
        if (_messages.isNotEmpty && _messages.last.isError) {
          _retryPayloads.remove(_messages.last.id);
          _messages.removeLast();
        }
        if (_messages.isNotEmpty && _messages.last.role == MessageRole.user) {
          _messages.removeLast();
        }
      }
    });

    _sendMessage(payload.content, retryPayload: payload);
  }

  void _handleReasoningToggle(bool enabled) {
    if (_currentModel == null) return;
    String? modelToPersist;

    setState(() {
      _reasoningEnabled = enabled;
      if (enabled) {
        _activeTools.add(ChatTool.reasoning);
      } else {
        _activeTools.remove(ChatTool.reasoning);
      }

      final baseModel = _baseReasoningModel(_currentModel!);
      final thinkingModel = _thinkingModelFor(baseModel);
      if (thinkingModel != null) {
        _currentModel = enabled ? thinkingModel : baseModel;
        modelToPersist = _currentModel;
      }
    });

    if (_selectedChatId != null && modelToPersist != null) {
      _api.updateChatModel(_selectedChatId!, modelToPersist!);
    }
  }

  Future<void> _sendMessage(
    String content, {
    _RetryPayload? retryPayload,
  }) async {
    if (_isLoading) return;

    if (_selectedChatId == null) {
      try {
        final chat = await _api.createChat(model: _currentModel);
        setState(() => _selectedChatId = chat['id']);
        await _loadChats();
      } catch (_) {
        return;
      }
    }

    final filesForSend =
        retryPayload?.files ?? List<PendingFile>.from(_pendingFiles);
    final toolsForSend =
        retryPayload?.tools ?? Set<ChatTool>.from(_activeTools);
    if (retryPayload == null && _looksLikeImageRequest(content, filesForSend)) {
      toolsForSend.add(ChatTool.createImage);
    }
    final retryDetails = _RetryPayload(
      content: content,
      files: filesForSend,
      tools: toolsForSend,
    );
    _lastRetryPayload = retryDetails;

    // Clean up old animation controllers
    _cleanupAnimControllers();

    final userMsg = ChatMessage.user(
      content,
      attachments: filesForSend.map(_attachmentFromPending).toList(),
    );
    final userAnim = _createAnimController();
    _animControllers[userMsg.id] = userAnim;

    final isCreatingImage = toolsForSend.contains(ChatTool.createImage);
    final isBrowsing = toolsForSend.contains(ChatTool.browseWeb);
    final thinkingMsg = isCreatingImage
        ? ChatMessage.imageLoading()
        : isBrowsing
        ? ChatMessage.browsing()
        : ChatMessage.thinking();
    final thinkingAnim = _createAnimController();
    _animControllers[thinkingMsg.id] = thinkingAnim;
    _retryPayloads[thinkingMsg.id] = retryDetails;

    setState(() {
      _messages.add(userMsg);
      _messages.add(thinkingMsg);
      _isLoading = true;
      if (retryPayload == null) {
        _pendingFiles = [];
      }
    });
    _scrollToBottom();

    final toolsList = toolsForSend
        .where((tool) => tool != ChatTool.reasoning)
        .map((tool) {
          switch (tool) {
            case ChatTool.browseWeb:
              return 'browse_web';
            case ChatTool.createImage:
              return 'create_image';
            case ChatTool.generatePdf:
              return 'generate_pdf';
            case ChatTool.generateDocx:
              return 'generate_docx';
            case ChatTool.generateTxt:
              return 'generate_txt';
            case ChatTool.generateCsv:
              return 'generate_csv';
            case ChatTool.reasoning:
              return 'reasoning'; // Filtered out above, but included for exhaustiveness
          }
        })
        .toList();
    final pendingFilesCopy = List<PendingFile>.from(filesForSend);

    try {
      String accumulated = '';
      bool firstToken = true;
      final idx = _messages.indexWhere((m) => m.id == thinkingMsg.id);
      // Time-based throttle keeps rebuild cost flat regardless of token rate.
      final updateThrottle = Stopwatch()..start();
      const updateInterval = Duration(milliseconds: 85);

      await for (final event in _api.sendMessageStream(
        _selectedChatId!,
        content,
        files: pendingFilesCopy,
        tools: toolsList,
      )) {
        if (!mounted) break;

        switch (event.type) {
          case SseEventType.token:
            accumulated += event.token ?? '';

            // Stream renders as lightweight typing text (isTyping) so the
            // expensive markdown parse runs once, on done. After the first
            // setState, tokens flow through _streamingText and only the
            // active bubble rebuilds — never the whole screen.
            if (firstToken && idx != -1) {
              firstToken = false;
              updateThrottle.reset();
              _streamingText.value = accumulated;
              // Update message in-place without triggering ListView rebuild
              _messages[idx] = ChatMessage(
                id: thinkingMsg.id,
                role: MessageRole.assistant,
                content: accumulated,
                timestamp: DateTime.now(),
                isLoading: false,
                isThinking: false,
                isTyping: true,
                revealedChars: accumulated.length,
              );
              // Only setState for UI state that needs updating
              if (mounted) {
                setState(() {
                  _streamingMessageId = thinkingMsg.id;
                  if (retryPayload == null) {
                    _pendingFiles = [];
                  }
                });
              }
              _scrollToBottom();
            } else if (idx != -1 && updateThrottle.elapsed >= updateInterval) {
              updateThrottle.reset();
              _streamingText.value = accumulated;
              _followStream();
            }
            break;

          case SseEventType.done:
            final doneMessage = event.metadata?['message'];
            final finalContent = doneMessage is Map
                ? (doneMessage['content']?.toString() ?? accumulated)
                : accumulated;
            final artifact = event.metadata?['artifact'] is Map
                ? ArtifactSummary.fromJson(
                    Map<String, dynamic>.from(
                      event.metadata!['artifact'] as Map,
                    ),
                  )
                : null;
            if (idx != -1) {
              setState(() {
                _messages[idx] = _messages[idx].copyWith(
                  content: finalContent,
                  isLoading: false,
                  isImageLoading: false,
                  isTyping: false,
                  revealedChars: finalContent.length,
                  artifact: artifact,
                );
                if (artifact != null &&
                    !_artifacts.any((item) => item.id == artifact.id)) {
                  _artifacts = [artifact, ..._artifacts];
                }
                _retryPayloads.remove(thinkingMsg.id);
                _streamingMessageId = null;
                _isLoading = false;
              });
              if (artifact != null) {
                await _openArtifact(artifact.id);
              }
            }
            if (event.metadata?['chat_title_updated'] == true) {
              await _loadChats();
            }
            break;

          case SseEventType.error:
            if (idx != -1) {
              setState(() {
                _messages[idx] = ChatMessage.error(
                  id: thinkingMsg.id,
                  content: _formatError(
                    event.error ?? 'Request gagal. Coba lagi.',
                    code: event.code,
                    requestId: event.requestId,
                  ),
                  timestamp: DateTime.now(),
                  errorCode: event.code,
                  requestId: event.requestId,
                );
                _streamingMessageId = null;
                _isLoading = false;
              });
            }
            _showErrorSnack(event.error ?? 'Request gagal. Coba lagi.');
            break;
        }
      }

      // Clear loading and finalize the message if the stream ended without a
      // done event (connection drop) so it doesn't stay in typing mode.
      if (mounted) {
        setState(() {
          if (idx != -1 && idx < _messages.length && _messages[idx].isTyping) {
            _messages[idx] = _messages[idx].copyWith(
              content: accumulated,
              isTyping: false,
              revealedChars: accumulated.length,
            );
          }
          _streamingMessageId = null;
          _isLoading = false;
        });
      }
    } catch (e) {
      final apiError = e is ApiException ? e : null;
      final errMsg = ChatMessage.error(
        id: thinkingMsg.id,
        content: _formatError(
          apiError?.message ?? e.toString(),
          code: apiError?.code,
          requestId: apiError?.requestId,
        ),
        timestamp: DateTime.now(),
        errorCode: apiError?.code,
        requestId: apiError?.requestId,
      );
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == thinkingMsg.id);
        if (idx != -1) _messages[idx] = errMsg;
        _streamingMessageId = null;
        _isLoading = false;
      });
      _showErrorSnack(apiError?.supportMessage ?? e.toString());
    }
    _scrollToBottom();
  }

  void _handleFileAdded(PendingFile file) {
    setState(() => _pendingFiles.add(file));
  }

  void _removeAttachment(int index) {
    setState(() => _pendingFiles.removeAt(index));
  }

  void _clearAllAttachments() {
    setState(() => _pendingFiles.clear());
  }

  void _handleToolToggle(ChatTool tool) {
    if (tool == ChatTool.reasoning) {
      _handleReasoningToggle(!_reasoningEnabled);
      return;
    }

    setState(() {
      if (_activeTools.contains(tool)) {
        _activeTools.remove(tool);
      } else {
        _activeTools.add(tool);
      }
      // Image tools are routed by the backend so normal chat model selection
      // and conversation continuity stay intact.
      if (tool == ChatTool.createImage && _activeTools.contains(tool)) {
        _reasoningEnabled = false;
        _activeTools.remove(ChatTool.reasoning);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= AppConstants.sidebarBreakpoint;

    final sidebar = ChatSidebar(
      chats: _chats,
      selectedChatId: _selectedChatId,
      onChatSelected: _selectChat,
      onNewChat: _createNewChat,
      onRenameChat: _renameChat,
      onDeleteChat: _deleteChat,
      onLogout: widget.onLogout,
      username: _profileDisplayName ?? _api.username ?? '',
      avatarUrl: _profileAvatarUrl,
      onEditProfile: _openProfileEditor,
    );

    final chatBody = Column(
      children: [
        if (_usageWarning != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Material(
              color: theme.colorScheme.errorContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _usageWarning!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(
          child: _selectedChatId == null && _messages.isEmpty
              ? WelcomeView(onSuggestionTap: _sendMessage)
              : Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: isDesktop
                          ? AppConstants.maxChatWidth
                          : double.infinity,
                    ),
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: EdgeInsets.symmetric(
                        horizontal: isDesktop ? 24 : 16,
                        vertical: 16,
                      ),
                      // Performance: reduce cache extent for faster scrolling
                      cacheExtent: 300,
                      // Performance: don't keep offscreen items alive
                      addAutomaticKeepAlives: false,
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        final anim = _animControllers[msg.id];
                        // Wrap each message in RepaintBoundary to isolate repaints
                        return RepaintBoundary(
                          child: MessageBubble(
                            key: ValueKey(msg.id),
                            message: msg,
                            animation: anim,
                            streamingText: msg.id == _streamingMessageId
                                ? _streamingText
                                : null,
                            onRetry: msg.isError
                                ? () => _retryMessage(msg.id)
                                : null,
                            onOpenArtifact: _openArtifact,
                            onOpenImage: (attachment) => showImageLightbox(
                              context,
                              bytes: attachment.previewBytes,
                              url: attachment.url,
                              label: attachment.name,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
        ),
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isDesktop
                  ? AppConstants.maxChatWidth + 48
                  : double.infinity,
            ),
            child: RepaintBoundary(
              child: ChatInput(
                onSend: _sendMessage,
                isLoading: _isLoading,
                onFileAdded: _handleFileAdded,
                attachedFiles: _pendingFiles,
                onRemoveAttachment: _removeAttachment,
                onClearAllAttachments: _clearAllAttachments,
                activeTools: _activeTools,
                onToolToggled: _handleToolToggle,
                supportsReasoning: _currentModel != null
                    ? _supportsReasoningModel(_currentModel!)
                    : false,
                currentModelSupportsVision: _models
                    .firstWhere(
                      (m) => m.id == _currentModel,
                      orElse: () => _models.first,
                    )
                    .supportsVision,
              ),
            ),
          ),
        ),
      ],
    );

    final appBar = AppBar(
      leading: isDesktop
          ? IconButton(
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  _sidebarOpen ? Icons.menu_open_rounded : Icons.menu_rounded,
                  key: ValueKey(_sidebarOpen),
                  size: 22,
                ),
              ),
              onPressed: () => setState(() => _sidebarOpen = !_sidebarOpen),
              tooltip: _sidebarOpen ? 'Tutup sidebar' : 'Buka sidebar',
            )
          : Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu_rounded, size: 22),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            ),
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      title: Row(
        children: [
          const SizedBox(width: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset('assets/logo.png', width: 28, height: 28),
          ),
          if (isDesktop) ...[
            const SizedBox(width: 10),
            Text(AppConstants.appName, style: theme.appBarTheme.titleTextStyle),
          ],
        ],
      ),
      actions: [
        const SizedBox(width: 24),
        if (screenWidth >= 760) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: InkWell(
              onTap: _isSubmittingFeedback ? null : _showFeedbackDialog,
              borderRadius: BorderRadius.circular(12),
              child: Opacity(
                opacity: _isSubmittingFeedback ? 0.55 : 1,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    'Kritik dan Saran',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ] else ...[
          IconButton(
            onPressed: _isSubmittingFeedback ? null : _showFeedbackDialog,
            icon: const Icon(Icons.feedback_outlined, size: 20),
            tooltip: 'Kritik dan Saran',
          ),
          const SizedBox(width: 4),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ModelSelector(
            currentModel: _currentModel ?? '',
            models: _models,
            onModelChanged: (model) {
              final nextModel = _reasoningEnabled
                  ? (_thinkingModelFor(model) ?? model)
                  : _baseReasoningModel(model);

              setState(() {
                _currentModel = nextModel;
                _reasoningEnabled = _isThinkingModel(nextModel);
                if (_reasoningEnabled) {
                  _activeTools.add(ChatTool.reasoning);
                } else {
                  _activeTools.remove(ChatTool.reasoning);
                }
              });
              // Persist model change to database for the active chat
              if (_selectedChatId != null) {
                ApiService().updateChatModel(_selectedChatId!, nextModel);
              }
            },
          ),
        ),
        // Playground only on desktop (web-only feature)
        if (isDesktop) ...[
          const SizedBox(width: 4),
          IconButton(
            onPressed: () async {
              await playground.loadLibrary();
              if (!context.mounted) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => playground.PlaygroundScreen(),
                ),
              );
            },
            icon: const Icon(Icons.code_rounded, size: 20),
            tooltip: 'Playground',
          ),
        ],
        const SizedBox(width: 4),
        IconButton(
          onPressed: () => AskLoApp.of(context)?.toggleTheme(),
          icon: Icon(
            Theme.of(context).brightness == Brightness.dark
                ? Icons.light_mode_rounded
                : Icons.dark_mode_rounded,
            size: 20,
          ),
          tooltip: 'Toggle theme',
        ),
        // Admin panel button (only visible for admin users)
        if (_api.isAdmin) ...[
          const SizedBox(width: 4),
          IconButton(
            onPressed: () => Navigator.of(context).pushNamed('/admin'),
            icon: const Icon(Icons.admin_panel_settings_rounded, size: 20),
            tooltip: 'Admin Panel',
          ),
        ],
        const SizedBox(width: 4),
      ],
    );

    if (isDesktop) {
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyN, control: true):
              _createNewChat,
          const SingleActivator(
            LogicalKeyboardKey.keyS,
            control: true,
            shift: true,
          ): () {
            setState(() => _sidebarOpen = !_sidebarOpen);
          },
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOutCubic,
                  width: _sidebarOpen ? AppConstants.sidebarWidth : 0,
                  child: _sidebarOpen
                      ? AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: 1.0,
                          child: sidebar,
                        )
                      : const SizedBox.shrink(),
                ),
                if (_sidebarOpen)
                  VerticalDivider(
                    width: 1,
                    color: theme.colorScheme.outline.withValues(alpha: 0.15),
                  ),
                Expanded(
                  child: Scaffold(appBar: appBar, body: chatBody),
                ),
                if (_artifactPanelOpen && _activeArtifact != null) ...[
                  VerticalDivider(
                    width: 1,
                    color: theme.colorScheme.outline.withValues(alpha: 0.15),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    width:
                        (screenWidth < 980.0
                            ? 980.0
                            : screenWidth > 1440.0
                            ? 1440.0
                            : screenWidth) *
                        0.38,
                    constraints: const BoxConstraints(
                      minWidth: 520,
                      maxWidth: 680,
                    ),
                    child: ArtifactViewer(
                      artifact: _activeArtifact!,
                      onClose: _closeArtifactPanel,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    } else {
      return Scaffold(
        appBar: appBar,
        drawer: Drawer(width: AppConstants.sidebarWidth, child: sidebar),
        body: chatBody,
        resizeToAvoidBottomInset: true,
      );
    }
  }
}

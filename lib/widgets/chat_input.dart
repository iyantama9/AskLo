import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../core/constants.dart';
import '../services/api_service.dart';

enum AttachmentKind { image, pdf, markdown, text, code, presentation, document }

/// Represents a pending file attachment (uploaded or pasted).
class PendingFile {
  final String url;
  final String name;
  final Uint8List? previewBytes;
  final String? contentType;
  final int? sizeBytes;
  final String? previewText;

  const PendingFile({
    required this.url,
    required this.name,
    this.previewBytes,
    this.contentType,
    this.sizeBytes,
    this.previewText,
  });

  static const _imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'];
  static const _codeExtensions = [
    'dart',
    'js',
    'ts',
    'jsx',
    'tsx',
    'py',
    'java',
    'kt',
    'swift',
    'c',
    'cpp',
    'h',
    'hpp',
    'cs',
    'go',
    'rs',
    'rb',
    'php',
    'html',
    'css',
    'scss',
    'sass',
    'less',
    'json',
    'yaml',
    'yml',
    'xml',
    'toml',
    'ini',
    'env',
    'sql',
    'sh',
    'bash',
    'bat',
    'ps1',
    'cmd',
    'vue',
    'svelte',
    'astro',
    'r',
    'lua',
    'perl',
    'scala',
    'clj',
    'ex',
    'exs',
    'erl',
    'dockerfile',
    'makefile',
    'cmake',
  ];

  String get extension {
    final parts = name.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : name.toLowerCase();
  }

  bool get isImage {
    final type = contentType?.toLowerCase() ?? '';
    return type.startsWith('image/') || _imageExtensions.contains(extension);
  }

  bool get isUploading => url.isEmpty;

  AttachmentKind get kind {
    if (isImage) return AttachmentKind.image;
    if (extension == 'pdf') return AttachmentKind.pdf;
    if (extension == 'md' || extension == 'markdown') {
      return AttachmentKind.markdown;
    }
    if (['txt', 'log', 'csv'].contains(extension)) return AttachmentKind.text;
    if (['ppt', 'pptx'].contains(extension)) return AttachmentKind.presentation;
    if (_codeExtensions.contains(extension)) return AttachmentKind.code;
    return AttachmentKind.document;
  }

  bool get isTextPreviewable =>
      kind == AttachmentKind.markdown ||
      kind == AttachmentKind.text ||
      kind == AttachmentKind.code;
}

/// Available tools
enum ChatTool { browseWeb, createImage, reasoning, generatePdf, generateDocx, generateTxt, generateCsv }

class ChatInput extends StatefulWidget {
  static const int maxFiles = 5;

  final ValueChanged<String> onSend;
  final bool isLoading;
  final ValueChanged<PendingFile>? onFileAdded;
  final VoidCallback? onClearAllAttachments;
  final ValueChanged<int>? onRemoveAttachment;
  final List<PendingFile> attachedFiles;
  final Set<ChatTool> activeTools;
  final ValueChanged<ChatTool>? onToolToggled;
  final bool supportsReasoning;
  final bool currentModelSupportsVision;

  const ChatInput({
    super.key,
    required this.onSend,
    this.isLoading = false,
    this.onFileAdded,
    this.onClearAllAttachments,
    this.onRemoveAttachment,
    this.attachedFiles = const [],
    this.activeTools = const {},
    this.onToolToggled,
    this.supportsReasoning = false,
    this.currentModelSupportsVision = true,
  });

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  late AnimationController _sendButtonAnimController;
  bool _hasText = false;
  bool _isUploading = false;
  final _toolsBtnKey = GlobalKey();
  OverlayEntry? _toolsOverlay;

  static const List<String> _allowedExtensions = [
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'bmp',
    'svg',
    'dart',
    'js',
    'ts',
    'jsx',
    'tsx',
    'py',
    'java',
    'kt',
    'swift',
    'c',
    'cpp',
    'h',
    'hpp',
    'cs',
    'go',
    'rs',
    'rb',
    'php',
    'html',
    'css',
    'scss',
    'sass',
    'less',
    'json',
    'yaml',
    'yml',
    'xml',
    'toml',
    'ini',
    'env',
    'sql',
    'sh',
    'bash',
    'bat',
    'ps1',
    'cmd',
    'md',
    'txt',
    'log',
    'csv',
    'vue',
    'svelte',
    'astro',
    'r',
    'lua',
    'perl',
    'scala',
    'clj',
    'ex',
    'exs',
    'erl',
    'dockerfile',
    'makefile',
    'cmake',
    'pdf',
    'ppt',
    'pptx',
  ];

  @override
  void initState() {
    super.initState();
    _sendButtonAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText) {
        setState(() => _hasText = hasText);
        hasText
            ? _sendButtonAnimController.forward()
            : _sendButtonAnimController.reverse();
      }
    });
  }

  @override
  void dispose() {
    _toolsOverlay?.remove();
    _controller.dispose();
    _focusNode.dispose();
    _sendButtonAnimController.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (!_canSend) return;

    final message = text.isEmpty ? 'Tolong analisis lampiran ini.' : text;
    widget.onSend(message);
    _controller.clear();
    _focusNode.requestFocus();
  }

  bool get _canAddMore => widget.attachedFiles.length < ChatInput.maxFiles;

  bool get _canSend =>
      (_hasText || widget.attachedFiles.isNotEmpty) &&
      !widget.attachedFiles.any((file) => file.isUploading) &&
      !widget.isLoading &&
      !_isUploading;

  void _showInputSnack(String message) {
    if (!mounted) return;
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: theme.colorScheme.errorContainer,
          elevation: 10,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 92),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: theme.colorScheme.error.withValues(alpha: 0.24),
            ),
          ),
          duration: const Duration(seconds: 4),
          content: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_rounded,
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
        ),
      );
  }

  String? _buildTextPreview(
    Uint8List bytes,
    String fileName,
    String contentType,
  ) {
    final probe = PendingFile(
      url: 'preview',
      name: fileName,
      contentType: contentType,
    );
    if (!probe.isTextPreviewable) return null;

    try {
      final decoded = utf8.decode(bytes.take(6000).toList(), allowMalformed: true);
      final normalized = decoded.replaceAll('\r\n', '\n').trim();
      if (normalized.isEmpty) return null;
      final lines = normalized.split('\n').take(40).join('\n');
      return lines.length > 2400 ? '${lines.substring(0, 2400)}â€¦' : lines;
    } catch (_) {
      return null;
    }
  }

  Future<void> _uploadBytes(
    Uint8List bytes,
    String fileName,
    String contentType,
  ) async {
    if (!_canAddMore) {
      _showInputSnack('Maksimal 5 file per pesan');
      return;
    }

    if (bytes.length > AppConstants.maxFileSize) {
      _showInputSnack('File terlalu besar (maks 1MB)');
      return;
    }

    // Images are allowed even when the selected text model has no vision flag:
    // the backend can auto-route image edit/generation prompts to Qwen Image Edit.
    final isImage = contentType.startsWith('image/');

    setState(() => _isUploading = true);

    try {
      final uploadResult = await ApiService().uploadFile(
        bytes,
        fileName,
        contentType,
      );
      widget.onFileAdded?.call(
        PendingFile(
          url: uploadResult['key'] ?? uploadResult['url'] ?? '',
          name: uploadResult['file_name'] ?? uploadResult['name'] ?? fileName,
          previewBytes: isImage ? bytes : null,
          contentType: contentType,
          sizeBytes: bytes.length,
          previewText: _buildTextPreview(bytes, fileName, contentType),
        ),
      );
    } catch (e) {
      _showInputSnack('Upload gagal: $e');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> handlePastedImage(Uint8List bytes, String mimeType) async {
    final ext = mimeType.split('/').last;
    final fileName =
        'pasted_image_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _uploadBytes(bytes, fileName, mimeType);
  }

  Future<void> _pickFile() async {
    if (_isUploading || widget.isLoading || !_canAddMore) {
      if (!_canAddMore) {
        _showInputSnack('Maksimal 5 file per pesan');
      }
      return;
    }

    final remaining = ChatInput.maxFiles - widget.attachedFiles.length;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedExtensions,
      withData: true,
      allowMultiple: remaining > 1,
    );

    if (result == null || result.files.isEmpty) return;

    final files = result.files.take(remaining).toList();

    for (final file in files) {
      if (file.bytes == null) continue;

      if (file.size > AppConstants.maxFileSize) {
        _showInputSnack('${file.name} terlalu besar (maks 1MB)');
        continue;
      }

      final ext = file.extension?.toLowerCase() ?? '';
      String contentType = 'application/octet-stream';
      if (['jpg', 'jpeg'].contains(ext)) contentType = 'image/jpeg';
      if (ext == 'png') contentType = 'image/png';
      if (ext == 'gif') contentType = 'image/gif';
      if (ext == 'webp') contentType = 'image/webp';
      if (ext == 'pdf') contentType = 'application/pdf';
      if (ext == 'ppt' || ext == 'pptx') {
        contentType = 'application/vnd.ms-powerpoint';
      }
      if (ext == 'svg') contentType = 'image/svg+xml';
      if (['txt', 'md', 'log', 'csv'].contains(ext)) contentType = 'text/plain';

      await _uploadBytes(file.bytes!, file.name, contentType);
    }
  }

  void _showToolsMenu() {
    if (_toolsOverlay != null) {
      _toolsOverlay!.remove();
      _toolsOverlay = null;
      return;
    }
    final trigger = _toolsBtnKey.currentContext?.findRenderObject();
    if (trigger is! RenderBox) return;
    final overlayCtx = Overlay.of(context).context;
    final vw = MediaQuery.sizeOf(context).width;
    final panelW = math.min(320.0, vw - 32);
    // Panel drops above the trigger (input is near the bottom of the screen).
    final btnPos = trigger.localToGlobal(Offset.zero,
        ancestor: overlayCtx.findRenderObject() as RenderBox);
    final topY = math.max(12.0, btnPos.dy - 360);
    final leftX = math.max(12.0, math.min(btnPos.dx, vw - panelW - 12));

    _toolsOverlay = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned(
            left: 0, top: 0, right: 0, bottom: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _closeToolsPanel,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(left: leftX, top: topY, width: panelW, child: _buildToolsPanel()),
        ],
      ),
    );
    Overlay.of(context).insert(_toolsOverlay!);
  }

  void _closeToolsPanel() {
    _toolsOverlay?.remove();
    _toolsOverlay = null;
  }

  Widget _buildToolsPanel() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final onSurf = cs.onSurface;
    final muted = cs.onSurfaceVariant;
    final accent = cs.primary;
    final fieldBg = cs.surfaceContainerHighest;
    final panelBg = cs.surface;

    List<({ChatTool tool, IconData icon, String title, String subtitle, Color color})> tools = [
      (tool: ChatTool.browseWeb, icon: Icons.travel_explore_rounded, title: 'Browse Web', subtitle: 'Jelajahi internet', color: const Color(0xFF0EA5E9)),
      (tool: ChatTool.createImage, icon: Icons.auto_awesome_rounded, title: 'Create Image', subtitle: 'Buat / edit gambar', color: const Color(0xFFEC4899)),
      if (widget.supportsReasoning)
        (tool: ChatTool.reasoning, icon: Icons.psychology_rounded, title: 'Reasoning', subtitle: 'Penalaran mendalam', color: const Color(0xFF7C3AED)),
      (tool: ChatTool.generatePdf, icon: Icons.picture_as_pdf_rounded, title: 'Generate PDF', subtitle: 'Dokumen PDF', color: const Color(0xFFEF4444)),
      (tool: ChatTool.generateDocx, icon: Icons.description_rounded, title: 'Generate DOCX', subtitle: 'Dokumen Word', color: const Color(0xFF3B82F6)),
      (tool: ChatTool.generateTxt, icon: Icons.text_snippet_rounded, title: 'Generate TXT', subtitle: 'File teks', color: const Color(0xFF10B981)),
      (tool: ChatTool.generateCsv, icon: Icons.table_chart_rounded, title: 'Generate CSV', subtitle: 'Tabel data', color: const Color(0xFFF59E0B)),
    ];

    Widget toolRow({required ChatTool tool, required IconData icon, required String title, required String subtitle, required Color color}) {
      final active = widget.activeTools.contains(tool);
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            widget.onToolToggled?.call(tool);
            _closeToolsPanel();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: active ? color.withValues(alpha: 0.12) : Colors.transparent,
              border: Border.all(color: active ? color.withValues(alpha: 0.4) : Colors.transparent, width: 1.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: active ? color.withValues(alpha: 0.18) : fieldBg.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: active ? color : Colors.transparent),
                  ),
                  child: Icon(icon, size: 19, color: active ? color : muted),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: TextStyle(fontSize: 14, fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: active ? color : onSurf)),
                      const SizedBox(height: 1),
                      Text(subtitle, style: TextStyle(fontSize: 12, color: muted.withValues(alpha: 0.75))),
                    ],
                  ),
                ),
                if (active)
                  Container(
                    width: 20, height: 20,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    child: const Icon(Icons.check, size: 13, color: Colors.white),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      builder: (ctx, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, (1 - v) * 6), child: child),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: panelBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: muted.withValues(alpha: 0.22)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 28, spreadRadius: 1, offset: const Offset(0, 10)),
          ],
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.construction_rounded, size: 16, color: accent),
                  const SizedBox(width: 8),
                  Text('Tools', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: onSurf)),
                  const Spacer(),
                  Text('${widget.activeTools.length} aktif', style: TextStyle(fontSize: 12, color: muted)),
                ],
              ),
            ),
            for (final t in tools) toolRow(tool: t.tool, icon: t.icon, title: t.title, subtitle: t.subtitle, color: t.color),
          ],
        ),
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasAttachments = widget.attachedFiles.isNotEmpty;
    final hasActiveTools = widget.activeTools.isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasAttachments)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SizedBox(
                  height: MediaQuery.sizeOf(context).width < 600 ? 116 : 160,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.attachedFiles.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) => _buildAttachmentPreview(
                      theme,
                      widget.attachedFiles[i],
                      i,
                    ),
                  ),
                ),
              ),
            if (hasActiveTools)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final tool in widget.activeTools)
                        _buildToolChip(theme, tool),
                    ],
                  ),
                ),
              ),
            // Input row
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.inputDecorationTheme.fillColor,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: theme.colorScheme.outline.withValues(
                          alpha: 0.15,
                        ),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Attach button
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 4),
                          child: IconButton(
                            onPressed: _isUploading ? null : _pickFile,
                            icon: _isUploading
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  )
                                : Badge(
                                    isLabelVisible: hasAttachments,
                                    label: Text(
                                      '${widget.attachedFiles.length}',
                                    ),
                                    child: Icon(
                                      Icons.add_rounded,
                                      size: 22,
                                      color: hasAttachments
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                            tooltip: _canAddMore
                                ? 'Attach file (${widget.attachedFiles.length}/${ChatInput.maxFiles})'
                                : 'Maksimal ${ChatInput.maxFiles} file',
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                          ),
                        ),
                        // Tools button
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: IconButton(
                            key: _toolsBtnKey,
                            onPressed: _showToolsMenu,
                            icon: Icon(
                              Icons.construction_rounded,
                              size: 20,
                              color: hasActiveTools
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                            tooltip: 'Tools',
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                          ),
                        ),
                        // Text field
                        Expanded(
                          child: Focus(
                            onKeyEvent: (node, event) {
                              if (event is KeyDownEvent &&
                                  event.logicalKey ==
                                      LogicalKeyboardKey.enter &&
                                  !HardwareKeyboard.instance.isShiftPressed) {
                                _handleSend();
                                return KeyEventResult.handled;
                              }
                              return KeyEventResult.ignored;
                            },
                            child: TextField(
                              controller: _controller,
                              focusNode: _focusNode,
                              maxLines: 5,
                              minLines: 1,
                              textInputAction: TextInputAction.newline,
                              style: theme.textTheme.bodyMedium,
                              decoration: InputDecoration(
                                hintText: widget.isLoading
                                    ? 'Menunggu respons...'
                                    : _getHintText(),
                                isDense: true,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                fillColor: Colors.transparent,
                                filled: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Send button
                        Padding(
                          padding: const EdgeInsets.only(right: 4, bottom: 4),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            height: 40,
                            width: 40,
                            decoration: BoxDecoration(
                              gradient: _canSend
                                  ? const LinearGradient(
                                      colors: [
                                        Color(0xFF7C3AED),
                                        Color(0xFF9333EA),
                                      ],
                                    )
                                  : null,
                              color: _canSend ? null : Colors.transparent,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: IconButton(
                              onPressed: _canSend ? _handleSend : null,
                              icon: widget.isLoading
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    )
                                  : Icon(
                                      Icons.arrow_upward_rounded,
                                      size: 20,
                                      color: _canSend
                                          ? Colors.white
                                          : theme.colorScheme.onSurfaceVariant
                                                .withValues(alpha: 0.4),
                                    ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 40,
                                minHeight: 40,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getHintText() {
    if (widget.activeTools.contains(ChatTool.browseWeb)) {
      return 'Minta AI browsing web...';
    }
    if (widget.activeTools.contains(ChatTool.createImage)) {
      return 'Deskripsikan gambar yang mau dibuat...';
    }
    if (widget.activeTools.contains(ChatTool.reasoning)) {
      return 'Tanya dengan penalaran mendalam...';
    }
    if (widget.activeTools.contains(ChatTool.generatePdf)) {
      return 'Minta AI buat dokumen PDF...';
    }
    if (widget.activeTools.contains(ChatTool.generateDocx)) {
      return 'Minta AI buat dokumen DOCX...';
    }
    if (widget.activeTools.contains(ChatTool.generateTxt)) {
      return 'Minta AI buat file teks...';
    }
    if (widget.activeTools.contains(ChatTool.generateCsv)) {
      return 'Minta AI buat data CSV...';
    }
    return 'Tanya apa saja...';
  }

  Widget _buildToolChip(ThemeData theme, ChatTool tool) {
    final (icon, label, colors) = switch (tool) {
      ChatTool.browseWeb => (
        Icons.travel_explore_rounded,
        'Browse Web',
        [const Color(0xFF0EA5E9), const Color(0xFF06B6D4)],
      ),
      ChatTool.createImage => (
        Icons.auto_awesome_rounded,
        'Create Image',
        [const Color(0xFFEC4899), const Color(0xFFF43F5E)],
      ),
      ChatTool.reasoning => (
        Icons.psychology_rounded,
        'Reasoning',
        [const Color(0xFF7C3AED), const Color(0xFF9333EA)],
      ),
      ChatTool.generatePdf => (
        Icons.picture_as_pdf_rounded,
        'Generate PDF',
        [const Color(0xFFDC2626), const Color(0xFFEF4444)],
      ),
      ChatTool.generateDocx => (
        Icons.description_rounded,
        'Generate DOCX',
        [const Color(0xFF2563EB), const Color(0xFF3B82F6)],
      ),
      ChatTool.generateTxt => (
        Icons.text_snippet_rounded,
        'Generate TXT',
        [const Color(0xFF059669), const Color(0xFF10B981)],
      ),
      ChatTool.generateCsv => (
        Icons.table_chart_rounded,
        'Generate CSV',
        [const Color(0xFFD97706), const Color(0xFFF59E0B)],
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: () => widget.onToolToggled?.call(tool),
            borderRadius: BorderRadius.circular(10),
            child: const Icon(
              Icons.close_rounded,
              size: 14,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentPreview(ThemeData theme, PendingFile file, int index) {
    if (file.isImage && file.previewBytes != null) {
      return _buildImageAttachmentPreview(theme, file, index);
    }
    return _buildDocumentAttachmentPreview(theme, file, index);
  }

  Widget _buildImageAttachmentPreview(
    ThemeData theme,
    PendingFile file,
    int index,
  ) {
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    final previewWidth = isMobile ? 108.0 : 156.0;
    final previewHeight = isMobile ? 108.0 : 152.0;

    return GestureDetector(
      onTap: () => _showAttachmentDetail(file),
      child: Hero(
        tag: 'attachment-preview-$index-${file.name}',
        child: Container(
          width: previewWidth,
          height: previewHeight,
          decoration: _attachmentDecoration(theme),
          child: Stack(
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(19),
                  child: Image.memory(
                    file.previewBytes!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Center(
                      child: Icon(
                        Icons.broken_image_rounded,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
              if (file.isUploading) _buildUploadingOverlay(),
              _buildAttachmentCaption(theme, file, Icons.image_rounded),
              _buildRemoveButton(file, index),
              _buildExpandBadge(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDocumentAttachmentPreview(
    ThemeData theme,
    PendingFile file,
    int index,
  ) {
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    final width = isMobile ? 220.0 : 280.0;
    final height = isMobile ? 108.0 : 152.0;
    final color = _attachmentAccentColor(file.kind);
    final hasTextPreview = file.previewText?.trim().isNotEmpty == true;

    return GestureDetector(
      onTap: () => _showAttachmentDetail(file),
      child: Container(
        width: width,
        height: height,
        padding: EdgeInsets.all(isMobile ? 10 : 12),
        decoration: _attachmentDecoration(theme),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: isMobile ? 30 : 36,
                      height: isMobile ? 30 : 36,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(_getFileIcon(file.name), color: color, size: 18),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            file.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${_kindLabel(file.kind)}${file.sizeBytes == null ? '' : ' â€¢ ${_formatBytes(file.sizeBytes!)}'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 26),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D0D1A).withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                    child: hasTextPreview
                        ? Text(
                            file.previewText!,
                            maxLines: isMobile ? 3 : 5,
                            overflow: TextOverflow.fade,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.78),
                              fontFamily: file.kind == AttachmentKind.code
                                  ? 'monospace'
                                  : null,
                              height: 1.35,
                              fontSize: isMobile ? 10.5 : 11.5,
                            ),
                          )
                        : Center(
                            child: Text(
                              'Preview dokumen tersedia setelah dikirim ke AI',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                  ),
                ),
              ],
            ),
            if (file.isUploading) _buildUploadingOverlay(),
            _buildRemoveButton(file, index),
          ],
        ),
      ),
    );
  }

  BoxDecoration _attachmentDecoration(ThemeData theme) {
    return BoxDecoration(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: theme.colorScheme.primary.withValues(alpha: 0.45),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.18),
          blurRadius: 16,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  Widget _buildUploadingOverlay() {
    return Positioned.fill(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(19),
        child: Container(
          color: Colors.black.withValues(alpha: 0.34),
          child: const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAttachmentCaption(
    ThemeData theme,
    PendingFile file,
    IconData icon,
  ) {
    return Positioned(
      left: 8,
      right: 8,
      bottom: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 13, color: Colors.white70),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                file.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRemoveButton(PendingFile file, int index) {
    return Positioned(
      top: 7,
      right: 7,
      child: Material(
        color: Colors.black.withValues(alpha: 0.65),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => widget.onRemoveAttachment?.call(index),
          child: const Padding(
            padding: EdgeInsets.all(6),
            child: Icon(Icons.close_rounded, size: 16, color: Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandBadge() {
    return Positioned(
      top: 7,
      left: 7,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Icon(
          Icons.open_in_full_rounded,
          size: 13,
          color: Colors.white,
        ),
      ),
    );
  }

  void _showAttachmentDetail(PendingFile file) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.82),
      builder: (context) {
        final theme = Theme.of(context);
        return Dialog.fullscreen(
          backgroundColor: Colors.transparent,
          child: SafeArea(
            child: Stack(
              children: [
                Center(child: _buildAttachmentDetailBody(theme, file)),
                Positioned(
                  top: 12,
                  right: 12,
                  child: IconButton.filledTonal(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Tutup preview',
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAttachmentDetailBody(ThemeData theme, PendingFile file) {
    if (file.isImage && file.previewBytes != null) {
      return InteractiveViewer(
        minScale: 0.8,
        maxScale: 4,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Image.memory(
              file.previewBytes!,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Icon(
                Icons.broken_image_rounded,
                color: theme.colorScheme.onSurface,
                size: 40,
              ),
            ),
          ),
        ),
      );
    }

    final width = MediaQuery.sizeOf(context).width;
    return Container(
      width: width < 700 ? width - 32 : 680,
      constraints: const BoxConstraints(maxHeight: 620),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(_getFileIcon(file.name), color: _attachmentAccentColor(file.kind)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${_kindLabel(file.kind)}${file.sizeBytes == null ? '' : ' â€¢ ${_formatBytes(file.sizeBytes!)}'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Flexible(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D1A),
                borderRadius: BorderRadius.circular(16),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  file.previewText?.trim().isNotEmpty == true
                      ? file.previewText!
                      : 'Preview isi belum tersedia untuk tipe file ini. File tetap akan dikirim ke AI untuk dianalisis.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.86),
                    height: 1.55,
                    fontFamily: file.kind == AttachmentKind.code
                        ? 'monospace'
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _kindLabel(AttachmentKind kind) {
    return switch (kind) {
      AttachmentKind.image => 'Image',
      AttachmentKind.pdf => 'PDF document',
      AttachmentKind.markdown => 'Markdown',
      AttachmentKind.text => 'Text file',
      AttachmentKind.code => 'Code file',
      AttachmentKind.presentation => 'Presentation',
      AttachmentKind.document => 'Document',
    };
  }

  Color _attachmentAccentColor(AttachmentKind kind) {
    return switch (kind) {
      AttachmentKind.image => const Color(0xFF8B5CF6),
      AttachmentKind.pdf => const Color(0xFFEF4444),
      AttachmentKind.markdown => const Color(0xFF38BDF8),
      AttachmentKind.text => const Color(0xFF22C55E),
      AttachmentKind.code => const Color(0xFFF59E0B),
      AttachmentKind.presentation => const Color(0xFFF97316),
      AttachmentKind.document => const Color(0xFFA78BFA),
    };
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  IconData _getFileIcon(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg'].contains(ext)) {
      return Icons.image_rounded;
    }
    if (ext == 'pdf') return Icons.picture_as_pdf_rounded;
    if (ext == 'md' || ext == 'markdown') return Icons.article_rounded;
    if (['txt', 'log', 'csv'].contains(ext)) return Icons.notes_rounded;
    if (['ppt', 'pptx'].contains(ext)) return Icons.slideshow_rounded;
    return Icons.code_rounded;
  }
}

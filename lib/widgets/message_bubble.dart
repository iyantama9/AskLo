import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:flutter_markdown_latex/flutter_markdown_latex.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';
import '../core/constants.dart';
import '../models/message_model.dart';

/// Opens a full-screen image lightbox.
void showImageLightbox(
  BuildContext context, {
  required List<int>? bytes,
  required String url,
  required String label,
}) {
  final theme = Theme.of(context);
  showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (_) => _ImageLightbox(
      bytes: bytes,
      url: url,
      label: label,
      onOpenExternal: (target) =>
          launchUrl(Uri.parse(target), mode: LaunchMode.externalApplication),
      theme: theme,
    ),
  );
}

class _ImageLightbox extends StatelessWidget {
  final List<int>? bytes;
  final String url;
  final String label;
  final Future<void> Function(String target) onOpenExternal;
  final ThemeData theme;

  const _ImageLightbox({
    required this.bytes,
    required this.url,
    required this.label,
    required this.onOpenExternal,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final bytes = widget.bytes;
    final url = widget.url;
    final label = widget.label;
    final onOpenExternal = widget.onOpenExternal;
    final theme = widget.theme;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.86,
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        child: Stack(
          alignment: Alignment.topRight,
          clipBehavior: Clip.none,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: bytes != null && bytes.isNotEmpty
                  ? Image.memory(Uint8List.fromList(bytes), fit: BoxFit.contain)
                  : Image.network(
                      url,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      errorBuilder: (context, error, stack) =>
                          _buildLightboxBroken(theme, label),
                    ),
            ),
            Positioned(
              right: 4,
              top: 4,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Material(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                    child: IconButton(
                      onPressed: () => onOpenExternal(url),
                      icon: const Icon(
                        Icons.open_in_new_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                      tooltip: 'Buka di tab baru',
                      constraints: BoxConstraints(),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Material(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                      tooltip: 'Tutup',
                      constraints: BoxConstraints(),
                    ),
                  ),
                ],
              ),
            ),
            if (label.isNotEmpty)
              Positioned(
                left: 10,
                bottom: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLightboxBroken(ThemeData theme, String label) {
    return Container(
      width: 260,
      height: 200,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.broken_image_rounded,
              size: 32,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

String normalizeMathMarkdown(String markdown) {
  return markdown.replaceAllMapped(RegExp(r'```[ \t]*\n([\s\S]*?)\n```'), (
    match,
  ) {
    final content = match.group(1)?.trim() ?? '';
    if (!_looksLikeFormulaBlock(content)) return match.group(0)!;
    return '\$\$\n$content\n\$\$';
  });
}

bool _looksLikeFormulaBlock(String content) {
  if (content.isEmpty || content.contains(';')) return false;

  final lines = content
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (lines.isEmpty || lines.length > 4) return false;

  final formulaSignals = RegExp(
    r'(\\(?:frac|sqrt|sum|prod|int|lim|sin|cos|tan|ln|log|times|cdot|mod|pm|leq|geq)|[=^_∑√π×÷±≤≥]|\b(?:mod|sin|cos|ln|log)\b)',
  );
  final proseSignals = RegExp(
    r'^(-|\*|\d+\.|for\s|if\s|while\s|return\s)',
    caseSensitive: false,
  );

  return lines.every(
    (line) => formulaSignals.hasMatch(line) && !proseSignals.hasMatch(line),
  );
}

bool _looksLikeProseBlock(String content) {
  final lines = content
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (lines.length < 2 || lines.length > 16) return false;

  final codeSignals = RegExp(
    r'(;|=>|==|===|!=|!==|\{|\}|<\/?[a-z][^>]*>|^\s*(const|let|var|final|class|function|def|import|export|return|if|for|while|switch|try|catch)\b)',
    caseSensitive: false,
  );
  final proseLines = lines.where((line) {
    final hasLetters = RegExp(r'[A-Za-zÀ-ÿ]').hasMatch(line);
    final hasSpaces = line.contains(' ');
    return hasLetters && hasSpaces && !codeSignals.hasMatch(line);
  }).length;

  return proseLines >= (lines.length * 0.7).ceil();
}

class MessageBubble extends StatefulWidget {
  final ChatMessage message;
  final Animation<double>? animation;
  final VoidCallback? onRetry;
  final ValueChanged<String>? onOpenArtifact;
  final void Function(MessageAttachment attachment)? onOpenImage;

  /// Live text source while this message is streaming. Only this bubble
  /// listens, so token updates never rebuild the rest of the screen.
  final ValueListenable<String>? streamingText;

  const MessageBubble({
    super.key,
    required this.message,
    this.animation,
    this.onRetry,
    this.onOpenArtifact,
    this.onOpenImage,
    this.streamingText,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble>
    with SingleTickerProviderStateMixin {
  bool _showCopied = false;
  late final AnimationController _cursorController;

  // Markdown parsing is expensive and the chat screen rebuilds every bubble
  // on each streaming tick. Returning the identical widget instance lets
  // Flutter skip the whole subtree, so completed bubbles parse only once.
  Widget? _cachedMarkdown;
  ChatMessage? _cachedMarkdownMsg;
  Brightness? _cachedMarkdownBrightness;

  @override
  void initState() {
    super.initState();
    _cursorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _cursorController.dispose();
    super.dispose();
  }

  void _copyContent() {
    // Use live streaming text if available (during streaming), otherwise use message content
    final text = widget.streamingText?.value ?? widget.message.content;
    Clipboard.setData(ClipboardData(text: text));
    setState(() => _showCopied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showCopied = false);
    });
  }

  Widget _buildMessageAction(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    final effectiveColor = color ?? theme.colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: effectiveColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: effectiveColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final msg = widget.message;
    final isUser = msg.role == MessageRole.user;
    final isBrowsing = msg.isBrowsing;
    final isThinking = msg.isThinking;
    final isImageLoading = msg.isImageLoading;
    final isTyping = msg.isTyping;
    final isDone =
        !msg.isLoading &&
        !isBrowsing &&
        !isThinking &&
        !isImageLoading &&
        !isTyping;

    Widget bubble = Container(
      margin: EdgeInsets.only(
        left: isUser ? 48 : 0,
        right: isUser ? 0 : 48,
        bottom: 8,
      ),
      child: Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          // Role label
          Padding(
            padding: const EdgeInsets.only(bottom: 6, left: 4, right: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isUser)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.asset(
                        'assets/logo.png',
                        width: 16,
                        height: 16,
                      ),
                    ),
                  )
                else
                  Icon(
                    Icons.person_rounded,
                    size: 14,
                    color: theme.colorScheme.primary,
                  ),
                const SizedBox(width: 4),
                Text(
                  isUser ? 'You' : 'AskLo',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          // Message body
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: msg.isError
                  ? theme.colorScheme.errorContainer.withValues(alpha: 0.35)
                  : isUser
                  ? theme.colorScheme.primary.withValues(alpha: 0.15)
                  : theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(isUser ? 18 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 18),
              ),
              border: Border.all(
                color: msg.isError
                    ? theme.colorScheme.error.withValues(alpha: 0.35)
                    : isUser
                    ? theme.colorScheme.primary.withValues(alpha: 0.2)
                    : theme.colorScheme.outline.withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
            child: msg.isError
                ? Align(
                    alignment: isUser
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: _buildErrorCard(theme, msg),
                  )
                : isBrowsing
                ? _buildBrowsingIndicator(theme)
                : isThinking
                ? _buildThinkingIndicator(theme)
                : isImageLoading
                ? const _ImageGenerationLoadingCard()
                : isUser
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (msg.content.trim().isNotEmpty)
                        SelectableText(
                          msg.content,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface,
                            height: 1.5,
                          ),
                        ),
                      if (msg.attachments.isNotEmpty) ...[
                        if (msg.content.trim().isNotEmpty)
                          const SizedBox(height: 12),
                        _SentAttachmentPreviewGrid(
                          attachments: msg.attachments,
                          onOpenImage: widget.onOpenImage,
                        ),
                      ],
                    ],
                  )
                // Performance: plain streaming text during typing,
                // full Markdown only when the message is complete.
                : isTyping
                ? _buildStreamingText(theme, msg)
                : _buildAssistantMarkdown(theme, msg),
          ),
          if (!isUser && msg.content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Wrap(
                spacing: 4,
                children: [
                  _buildMessageAction(
                    theme,
                    icon: _showCopied
                        ? Icons.check_rounded
                        : Icons.copy_rounded,
                    label: _showCopied ? 'Copied!' : 'Copy',
                    color: _showCopied ? Colors.green : null,
                    onTap: _copyContent,
                  ),
                  if (isDone && widget.onRetry != null)
                    _buildMessageAction(
                      theme,
                      icon: Icons.refresh_rounded,
                      label: 'Retry',
                      color: theme.colorScheme.primary,
                      onTap: widget.onRetry!,
                    ),
                ],
              ),
            ),
        ],
      ),
    );

    if (widget.animation != null) {
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: widget.animation!,
          curve: Curves.easeOut,
        ),
        child: bubble,
      );
    }

    return bubble;
  }

  Widget _buildStreamingText(ThemeData theme, ChatMessage msg) {
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurface,
      height: 1.6,
    );
    final listenable = widget.streamingText;

    Widget buildWithText(String text) {
      return AnimatedBuilder(
        animation: _cursorController,
        builder: (context, _) {
          final opacity = 0.3 + (_cursorController.value * 0.7);
          return Text.rich(
            TextSpan(
              children: [
                TextSpan(text: text, style: style),
                TextSpan(
                  text: ' ▌',
                  style: style?.copyWith(
                    color: theme.colorScheme.primary.withValues(alpha: opacity),
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    if (listenable == null) {
      return buildWithText(msg.displayContent);
    }
    return ValueListenableBuilder<String>(
      valueListenable: listenable,
      builder: (context, text, _) => buildWithText(text),
    );
  }

  Widget _buildAssistantMarkdown(ThemeData theme, ChatMessage msg) {
    if (_cachedMarkdown != null &&
        identical(_cachedMarkdownMsg, msg) &&
        _cachedMarkdownBrightness == theme.brightness) {
      return _cachedMarkdown!;
    }

    final built = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MarkdownBody(
          data: normalizeMathMarkdown(msg.displayContent),
          selectable: true,
          styleSheet: _markdownStyle(theme),
          extensionSet: md.ExtensionSet(
            [
              LatexBlockSyntax(),
              ...md.ExtensionSet.gitHubFlavored.blockSyntaxes,
            ],
            [
              LatexInlineSyntax(),
              ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
            ],
          ),
          builders: {
            'pre': _CodeBlockBuilder(),
            'latex': LatexElementBuilder(
              textStyle: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          },
          onTapLink: (text, href, title) => _openSafeLink(href),
          sizedImageBuilder: (config) =>
              _buildImage(config.uri, config.title, config.alt, theme),
        ),
        if (msg.artifact != null) ...[
          const SizedBox(height: 12),
          _ArtifactMessageCard(
            title: msg.artifact!.title,
            kind: msg.artifact!.kind,
            fileCount: msg.artifact!.fileCount,
            onTap: widget.onOpenArtifact == null
                ? null
                : () => widget.onOpenArtifact!(msg.artifact!.id),
          ),
        ],
      ],
    );

    _cachedMarkdownMsg = msg;
    _cachedMarkdownBrightness = theme.brightness;
    _cachedMarkdown = built;
    return built;
  }

  bool _isSafeHttpUrl(Uri uri) {
    return uri.scheme == 'https' || uri.scheme == 'http';
  }

  bool _isTrustedImageUri(Uri uri) {
    if (uri.scheme == 'data') {
      return uri.toString().toLowerCase().startsWith('data:image/');
    }
    if (!_isSafeHttpUrl(uri)) return false;
    final host = uri.host.toLowerCase();
    return host == 'asklo.iyantama.tech' || host == 'www.asklo.iyantama.tech';
  }

  Future<void> _openSafeLink(String? href) async {
    if (href == null || href.trim().isEmpty) return;
    final uri = Uri.tryParse(href.trim());
    if (uri == null || !_isSafeHttpUrl(uri)) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _buildBlockedImage(ThemeData theme) {
    return Container(
      height: 100,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Center(
        child: Text(
          'Gambar eksternal diblokir',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildBrokenImage(ThemeData theme) {
    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.3),
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_rounded, color: theme.colorScheme.error),
            const SizedBox(height: 4),
            Text('Gagal memuat gambar', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _buildImageContent(String imageUrl, Uri safeUri, ThemeData theme) {
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final maxLogicalWidth = math.min(
      MediaQuery.sizeOf(context).width,
      AppConstants.maxChatWidth,
    );
    final cacheWidth = (maxLogicalWidth * pixelRatio).round();

    if (safeUri.scheme == 'data') {
      if (imageUrl.length > 8 * 1024 * 1024) return _buildBrokenImage(theme);
      try {
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            UriData.parse(imageUrl).contentAsBytes(),
            fit: BoxFit.contain,
            cacheWidth: cacheWidth,
            filterQuality: FilterQuality.medium,
            errorBuilder: (context, error, stack) => _buildBrokenImage(theme),
          ),
        );
      } catch (_) {
        return _buildBrokenImage(theme);
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        imageUrl,
        fit: BoxFit.contain,
        cacheWidth: cacheWidth,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) return child;
          return _buildImagePlaceholder(theme, null);
        },
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return _buildImagePlaceholder(theme, progress);
        },
        errorBuilder: (context, error, stack) => _buildBrokenImage(theme),
      ),
    );
  }

  Widget _buildImagePlaceholder(ThemeData theme, ImageChunkEvent? progress) {
    final value = progress?.expectedTotalBytes == null
        ? null
        : progress!.cumulativeBytesLoaded / progress.expectedTotalBytes!;

    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.16),
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(value: value, strokeWidth: 2.4),
            ),
            const SizedBox(height: 10),
            Text(
              'Memuat gambar...',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage(Uri uri, String? title, String? alt, ThemeData theme) {
    // Rewrite localhost URLs for mobile compatibility
    String imageUrl = uri.toString();
    imageUrl = imageUrl.replaceFirst(
      RegExp(r'http://localhost:\d+'),
      AppConstants.backendUrl,
    );

    final safeUri = Uri.tryParse(imageUrl);
    if (safeUri == null || !_isTrustedImageUri(safeUri)) {
      return _buildBlockedImage(theme);
    }

    final canOpenDownload = _isSafeHttpUrl(safeUri);

    final content = _buildImageContent(imageUrl, safeUri, theme);

    Widget openable = content;
    if (canOpenDownload) {
      openable = GestureDetector(
        onTap: () => _openSafeLink(imageUrl),
        child: MouseRegion(cursor: SystemMouseCursors.click, child: content),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Stack(
        children: [
          openable,
          if (canOpenDownload)
            Positioned(
              right: 8,
              bottom: 8,
              child: Material(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _openSafeLink(imageUrl),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(
                      Icons.download_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  MarkdownStyleSheet _markdownStyle(ThemeData theme) {
    final body = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurface,
      height: 1.72,
      letterSpacing: 0.05,
    );

    return MarkdownStyleSheet(
      p: body,
      pPadding: const EdgeInsets.only(bottom: 6),
      blockSpacing: 14,
      listIndent: 26,
      listBulletPadding: const EdgeInsets.only(right: 8),
      code: theme.textTheme.bodySmall?.copyWith(
        fontFamily: 'monospace',
        backgroundColor: const Color(0xFF1E1E2E),
        color: const Color(0xFFFCA5A5),
        fontSize: 13,
      ),
      codeblockDecoration: const BoxDecoration(),
      codeblockPadding: EdgeInsets.zero,
      h1: theme.textTheme.headlineSmall?.copyWith(
        color: theme.colorScheme.onSurface,
        fontWeight: FontWeight.w800,
        height: 1.25,
      ),
      h1Padding: const EdgeInsets.only(top: 4, bottom: 12),
      h2: theme.textTheme.titleLarge?.copyWith(
        color: theme.colorScheme.onSurface,
        fontWeight: FontWeight.w800,
        height: 1.3,
      ),
      h2Padding: const EdgeInsets.only(top: 12, bottom: 8),
      h3: theme.textTheme.titleMedium?.copyWith(
        color: theme.colorScheme.onSurface,
        fontWeight: FontWeight.w700,
        height: 1.35,
      ),
      h3Padding: const EdgeInsets.only(top: 10, bottom: 6),
      blockquote: body?.copyWith(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.86),
      ),
      blockquoteDecoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(color: theme.colorScheme.primary, width: 3),
        ),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
      listBullet: body?.copyWith(fontWeight: FontWeight.w700),
      strong: body?.copyWith(fontWeight: FontWeight.w800),
      em: body?.copyWith(fontStyle: FontStyle.italic),
      a: body?.copyWith(
        color: theme.colorScheme.primary,
        decoration: TextDecoration.underline,
        decorationThickness: 1.4,
      ),
      tableColumnWidth: const IntrinsicColumnWidth(),
      tableScrollbarThumbVisibility: true,
      tableCellsPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      tableCellsDecoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.34),
      ),
      tableBorder: TableBorder.all(
        color: theme.colorScheme.outline.withValues(alpha: 0.24),
        width: 0.6,
        borderRadius: BorderRadius.circular(8),
      ),
      tableHead: theme.textTheme.bodySmall?.copyWith(
        fontWeight: FontWeight.w800,
        color: theme.colorScheme.onSurface,
      ),
      tableBody: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
        height: 1.45,
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.28),
            width: 3,
          ),
        ),
      ),
    );
  }

  Widget _buildErrorCard(ThemeData theme, ChatMessage msg) {
    final lines = msg.content
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();
    final title = lines.isEmpty ? 'Pesan gagal dikirim' : lines.first;
    final details = lines.skip(1).join('\n');
    final showToggle = details.isNotEmpty;
    final isCompact = msg.requestId == null;

    return Container(
      padding: isCompact
          ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
          : const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: isCompact
            ? BorderRadius.circular(999)
            : BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: isCompact ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
                if (showToggle) ...[
                  const SizedBox(height: 4),
                  Text(
                    details,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer.withValues(
                        alpha: 0.8,
                      ),
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (msg.requestId != null)
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: SelectableText(
                'ID ${msg.requestId}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer.withValues(
                    alpha: 0.6,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildThinkingIndicator(ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: theme.colorScheme.primary.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'Thinking...',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  Widget _buildBrowsingIndicator(ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: theme.colorScheme.primary.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'Browsing web...',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

class _ArtifactMessageCard extends StatefulWidget {
  final String title;
  final String kind;
  final int fileCount;
  final VoidCallback? onTap;

  const _ArtifactMessageCard({
    required this.title,
    required this.kind,
    required this.fileCount,
    this.onTap,
  });

  @override
  State<_ArtifactMessageCard> createState() => _ArtifactMessageCardState();
}

class _ArtifactMessageCardState extends State<_ArtifactMessageCard>
    with SingleTickerProviderStateMixin {
  bool _hovered = false;
  late final AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCode = widget.kind == 'code_file' || widget.kind == 'code_project';

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        transform: _hovered
            ? Matrix4.diagonal3Values(1.01, 1.01, 1.0)
            : Matrix4.identity(),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF0D1117),
                    const Color(0xFF161B22),
                    theme.colorScheme.primary.withValues(alpha: 0.08),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _hovered
                      ? theme.colorScheme.primary.withValues(alpha: 0.5)
                      : theme.colorScheme.primary.withValues(alpha: 0.2),
                  width: _hovered ? 1.5 : 1,
                ),
                boxShadow: _hovered
                    ? [
                        BoxShadow(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.15,
                          ),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Animated icon container
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              theme.colorScheme.primary.withValues(alpha: 0.25),
                              theme.colorScheme.tertiary.withValues(
                                alpha: 0.15,
                              ),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.2,
                            ),
                          ),
                        ),
                        child: Icon(
                          isCode
                              ? Icons.code_rounded
                              : Icons.description_rounded,
                          color: theme.colorScheme.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary.withValues(
                                      alpha: 0.15,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    isCode ? '💻 Code' : '📄 Document',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${widget.fileCount} file${widget.fileCount > 1 ? 's' : ''}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Shimmer bar
                  AnimatedBuilder(
                    animation: _shimmerController,
                    builder: (context, _) {
                      return Container(
                        height: 3,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          gradient: LinearGradient(
                            begin: Alignment(
                              -1.0 + 2.0 * _shimmerController.value,
                              0,
                            ),
                            end: Alignment(
                              -0.5 + 2.0 * _shimmerController.value,
                              0,
                            ),
                            colors: [
                              Colors.transparent,
                              theme.colorScheme.primary.withValues(alpha: 0.4),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  // Open button
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: widget.onTap,
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: Text(
                        isCode ? '🖥️ Buka Code View' : '📂 Buka Artifact',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SentAttachmentPreviewGrid extends StatelessWidget {
  final List<MessageAttachment> attachments;
  final void Function(MessageAttachment attachment)? onOpenImage;

  const _SentAttachmentPreviewGrid({
    required this.attachments,
    this.onOpenImage,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: attachments
          .map(
            (attachment) => _SentAttachmentCard(
              attachment: attachment,
              onOpenImage: onOpenImage,
            ),
          )
          .toList(),
    );
  }
}

class _SentAttachmentCard extends StatefulWidget {
  final MessageAttachment attachment;
  final void Function(MessageAttachment attachment)? onOpenImage;

  const _SentAttachmentCard({required this.attachment, this.onOpenImage});

  @override
  State<_SentAttachmentCard> createState() => _SentAttachmentCardState();
}

class _SentAttachmentCardState extends State<_SentAttachmentCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final attachment = widget.attachment;
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    final width = attachment.isImage ? (isMobile ? 118.0 : 154.0) : 220.0;
    final height = attachment.isImage ? (isMobile ? 118.0 : 144.0) : 76.0;

    final canOpen = attachment.isImage && widget.onOpenImage != null;

    Widget body = Container(
      width: width,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _hovered && canOpen
              ? theme.colorScheme.primary.withValues(alpha: 0.5)
              : theme.colorScheme.primary.withValues(alpha: 0.22),
          width: _hovered && canOpen ? 1.5 : 1,
        ),
      ),
      child: attachment.isImage
          ? _buildImagePreview(theme)
          : _buildFilePreview(theme),
    );

    if (!canOpen) {
      return body;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _hovered = true),
        onTapUp: (_) => setState(() => _hovered = false),
        onTapCancel: () => setState(() => _hovered = false),
        onTap: () => widget.onOpenImage!(attachment),
        child: body,
      ),
    );
  }

  Widget _buildImagePreview(ThemeData theme) {
    final bytes = widget.attachment.previewBytes;
    if (bytes != null && bytes.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(
            Uint8List.fromList(bytes),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildFilePreview(theme),
          ),
          if (_hovered)
            Positioned.fill(
              child: Container(color: Colors.black.withValues(alpha: 0.18)),
            ),
          if (_hovered)
            Positioned(
              right: 8,
              top: 8,
              child: Material(
                color: Colors.black.withValues(alpha: 0.62),
                borderRadius: BorderRadius.circular(20),
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(
                    Icons.zoom_in_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: _caption(theme, Icons.image_rounded),
          ),
        ],
      );
    }
    return _buildFilePreview(theme);
  }

  Widget _buildFilePreview(ThemeData theme) {
    final attachment = widget.attachment;
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_icon, size: 18, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  attachment.sizeBytes == null
                      ? _label
                      : '$_label • ${_formatBytes(attachment.sizeBytes!)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _caption(ThemeData theme, IconData icon) {
    final attachment = widget.attachment;
    return Container(
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
              attachment.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  IconData get _icon {
    final ext = widget.attachment.extension;
    if (ext == 'pdf') return Icons.picture_as_pdf_rounded;
    if (['ppt', 'pptx'].contains(ext)) return Icons.slideshow_rounded;
    if (['txt', 'md', 'log', 'csv'].contains(ext)) return Icons.notes_rounded;
    return Icons.insert_drive_file_rounded;
  }

  String get _label {
    final ext = widget.attachment.extension;
    if (ext == 'pdf') return 'PDF';
    if (['ppt', 'pptx'].contains(ext)) return 'Presentation';
    if (['txt', 'md', 'log', 'csv'].contains(ext)) return 'Text file';
    return 'Attachment';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _ImageGenerationLoadingCard extends StatefulWidget {
  const _ImageGenerationLoadingCard();

  @override
  State<_ImageGenerationLoadingCard> createState() =>
      _ImageGenerationLoadingCardState();
}

class _ImageGenerationLoadingCardState
    extends State<_ImageGenerationLoadingCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMobile = MediaQuery.sizeOf(context).width < 600;

    return Container(
      height: isMobile ? 260 : 340,
      decoration: BoxDecoration(
        color: const Color(0xFF2B2B31),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _ImageLoadingDotsPainter(
                      progress: _controller.value,
                      dotColor: Colors.white,
                      accentColor: theme.colorScheme.primary,
                    ),
                  );
                },
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.45, 0.05),
                    radius: 0.9,
                    colors: [
                      theme.colorScheme.primary.withValues(alpha: 0.12),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: isMobile ? 18 : 28,
              top: isMobile ? 18 : 26,
              child: Text(
                'Creating image',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w800,
                  fontSize: isMobile ? 18 : 22,
                ),
              ),
            ),
            Positioned(
              left: isMobile ? 18 : 28,
              right: isMobile ? 18 : 28,
              bottom: isMobile ? 18 : 24,
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Membuat gambar... preview akan muncul di sini.',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.66),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
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

class _ImageLoadingDotsPainter extends CustomPainter {
  final double progress;
  final Color dotColor;
  final Color accentColor;

  const _ImageLoadingDotsPainter({
    required this.progress,
    required this.dotColor,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const columns = 18;
    const rows = 14;
    final horizontalGap = size.width / (columns + 1);
    final verticalGap = size.height / (rows + 1);
    final wave = progress * (columns + rows + 4);

    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        final x = horizontalGap * (column + 1);
        final y = verticalGap * (row + 1);
        final diagonal = column + row;
        final distance = (diagonal - wave).abs();
        final highlight = math.max(0.0, 1.0 - distance / 4.0);
        final centerBias =
            1 -
            math.min(
              1.0,
              ((x - size.width * 0.62).abs() / size.width) +
                  ((y - size.height * 0.48).abs() / size.height),
            );
        final alpha = 0.12 + (highlight * 0.42) + (centerBias * 0.12);
        final safeAlpha = alpha < 0.08
            ? 0.08
            : alpha > 0.68
            ? 0.68
            : alpha;
        final radius = 1.35 + (highlight * 0.75);
        final color = Color.lerp(
          dotColor,
          accentColor,
          highlight * 0.28,
        )!.withValues(alpha: safeAlpha.toDouble());

        canvas.drawCircle(Offset(x, y), radius, Paint()..color = color);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ImageLoadingDotsPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.dotColor != dotColor ||
        oldDelegate.accentColor != accentColor;
  }
}

/// Custom code block builder with syntax highlighting and copy button
class _CodeBlockBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    // Extract language and code
    String code = element.textContent;
    String language = '';

    if (element.children != null && element.children!.isNotEmpty) {
      final first = element.children!.first;
      if (first is md.Element && first.tag == 'code') {
        final cls = first.attributes['class'] ?? '';
        if (cls.startsWith('language-')) {
          language = cls.replaceFirst('language-', '');
        }
        code = first.textContent;
      }
    }

    // Remove trailing newline
    if (code.endsWith('\n')) code = code.substring(0, code.length - 1);

    if (language.isEmpty && _looksLikeProseBlock(code)) {
      return _ProseBlockWidget(text: code);
    }

    return _CodeBlockWidget(code: code, language: language);
  }
}

class _ProseBlockWidget extends StatelessWidget {
  final String text;

  const _ProseBlockWidget({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.16),
        ),
      ),
      child: SelectableText(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.92),
          height: 1.58,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _CodeBlockWidget extends StatefulWidget {
  final String code;
  final String language;

  const _CodeBlockWidget({required this.code, required this.language});

  @override
  State<_CodeBlockWidget> createState() => _CodeBlockWidgetState();
}

class _CodeBlockWidgetState extends State<_CodeBlockWidget> {
  bool _copied = false;

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: widget.code));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  // Map common language aliases
  String _normalizeLanguage(String lang) {
    final map = {
      'js': 'javascript',
      'ts': 'typescript',
      'py': 'python',
      'rb': 'ruby',
      'kt': 'kotlin',
      'rs': 'rust',
      'sh': 'bash',
      'yml': 'yaml',
      'md': 'markdown',
      'cs': 'csharp',
      'cpp': 'cpp',
      'tsx': 'typescript',
      'jsx': 'javascript',
    };
    return map[lang.toLowerCase()] ?? lang.toLowerCase();
  }

  String _displayLanguage(String lang) {
    if (lang.isEmpty) return 'code';
    final display = {
      'javascript': 'JavaScript',
      'typescript': 'TypeScript',
      'python': 'Python',
      'dart': 'Dart',
      'html': 'HTML',
      'css': 'CSS',
      'json': 'JSON',
      'yaml': 'YAML',
      'bash': 'Bash',
      'shell': 'Shell',
      'sql': 'SQL',
      'rust': 'Rust',
      'go': 'Go',
      'java': 'Java',
      'kotlin': 'Kotlin',
      'swift': 'Swift',
      'csharp': 'C#',
      'cpp': 'C++',
      'c': 'C',
      'php': 'PHP',
      'ruby': 'Ruby',
      'markdown': 'Markdown',
      'xml': 'XML',
      'dockerfile': 'Dockerfile',
    };
    final norm = _normalizeLanguage(lang);
    return display[norm] ?? lang.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final normalizedLang = _normalizeLanguage(widget.language);
    final isMobile = MediaQuery.of(context).size.width < 600;
    final codeFontSize = isMobile ? 11.5 : 13.0;
    final codePadding = isMobile ? 10.0 : 14.0;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D1A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFF7C3AED).withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header bar
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 10 : 14,
              vertical: isMobile ? 6 : 8,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF12121E),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
            ),
            child: Row(
              children: [
                // Language dot
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: _getLanguageColor(normalizedLang),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _displayLanguage(widget.language),
                  style: TextStyle(
                    color: const Color(0xFF8B8FA7),
                    fontSize: isMobile ? 10.5 : 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                // Copy button
                InkWell(
                  onTap: _copyCode,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 6 : 8,
                      vertical: 3,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _copied ? Icons.check_rounded : Icons.copy_rounded,
                          size: isMobile ? 12 : 14,
                          color: _copied
                              ? const Color(0xFF22C55E)
                              : const Color(0xFF8B8FA7),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _copied ? 'Copied!' : 'Copy',
                          style: TextStyle(
                            fontSize: isMobile ? 10.5 : 12,
                            color: _copied
                                ? const Color(0xFF22C55E)
                                : const Color(0xFF8B8FA7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Code body with syntax highlighting
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: EdgeInsets.all(codePadding),
              child: HighlightView(
                widget.code,
                language: normalizedLang.isEmpty ? 'plaintext' : normalizedLang,
                theme: monokaiSublimeTheme,
                padding: EdgeInsets.zero,
                textStyle: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: codeFontSize,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getLanguageColor(String lang) {
    final colors = {
      'javascript': const Color(0xFFF7DF1E),
      'typescript': const Color(0xFF3178C6),
      'python': const Color(0xFF3776AB),
      'dart': const Color(0xFF0175C2),
      'html': const Color(0xFFE34F26),
      'css': const Color(0xFF1572B6),
      'json': const Color(0xFF292929),
      'rust': const Color(0xFFDEA584),
      'go': const Color(0xFF00ADD8),
      'java': const Color(0xFFB07219),
      'kotlin': const Color(0xFF7F52FF),
      'swift': const Color(0xFFFA7343),
      'csharp': const Color(0xFF178600),
      'cpp': const Color(0xFFF34B7D),
      'ruby': const Color(0xFFCC342D),
      'php': const Color(0xFF777BB4),
      'bash': const Color(0xFF4EAA25),
      'sql': const Color(0xFFE38C00),
    };
    return colors[lang] ?? const Color(0xFF8B8FA7);
  }
}

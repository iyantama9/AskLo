import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A single model entry for the modern dropdown picker.
class PickerModel {
  final String id;
  final String label;
  final String? category;
  final String? logoUrl;

  const PickerModel({
    required this.id,
    required this.label,
    this.category,
    this.logoUrl,
  });
}

/// A layout-safe model **dropdown** that opens a bounded panel BELOW the
/// trigger (like a native select box). The panel shows the model list
/// grouped by provider with a purple section header per provider and a
/// checkmark on the active model — matching the original AskLo design.
class ModelDropdown extends StatefulWidget {
  final String? selectedId;
  final List<PickerModel> items;
  final ValueChanged<String> onPicked;
  final IconData? icon;
  final int pageSize;
  final double panelWidth;
  final bool fillWidth;

  const ModelDropdown({
    super.key,
    required this.selectedId,
    required this.items,
    required this.onPicked,
    this.icon,
    this.pageSize = 6,
    this.panelWidth = 300,
    this.fillWidth = true,
  });

  @override
  State<ModelDropdown> createState() => _ModelDropdownState();
}

class _ModelDropdownState extends State<ModelDropdown> {
  final _triggerKey = GlobalKey();
  OverlayEntry? _overlayEntry;

  String get _currentLabel {
    if (widget.selectedId == null) return '';
    for (final m in widget.items) {
      if (m.id == widget.selectedId) return m.label;
    }
    return '';
  }

  double get _panelW {
    // Tight, content-width panel. On phones it hugs the trigger pill; on
    // wide screens it never overflows past a comfortable cap.
    final vw = MediaQuery.sizeOf(context).width;
    // Small screens: ~72% of viewport so it reads as a compact dropdown, not a
    // wide panel. Large screens: hard-cap at 300.
    final cap = vw < 640 ? vw * 0.72 : 300.0;
    final preferred = math.min(widget.panelWidth, cap);
    // Floor of 200 so labels never get crushed; never exceed the viewport.
    return math.max(200, math.min(preferred, vw - 24));
  }

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _open() {
    if (_overlayEntry != null) return;
    final triggerCtx = _triggerKey.currentContext;
    if (triggerCtx == null) return;
    final trigger = triggerCtx.findRenderObject();
    if (trigger is! RenderBox) return;

    final rect = trigger.localToGlobal(Offset.zero) & trigger.size;
    final vw = MediaQuery.sizeOf(context).width;
    final vh = MediaQuery.sizeOf(context).height;
    final panelW = _panelW;
    final alignRight = !widget.fillWidth;

    final rawLeft = alignRight ? rect.right - panelW : rect.left;
    final left = math.max(12.0, math.min(rawLeft, vw - panelW - 12));

    final spaceBelow = vh - rect.bottom;
    final spaceAbove = rect.top;
    final openUpward = spaceBelow < 200 && spaceAbove > spaceBelow + 80;
    final maxHeight = openUpward
        ? math.min(440.0, spaceAbove - 12)
        : math.max(160.0, math.min(440.0, spaceBelow - 12));
    final top = openUpward
        ? math.max(12.0, rect.top - (maxHeight + 120))
        : rect.bottom + 6;

    final panel = _ModelPanel(
      width: panelW,
      maxHeight: maxHeight,
      items: widget.items,
      selectedId: widget.selectedId,
      onPicked: (id) {
        _removeOverlay();
        widget.onPicked(id);
      },
      onDismiss: _removeOverlay,
      pageSize: widget.pageSize,
    );

    _overlayEntry = OverlayEntry(
      builder: (_) => Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            bottom: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _removeOverlay,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(left: left, top: top, child: panel),
        ],
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final muted = theme.colorScheme.onSurfaceVariant;
    final accent = theme.colorScheme.primary;
    final fieldBg = theme.colorScheme.surfaceContainerHighest;

    final isOpen = _overlayEntry != null;
    final currentLabel = _currentLabel;
    final alignRight = !widget.fillWidth;

    return Align(
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: isOpen ? _removeOverlay : _open,
        child: Container(
          key: _triggerKey,
          width: widget.fillWidth ? double.infinity : null,
          height: 46,
          decoration: BoxDecoration(
            color: fieldBg.withValues(alpha: 0.6),
            border: Border.all(
              color: isOpen ? accent : muted.withValues(alpha: 0.35),
              width: isOpen ? 1.4 : 1,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize:
                widget.fillWidth ? MainAxisSize.max : MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Icon(widget.icon!, size: 18, color: accent),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  currentLabel.isNotEmpty ? currentLabel : 'Pilih model...',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: currentLabel.isNotEmpty ? onSurface : muted,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(
                  isOpen
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 20,
                  color: muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Panel content: grouped by provider (matches original AskLo design) ───

class _ModelPanel extends StatefulWidget {
  final double width;
  final double maxHeight;
  final List<PickerModel> items;
  final String? selectedId;
  final ValueChanged<String> onPicked;
  final VoidCallback onDismiss;
  final int pageSize;

  const _ModelPanel({
    required this.width,
    this.maxHeight = 440,
    required this.items,
    required this.selectedId,
    required this.onPicked,
    required this.onDismiss,
    this.pageSize = 6,
  });

  @override
  State<_ModelPanel> createState() => _ModelPanelState();
}

class _ModelPanelState extends State<_ModelPanel> {
  // Build groups once per build — preserves original AskLo ordering.
  List<(String provider, List<PickerModel> models)> get _groups {
    final map = <String, List<PickerModel>>{};
    final order = <String>[];
    for (final m in widget.items) {
      final prov = m.category?.trim().isNotEmpty == true
          ? m.category!.trim()
          : 'Lainnya';
      if (!map.containsKey(prov)) {
        map[prov] = [];
        order.add(prov);
      }
      map[prov]!.add(m);
    }
    return [
      for (final p in order) (p, map[p]!),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final muted = theme.colorScheme.onSurfaceVariant;
    final accent = theme.colorScheme.primary;
    final panelBg = theme.colorScheme.surface;
    final groups = _groups;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      builder: (_, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, (1 - v) * -6), child: child),
      ),
      child: Container(
        width: widget.width,
        decoration: BoxDecoration(
          color: panelBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: muted.withValues(alpha: 0.25)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 24, offset: const Offset(0, 8)),
          ],
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: widget.maxHeight),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var gi = 0; gi < groups.length; gi++) ...[
                  if (gi > 0) const SizedBox(height: 8),
                  // Provider section header — left-aligned, no underline
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        groups[gi].$1,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: muted,
                        ),
                      ),
                    ),
                  ),
                  for (final m in groups[gi].$2)
                    _modelRow(m, onSurface, muted, accent),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _modelRow(
    PickerModel m,
    Color onSurface,
    Color muted,
    Color accent,
  ) {
    final sel = m.id == widget.selectedId;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => widget.onPicked(m.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Row(
            children: [
              _ModelBrandLogo(url: m.logoUrl, label: m.label, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  m.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                    color: sel ? accent : onSurface,
                  ),
                ),
              ),
              if (sel)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(Icons.check_rounded, size: 16, color: accent),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A 26px model-brand logo: shows admin-uploaded provider image when available,
/// otherwise a colored initial chip keyed to the **AI model brand** (DeepSeek,
/// Gemini, GPT, Grok, GLM, Kimi, etc.) — not the provider.
class _ModelBrandLogo extends StatelessWidget {
  final String? url;
  final String? label;
  final double size;

  const _ModelBrandLogo({this.url, this.label, this.size = 26});

  /// Detect the AI model brand from the display label.
  static (String letter, Color color) _detectBrand(String label) {
    final l = label.toLowerCase();
    if (l.contains('deepseek')) return ('D', const Color(0xFF4D6BFE));
    if (l.contains('gemini')) return ('G', const Color(0xFF7C4DFF));
    if (l.contains('gpt') || l.contains('chatgpt') || l.contains('openai'))
      return ('G', const Color(0xFF10A37F));
    if (l.contains('grok') || l.contains('xai'))
      return ('X', const Color(0xFFFF5722));
    if (l.contains('glm') || l.contains('zhipu'))
      return ('G', const Color(0xFF00B8D9));
    if (l.contains('kimi') || l.contains('moonshot'))
      return ('K', const Color(0xFF2196F3));
    if (l.contains('qwen') || l.contains('tongyi'))
      return ('Q', const Color(0xFF00838F));
    if (l.contains('claude') || l.contains('anthropic'))
      return ('C', const Color(0xFFD97757));
    if (l.contains('llama') || l.contains('meta'))
      return ('L', const Color(0xFF1877F2));
    if (l.contains('mistral'))
      return ('M', const Color(0xFFFF7500));
    if (l.contains('codex'))
      return ('C', const Color(0xFF6E40C9));
    // Fallback: first letter of label
    final letter = label.isNotEmpty ? label[0].toUpperCase() : '?';
    return (letter, _hashColor(label));
  }

  /// Map detected brand name to a bundled local color logo (all .png now).
  static String? _brandAsset(String label) {
    final l = label.toLowerCase();
    String? key;
    if (l.contains('deepseek')) key = 'deepseek';
    else if (l.contains('gemini') || l.contains('google')) key = 'gemini';
    else if (l.contains('gpt') || l.contains('openai') || l.contains('codex') || l.contains('o1') || l.contains('o3') || l.contains('o4') || l.contains('luna')) key = 'openai';
    else if (l.contains('grok') || l.contains('xai') || l.contains('x ai')) key = 'grok';
    else if (l.contains('glm') || l.contains('zhipu')) key = 'glm';
    else if (l.contains('kimi') || l.contains('moonshot')) key = 'kimi';
    else if (l.contains('qwen') || l.contains('tongyi')) key = 'qwen';
    else if (l.contains('claude') || l.contains('anthropic')) key = 'claude';
    else if (l.contains('llama') || l.contains('meta')) key = 'llama';
    else if (l.contains('mistral')) key = 'mistral';
    if (key == null) return null;
    return 'lib/assets/logos/$key.png';
  }

  static Color _hashColor(String key) {
    const palette = [
      Color(0xFF3B82F6),
      Color(0xFF8B5CF6),
      Color(0xFF10B981),
      Color(0xFFF59E0B),
      Color(0xFFEF4444),
      Color(0xFF06B6D4),
      Color(0xFFEC4899),
      Color(0xFF6366F1),
    ];
    final h = key.codeUnits.fold<int>(7, (p, e) => p + e * 31);
    return palette[h % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final lbl = (label ?? '').trim();
    final (letter, color) = _detectBrand(lbl);
    final asset = _brandAsset(lbl);

    Widget fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          fontSize: size * 0.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );

    // 1) Admin-uploaded provider logo (network) wins if present.
    if (url != null && url!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.28),
        child: Image.network(
          url!,
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (ctx, err, st) => _assetOrFallback(asset, fallback, size),
          loadingBuilder: (ctx, child, progress) {
            if (progress == null) return child;
            return _assetOrFallback(asset, fallback, size);
          },
        ),
      );
    }

    // 2) Bundled brand logo.
    return _assetOrFallback(asset, fallback, size);
  }

  Widget _assetOrFallback(String? asset, Widget fallback, double s) {
    if (asset == null) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(s * 0.28),
      child: Image.asset(asset,
        width: s,
        height: s,
        fit: BoxFit.contain,
        errorBuilder: (ctx, err, st) => fallback,
      ),
    );
  }
}

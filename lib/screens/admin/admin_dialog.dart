import 'package:flutter/material.dart';

/// Dark, modern styling tokens shared by every admin modal so dialogs look
/// consistent instead of the default white Material card.
class AdminUi {
  AdminUi._();
  static const Color bg = Color(0xFF0B0C14);
  static const Color surface = Color(0xFF141520);
  static const Color field = Color(0xFF0B0C14);
  static const Color border = Color(0xFF262738);
  static const Color borderFocus = Color(0xFF7C3AED);
  static const Color accent = Color(0xFFA78BFA);
  static const Color muted = Color(0xFF8B8CA0);
  static const Color text = Color(0xFFEDEDF5);
  static const Color danger = Color(0xFFDC2626);
}

/// A dark, rounded dialog shell with a title, subtitle, and content/actions.
/// Used by all admin modals so they share one consistent modern look.
class AdminModal extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;
  final double width;

  const AdminModal({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    required this.actions,
    this.width = 480,
  });

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 520;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: isNarrow ? double.maxFinite : width,
        margin: isNarrow
            ? const EdgeInsets.all(12)
            : const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        decoration: BoxDecoration(
          color: AdminUi.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AdminUi.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.55),
              blurRadius: 40,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AdminUi.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(subtitle!,
                        style: const TextStyle(color: AdminUi.muted, fontSize: 13)),
                  ],
                ],
              ),
            ),
            // Body
            Flexible(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 520),
                  child: child,
                ),
              ),
            ),
            // Actions
            Container(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AdminUi.border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (final a in actions) ...[
                    a,
                    const SizedBox(width: 10),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A modern, dark, rounded [TextField] that matches the admin surface.
Widget darkField({
  required TextEditingController controller,
  String? label,
  String? hint,
  IconData? icon,
  bool obscure = false,
  bool enabled = true,
  int maxLines = 1,
  TextInputType? keyboardType,
  Widget? suffix,
  ValueChanged<String>? onChanged,
}) {
  return TextField(
    controller: controller,
    obscureText: obscure,
    enabled: enabled,
    maxLines: maxLines,
    keyboardType: keyboardType,
    onChanged: onChanged,
    style: const TextStyle(color: AdminUi.text, fontSize: 14),
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon == null ? null : Icon(icon, color: AdminUi.muted, size: 18),
      suffixIcon: suffix,
      labelStyle: const TextStyle(color: AdminUi.muted),
      hintStyle: TextStyle(color: AdminUi.muted.withValues(alpha: 0.7)),
      filled: true,
      fillColor: AdminUi.field,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AdminUi.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
            color: enabled ? AdminUi.border : AdminUi.border.withValues(alpha: 0.4)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AdminUi.borderFocus, width: 1.5),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide:
            const BorderSide(color: AdminUi.border, style: BorderStyle.solid),
      ),
    ),
  );
}

/// A rounded, section-labeled pill row of toggles (checkbox chips).
Widget pillToggleRow({
  required String label,
  required bool value,
  required ValueChanged<bool> onChanged,
  IconData? icon,
}) {
  return Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: value ? const Color(0xFF1F1B3A) : AdminUi.field,
          border: Border.all(color: value ? AdminUi.accent : AdminUi.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon ?? Icons.check_circle_outline,
                size: 16, color: value ? AdminUi.accent : AdminUi.muted),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    color: value ? Colors.white : AdminUi.muted,
                    fontSize: 13,
                    fontWeight: value ? FontWeight.w600 : FontWeight.w400)),
          ],
        ),
      ),
    ),
  );
}

/// Modern cancel / confirm buttons for [AdminModal.actions].
List<Widget> modalActions({
  required VoidCallback onCancel,
  required VoidCallback onConfirm,
  String cancelLabel = 'Batal',
  required String confirmLabel,
  bool busy = false,
  Color? confirmColor,
}) {
  return [
    TextButton(
      onPressed: busy ? null : onCancel,
      style: TextButton.styleFrom(
        foregroundColor: AdminUi.muted,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
      child: Text(cancelLabel),
    ),
    FilledButton(
      onPressed: busy ? null : onConfirm,
      style: FilledButton.styleFrom(
        backgroundColor: confirmColor ?? const Color(0xFF7C3AED),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
      ),
      child: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2))
          : Text(confirmLabel),
    ),
  ];
}

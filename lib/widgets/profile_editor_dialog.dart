import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';

/// Modal dialog that lets the signed-in user change their nickname
/// (display_name) and profile photo (avatar).
class ProfileEditorDialog extends StatefulWidget {
  final String displayName;
  final String? avatarUrl;
  final ValueChanged<String> onChanged;

  const ProfileEditorDialog({
    super.key,
    required this.displayName,
    required this.avatarUrl,
    required this.onChanged,
  });

  static Future<void> show(
    BuildContext context, {
    required String displayName,
    required String? avatarUrl,
    required ValueChanged<String> onChanged,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => ProfileEditorDialog(
        displayName: displayName,
        avatarUrl: avatarUrl,
        onChanged: onChanged,
      ),
    );
  }

  @override
  State<ProfileEditorDialog> createState() => _ProfileEditorDialogState();
}

class _ProfileEditorDialogState extends State<ProfileEditorDialog> {
  final _api = ApiService();
  late final TextEditingController _nameController;

  String? _pendingAvatarUrl;
  String? _avatarError;
  bool _uploadingAvatar = false;
  bool _removingAvatar = false;
  bool _savingName = false;

  final double _maxAvatarBytes = 2 * 1024 * 1024; // 2MB

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.displayName);
    _pendingAvatarUrl = widget.avatarUrl;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadAvatar() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'gif'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;

    if (file.bytes == null) {
      setState(() => _avatarError = 'Gagal membaca gambar.');
      return;
    }

    if (file.size > _maxAvatarBytes) {
      setState(() => _avatarError = 'Foto terlalu besar (maks 2MB).');
      return;
    }

    final ext = file.extension?.toLowerCase() ?? '';
    String contentType = 'image/jpeg';
    if (['jpg', 'jpeg'].contains(ext)) contentType = 'image/jpeg';
    if (ext == 'png') contentType = 'image/png';
    if (ext == 'gif') contentType = 'image/gif';
    if (ext == 'webp') contentType = 'image/webp';

    setState(() {
      _uploadingAvatar = true;
      _avatarError = null;
    });

    try {
      final url = await _api.uploadAvatar(file.bytes!, file.name, contentType);
      if (!mounted) return;
      setState(() {
        _pendingAvatarUrl = url;
        _uploadingAvatar = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploadingAvatar = false;
        _avatarError = 'Upload foto gagal: $e';
      });
    }
  }

  Future<void> _removeAvatar() async {
    setState(() {
      _removingAvatar = true;
      _avatarError = null;
    });
    try {
      await _api.removeAvatar();
      if (!mounted) return;
      setState(() {
        _pendingAvatarUrl = null;
        _removingAvatar = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _removingAvatar = false;
        _avatarError = 'Gagal hapus foto: $e';
      });
    }
  }

  Future<void> _saveName() async {
    final name = _nameController.text.trim();
    if (name.length < 2 || name.length > 50 || _savingName) return;

    setState(() => _savingName = true);
    try {
      await _api.updateDisplayName(name);
      if (!mounted) return;
      widget.onChanged(name);
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _savingName = false;
        _avatarError = 'Gagal simpan nama: $e';
      });
    }
  }

  Widget _avatarView(BuildContext context, ThemeData theme) {
    final avatarUrl = _pendingAvatarUrl;
    final isBusy = _uploadingAvatar || _removingAvatar;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            GestureDetector(
              onTap: isBusy ? null : () => _pickAndUploadAvatar(),
              child: CircleAvatar(
                radius: 44,
                backgroundColor: theme.colorScheme.primary,
                backgroundImage:
                    (avatarUrl != null && avatarUrl.isNotEmpty)
                        ? NetworkImage(avatarUrl)
                        : null,
                child: (avatarUrl != null && avatarUrl.isNotEmpty)
                    ? null
                    : Text(
                        widget.displayName[0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            if (isBusy)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.25),
                  child: const Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.icon(
              onPressed: isBusy ? null : () => _pickAndUploadAvatar(),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.photo_camera_outlined, size: 18),
              label: Text(_pendingAvatarUrl != null ? 'Ganti Foto' : 'Pilih Foto'),
            ),
            if (_pendingAvatarUrl != null) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: isBusy ? null : _removeAvatar,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Hapus'),
              ),
            ],
          ],
        ),
        if (_avatarError != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              _avatarError!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface =
        isDark ? const Color(0xFF191925) : theme.colorScheme.surface;
    final fieldColor = isDark
        ? const Color(0xFF24243A)
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55);
    final outlineColor =
        theme.colorScheme.outline.withValues(alpha: isDark ? 0.18 : 0.55);

    final name = _nameController.text.trim();
    final canSave =
        name.length >= 2 && name.length <= 50 && !_savingName;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
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
                            'Edit Profil',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Ubah nickname atau foto profil kamu.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, size: 20),
                      tooltip: 'Tutup',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.center,
                  child: _avatarView(context, theme),
                ),
                const SizedBox(height: 24),
                Text(
                  'Nickname / Username',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameController,
                  maxLength: 50,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Ketik nickname baru',
                    hintMaxLines: 1,
                    counterText: '',
                    filled: true,
                    fillColor: fieldColor,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: outlineColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: outlineColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: theme.colorScheme.primary,
                        width: 1.6,
                      ),
                    ),
                  ),
                ),
                if (_avatarError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      _avatarError!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Batal'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: canSave ? _saveName : null,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: _savingName
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_rounded, size: 18),
                      label: Text(_savingName ? 'Menyimpan...' : 'Simpan'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

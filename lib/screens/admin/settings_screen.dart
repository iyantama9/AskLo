import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/admin_service.dart';
import '../../services/chat_service.dart';
import '../../widgets/modern_model_picker.dart';
import 'admin_shell.dart';

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  late AdminService _adminService;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  List<PickerModel> _chatModels = [];
  List<PickerModel> _imageModels = [];
  Map<String, dynamic> _settings = {};

  String? _defaultModel;
  String? _fallbackChat;
  String? _fallbackImage;

  @override
  void initState() {
    super.initState();
    _adminService = AdminService(ApiService().token ?? '');
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final catalog = await ApiService().getModelCatalog();
      final models = catalog.models.map(ModelInfo.fromJson).toList();
      final settingsResult = await _adminService.getSettings();
      final settings =
          settingsResult['settings'] as Map<String, dynamic>? ?? {};

      PickerModel toPicker(ModelInfo m) => PickerModel(
            id: m.id,
            label: '${m.displayName} (${m.id})',
            category: m.provider,
            logoUrl: m.logoUrl,
          );

      setState(() {
        _chatModels = models.where((m) => !m.supportsImageGen).map(toPicker).toList();
        _imageModels =
            models.where((m) => m.supportsImageGen).map(toPicker).toList();
        _settings = settings;
        _defaultModel =
            _extractSetting('default_model') ?? catalog.defaultModel;
        _fallbackChat = _extractSetting('fallback_chat');
        _fallbackImage = _extractSetting('fallback_image');
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  String? _extractSetting(String key) {
    final val = _settings[key];
    if (val == null) return null;
    if (val is String) return val.replaceAll('"', '');
    return val.toString();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      if (_defaultModel != null) {
        await _adminService.updateSetting('default_model', _defaultModel);
      }
      if (_fallbackChat != null) {
        await _adminService.updateSetting('fallback_chat', _fallbackChat);
      }
      if (_fallbackImage != null) {
        await _adminService.updateSetting('fallback_image', _fallbackImage);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Settings saved'),
            backgroundColor: Colors.green[700],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AdminShell(
      section: 'settings',
      onSectionSelected: AdminSectionController.select,
      title: 'Settings',
      subtitle: 'Konfigurasi model default dan fallback',
      headerActions: IconButton(
        icon: const Icon(Icons.refresh),
        onPressed: _loadData,
        tooltip: 'Refresh',
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error,
                          size: 48, color: theme.colorScheme.error),
                      const SizedBox(height: 16),
                      Text('Error: $_error'),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _loadData,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : LayoutBuilder(
                  builder: (context, c) {
                    final isNarrow = c.maxWidth < 560;
                    return SingleChildScrollView(
                      padding: isNarrow ? const EdgeInsets.all(16) : const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      const Text(
                        'Model Configuration',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Configure which models are used for different tasks. '
                        'Image models are hidden from the chat selector and '
                        'used automatically for image generation requests.',
                        style: TextStyle(
                            color: Color(0xFF8B8CA0), fontSize: 14),
                      ),
                      const SizedBox(height: 28),

                      // Default Model
                      _modelCard(
                        label: 'Default Model',
                        subtitle: 'Model used for new chats',
                        icon: Icons.smart_toy,
                        value: _defaultModel,
                        items: _chatModels,
                        onChanged: (v) => setState(() => _defaultModel = v),
                      ),
                      const SizedBox(height: 20),

                      // Fallback Chat
                      _modelCard(
                        label: 'Fallback Chat Model',
                        subtitle: 'Used when the selected model fails',
                        icon: Icons.swap_horiz,
                        value: _fallbackChat,
                        items: _chatModels,
                        onChanged: (v) => setState(() => _fallbackChat = v),
                      ),
                      const SizedBox(height: 20),

                      // Fallback Image
                      _modelCard(
                        label: 'Fallback Image Model',
                        subtitle: 'Used for image generation requests',
                        icon: Icons.image,
                        value: _fallbackImage,
                        items: _imageModels,
                        onChanged: (v) =>
                            setState(() => _fallbackImage = v),
                      ),
                      const SizedBox(height: 28),

                      // Info card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1F1B3A),
                          border: Border.all(color: const Color(0xFF4C3D8F)),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline,
                                color: Color(0xFFA78BFA)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Image models are automatically selected when '
                                'the user asks to generate or edit an image. '
                                "They don't appear in the chat model selector.",
                                style: const TextStyle(
                                    color: Color(0xFFC4B5FD),
                                    fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Save button
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _isSaving ? null : _save,
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Icon(Icons.save),
                          label:
                              Text(_isSaving ? 'Saving...' : 'Save Settings'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _modelCard({
    required String label,
    required String subtitle,
    required IconData icon,
    required String? value,
    required List<PickerModel> items,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141520),
        border: Border.all(color: const Color(0xFF262738)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: const Color(0xFFA78BFA)),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(subtitle,
              style:
                  const TextStyle(color: Color(0xFF8B8CA0), fontSize: 13)),
          const SizedBox(height: 12),
          // Modern dropdown (panel drops down from trigger)
          ModelDropdown(
            selectedId: value,
            items: items,
            onPicked: onChanged,
            icon: icon,
            pageSize: 8,
          ),
        ],
      ),
    );
  }
}

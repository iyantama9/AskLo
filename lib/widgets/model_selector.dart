import 'package:flutter/material.dart';
import '../services/chat_service.dart';
import 'modern_model_picker.dart';

/// Compact pill in the chat header that opens the modern model dropdown
/// (a panel that drops down from the trigger — not a bottom-sheet/modal).
class ModelSelector extends StatelessWidget {
  final String currentModel;
  final List<ModelInfo> models;
  final ValueChanged<String> onModelChanged;

  const ModelSelector({
    super.key,
    required this.currentModel,
    required this.models,
    required this.onModelChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Only chat-visible models: hide thinking variants and image-gen models.
    final visible = models
        .where((m) => !m.id.contains('-thinking') && !m.supportsImageGen)
        .toList();

    final pickerItems =
        visible.map((m) => PickerModel(
              id: m.id,
              label: m.displayName,
              category: m.provider,
              logoUrl: m.logoUrl,
            )).toList();

    return ModelDropdown(
      selectedId: currentModel,
      items: pickerItems,
      onPicked: onModelChanged,
      icon: Icons.smart_toy_rounded,
      fillWidth: false,
      panelWidth: 280,
    );
  }
}

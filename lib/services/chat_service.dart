import 'api_service.dart';

class ChatService {
  /// Fetches the model catalog from the backend. The router + admin dashboard
  /// own this list; the client has no local fallback so models can only ever be
  /// added or removed from one place.
  Future<List<ModelInfo>> getModels() async {
    final models = await ApiService().getModels();
    return models.map(ModelInfo.fromJson).toList();
  }
}

class ModelInfo {
  final String id;
  final String ownedBy;
  final String? displayNameOverride;
  final String? logoUrl;
  final bool supportsReasoning;
  final bool supportsVision;
  final bool supportsImageGen;
  final bool supportsBrowse;
  final String costTier;

  const ModelInfo({
    required this.id,
    required this.ownedBy,
    this.displayNameOverride,
    this.logoUrl,
    this.supportsReasoning = false,
    this.supportsVision = false,
    this.supportsImageGen = false,
    this.supportsBrowse = false,
    this.costTier = 'standard',
  });

  factory ModelInfo.fromJson(Map<String, dynamic> json) {
    return ModelInfo(
      id: json['id']?.toString() ?? '',
      ownedBy:
          json['owned_by']?.toString() ??
          json['ownedBy']?.toString() ??
          'Unknown',
      displayNameOverride:
          json['display_name']?.toString() ?? json['displayName']?.toString(),
      logoUrl: json['logo_url']?.toString(),
      supportsReasoning: json['supports_reasoning'] == true,
      supportsVision: json['supports_vision'] == true,
      supportsImageGen: json['supports_image_generation'] == true,
      supportsBrowse: json['supports_browse'] == true,
      costTier: json['cost_tier']?.toString() ?? 'standard',
    );
  }

  String get displayName => displayNameOverride ?? id;

  String get provider => ownedBy;
}

class ChatException implements Exception {
  final String message;
  const ChatException(this.message);

  @override
  String toString() => message;
}

import 'artifact_model.dart';

enum MessageRole { user, assistant, system }

class MessageAttachment {
  final String url;
  final String name;
  final String? contentType;
  final int? sizeBytes;
  final List<int>? previewBytes;

  const MessageAttachment({
    required this.url,
    required this.name,
    this.contentType,
    this.sizeBytes,
    this.previewBytes,
  });

  String get extension {
    final parts = name.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : name.toLowerCase();
  }

  bool get isImage {
    final type = contentType?.toLowerCase() ?? '';
    return type.startsWith('image/') ||
        ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(extension);
  }
}

class ChatMessage {
  final String id;
  final MessageRole role;
  final String content;
  final DateTime timestamp;
  final List<MessageAttachment> attachments;
  final bool isLoading;
  final bool isThinking; // "Thinking..." phase
  final bool isBrowsing; // "Browsing web..." phase
  final bool isImageLoading; // Image generation placeholder phase
  final bool isTyping; // Typewriter reveal phase
  final int revealedChars; // How many chars are revealed
  final bool isError;
  final String? errorCode;
  final String? requestId;
  final ArtifactSummary? artifact;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.attachments = const [],
    this.isLoading = false,
    this.isThinking = false,
    this.isBrowsing = false,
    this.isImageLoading = false,
    this.isTyping = false,
    this.revealedChars = 0,
    this.isError = false,
    this.errorCode,
    this.requestId,
    this.artifact,
  });

  factory ChatMessage.user(
    String content, {
    List<MessageAttachment> attachments = const [],
  }) {
    return ChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      role: MessageRole.user,
      content: content,
      timestamp: DateTime.now(),
      attachments: attachments,
    );
  }

  factory ChatMessage.thinking() {
    return ChatMessage(
      id: 'thinking_${DateTime.now().microsecondsSinceEpoch}',
      role: MessageRole.assistant,
      content: '',
      timestamp: DateTime.now(),
      isLoading: true,
      isThinking: true,
    );
  }

  factory ChatMessage.browsing() {
    return ChatMessage(
      id: 'browsing_${DateTime.now().microsecondsSinceEpoch}',
      role: MessageRole.assistant,
      content: '',
      timestamp: DateTime.now(),
      isLoading: true,
      isBrowsing: true,
    );
  }

  factory ChatMessage.imageLoading() {
    return ChatMessage(
      id: 'image_${DateTime.now().microsecondsSinceEpoch}',
      role: MessageRole.assistant,
      content: '',
      timestamp: DateTime.now(),
      isLoading: true,
      isImageLoading: true,
    );
  }

  factory ChatMessage.error({
    required String id,
    required String content,
    required DateTime timestamp,
    String? errorCode,
    String? requestId,
  }) {
    return ChatMessage(
      id: id,
      role: MessageRole.assistant,
      content: content,
      timestamp: timestamp,
      isError: true,
      errorCode: errorCode,
      requestId: requestId,
    );
  }

  ChatMessage copyWith({
    String? id,
    String? content,
    List<MessageAttachment>? attachments,
    bool? isLoading,
    bool? isThinking,
    bool? isBrowsing,
    bool? isImageLoading,
    bool? isTyping,
    int? revealedChars,
    bool? isError,
    String? errorCode,
    String? requestId,
    ArtifactSummary? artifact,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role,
      content: content ?? this.content,
      timestamp: timestamp,
      attachments: attachments ?? this.attachments,
      isLoading: isLoading ?? this.isLoading,
      isThinking: isThinking ?? this.isThinking,
      isBrowsing: isBrowsing ?? this.isBrowsing,
      isImageLoading: isImageLoading ?? this.isImageLoading,
      isTyping: isTyping ?? this.isTyping,
      revealedChars: revealedChars ?? this.revealedChars,
      isError: isError ?? this.isError,
      errorCode: errorCode ?? this.errorCode,
      requestId: requestId ?? this.requestId,
      artifact: artifact ?? this.artifact,
    );
  }

  /// The text to actually display (for typewriter effect)
  String get displayContent {
    if (isTyping && revealedChars < content.length) {
      return content.substring(0, revealedChars);
    }
    return content;
  }

  Map<String, String> toApiMessage() {
    return {'role': role.name, 'content': content};
  }
}

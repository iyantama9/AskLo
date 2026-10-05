class ArtifactSummary {
  final String id;
  final String title;
  final String kind;
  final int fileCount;
  final int? chatId;
  final int? messageId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ArtifactSummary({
    required this.id,
    required this.title,
    required this.kind,
    required this.fileCount,
    this.chatId,
    this.messageId,
    this.createdAt,
    this.updatedAt,
  });

  factory ArtifactSummary.fromJson(Map<String, dynamic> json) {
    return ArtifactSummary(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Artifact',
      kind: json['kind']?.toString() ?? 'text',
      fileCount:
          (json['file_count'] as num?)?.toInt() ??
          (json['fileCount'] as num?)?.toInt() ??
          0,
      chatId: (json['chat_id'] as num?)?.toInt(),
      messageId: (json['message_id'] as num?)?.toInt(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
    );
  }

  bool get isCode => kind == 'code_file' || kind == 'code_project';
}

class ArtifactFile {
  final String path;
  final String name;
  final String language;
  final String mimeType;
  final String content;
  final int size;

  const ArtifactFile({
    required this.path,
    required this.name,
    required this.language,
    required this.mimeType,
    required this.content,
    required this.size,
  });

  factory ArtifactFile.fromJson(Map<String, dynamic> json) {
    return ArtifactFile(
      path: json['path']?.toString() ?? json['name']?.toString() ?? 'artifact.txt',
      name: json['name']?.toString() ?? json['path']?.toString() ?? 'artifact.txt',
      language: json['language']?.toString() ?? 'text',
      mimeType:
          json['mime_type']?.toString() ??
          json['mimeType']?.toString() ??
          'text/plain',
      content: json['content']?.toString() ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
    );
  }
}

class ChatArtifact extends ArtifactSummary {
  final List<ArtifactFile> files;

  const ChatArtifact({
    required super.id,
    required super.title,
    required super.kind,
    required super.fileCount,
    super.chatId,
    super.messageId,
    super.createdAt,
    super.updatedAt,
    required this.files,
  });

  factory ChatArtifact.fromJson(Map<String, dynamic> json) {
    final summary = ArtifactSummary.fromJson(json);
    final rawFiles = json['files'];
    return ChatArtifact(
      id: summary.id,
      title: summary.title,
      kind: summary.kind,
      fileCount: summary.fileCount,
      chatId: summary.chatId,
      messageId: summary.messageId,
      createdAt: summary.createdAt,
      updatedAt: summary.updatedAt,
      files: rawFiles is List
          ? rawFiles
                .whereType<Map>()
                .map(
                  (file) => ArtifactFile.fromJson(
                    Map<String, dynamic>.from(file),
                  ),
                )
                .toList()
          : const [],
    );
  }

  ArtifactFile? get firstFile => files.isEmpty ? null : files.first;
}

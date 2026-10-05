import 'package:flutter_test/flutter_test.dart';
import 'package:getai_chat/models/artifact_model.dart';

void main() {
  test('parses artifact summary from backend json', () {
    final summary = ArtifactSummary.fromJson({
      'id': 'a1',
      'title': 'Generated Code',
      'kind': 'code_project',
      'file_count': 2,
      'message_id': 10,
    });

    expect(summary.id, 'a1');
    expect(summary.title, 'Generated Code');
    expect(summary.isCode, isTrue);
    expect(summary.fileCount, 2);
    expect(summary.messageId, 10);
  });

  test('parses full artifact files', () {
    final artifact = ChatArtifact.fromJson({
      'id': 'a1',
      'title': 'Generated Code',
      'kind': 'code_file',
      'file_count': 1,
      'files': [
        {
          'path': 'lib/main.dart',
          'name': 'main.dart',
          'language': 'dart',
          'mime_type': 'text/x-dart',
          'content': 'void main() {}',
          'size': 14,
        }
      ],
    });

    expect(artifact.files, hasLength(1));
    expect(artifact.firstFile?.path, 'lib/main.dart');
    expect(artifact.firstFile?.language, 'dart');
  });
}

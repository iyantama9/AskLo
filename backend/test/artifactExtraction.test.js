const {
  buildCodeArtifact,
  buildExplicitFileArtifact,
  looksCodeHeavy,
  parseCodeFences,
  summarizeArtifact,
} = require('../src/utils/artifactExtraction');

describe('artifact extraction', () => {
  test('extracts a long code block into a code artifact', () => {
    const code = Array.from({ length: 82 }, (_, index) => `print(${index});`).join('\n');
    const artifact = buildCodeArtifact(`Berikut kodenya:\n\n\`\`\`dart\n// lib/main.dart\n${code}\n\`\`\``);

    expect(artifact).toMatchObject({
      title: 'main.dart',
      kind: 'code_file',
    });
    expect(artifact.files).toHaveLength(1);
    expect(artifact.files[0]).toMatchObject({
      path: 'lib/main.dart',
      name: 'main.dart',
      language: 'dart',
      mime_type: 'text/x-dart',
    });
  });

  test('extracts multiple named files from markdown headings', () => {
    const response = `### lib/a.dart\n\n\`\`\`dart\nclass A {}\n\`\`\`\n\n### lib/b.dart\n\n\`\`\`dart\nclass B {}\n\`\`\``;
    const artifact = buildCodeArtifact(response);

    expect(looksCodeHeavy(response, parseCodeFences(response))).toBe(true);
    expect(artifact.kind).toBe('code_project');
    expect(artifact.files.map((file) => file.path)).toEqual(['lib/a.dart', 'lib/b.dart']);
  });

  test('explicit non-code artifact only triggers on file/export request', () => {
    expect(buildExplicitFileArtifact('jelaskan data ini', 'jawaban biasa')).toBeNull();

    const artifact = buildExplicitFileArtifact('buatkan csv downloadable', 'name,value\na,1');
    expect(artifact).toMatchObject({ title: 'data.csv', kind: 'csv' });
    expect(artifact.files[0]).toMatchObject({ mime_type: 'text/csv' });
  });

  test('summarizes artifact with file list', () => {
    const summary = summarizeArtifact({
      kind: 'code_project',
      files: [
        { path: 'lib/a.dart' },
        { path: 'lib/b.dart' },
      ],
    });

    expect(summary).toContain('Saya sudah membuat 2 file kode');
    expect(summary).toContain('- lib/a.dart');
    expect(summary).toContain('- lib/b.dart');
  });
});

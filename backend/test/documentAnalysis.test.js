const {
  extractCsv,
  extractText,
  formatDocumentContext,
  selectRelevantChunks,
} = require('../src/utils/documentAnalysis');

describe('document analysis helpers', () => {
  test('selects prompt-relevant chunks while keeping intro', () => {
    const chunks = [
      { text: 'intro overview '.repeat(40), pageNumber: 1 },
      { text: 'unrelated paragraph '.repeat(40), pageNumber: 2 },
      { text: 'revenue churn customer retention detail '.repeat(40), pageNumber: 3 },
    ];

    const selected = selectRelevantChunks(chunks, 'apa revenue dan churn?', 2500);
    expect(selected.chunks.map((chunk) => chunk.pageNumber)).toEqual([1, 3]);
  });

  test('extracts CSV columns and sample rows', () => {
    const result = extractCsv(Buffer.from('name,value\na,1\nb,2'), 'data.csv');

    expect(result.columns).toEqual(['name', 'value']);
    expect(result.rowCount).toBe(2);
    expect(result.sampleRows[0]).toEqual(['a', '1']);
  });

  test('formats structured document context', () => {
    const result = extractText(Buffer.from('First section\n\nRelevant project budget detail'), 'notes.txt');
    const context = formatDocumentContext(result, 'budget');

    expect(context).toContain('--- Dokumen Terlampir ---');
    expect(context).toContain('Nama: notes.txt');
    expect(context).toContain('Konten relevan:');
    expect(context).toContain('Relevant project budget detail');
  });
});

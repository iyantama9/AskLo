const pdfParse = require('pdf-parse');

const DEFAULT_CONTEXT_CAP = 18_000;
const CHUNK_TARGET = 1_800;

const CODE_EXTENSIONS = new Set([
  'dart', 'js', 'ts', 'jsx', 'tsx', 'py', 'java', 'kt', 'swift', 'c', 'cpp', 'h',
  'hpp', 'cs', 'go', 'rs', 'rb', 'php', 'html', 'css', 'scss', 'sass', 'less',
  'json', 'yaml', 'yml', 'xml', 'toml', 'ini', 'env', 'sql', 'sh', 'bash', 'bat',
  'ps1', 'cmd', 'vue', 'svelte', 'astro', 'r', 'lua', 'perl', 'scala', 'clj',
  'ex', 'exs', 'erl', 'dockerfile', 'makefile', 'cmake',
]);

function extensionOf(fileName = '') {
  const parts = String(fileName).split('.');
  return parts.length > 1 ? parts.pop().toLowerCase() : String(fileName).toLowerCase();
}

function normalizeText(text = '') {
  return String(text)
    .replace(/\r\n/g, '\n')
    .replace(/\r/g, '\n')
    .replace(/[\t ]+\n/g, '\n')
    .replace(/\n{4,}/g, '\n\n\n')
    .trim();
}

function promptTerms(prompt = '') {
  return new Set(
    String(prompt)
      .toLowerCase()
      .replace(/[^a-z0-9_\p{L}\s-]/gu, ' ')
      .split(/\s+/)
      .filter((term) => term.length >= 3)
  );
}

function chunkText(text = '', pageNumber = null) {
  const normalized = normalizeText(text);
  if (!normalized) return [];

  const paragraphs = normalized.split(/\n{2,}/);
  const chunks = [];
  let current = '';

  for (const paragraph of paragraphs) {
    const next = current ? `${current}\n\n${paragraph}` : paragraph;
    if (next.length > CHUNK_TARGET && current) {
      chunks.push({ text: current, pageNumber });
      current = paragraph;
    } else {
      current = next;
    }
  }
  if (current) chunks.push({ text: current, pageNumber });
  return chunks;
}

function scoreChunk(chunk, terms) {
  if (!terms.size) return 0;
  const lower = chunk.text.toLowerCase();
  let score = 0;
  for (const term of terms) {
    if (lower.includes(term)) score += 1;
  }
  return score;
}

function selectRelevantChunks(chunks, prompt = '', cap = DEFAULT_CONTEXT_CAP) {
  if (!chunks.length) return { chunks: [], truncated: false };

  const terms = promptTerms(prompt);
  const intro = chunks[0];
  const scored = chunks
    .map((chunk, index) => ({ ...chunk, index, score: scoreChunk(chunk, terms) }))
    .sort((a, b) => b.score - a.score || a.index - b.index);

  const selected = [];
  const seen = new Set();
  let used = 0;

  function add(chunk) {
    if (!chunk || seen.has(chunk.index)) return;
    const text = chunk.text.trim();
    if (!text) return;
    if (used + text.length > cap && selected.length > 0) return;
    selected.push(chunk);
    seen.add(chunk.index);
    used += text.length;
  }

  add({ ...intro, index: 0, score: scoreChunk(intro, terms) });
  for (const chunk of scored) add(chunk);

  selected.sort((a, b) => a.index - b.index);
  return { chunks: selected, truncated: selected.length < chunks.length };
}

function pageSummaries(pages) {
  return pages
    .slice(0, 12)
    .map((page) => {
      const firstLine = normalizeText(page.text).split('\n').find(Boolean) || '[kosong]';
      return `- Halaman ${page.pageNumber}: ${firstLine.slice(0, 180)}`;
    })
    .join('\n');
}

function formatDocumentContext(result, userPrompt = '', cap = DEFAULT_CONTEXT_CAP) {
  const chunks = result.chunks?.length ? result.chunks : chunkText(result.text || '');
  const selected = selectRelevantChunks(chunks, userPrompt, cap);
  const content = selected.chunks
    .map((chunk) => {
      const label = chunk.pageNumber ? `Halaman ${chunk.pageNumber}` : 'Bagian';
      return `### ${label}\n${chunk.text.trim()}`;
    })
    .join('\n\n');

  const metadata = [
    `Nama: ${result.fileName}`,
    `Tipe: ${result.type}`,
    result.pageCount ? `Halaman: ${result.pageCount}` : null,
    result.rowCount != null ? `Perkiraan baris: ${result.rowCount}` : null,
    result.columns?.length ? `Kolom: ${result.columns.join(', ')}` : null,
    result.language ? `Bahasa kode: ${result.language}` : null,
    result.lineCount != null ? `Jumlah baris: ${result.lineCount}` : null,
    `Ekstraksi: ${selected.truncated ? 'konten dipotong ke bagian awal dan paling relevan' : 'konten terbaca penuh dalam batas konteks'}`,
  ].filter(Boolean).join('\n');

  const structure = result.pages?.length
    ? `\n\nRingkasan struktur:\n${pageSummaries(result.pages)}`
    : result.sampleRows?.length
      ? `\n\nSample rows:\n${result.sampleRows.map((row) => `- ${row.join(' | ')}`).join('\n')}`
      : '';

  return `--- Dokumen Terlampir ---\n${metadata}${structure}\n\nKonten relevan:\n${content || '[Tidak ada teks yang berhasil diekstrak]'}\n--- Akhir Dokumen ---`;
}

async function extractPdf(buffer, fileName) {
  const data = await pdfParse(buffer);
  const text = normalizeText(data.text || '');
  const estimatedPages = Math.max(1, data.numpages || 1);
  const splitByFormFeed = text.split('\f').filter((page) => page.trim());
  const pages = splitByFormFeed.length > 1
    ? splitByFormFeed.map((page, index) => ({ pageNumber: index + 1, text: normalizeText(page) }))
    : Array.from({ length: estimatedPages }, (_, index) => {
        const size = Math.ceil(text.length / estimatedPages);
        return { pageNumber: index + 1, text: normalizeText(text.slice(index * size, (index + 1) * size)) };
      });

  return {
    type: 'PDF',
    fileName,
    pageCount: data.numpages || pages.length,
    text,
    pages,
    chunks: pages.flatMap((page) => chunkText(page.text, page.pageNumber)),
  };
}

function extractText(buffer, fileName) {
  const text = normalizeText(buffer.toString('utf8'));
  return {
    type: extensionOf(fileName) === 'md' ? 'Markdown/Text' : 'Text',
    fileName,
    text,
    chunks: chunkText(text),
  };
}

function parseCsvLine(line) {
  const cells = [];
  let current = '';
  let quoted = false;
  for (let i = 0; i < line.length; i++) {
    const char = line[i];
    const next = line[i + 1];
    if (char === '"' && quoted && next === '"') {
      current += '"';
      i++;
    } else if (char === '"') {
      quoted = !quoted;
    } else if (char === ',' && !quoted) {
      cells.push(current);
      current = '';
    } else {
      current += char;
    }
  }
  cells.push(current);
  return cells.map((cell) => cell.trim());
}

function extractCsv(buffer, fileName) {
  const raw = normalizeText(buffer.toString('utf8'));
  const lines = raw.split('\n').filter((line) => line.trim());
  const rows = lines.slice(0, 30).map(parseCsvLine);
  const columns = rows[0] || [];
  const sampleRows = rows.slice(1, 8);
  const text = [
    `Columns: ${columns.join(', ')}`,
    `Estimated rows: ${Math.max(0, lines.length - 1)}`,
    '',
    raw,
  ].join('\n');

  return {
    type: 'CSV',
    fileName,
    columns,
    rowCount: Math.max(0, lines.length - 1),
    sampleRows,
    text,
    chunks: chunkText(text),
  };
}

function extractCode(buffer, fileName) {
  const text = normalizeText(buffer.toString('utf8'));
  const ext = extensionOf(fileName);
  return {
    type: 'Code',
    fileName,
    language: ext,
    lineCount: text ? text.split('\n').length : 0,
    text,
    chunks: chunkText(text),
  };
}

function extractUnsupported(fileName) {
  return {
    type: 'Unsupported document',
    fileName,
    text: `[File ${fileName} disimpan sebagai lampiran, tetapi format ini belum bisa diekstrak langsung. Jika perlu analisis detail, minta pengguna mengunggah versi PDF/TXT/CSV atau menyalin isi dokumen.]`,
    chunks: [],
  };
}

async function extractAttachment(buffer, fileName) {
  const ext = extensionOf(fileName);
  if (ext === 'pdf') return extractPdf(buffer, fileName);
  if (ext === 'csv') return extractCsv(buffer, fileName);
  if (['txt', 'md', 'markdown', 'log'].includes(ext)) return extractText(buffer, fileName);
  if (CODE_EXTENSIONS.has(ext)) return extractCode(buffer, fileName);
  return extractUnsupported(fileName);
}

module.exports = {
  extractAttachment,
  extractPdf,
  extractText,
  extractCsv,
  extractCode,
  formatDocumentContext,
  selectRelevantChunks,
  chunkText,
};

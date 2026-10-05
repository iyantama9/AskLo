const path = require('path');

const MAX_FILE_CONTENT = 240_000;
const MAX_ARTIFACT_BYTES = 900_000;

const LANGUAGE_EXTENSIONS = {
  dart: 'dart',
  javascript: 'js',
  js: 'js',
  typescript: 'ts',
  ts: 'ts',
  jsx: 'jsx',
  tsx: 'tsx',
  python: 'py',
  py: 'py',
  java: 'java',
  kotlin: 'kt',
  kt: 'kt',
  swift: 'swift',
  c: 'c',
  cpp: 'cpp',
  csharp: 'cs',
  cs: 'cs',
  go: 'go',
  rust: 'rs',
  rs: 'rs',
  ruby: 'rb',
  rb: 'rb',
  php: 'php',
  html: 'html',
  css: 'css',
  scss: 'scss',
  json: 'json',
  yaml: 'yml',
  yml: 'yml',
  xml: 'xml',
  toml: 'toml',
  sql: 'sql',
  shell: 'sh',
  bash: 'sh',
  sh: 'sh',
  markdown: 'md',
  md: 'md',
  text: 'txt',
  txt: 'txt',
  csv: 'csv',
};

const MIME_TYPES = {
  dart: 'text/x-dart',
  js: 'text/javascript',
  jsx: 'text/javascript',
  ts: 'text/typescript',
  tsx: 'text/typescript',
  py: 'text/x-python',
  java: 'text/x-java-source',
  kt: 'text/x-kotlin',
  swift: 'text/x-swift',
  c: 'text/x-c',
  cpp: 'text/x-c++',
  h: 'text/x-c',
  hpp: 'text/x-c++',
  cs: 'text/x-csharp',
  go: 'text/x-go',
  rs: 'text/x-rustsrc',
  rb: 'text/x-ruby',
  php: 'application/x-php',
  html: 'text/html',
  css: 'text/css',
  scss: 'text/x-scss',
  json: 'application/json',
  yml: 'application/x-yaml',
  yaml: 'application/x-yaml',
  xml: 'application/xml',
  toml: 'application/toml',
  sql: 'application/sql',
  sh: 'application/x-sh',
  md: 'text/markdown',
  txt: 'text/plain',
  csv: 'text/csv',
};

function normalizeArtifactPath(value) {
  const clean = String(value || '')
    .trim()
    .replace(/^file:\/\//i, '')
    .replace(/^['"`]+|['"`]+$/g, '')
    .replace(/^[./\\]+/, '')
    .replace(/\\/g, '/');

  if (!clean || clean.includes('..') || path.isAbsolute(clean)) return '';
  if (!/[A-Za-z0-9_.-]/.test(clean)) return '';
  return clean.substring(0, 180);
}

function extensionForLanguage(language = '') {
  return LANGUAGE_EXTENSIONS[String(language).toLowerCase()] || 'txt';
}

function languageForPath(filePath = '', fallback = '') {
  const ext = filePath.split('.').pop()?.toLowerCase() || extensionForLanguage(fallback);
  const byExt = Object.entries(LANGUAGE_EXTENSIONS).find(([, value]) => value === ext);
  return byExt?.[0] || fallback || ext || 'text';
}

function mimeForPath(filePath = '', language = '') {
  const ext = filePath.split('.').pop()?.toLowerCase() || extensionForLanguage(language);
  return MIME_TYPES[ext] || 'text/plain';
}

function lineCount(text = '') {
  if (!text) return 0;
  return text.split(/\r?\n/).length;
}

function extractPathFromFenceInfo(info = '') {
  const text = info.trim();
  if (!text) return '';

  const fileMatch = text.match(/(?:file|filename|path)\s*[:=]\s*([^\s]+)$/i);
  if (fileMatch) return normalizeArtifactPath(fileMatch[1]);

  const parts = text.split(/\s+/);
  return parts.map(normalizeArtifactPath).find((part) => part.includes('/') || part.includes('.')) || '';
}

function extractPathFromNearbyText(prefix = '') {
  const lines = prefix.split(/\r?\n/).slice(-5).reverse();
  for (const line of lines) {
    const trimmed = line.trim();
    const patterns = [
      /^#{1,6}\s*(?:file\s*:\s*)?(.+\.[A-Za-z0-9]+)\s*$/i,
      /^\*\*(?:file|path)\s*:\s*([^*]+)\*\*$/i,
      /^`([^`]+\.[A-Za-z0-9]+)`\s*$/i,
    ];
    for (const pattern of patterns) {
      const match = trimmed.match(pattern);
      if (match) {
        const candidate = normalizeArtifactPath(match[1]);
        if (candidate) return candidate;
      }
    }
  }
  return '';
}

function extractPathFromCodeComment(code = '') {
  const firstLines = code.split(/\r?\n/).slice(0, 3);
  for (const line of firstLines) {
    const match = line.match(/^\s*(?:\/\/|#|--|<!--)\s*([^\s<>]+\.[A-Za-z0-9]+)\s*(?:-->)?\s*$/);
    if (match) {
      const candidate = normalizeArtifactPath(match[1]);
      if (candidate) return candidate;
    }
  }
  return '';
}

function fallbackFileName(language, index) {
  const ext = extensionForLanguage(language);
  const base = {
    dart: 'main',
    javascript: 'script',
    js: 'script',
    typescript: 'index',
    ts: 'index',
    html: 'index',
    css: 'style',
    json: 'data',
    markdown: 'document',
    md: 'document',
    csv: 'data',
  }[String(language || '').toLowerCase()] || 'file';
  return index === 0 ? `${base}.${ext}` : `${base}-${index + 1}.${ext}`;
}

function dedupePath(filePath, used) {
  let candidate = filePath;
  let count = 2;
  while (used.has(candidate)) {
    const slash = candidate.lastIndexOf('/');
    const dir = slash === -1 ? '' : `${candidate.slice(0, slash + 1)}`;
    const name = slash === -1 ? candidate : candidate.slice(slash + 1);
    const dot = name.lastIndexOf('.');
    candidate = dot === -1
      ? `${dir}${name}-${count}`
      : `${dir}${name.slice(0, dot)}-${count}${name.slice(dot)}`;
    count++;
  }
  used.add(candidate);
  return candidate;
}

function parseCodeFences(markdown = '') {
  const fences = [];
  const regex = /```([^\n`]*)\n([\s\S]*?)```/g;
  let match;
  while ((match = regex.exec(markdown)) !== null) {
    const info = (match[1] || '').trim();
    const language = (info.split(/\s+/)[0] || 'text').toLowerCase();
    const content = (match[2] || '').replace(/^\n+|\n+$/g, '');
    const before = markdown.slice(Math.max(0, match.index - 500), match.index);
    fences.push({ info, language, content, before, lines: lineCount(content) });
  }
  return fences;
}

function hasCommonFileHeader(text = '') {
  return /(?:^|\n)\s*(?:\/\/|#|<!--)\s*(?:lib|src|backend|frontend|app|test|web)\/[\w./-]+\.[A-Za-z0-9]+|(?:package\.json|pubspec\.yaml)|(?:^|\n)#{1,6}\s*(?:file\s*:\s*)?[\w./-]+\.[A-Za-z0-9]+/i.test(text);
}

function looksCodeHeavy(markdown = '', fences = parseCodeFences(markdown)) {
  // Filter out plain text fences - they're not code artifacts
  const codeFences = fences.filter(fence => fence.language !== 'text' && fence.language !== 'txt');

  if (codeFences.length === 0) return false;

  // Single large code file
  if (codeFences.some((fence) => fence.lines >= 80)) return true;

  // Multiple substantial code files (require at least 2 actual code fences)
  const totalLines = codeFences.reduce((sum, fence) => sum + fence.lines, 0);
  if (totalLines >= 120 && codeFences.length >= 2) return true;

  // Explicit file names indicate this is meant to be downloadable
  const withNames = codeFences.filter((fence) =>
    extractPathFromFenceInfo(fence.info) ||
    extractPathFromNearbyText(fence.before) ||
    extractPathFromCodeComment(fence.content)
  );
  if (withNames.length >= 2) return true;

  return hasCommonFileHeader(markdown);
}

function buildCodeArtifact(markdown = '') {
  const fences = parseCodeFences(markdown);
  if (!looksCodeHeavy(markdown, fences)) return null;

  const used = new Set();
  const files = [];
  let totalBytes = 0;

  fences.forEach((fence, index) => {
    if (!fence.content.trim()) return;
    const rawPath = extractPathFromCodeComment(fence.content) ||
      extractPathFromFenceInfo(fence.info) ||
      extractPathFromNearbyText(fence.before) ||
      fallbackFileName(fence.language, index);
    const filePath = dedupePath(normalizeArtifactPath(rawPath) || fallbackFileName(fence.language, index), used);
    const content = fence.content.slice(0, MAX_FILE_CONTENT);
    const size = Buffer.byteLength(content, 'utf8');
    totalBytes += size;
    if (totalBytes > MAX_ARTIFACT_BYTES) return;

    files.push({
      path: filePath,
      name: filePath.split('/').pop() || filePath,
      language: languageForPath(filePath, fence.language),
      mime_type: mimeForPath(filePath, fence.language),
      content,
      size,
    });
  });

  if (files.length === 0) return null;
  return {
    title: files.length === 1 ? files[0].name : 'Generated Code Files',
    kind: files.length === 1 ? 'code_file' : 'code_project',
    files,
  };
}

function wantsExplicitFileArtifact(prompt = '', tools = []) {
  // Check if document generation tools are active
  if (tools.includes('generate_pdf') || tools.includes('generate_docx') ||
      tools.includes('generate_txt') || tools.includes('generate_csv')) {
    return true;
  }

  // Fallback to keyword detection
  return /\b(?:buat\s+file|buatkan\s+file|jadikan\s+file|simpan\s+sebagai|export|downloadable|convert\s+(?:to|ke)|buat(?:kan)?\s+(?:pdf|word|docx|csv|txt|markdown|md|json)|jadikan\s+(?:pdf|word|docx|csv|txt|markdown|md|json)|download\s+(?:file|pdf|docx|word|csv|txt|markdown|md|json)|ubah\s+(?:jadi|ke)\s+(?:pdf|docx|word|csv))\b/i.test(prompt);
}

function extensionFromPrompt(prompt = '', content = '') {
  const lower = prompt.toLowerCase();
  if (/\b(?:csv|spreadsheet|tabel)\b/.test(lower)) return 'csv';
  if (/\b(?:pdf)\b/.test(lower)) return 'pdf';
  if (/\b(?:docx|word|doc)\b/.test(lower)) return 'docx';
  if (/\b(?:json)\b/.test(lower)) return 'json';
  if (/\b(?:markdown|md)\b/.test(lower)) return 'md';
  if (/\b(?:txt|teks|text)\b/.test(lower)) return 'txt';
  if (/^\s*[{[]/.test(content)) return 'json';

  // Auto-detect CSV from content
  const { looksLikeCSV } = require('./documentGeneration');
  if (looksLikeCSV(content)) return 'csv';

  return 'txt';
}

function stripMarkdownFences(markdown = '') {
  const fences = parseCodeFences(markdown);
  if (fences.length === 1 && fences[0].content.trim().length > 0) {
    return fences[0].content.trim();
  }
  return markdown.trim();
}

function buildExplicitFileArtifact(prompt = '', response = '', tools = []) {
  if (!wantsExplicitFileArtifact(prompt, tools)) return null;
  const ext = extensionFromPrompt(prompt, response);

  // Determine file name based on extension
  const fileNames = {
    pdf: 'document.pdf',
    docx: 'document.docx',
    csv: 'data.csv',
    md: 'document.md',
    json: 'data.json',
    txt: 'document.txt',
  };
  const fileName = fileNames[ext] || `artifact.${ext}`;

  const content = stripMarkdownFences(response).slice(0, MAX_FILE_CONTENT);

  // Determine kind and mime type
  const kinds = {
    pdf: 'document',
    docx: 'document',
    csv: 'csv',
    md: 'text',
    txt: 'text',
    json: 'document',
  };
  const kind = kinds[ext] || 'document';

  const mimeTypes = {
    pdf: 'application/pdf',
    docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    csv: 'text/csv',
    md: 'text/markdown',
    json: 'application/json',
    txt: 'text/plain',
  };
  const mimeType = mimeTypes[ext] || 'text/plain';

  return {
    title: fileName,
    kind,
    needsGeneration: ext === 'pdf' || ext === 'docx', // Flag for async generation
    targetFormat: ext,
    files: [{
      path: fileName,
      name: fileName,
      language: ext === 'md' ? 'markdown' : ext,
      mime_type: mimeType,
      content,
      size: Buffer.byteLength(content, 'utf8'),
    }],
  };
}

function summarizeArtifact(artifact) {
  const fileList = artifact.files.slice(0, 12).map((file) => `- ${file.path}`).join('\n');
  const more = artifact.files.length > 12 ? `\n- ...dan ${artifact.files.length - 12} file lainnya` : '';
  const noun = artifact.kind.startsWith('code') ? 'file kode' : 'file';
  return `Saya sudah membuat ${artifact.files.length} ${noun}. Buka artifact untuk melihat, copy, atau download.\n\n${fileList}${more}`.trim();
}

function artifactSummary(row) {
  const files = Array.isArray(row.files) ? row.files : [];
  return {
    id: row.id,
    title: row.title,
    kind: row.kind,
    message_id: row.message_id,
    chat_id: row.chat_id,
    file_count: files.length,
    created_at: row.created_at,
    updated_at: row.updated_at,
  };
}

function buildArtifactForResponse({ userPrompt = '', assistantContent = '', tools = [] }) {
  return buildCodeArtifact(assistantContent) || buildExplicitFileArtifact(userPrompt, assistantContent, tools);
}

module.exports = {
  buildArtifactForResponse,
  buildCodeArtifact,
  buildExplicitFileArtifact,
  looksCodeHeavy,
  parseCodeFences,
  summarizeArtifact,
  artifactSummary,
  normalizeArtifactPath,
};

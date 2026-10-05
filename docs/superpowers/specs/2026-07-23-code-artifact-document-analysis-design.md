# Code Artifact View and Document Analysis Design

## Goal

Make AskCore handle long/code-heavy AI output more cleanly by moving generated code into a persisted VS Code-style artifact tab instead of dumping huge code blocks into chat, while improving document/file analysis for uploaded PDF, CSV, Word, text, and code files.

## Scope

This design covers two related improvements:

1. **Code artifacts by default** — when assistant output contains long generated code or multiple code files, AskCore saves those files as an artifact and opens a read-only editor view automatically.
2. **File/document artifacts by explicit request** — non-code output such as TXT, Markdown, CSV, PDF, and Word-style documents becomes downloadable/previewable files only when the user clearly asks for a file/export/document.

This design does **not** include running generated code, applying generated files to the real project, collaborative editing, or full binary office-document generation in the first version unless already supported by available backend libraries.

## Current Context

AskCore currently renders assistant output directly inside chat using `MessageBubble` markdown/code rendering. Large code responses can make the chat hard to read and may be truncated by output limits. File uploads already support image/PDF/text/code upload, and backend message handling extracts PDF/text content into the user message before calling the AI. Attachments now appear in sent user bubbles and support input-side preview cards.

The existing app is Flutter frontend + Node/Express backend + PostgreSQL + R2 for file storage. The right fit is a persisted backend artifact model with a Flutter editor-style panel layered into the chat UI.

## User Decisions

- Auto-artifact behavior is for **code only** for now.
- Non-code outputs become file artifacts only when the user explicitly asks.
- Non-code file artifacts must support preview and download.
- Generated artifacts are saved for manual copy/download; they do not need to run.
- UI should look polished, closeable, reopenable, and visually similar to VS Code tabs/file explorer.

## Backend Design

### Database

Add a new `artifacts` table:

```sql
CREATE TABLE IF NOT EXISTS artifacts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id INT REFERENCES users(id) ON DELETE CASCADE,
  chat_id INT REFERENCES chats(id) ON DELETE CASCADE,
  message_id INT REFERENCES messages(id) ON DELETE SET NULL,
  title VARCHAR(255) NOT NULL,
  kind VARCHAR(40) NOT NULL,
  files JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_artifacts_chat_id ON artifacts(chat_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_artifacts_owner_id ON artifacts(owner_id, created_at DESC);
```

`kind` values:

- `code_project` — multiple generated code files/folders.
- `code_file` — one generated code file.
- `document` — explicit user-requested document export.
- `csv` — explicit CSV export.
- `text` — explicit TXT/Markdown export.

`files` stores small-to-medium generated file content in JSONB:

```json
[
  {
    "path": "lib/screens/home_screen.dart",
    "name": "home_screen.dart",
    "language": "dart",
    "mime_type": "text/x-dart",
    "content": "...",
    "size": 12345
  }
]
```

For v1, store artifact text content in Postgres JSONB. If generated files exceed a safe size threshold, store them in R2 later and keep R2 keys in `files`.

### Routes

Add `backend/src/routes/artifacts.js`:

- `GET /api/chats/:chatId/artifacts` — list artifacts for a chat.
- `GET /api/artifacts/:artifactId` — get full artifact with files.
- `GET /api/artifacts/:artifactId/files/*` — download a single artifact file.
- `GET /api/artifacts/:artifactId/download.zip` — download all files as a ZIP when multiple files exist.
- Optional v1.1: `DELETE /api/artifacts/:artifactId` — remove artifact if user wants cleanup.

All routes require `authMiddleware` and verify artifact ownership.

### Artifact Extraction

After the backend receives the assistant response, before returning it to the client:

1. Detect generated code blocks.
2. If response is code-heavy, extract code into files.
3. Save artifact linked to the assistant message.
4. Replace or shorten chat content with a compact summary and artifact marker metadata.

Code-heavy detection rules:

- A fenced code block has 80+ lines, or
- total fenced code across response is 120+ lines, or
- response contains 2+ fenced code blocks with filename hints, or
- response contains common file headers such as `// lib/...`, `# backend/...`, `package.json`, `pubspec.yaml`, or markdown headings like `### file: path/to/file.ts`.

Filename extraction order:

1. Explicit file marker: `// path/to/file.dart`, `# path/to/file.py`, `<!-- path/to/file.html -->`.
2. Markdown heading near block: `### lib/main.dart`, `**File: backend/src/index.js**`.
3. Language fallback: `main.dart`, `script.js`, `style.css`, `index.html`, `file.txt`.
4. Deduplicate fallback names with numeric suffixes.

When artifact is created, saved assistant chat content becomes short:

```md
Saya sudah membuat 3 file kode. Buka artifact untuk melihat, copy, atau download.

- lib/screens/home_screen.dart
- lib/widgets/result_card.dart
- pubspec.yaml
```

The API response includes artifact metadata:

```json
{
  "message": { ... },
  "artifact": {
    "id": "...",
    "title": "Generated Flutter UI",
    "kind": "code_project",
    "file_count": 3
  }
}
```

### Explicit Non-Code File Artifact Detection

Non-code artifacts are created only if the user asks explicitly. Trigger phrases include Indonesian and English patterns:

- `buat file`, `jadikan file`, `simpan sebagai`, `export`, `downloadable`
- `buat pdf`, `jadikan pdf`, `buat word`, `buat docx`, `buat csv`, `buat txt`, `buat markdown`

For v1, support reliable text-based exports:

- `.txt` — plain text.
- `.md` — markdown.
- `.csv` — generated CSV content.
- `.json` — generated JSON content.

PDF/DOCX can be represented as previewable markdown/text artifact if binary generation is not yet available. The UI should show a clear label if the actual file is Markdown/Text rather than native PDF/DOCX. If adding PDF/DOCX libraries is cheap and stable, v1 can include them; otherwise v1.1.

## Frontend Design

### Data Models

Add model classes:

- `ArtifactSummary`
- `ArtifactFile`
- `ChatArtifact`

Fields should mirror backend JSON: id, title, kind, files, file count, message id, created time.

### API Service

Add methods in `ApiService`:

- `getChatArtifacts(chatId)`
- `getArtifact(artifactId)`
- `downloadArtifactFileUrl(artifactId, path)` or open URL directly
- `downloadArtifactZipUrl(artifactId)`

When `sendMessage`/`sendMessageStream` receives artifact metadata, the chat screen stores it and opens it automatically.

### Chat Integration

`ChatScreen` owns artifact state:

- `List<ArtifactSummary> _artifacts`
- `ChatArtifact? _activeArtifact`
- `bool _artifactPanelOpen`
- selected file path inside the artifact

When a message response includes an artifact:

1. Add it to `_artifacts`.
2. Fetch full artifact details if needed.
3. Open artifact panel automatically.
4. Show an inline compact card in the assistant bubble: title, file count, button “Buka Code View”.

When loading an existing chat, fetch artifacts for that chat so old artifacts can be reopened.

### Artifact UI

Desktop layout:

- Chat remains in the existing center area.
- Right side opens a resizable or fixed-width artifact panel, around 520–680 px.
- Panel style resembles VS Code:
  - top title bar with close button
  - file tabs row
  - file tree sidebar
  - read-only code editor area
  - action buttons: Copy, Download file, Download ZIP

Mobile layout:

- Artifact opens as fullscreen route/modal.
- Top app bar with close button.
- File selector as dropdown or horizontal tabs.
- Read-only code area below.

Code display:

- Use existing `flutter_highlight` if possible for syntax highlighting.
- Use monospace font and dark editor theme.
- Preserve indentation and horizontal scroll.
- Copy current file content to clipboard.

Non-code preview:

- Text/Markdown: preview readable text.
- CSV: show raw CSV v1, table preview v1.1 if time allows.
- PDF/DOCX generated artifacts: preview extracted/markdown text, download actual available file format.

## Document Analysis Improvements

### Current Issue

Document extraction currently feeds a capped substring of PDF/text directly into the latest user message. This loses structure and can miss relevant content when documents are long.

### Improved Extraction

Add a document extraction helper in backend, e.g. `backend/src/utils/documentAnalysis.js`, with functions:

- `extractPdf(buffer, fileName)` — returns page count, text by page, overall text.
- `extractText(buffer, fileName)` — returns normalized UTF-8 text.
- `extractCsv(buffer, fileName)` — returns columns, row count estimate, sample rows, raw capped content.
- `extractCode(buffer, fileName)` — returns language, line count, capped content.
- `extractDocx(buffer, fileName)` — if library available; otherwise returns unsupported-but-stored result.

The extracted context inserted into the AI prompt should be structured:

```md
--- Dokumen Terlampir ---
Nama: report.pdf
Tipe: PDF
Halaman: 12
Ekstraksi: 12 halaman terbaca, konten dipotong ke bagian paling relevan

Ringkasan struktur:
- Halaman 1: ...
- Halaman 2: ...

Konten relevan:
...
--- Akhir Dokumen ---
```

### Relevance Selection

For long documents, avoid only taking the first 15,000 characters. Use simple keyword relevance based on the user prompt:

1. Always keep metadata and first page/first section.
2. Split text into chunks by page or paragraph.
3. Score chunks by overlap with user prompt terms.
4. Include top relevant chunks plus intro chunk until cap is reached.
5. Clearly tell the AI if content was truncated.

### Prompt Improvement

Update system/document instructions:

- Analyze only from attached document when user asks about it.
- If extraction is partial, say that conclusion is based on extracted content.
- For CSV, identify columns and ask clarifying questions if user requests statistical conclusions that need full data but only sample is available.
- For code files, preserve exact symbols and filenames in answers.

## Error Handling

- If artifact extraction fails, still return normal assistant message.
- If artifact save fails, log warning and include full/trimmed content in chat as fallback.
- If artifact download fails, show polished error snackbar.
- If document extraction fails, include a structured note in prompt and visible assistant response should explain the file could not be read.
- If PDF/DOCX native generation is unavailable, UI labels the artifact as preview/download text-based export instead of pretending it is a real binary document.

## Testing

Backend:

- Unit test code block extraction from one long block.
- Unit test multiple file extraction with file paths.
- Unit test non-code artifact detection only triggers on explicit file/export phrases.
- Unit test artifact ownership route checks.
- Unit test PDF/text/CSV extraction helper with sample inputs where possible.
- `node --check` for all modified backend files.

Frontend:

- Widget test artifact panel opens with file tree and tabs.
- Widget test copy button exists and displays selected file.
- Widget test assistant artifact card can reopen a closed artifact.
- Widget test mobile/fullscreen artifact layout if feasible.
- `flutter analyze` and `flutter test`.

Manual checks:

- Ask for a long Flutter widget; verify chat has summary and artifact opens automatically.
- Ask for multiple files; verify file tree and tabs.
- Close artifact and reopen from message card.
- Download one file and all files as ZIP.
- Ask for normal long explanation; verify it stays in chat.
- Ask explicitly “buatkan CSV”; verify preview/download artifact.
- Upload PDF/CSV and ask questions; verify answers cite extracted document structure.

## Rollout Plan

1. Add backend artifact schema and routes.
2. Add code artifact extraction and save after AI response.
3. Add frontend artifact models/API methods.
4. Add desktop/mobile artifact viewer UI.
5. Wire auto-open/reopen behavior in `ChatScreen` and `MessageBubble`.
6. Add explicit non-code file artifact support.
7. Refactor document extraction into a utility and improve relevance selection.
8. Run verification and manual checks.

## Open Implementation Notes

- Keep generated artifacts read-only in v1.
- Do not execute code.
- Do not hide assistant reasoning or final explanation; only replace excessive code bodies with artifact summary.
- Store small text artifacts in Postgres first; add R2 backing only if size demands it.
- Keep UI polished but lightweight; reuse existing syntax highlighting dependencies before adding new editor packages.

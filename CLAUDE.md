# Project Rules

## Code Review Graph (CRG) — wajib, bukan opsional

CRG sudah ter-build di repo ini. **Setiap task yang menyentuh kode
MULAI dari CRG** — jangan review bareh file, cari impact dengan grep
saja, atau commit tanpa cek blast radius.

### Ground rules
1. **Call pertama untuk task apa pun**: `get_minimal_context_tool(task="<task>")`.
   ~100 token, ngasih summary + risk + `next_tool_suggestions`. Ikuti
   saran `next_tool_suggestions` — itu routing yang udah di-tune.
2. **`status: not_ready` / `head_matches_build: false`** → panggil
   `build_or_update_graph_tool` (incremental, tanpa argumen) terus
   lanjutin task. Jangan jalanin review di graph stale.
3. **Budget**: ~5 tool call CRG per task. Kalau keliatan perlu
   eksplorasi lebih luas, pakai MCP prompt (lihat bawah) atau
   sub-agent `general-purpose` — bukan numpuk tool call manual.
4. **Selalu `detail_level: "minimal"`** kecuali butuh detail; naikin
   ke `"standard"` cuma kalau minimal nggak cukup.
5. **Targeted query > broad listing**: panggil `query_graph_tool`
   dengan pattern spesifik, jangan `list_*` dulu.

### Per skenario

**Menulis / nge-modify kode**
- `detect_changes_tool` (kalau udah ada diff) → `get_impact_radius_tool`
  buat simbol yang bakal di-touch → baru nulis kode.
- `semantic_search_nodes_tool` kalau belum tau di mana fitur itu
  di-handle.
- Setelah nulis: `detect_changes_tool(base: "HEAD")` lagi — confirm
  blast radius sesuai ekspektasi, cek `test_gaps`.

**Code review / PR review**
- MCP prompt: `review_changes` (diff-based) atau `review-delta`.
- `get_affected_flows_tool` — apaan user-facing flow yang kena.
- `query_graph_tool(pattern: "tests_for", target: "<symbol>")` —
  verifikasi test nyangkep perubahan itu.
- `code-reviewer` sub-agent buat dive manual kalau perlu.

**Debug issue / bug**
- MCP prompt: `debug_issue`.
- `get_affected_flows_tool` + `query_graph_tool(pattern: "callers_of")`
  buat narrow di mana bug-nya.
- `traverse_graph_tool(query="<symptom keyword>", mode="dfs")` kalau
  masih nyasar.

**Pre-merge / commit gate**
- MCP prompt: `pre_merge_check`.
- `detect_changes_tool(base: "HEAD~1")` → `test_gaps` = blocker,
  `affected_flows` = review focus.
- Jangan merge kalau fungsi berisiko tinggi belum punya test.

**Onboarding / arsitektur / navigasi**
- MCP prompt: `onboard_developer` atau `architecture_map`.
- `get_architecture_overview_tool`, `list_communities_tool`,
  `list_flows_tool` — map big picture dulu.

**Refactor aman**
- MCP prompt: `refactor-safely` / CLI `code-review-graph refactor`.
- `refactor_tool(mode: "rename")` → `apply_refactor_tool` (dry-run
  dulu kalau mau liat diff).
- `refactor_tool(mode: "dead_code")` sebelum nambah fitur baru —
  hapus yang udah nggak kepake.

**Kualitas & struktur**
- `find_large_functions_tool` — fungsi terlalu panjang.
- `get_knowledge_gaps_tool` — hotspot yang belum punya test.
- `get_hub_nodes_tool` / `get_bridge_nodes_tool` — chokepoint
  arsitektural, hati-hati kalau nge-touch.
- `get_surprising_connections_tool` — coupling aneh antar-community.

### MCP prompt bawaan CRG (pakai, jangan ngerjain manual)
| Prompt | Kapan |
|--------|-------|
| `review_changes` | review diff / PR |
| `review-delta` | review perubahan sejak build terakhir |
| `review-pr` | review PR spesifik |
| `debug_issue` | tracing bug / issue |
| `pre_merge_check` | gate sebelum commit/merge |
| `onboard_developer` | ngerti codebase dari nol |
| `architecture_map` | peta arsitektur & coupling |
| `refactor-safely` | plan + execute refactor |

### CLI (jalankan via shell, bukan MCP)
```
code-review-graph status       # graph sehat?
code-review-graph detect-changes   # tanpa MCP
code-review-graph dead-code    # cari dead code
code-review-graph wiki         # generate wiki per community
code-review-graph watch       # auto-update saat nulis
```

### Known test gaps (build 2026-10-01, commit dc48c3f)
| Simbol | File | Risk |
|--------|------|------|
| `fetchAI` | backend/src/routes/messages.js:132 | 0.71 |
| `refreshModelsCache` | backend/src/utils/modelCatalog.js:75 | 0.68 |
| `selectEffectiveModel` | backend/src/routes/messages.js:28 | 0.66 |
| `checkQuota` | backend/src/utils/usage.js:35 | 0.615 |

Gap ini merge blocker — nggak boleh commit yang nge-touch simbol
di atas tanpa nambahin test-nya.

### Rebuild
Graph di-build per-commit. Kalau [SessionStart hook] nunjukin
"Built at commit: X" tapi `git rev-parse HEAD` ≠ X, auto-panggil
`build_or_update_graph_tool`.

## Sub-Agents
Di `.claude/agents/`. Semua `model: inherit` (ngikutin model
session). Pakai berdasarkan domain, bukan karena "bisa dipake".

| Agent | Domain |
|-------|--------|
| `backend-developer` | Express routes, JWT, S3, Postgres |
| `flutter-expert` | Flutter widget, state mgmt, multiplatform |
| `frontend-developer` | UI / component / layout |
| `code-reviewer` | security + quality review (padukan CRG di atas) |
| `test-automator` | Jest + flutter_test |
| `docker-expert` | Dockerfile, compose, deploy |
| `git-workflow-manager` | commit/branch/PR convention |

**Paduan dengan CRG**: sub-agent itu eksekutor. CRG itu context.
Sebelum spawn sub-agent buat task besar, jalankan
`get_minimal_context_tool(task=...)` dulu, terus tembusin hasil
itu ke prompt-nya. Setelah sub-agent selesai, verifikasi dengan
`detect_changes_tool` — jangan percaya report doang.

# Development workflow

This document defines how the named subagents collaborate to build the otameishi app. The authoritative product spec is [`requirements.md`](../requirements.md); this doc is process, not product.

## Agents

| Agent | Role | When invoked |
|-------|------|--------------|
| `planner` | Break down features into phased, file-specific plans | Before any non-trivial implementation work |
| `designer` | UX flow, screen specs, design tokens, copy | Before building any new screen or reworking a flow |
| `backend` | Services, OCR, camera, image pipeline, models | Logic, device capability, data transformation |
| `db` | SQLite schema, migrations, repositories, indexes | Any persistence change |
| `frontend` | Widgets, screens, routing, theming | Any UI work |
| `code-reviewer` | Quality / security / maintainability review | Immediately after code is written |
| `claude-code-guide` | Flutter / Dart / package documentation lookup | When verifying SDK behavior or package APIs |

Each agent's full charter lives in `~/.claude/agents/<name>.md`.

## Standard feature flow

```
requirements.md
       │
       ▼
   planner ── produces phased plan with file paths
       │
       ├──► designer ── produces docs/design/screens/*.md (if UI touched)
       │
       ├──► db ── migration + repository (if persistence touched)
       │
       ├──► backend ── services + models against db interfaces
       │
       └──► frontend ── widgets consuming backend via providers
                │
                ▼
           code-reviewer ── pre-commit review
```

### Rules of engagement

1. **Planner first** for features spanning more than one file.
2. **Designer before frontend** for any new screen. Frontend implements the spec; it does not invent flow.
3. **DB interface before backend implementation.** Backend declares the repository interface it needs; db implements it. This keeps services testable with mocks.
4. **Tests before code (TDD)**. Each agent writes failing tests first under `test/<area>/...`.
5. **Code-reviewer is mandatory** after any write. Run it before considering work done.
6. **claude-code-guide for SDK questions** — never guess at package API surface; verify against current docs.

## Suggested phasing for MVP

Mapped to requirements §7 (MVP完成条件). Each phase is independently shippable.

| Phase | Deliverable | Lead agents |
|-------|-------------|-------------|
| 0 | Project scaffolding, design system tokens, base routing | designer, frontend |
| 1 | DB schema + repositories (cards, events, tags, FTS) | db |
| 2 | Card capture: camera preview + manual save (no OCR yet) | designer, backend, frontend |
| 3 | Edge detection + perspective correction (OpenCV) | backend |
| 4 | OCR (ML Kit) + QR (mobile_scanner) extraction | backend, frontend (edit UI) |
| 5 | Card list, detail, tag, event browse | designer, frontend |
| 6 | Search (FTS5) — Japanese tokenization | db, frontend |
| 7 | SNS link launch + polish | frontend |

Each phase ends with: tests green, `code-reviewer` clean, manual smoke on iOS + Android sim.

## TDD loop

```
1. Read the requirement section + relevant agent charter
2. Sketch the interface (function signature / widget API)
3. Write failing test (RED)
4. Minimum implementation (GREEN)
5. Refactor for clarity (IMPROVE)
6. Verify coverage ≥ 80% on touched files
7. code-reviewer
```

## Performance gates (per requirements §4-1)

Each phase must verify the relevant budget before being declared complete:

| Operation | Budget | Verified by |
|-----------|--------|-------------|
| Cold start | ≤ 3s | manual timing on physical device |
| Search across 5k cards | ≤ 1s | `test/db/bench/search_bench_test.dart` |
| Scan + perspective correction | ≤ 3s | `test/services/scan_bench_test.dart` |

If a budget is missed, the phase is not done.

## Codegen

Models and JSON use `freezed` + `json_serializable`. After editing a model file:

```bash
cd app
dart run build_runner build --delete-conflicting-outputs
```

Commit the generated `.g.dart` / `.freezed.dart` files alongside source.

## Out of scope (do not implement)

Per requirements §8: SNS features, follow/feed, chat, posting, card creation, cloud sync, server share, AI image generation, video, high-precision AI OCR, realtime share. If a task starts pulling in any of these, stop and check with the user.

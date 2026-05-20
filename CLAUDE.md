# otameishi (推し活イベント名刺管理アプリ)

Local-first Flutter mobile app for personally archiving business / fan cards exchanged at 推し活 events (Comiket, Vtuber events, lives, cosplay, etc.). On-device only — no server, no sync, no cloud.

**Authoritative requirements**: [`requirements.md`](./requirements.md). When in doubt, defer to that document.

## Repository layout

```
otameishi/
  requirements.md       # MVP v1 spec (source of truth)
  CLAUDE.md             # this file
  docs/
    DEVELOPMENT.md      # workflow + agent orchestration
    design/             # designer outputs (specs, tokens, flows)
  app/                  # Flutter project (run flutter commands from here)
    lib/
      models/           # backend: immutable domain models (freezed)
      services/         # backend: OCR, camera, image pipeline, QR
      usecases/         # backend: cross-service orchestration
      core/             # backend: shared utilities, isolates, result types
      db/
        migrations/     # db: append-only SQL migrations
        repositories/   # db: concrete sqflite implementations
      screens/          # frontend: one screen per file
      widgets/          # frontend: reusable widgets
      router/           # frontend: go_router config
      theme/            # frontend: design tokens from designer specs
    test/
      services/         # backend unit tests
      db/               # db integration + bench tests
      widgets/          # frontend widget tests
      integration/      # end-to-end flow tests
```

## Subagent ownership map

| Area | Owner | Tools |
|------|-------|-------|
| `lib/services/`, `lib/usecases/`, `lib/core/`, `lib/models/` | **backend** | Read, Write, Edit, Bash, Grep, Glob |
| `lib/db/**` | **db** | Read, Write, Edit, Bash, Grep, Glob |
| `lib/screens/`, `lib/widgets/`, `lib/router/`, `lib/theme/` | **frontend** | Read, Write, Edit, Bash, Grep, Glob |
| `docs/design/**` | **designer** | Read, Write, Edit, Grep, Glob |
| Cross-cutting implementation plans | **planner** | Read, Grep, Glob |
| Any code review (post-write) | **code-reviewer** | Read, Grep, Glob, Bash |
| Flutter / SDK / API questions | **claude-code-guide** | Bash, Read, WebFetch, WebSearch |

## Non-negotiables (apply across all agents)

1. **Local-first** — No server, no sync, no telemetry. The only network traffic is the user explicitly launching an SNS/web URL.
2. **Offline-capable** — List, search, tag browse, scanned-data view must work in airplane mode.
3. **Privacy** — Memos and card contents never leave the device.
4. **Performance** — Start ≤ 3s, search ≤ 1s, scan + correction ≤ 3s (requirements §4-1).
5. **Image cap** — 1920px, 1MB (requirements §3-1-5).
6. **Immutability** — Domain models and state are immutable (`freezed` / `copyWith`).
7. **Repository pattern** — Services never touch sqflite directly; UI never touches services without going through providers.
8. **TDD** — Tests first. Target 80%+ coverage on services and repositories.
9. **Japanese-first copy** — All user-facing text drafted in Japanese.
10. **Out of scope (MVP)** — SNS features, accounts, cloud sync, card creation, AI image generation. See requirements §8.

## How to start a task

1. Read [`docs/DEVELOPMENT.md`](./docs/DEVELOPMENT.md) for the workflow.
2. For a new feature, invoke `planner` first.
3. For a new screen, invoke `designer` before `frontend`.
4. After any code change, invoke `code-reviewer`.

## Working directory

All Flutter commands run from `app/`:

```bash
cd app
flutter pub get
flutter run
flutter test
dart run build_runner build --delete-conflicting-outputs   # freezed/json codegen
```

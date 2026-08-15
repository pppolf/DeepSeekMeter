# Contributing to DeepSeekMeter

Thanks for your interest in contributing! 🐳

[中文版](CONTRIBUTING.zh-CN.md)

**Using an AI coding agent?** Read [AGENTS.md](AGENTS.md) at the repo root first — it is the operating manual for AI agents and defines the project's hard boundaries.

## Quick Start

- Repo: https://github.com/pppolf/DeepSeekMeter
- Default branch: `main`
- User docs: [README.md](README.md) / [README.zh-CN.md](README.zh-CN.md)

## Development Setup

- macOS 14+ (Apple Silicon or Intel)
- Xcode Command Line Tools only: `xcode-select --install`
- No Xcode project, no third-party dependencies — pure Swift Package Manager

## Common Commands

```bash
swift run                        # run in dev mode (no .app shell)
swift build                      # debug build
swift build -c release           # release build
bash Scripts/run-tests.sh        # run lightweight self-tests (swiftc, no XCTest)
bash Scripts/build-app.sh release # assemble build/DeepSeekMeter.app + codesign
bash Scripts/install.sh          # build, install to /Applications, launch
```

CI runs the full chain on every push/PR: `swift build` → `swift build -c release` → `run-tests.sh` → `build-app.sh release` → 6s smoke launch. **Everything must pass locally before opening a PR.**

## Repository Layout

```
Sources/DeepSeekMeter/           App sources (SwiftUI + AppKit)
  Views/                         Popover UI
  AppModel.swift                 State hub (@MainActor ObservableObject)
  PlatformService.swift          DeepSeek platform API client
  Models.swift                   Decodable models + aggregation
  SettingsStore.swift            UserDefaults persistence + launch-at-login
windows/                         Windows version (.NET 8 + WPF, feature-aligned with the macOS app)
  src/DeepSeekMeter.Core/        Pure-logic library (Models / Formatting / PlatformService / SettingsStore)
  src/DeepSeekMeter/             WPF app (MainViewModel / TrayIconController / PopoverWindow / LoginWindow)
  tests/DeepSeekMeter.Selftest/  Lightweight self-tests (console, no test framework)
Scripts/                         Info.plist / build / install / notarize / icon / tests
  selftest/                      Lightweight unit tests (swiftc, no Xcode)
.github/workflows/               ci.yml (push/PR: macOS + Windows) + release.yml (v* tags)
```

> **Windows version**: the `.NET 8 + WPF` implementation lives in `windows/` and mirrors the macOS app's features and platform API contract (see [windows/README.md](windows/README.md)). WPF/WinForms are .NET platform components; `Microsoft.Web.WebView2` (official Microsoft package, runtime preinstalled on Windows 10 1809+/11) is the one deliberate exception to the zero-dependency rule, needed to embed the official login page. Keep the Swift side dependency-free.

## Code Conventions

- **Single executable target, zero third-party dependencies** — a deliberate design; propose new dependencies via an issue first
- Swift 6 toolchain, **Swift 5 language mode** (set in Package.swift)
- Layering: UI (Views/StatusItemController) → AppModel/SettingsStore (state) → PlatformService (network) → Foundation. UI never calls the network directly; all requests go through `PlatformService` and errors map to `PlatformError` with user-facing Chinese messages
- Response models: `Decodable` structs in Models.swift, following the platform envelope `{code, msg, data: {biz_code, biz_msg, biz_data}}` (note `biz_data` is sometimes an object, sometimes an array — trust the real response)
- Pure helpers (formatting, currency symbols, aggregation) go in Formatting.swift / computed properties, with selftest coverage
- Comments and UI strings are in **Chinese** (`///` doc comments, `// MARK: -` grouping); keep it that way
- Add checks to Scripts/selftest/main.swift for new pure logic (formatting, decoding, aggregation)

## Commit Messages

Conventional Commits with a Chinese description:

```
<type>(<scope>): <short Chinese description>
```

- type: `feat` / `fix` / `docs` / `refactor` / `chore` / `ci` / `test` / `perf` (scope optional, e.g. `ci`, `ui`, `api`)
- Example: `fix(ci): build-app.sh 在无开发者证书环境下不再被 set -e 中断`
- Small focused commits; never commit build artifacts (`.build/`, `build/`, `.DS_Store`) or real tokens/credentials

## Branching & Pull Requests

1. Branch from `main` — suggest `feat/xxx` or `fix/xxx`
2. Verify locally (build debug + release, run-tests.sh, build-app.sh)
3. Open a PR to `main` and fill in the [PR template](.github/pull_request_template.md) — every checkbox matters
4. PR triggers CI; **merge only when CI is green** (squash merge recommended)
5. Same-repo PRs also get an automatic **AI review** (DeepSeek API, follows AGENTS.md) — it comments as `github-actions[bot]`, advisory only; the maintainer merges manually
6. Pushes to `main` also run CI

## Scope & Boundaries

Keep the project inside these lines — they are privacy and stability commitments:

1. **No third-party dependencies** — zero-dependency single target is intentional
2. **Token stays in UserDefaults** — do not move it back to the Keychain (ad-hoc signing would prompt for a password on every launch; a one-time migration already exists in SettingsStore)
3. **Never commit real tokens/credentials** — in code, logs, screenshots, or commits
4. **Don't invent platform APIs** — PlatformService talks to *private* endpoints of platform.deepseek.com (`get_user_summary` / `usage/by_api_key/amount` / `usage/by_api_key/cost`, params `start`/`end` in Unix seconds, `tz` as second offset, `bucket` granularity); verify against a real response before changing URLs, params, or response shapes, and update the selftest fixtures
5. **No data flow changes** — data comes only from DeepSeek's official endpoints; nothing is sent to third parties
6. **No Xcode project / XCTest** — keep tests as lightweight swiftc self-tests; open an issue for heavier test tooling
7. **Keep platform constraints** — macOS 14+, Swift 5 language mode
8. **Keep the language baseline** — Chinese comments/UI; bilingual docs (README.md EN + README.zh-CN.md ZH)

## Release Process (maintainers)

1. Bump `Scripts/Info.plist` (`CFBundleShortVersionString` and `CFBundleVersion`)
2. Verify with `bash Scripts/build-app.sh release`
3. Tag and push: `git tag v0.1.0 && git push origin v0.1.0`
4. [release.yml](.github/workflows/release.yml) builds the DMG and publishes the GitHub Release automatically
5. Optional: sign + notarize with `Scripts/notarize.sh` (requires a paid Developer ID certificate) and re-publish

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).

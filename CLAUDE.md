# osx-clamshell-guard

## Project Overview

A macOS LaunchDaemon that prevents clamshell sleep during USB-C dock power delivery renegotiation. Written in Swift, distributed via Homebrew.

## Build

```bash
make build        # compile
make clean        # remove binary
```

Requires Xcode Command Line Tools. Single-file Swift project — no package manager needed.

## Test

```bash
sudo ./osx-clamshell-guard           # run manually (requires root for IOKit assertions)
./osx-clamshell-guard --version     # verify build
```

No automated test suite — the daemon interacts with IOKit power management which requires a real system sleep/wake cycle to test.

## Architecture

Single source file: `Sources/main.swift` (~195 lines)

- Registers for IOKit system power notifications via `IORegisterForSystemPower`
- On wake (`kIOMessageSystemHasPoweredOn`): creates `PreventSystemSleep` assertion + starts grace period timer
- During grace period: denies `kIOMessageCanSystemSleep` requests via `IOCancelPowerChange`
- After grace period: releases assertion, allows normal sleep
- Signal handling via GCD `DispatchSource` (not POSIX `signal()`) for async-signal-safety

All state is process-scoped — kernel cleans up assertions if process dies.

## Distribution

- **Homebrew tap**: separate repo `mkrinke/homebrew-osx-clamshell-guard` (contains `Formula/osx-clamshell-guard.rb`)
- **GitHub Actions**: `.github/workflows/build.yml` (CI), `.github/workflows/release.yml` (tag-triggered release + auto-updates tap formula via `mislav/bump-homebrew-formula-action`)
- **Manual install**: `sudo make install-service` (uses `com.osx-clamshell-guard.plist` template)

## Release Process

1. Tag: `git tag v1.x.x && git push --tags`
2. GitHub Actions creates a release and auto-updates the formula in the tap repo (SHA256 + version)
3. Requires `HOMEBREW_TAP_TOKEN` secret (PAT with `repo` scope for the tap repo)

## Key Files

| File | Purpose |
|------|---------|
| `Sources/main.swift` | All daemon logic |
| `Makefile` | Build, install, service management |
| `com.osx-clamshell-guard.plist` | LaunchDaemon template (for manual install) |

## Conventions

- Binary name: `osx-clamshell-guard`
- LaunchDaemon label: `com.osx-clamshell-guard` (manual) or `homebrew.mxcl.osx-clamshell-guard` (brew services)
- Logs: `/var/log/osx-clamshell-guard/` (manual) or `$(brew --prefix)/var/log/osx-clamshell-guard/` (Homebrew)
- Commits use `--no-gpg-sign`

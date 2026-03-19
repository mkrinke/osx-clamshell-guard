# osx-clamshell-guard

Prevents macOS from going back to sleep during USB-C dock power delivery renegotiation when waking in clamshell (closed-lid) mode.

## The Problem

Many USB-C docks briefly drop power delivery (PD) when a Mac wakes from sleep. macOS requires AC power for clamshell mode, so even a 2-second PD dropout triggers an immediate "Clamshell Sleep" cycle. The Mac wakes, the dock drops PD, macOS sees battery power, and puts the Mac right back to sleep — often in an endless loop.

## How It Works

osx-clamshell-guard is a LaunchDaemon that:

1. Listens for system wake events via IOKit power notifications
2. On wake, creates a `PreventSystemSleep` assertion and denies sleep requests for a 30-second grace period
3. After the grace period, releases the assertion and restores normal sleep behavior

This gives the dock enough time to renegotiate USB-C PD without macOS yanking the rug out.

Two complementary mechanisms are used:

- **IOPMAssertion** (`PreventSystemSleep`): Tells macOS power management not to initiate system sleep
- **IOCancelPowerChange**: Actively denies "can I sleep?" requests from the kernel during the grace period

Forced sleep events (user-initiated, low battery, thermal) are always respected. The daemon holds no persistent state — if the process dies for any reason, the kernel automatically cleans up all assertions.

## Requirements

- macOS 13+ (Apple Silicon or Intel)
- Xcode Command Line Tools (`xcode-select --install`)

## Install

### Homebrew (recommended)

```bash
brew tap mkrinke/osx-clamshell-guard
brew install osx-clamshell-guard
sudo brew services start osx-clamshell-guard
```

The service persists across reboots. `sudo` is needed because the daemon requires root privileges for `PreventSystemSleep` assertions.

### Upgrade

```bash
sudo brew services stop osx-clamshell-guard
brew upgrade osx-clamshell-guard
sudo brew services start osx-clamshell-guard
```

### Uninstall

```bash
sudo brew services stop osx-clamshell-guard
brew uninstall osx-clamshell-guard
brew untap mkrinke/osx-clamshell-guard
```

### Logs

```bash
tail -f $(brew --prefix)/var/log/osx-clamshell-guard/osx-clamshell-guard.log
```

## Development

### Build and test

```bash
make build
sudo ./osx-clamshell-guard
```

### Install from source (without Homebrew)

```bash
sudo make install-service
```

### Makefile targets

| Target            | Description                              |
|-------------------|------------------------------------------|
| `build`           | Compile the binary                       |
| `install`         | Install binary to PREFIX                 |
| `install-service` | Install binary + register LaunchDaemon   |
| `uninstall`       | Remove binary + daemon                   |
| `load` / `unload` | Start / stop the daemon                  |
| `restart`         | Restart the daemon                       |
| `status`          | Show daemon status and power assertions  |
| `log`             | Tail the log file                        |
| `clean`           | Remove build artifacts                   |

## License

MIT

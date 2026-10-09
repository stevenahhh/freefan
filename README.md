# FreeFan

Minimal macOS menu-bar fan control for Apple Silicon.

- Live temperatures and fan RPM in the menu bar
- Temperature-to-speed curves edited on a graph
- Saved presets, switchable from the menu
- Near-zero CPU and memory overhead

## Build and run

```sh
swift build --scratch-path build/scratch
bash scripts/build-app.sh          # assembles and ad-hoc signs build/FreeFan.app
open build/FreeFan.app
```

Then choose **Install Helper…** from the menu. That asks for an administrator password once and
installs a small root daemon (`/Library/LaunchDaemons/com.stevenahhh.freefan.helper.plist`) which is
the only process that writes to the SMC. Uninstall it again from the same menu.

The app shows `52° 2.3k` in the menu bar, opens a menu with live CPU/GPU/fan readings, the preset
list and the curve editor. Selecting a preset sends the curve to the daemon; selecting **Auto**
returns the fans to the system. "Auto" is a mode, not a preset.

## Layout

| path | what |
|---|---|
| `Sources/FreeFanSMC` | AppleSMC access and sensor discovery |
| `Sources/FreeFanCore` | fan curve, preset store, socket protocol |
| `Sources/FreeFanControl` | the decision engine (hysteresis, dead band, panic) |
| `Sources/FreeFanHelper` | the root daemon: socket, lease watchdog, control tick, sleep handling |
| `Sources/FreeFan` | the menu bar app and the curve editor |
| `Sources/*Check` | executable checks (XCTest is unavailable with Command Line Tools only) |
| `docs/SPEC.md` | the researched implementation spec |
| `docs/HARDWARE-VERIFICATION.md` | measured evidence on the target machine |

## Safety model

- Writes go to `F{n}Tg` (target RPM, clamped to `[Mn, Mx]`) **before** `F{n}md = 1`. Engaging manual
  mode without a target stops a fan.
- The daemon holds a 1 s control timer only while controlling, and releases the fans (`md = 0`) when
  its client stops talking for 12 s, when the client's socket closes, on SIGTERM/SIGINT/SIGHUP, and
  before sleep. It also resets a stale manual mode at startup.
- A failed SMC write degrades to monitor-only mode and refuses further control commands.
- Only root and the installing user may talk to the daemon (`getpeereid`), and every value it accepts
  is range-checked.

## Checks

```sh
swift run --scratch-path build/scratch SMCCheck
swift run --scratch-path build/scratch CoreCheck
swift run --scratch-path build/scratch ControlCheck
```

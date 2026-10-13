# OpenFan

Minimal macOS menu-bar fan control for Apple Silicon.

- Live temperatures and fan speeds in the menu bar, in a format you write yourself
- A popover with CPU, GPU and (on a laptop) battery temperatures and one column per fan, as a percentage of full speed or in rpm (click the fan row to switch)
- Temperature-to-speed curves edited on a graph
- Saved presets in a horizontally scrolling row, one click away
- Built-in presets that cannot be changed by accident, and your own on top
- Near-zero CPU and memory overhead

## Download

Each [release](https://github.com/stevenahhh/openfan/releases/latest) from 1.4 on carries `OpenFan.zip`. Unzip it,
move `OpenFan.app` to `/Applications` and open it. The app is ad-hoc signed and not notarized, so the first launch
needs a right-click on the app and **Open** (or `xattr -dr com.apple.quarantine /Applications/OpenFan.app`).

## Updates

OpenFan looks for a newer release when it starts and when you open the popover, at most once a day. Nothing appears
unless there is one: then the footer shows **Update available!**. Clicking it downloads the release, checks its
Ed25519 signature against the key built into the app and the app's code signature, swaps it in and relaunches. There
are no notifications and no background timer. When a release changes the helper, the popover says so and the ☰ menu
gets **Update Helper…** (one administrator password).

## Build and run

```sh
swift build --scratch-path build/scratch
bash scripts/build-app.sh          # assembles and ad-hoc signs build/OpenFan.app
open build/OpenFan.app
```

Then click the menu-bar item and choose **Install Helper…** in the popover footer. That asks for an
administrator password once and installs a small root daemon
(`/Library/LaunchDaemons/com.stevenahhh.openfan.helper.plist`) which is the only process that writes
to the SMC. Uninstall it again from the same place.

The app shows `52° 2.3k` in the menu bar. Clicking it opens a popover with CPU, GPU and battery
temperatures, one column per fan, a row of presets and the curve editor. Clicking a preset activates it
and shows its curve; every edit is saved when you let go of the mouse and sent to the daemon right away.
**Auto** returns the fans to the system. "Auto" is a mode, not a preset.
A curve follows the hottest of CPU and GPU, the CPU, the GPU or the battery average (the pop-up menu
next to the name); whatever it follows, the fans go to full speed when the CPU or GPU reaches 95 °C.

A fan column reads as a percentage of full speed until you click the fan row, which switches it to rpm;
the choice is remembered. **Silent**, **Balanced**, **Performance** and **Full** are built in and
cannot be edited — duplicate one to make it yours — and Full is not a curve at all: it holds both fans
at maximum speed. A curve that reaches its bottom edge hands the fans back to macOS (the graph says Auto
there), which stops them while the Mac is cool, so letting the fans stop needs no special setting. The graph's
readouts use the same unit as the fan row, so the speed beside the temperature on the graph is the speed in the
header. Your own presets live in
`~/Library/Application Support/OpenFan/presets.json` (version 2 stores only those; an older file is
migrated on load).

**Menu Bar Text…** in the popover footer opens the settings page. The text is a template; click a name
to insert it, and the preview shows what the menu bar will say. The names are `{max}` (hottest of CPU
and GPU), `{cpu}`, `{gpu}`, `{bat}` (battery average), `{rpm}` (fastest fan), `{rpm0}`, `{rpm1}` and
`{preset}`. Anything that is not a name is shown as typed, and at most 40 characters are shown. Leave
the field empty to show only the pressure dot; the Default button puts the default template back. The
memory pressure dot can be turned off on the same page. Settings live in
`~/Library/Application Support/OpenFan/settings.json`; an unreadable file is kept as `settings.json.bak`
and the defaults are used.

Hovering the **?** in the footer explains the editor: drag a point to move it, double-click empty
space to add one, right-click a point to remove it, and built-in presets have to be duplicated before
they can be changed. The **☰** menu next to it installs or uninstalls the helper and quits the app.

## Coming from FreeFan

OpenFan is FreeFan under a new name. The identifiers changed with it, so an installation of FreeFan needs
two steps once:

1. Install OpenFan's helper (**Install Helper…**). The installer stops and removes the old FreeFan helper
   first, which hands the fans back to macOS, so only one helper is ever installed.
2. Move your presets and settings: `mv ~/Library/Application\ Support/FreeFan ~/Library/Application\ Support/OpenFan`
   before the first launch. Without it OpenFan starts with the built-in presets.

Then delete `FreeFan.app`.

## Supported Macs

OpenFan is verified on one model so far, the MacBook Pro Mac17,9 (Apple M5 Pro). It is written to also handle one-fan
MacBook Pros, Mac mini, Mac Studio and iMac (no battery column there), M1 to M4 chips (their own temperature keys and
fan mode key; M3 and M4 need the `Ftst` unlock) and fanless MacBook Airs (temperatures only), but none of these has
been tested. The helper writes to the SMC on your behalf, so on any other Mac start with `swift run --scratch-path build/scratch OpenFanProbe`: it only reads,
and prints your model, fans and sensors. [docs/hardware](docs/hardware/README.md) lists the verified models and
explains how to add yours.

## Xcode canvas and preview host

The popover is previewable in Xcode's canvas. Open the package (**File ▸ Open…** on `Package.swift`), open
`Sources/OpenFanUI/Previews.swift` and switch the canvas on with **Editor ▸ Canvas** (a **Resume** button appears
if the canvas is paused). Three variants are declared: the popover, plus light and dark appearances.

Previews need the UI in a library target: Xcode refuses to preview an executable target unless the project sets
`ENABLE_DEBUG_DYLIB`, which a Swift package cannot express, so the popover lives in `OpenFanUI` and the `OpenFan`
executable is only the menu bar item and the helper client.

For a plain window rather than the canvas, run the **OpenFanPreview** scheme (⌘R): it hosts the same controller
with sample data, which pairs well with **Debug ▸ View Debugging ▸ Capture View Hierarchy**. Both preview paths
use a throwaway store under the temporary directory, so they never read or write the real `settings.json` or
`presets.json`, and neither involves the helper.

`#Preview` expands through macro plugins that only ship with Xcode, so `scripts/build-app.sh` prefers the Xcode
toolchain when it is installed; with only the Command Line Tools, remove `Sources/OpenFanUI/Previews.swift`
before building.

## Layout

| path | what |
|---|---|
| `Sources/OpenFanSMC` | AppleSMC access and sensor discovery |
| `Sources/OpenFanCore` | fan curve, preset store, socket protocol |
| `Sources/OpenFanControl` | the decision engine (hysteresis, dead band, panic) |
| `Sources/OpenFanHelper` | the root daemon: socket, lease watchdog, control tick, sleep handling |
| `Sources/OpenFanUI` | the popover and its views, plus the preview harness |
| `Sources/OpenFan` | the menu bar app: status item, telemetry, helper client |
| `Sources/OpenFanPreview` | a window that hosts the popover with sample data |
| `Sources/OpenFanProbe` | a read-only report of a Mac's SMC: model, fans, sensors |
| `Sources/*Check` | executable checks (XCTest is unavailable with Command Line Tools only) |
| `docs/SPEC.md` | the researched implementation spec |
| `docs/hardware` | measured evidence per Mac model, and the template for adding yours |

## Safety model

- Writes go to `F{n}Tg` (target RPM, clamped to `[Mn, Mx]`) **before** `F{n}md = 1`. Engaging manual
  mode without a target stops a fan.
- A curve at 0 % releases the fan (`md = 0`) instead of asking for the lowest speed, so no target below
  `Mn` is ever written; leaving that zone re-engages target-first.
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

## Contributing

Pull requests are welcome, above all for support of other Macs. See [CONTRIBUTING.md](CONTRIBUTING.md) and
[docs/hardware](docs/hardware/README.md); report security problems as described in [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE): free to use, modify, distribute and sell, commercially too.

There is no warranty, and this software writes to your Mac's SMC through a root helper. Read the safety model above,
check [docs/hardware](docs/hardware/README.md) to see whether your model has been verified, and use it at your own risk.

The prebuilt app is ad-hoc signed and not notarized; you can always build it yourself as described above.

OpenFan was written from scratch. The AppleSMC protocol and the key names were learned from open-source projects such
as [Stats](https://github.com/exelban/stats), [SMCKit](https://github.com/beltex/SMCKit),
[fand](https://github.com/yolo-labz/fand) and [fanctl](https://github.com/erogol/fanctl) (all MIT). No code was copied
from them or from any other project that was read; that was checked line by line.

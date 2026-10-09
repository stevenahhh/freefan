# Hardware verification

Measured on the target machine: MacBook Pro Mac17,9 (Apple M5 Pro), macOS 27.0.1 (26A434), two fans
(`F0`, `F1`), `Mn` = 2317 rpm, `Mx` = 7826 rpm.

Reproduce with:

```sh
swift build --scratch-path build/scratch
swift run --scratch-path build/scratch SMCCheck     # 42 checks
swift run --scratch-path build/scratch CoreCheck    # 215 checks
swift run --scratch-path build/scratch ControlCheck # 132 checks
bash scripts/build-app.sh && codesign --verify --strict build/FreeFan.app
```

All four exit 0 on this machine. Reference values below were read with an independent SMC probe (a
separate binary that speaks the same protocol) so the app's own readings could be cross-checked.

## C1 - telemetry

Menu bar title `56° 2.5k` while the probe read CPU 54.6-56.2 °C and the highest fan 2498-2509 rpm
(delta 0.0-1.4 °C and 0-2 rpm against the displayed rounded value). Error budget was ±3 °C / ±200 rpm.
GPU read 52.0-52.5 °C through the same window.

## C2 - control

With the app idle in Auto (`md=0`, 2316 / 2499 rpm), a 100 percent curve was sent over the socket:

| t | F0 | F1 | target | md |
|---|---|---|---|---|
| +0 s | 2316 | 2499 | 2317 / 2502 | 0 |
| +2 s | 7621 | 7568 | 7826 | 1 |
| +28 s | 7817 | 7831 | 7826 | 1 |
| +30 s (AUTO) | 6051 | 5975 | 2317 / 2502 | 0 |
| +32 s | 2187 | 2538 | 2317 / 2502 | 0 |

Peak of the lower fan: 7832 rpm. Requirement: above 5500 rpm within 20 s - reached in ~2 s; Auto
restored `md=0` within one tick.

## C3 - curve editor and persistence

The curve editor now lives in the popover (there is no separate window). It draws the selected preset's curve (grid, both axes titled, the Silent preset's
points 50:0 / 70:15 / 85:45 / 95:100, a translucent fill) and overlays a live marker: a dashed line at
the current temperature with `53.4 °C 2501 / 7826 rpm` - the fan RPM matched the probe's 2498-2509 at
that moment.

Persistence: with `active = "performance"` in `~/Library/Application Support/FreeFan/presets.json`,
relaunching the app produced `OK mode=curve temp=48.34 rpm=4031.6763,4031.6763 writes=8` within one
tick and the probe showed 4060 rpm. Quitting the app returned `OK mode=auto ...` and the fans spun down.

The store creates defaults when the file is missing, quarantines an undecodable file to
`presets.json.bak`, and drops presets whose curve fails validation (covered by CoreCheck).

## C4 - safety

**kill -9 of the controlling client.** Fans were under control at 7820 / 7818 rpm (`md=1`). The client
was killed; the daemon logged `lease expired: controlling connection closed` and
`release (lease): md=0 written on 2 of 2 fan(s), 0 failed`; the first sample two seconds later read
`md=0` with both fans spinning down. Budget was 20 s.

**SIGTERM to the daemon.** While controlling at 7826 / 7845 rpm the daemon received SIGTERM, logged
`SIGTERM received: shutting down`, `release (shutdown): md=0 written on 2 of 2 fan(s), 0 failed` and
`socket removed, exiting`. Two seconds later both fans read `md=0` and the socket file was gone.
launchd restarted the service (`KeepAlive`), the new instance logged
`boot reset: no fan was under manual control` - the boot reset that also covers a hard crash - and the
fans stayed in Auto.

**Hostile input.** Eight malformed commands were refused with a specific reason and no SMC write
occurred during the sequence (the daemon's write counter did not move):

| command | reply |
|---|---|
| `CURVE max nan:10,50:20` | `ERR bad value: non-finite temperature: nan` |
| `CURVE max 999:5,1000:5` | `ERR bad value: point 0 temperature is outside 0...130` |
| `CURVE max 40:20,40:30` | `ERR bad value: point 1 is not strictly above the previous temperature` |
| `CURVE max 40:20` | `ERR bad value: curve needs at least 2 points (has 1)` |
| `FIXED 500` | `ERR bad value: fixed percent outside 0...100: 500` |
| `FIXED -1` | `ERR bad value: fixed percent outside 0...100: -1` |
| `CURVE bogusmax 40:20,50:30` | `ERR bad value: unknown curve input bogusmax` |
| `AUTOO` | `ERR unknown command: AUTOO` |

A 600-byte line is answered with `ERR too long` and the connection is closed.

**Peer uid.** A daemon started with `--allow-uid 0` refused a connection from uid 501
(`ERR unauthorized`, logged as `connection refused: uid 501 is not allowed`) while accepting uid 0.
The installed daemon is launched with `--allow-uid 501`, so exactly the installing user and root may
speak to it; the socket itself is mode 0666 and `getpeereid` is the gate.

## C5 - overhead

| process | CPU | memory |
|---|---|---|
| FreeFan (menu bar app, idle) | 0.0 % | phys_footprint 14 MB |
| FreeFanHelper (idle, Auto) | 0.0 % | ~2.4 MB resident |

Remeasured with the popover build installed in `/Applications`, from the cumulative CPU time:

| process | state | CPU | memory |
|---|---|---|---|
| FreeFan | popover closed, Performance curve applied, 180 s | 0.14 % | phys_footprint 17 MB |
| FreeFanHelper | controlling (1 s tick), 180 s | 0.11 % | 6.9 MB resident |
| FreeFanHelper | idle in Auto (no client), 120 s | 0.000 % | 6.2 MB resident |

The helper is at its 0.1 % budget only while it controls the fans; idle it uses no CPU at all. kill -9
of the app returned `md=0` in 10 ms and SIGTERM of the helper in 19 ms (independent probe), after
which launchd restarted the helper and the app took control again.

Budgets were 0.5 % / 50 MB for the app and 0.1 % / 10 MB for the daemon. The daemon holds no timer
while idle - it blocks on the socket - and the app reads the SMC on a utility queue and rewrites the
status title only when the rendered string changes.

## C6 - battery input

With the helper reinstalled from the current bundle, `CURVE battery 20:10,40:30` was held on one
connection. The helper reported `temp=32.23` while the independent probe read TB0T / TB1T / TB2T =
32.40 / 31.90 / 32.40 °C (mean 32.23); the worst difference over the settled samples was 0.03 °C. At
32.23 °C the curve gives 22.23 %, i.e. 2317 + 0.2223 × 5509 = 3541.8 rpm; the SMC targets read 3541 and
the fans settled within 7 rpm of it. `AUTO` returned both targets to the system. The 95 °C guard
watches the hottest CPU/GPU sensor whatever the curve input is, so a cool battery curve cannot hide a
hot SoC (ControlCheck). `CURVE battery nan:1,50:2` and `CURVE batt 20:0,40:100` were refused with no
SMC write.

## C7 - popover, menu bar text and memory pressure

- Dragging a point in the popover editor rewrote `presets.json`; chips switched presets (helper
  `mode=curve`) and Auto (`md=0`); points clamp to 0-110 °C / 0-100 %; Escape during a drag wrote
  nothing.
- Typing `CPU {cpu}° · {rpm}` in the settings page and pressing Return changed the menu bar to
  `CPU 40° · 2.3k`; the text survived a relaunch. A corrupt `settings.json` was moved to
  `settings.json.bak` and the default `38° 2.3k` shown. The pressure dot can be switched off and on.
- The memory pressure dot is green at level 1 (Normal), like Activity Monitor.
- Popover memory: about 26 MB closed, 28-30 MB open, back to 26 MB after 30 open/close cycles. kill -9
  of the app while a curve was applied returned `md=0` in 144 ms.

## Not covered

- A real sleep/wake cycle (the daemon releases the fans before sleep and re-applies the curve after
  wake, and `ControlCheck` covers the engine, but no end-to-end suspend was performed here).
- Whether the system reclaims fan control after tens of minutes of manual operation.
- The reported per-boot SMC write limit: the design writes only when the target moves by at least
  100 rpm, and a full verification sequence used 16 writes.

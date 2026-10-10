# Hardware verification: <model identifier>

Copy this file to `docs/hardware/<model identifier>.md` and replace everything in angle brackets. Delete nothing:
a check you could not run stays in the file, marked "not run", with the reason.

Measured on: <model name and identifier>, <chip>, macOS <version and build>, <number> fans (`F0`, ...),
`Mn` = <rpm>, `Mx` = <rpm>. Date: <date>. Verified by: @<github handle>.

## Probe

Paste the full output of `swift run --scratch-path build/scratch FreeFanProbe` (it is read-only). Put it in a
`<details>` block if it is long.

## Code changes

<What you added to `SensorCatalog` or elsewhere, and how you decided: which keys, which group, why. "None" if the
catalogue already covered the machine.>

## Checks

```sh
swift run --scratch-path build/scratch SMCCheck     # <n> checks
swift run --scratch-path build/scratch CoreCheck    # <n> checks
swift run --scratch-path build/scratch ControlCheck # <n> checks
bash scripts/build-app.sh && codesign --verify --strict build/FreeFan.app
```

<All exit 0? Paste the last line of each. Any SKIP or failure, with the reason.>

## C1 - telemetry (required)

Compare the app with a second tool (Stats, iStat Menus, Macs Fan Control, or the probe itself) at the same moment.
Budget: 3 °C and 200 rpm.

| sample | app CPU | other CPU | app fan rpm | other fan rpm |
|---|---|---|---|---|
| <1> | <°C> | <°C> | <rpm> | <rpm> |
| <2> | | | | |
| <3> | | | | |

<Also the GPU and, if you use a battery curve, the battery mean.>

## C2 - control (required)

Install the helper from your build, select **Full** (both fans at maximum), and read the fans every few seconds with
the probe. Then select **Auto**. Pass: above 70 % of `Mx` within 20 s, and `md` back to 0 within one tick after
Auto.

| t | F0 rpm | F1 rpm | target | md |
|---|---|---|---|---|
| +0 s | <> | <> | <> | 0 |
| +2 s | | | | |
| ... | | | | |
| Auto +0 s | | | | |
| Auto +2 s | | | | |

## C3 - persistence (required)

Select a curve preset, quit the app from its menu and relaunch it.
`printf 'STATUS\n' | nc -U /var/run/com.stevenahhh.freefan.sock` shows the helper's view.

<What you saw: the fans after quitting (back to the system?), and the helper status within one tick of relaunching.>

## C4 - safety (required)

**kill -9 of the app while controlling.** Fans at <rpm> (`md = 1`). `pkill -9 -x FreeFan`. <Log lines from
`/var/log/com.stevenahhh.freefan.helper.log` and the first reading after: `md`, rpm, time in seconds.> Budget: 20 s.

**SIGTERM of the helper while controlling.** `sudo kill -TERM $(pgrep -f FreeFanHelper)`. <Log lines, `md` two
seconds later, whether launchd restarted it and what its boot reset logged.>

**Malformed commands.** Send each with `printf '<command>\n' | nc -U /var/run/com.stevenahhh.freefan.sock`. Every one
must be refused with a reason, and the helper's write counter (`writes=` in `STATUS`) must not move.

| command | reply |
|---|---|
| `CURVE max nan:10,50:20` | <> |
| `CURVE max 999:5,1000:5` | <> |
| `CURVE max 40:20,40:30` | <> |
| `CURVE max 40:20` | <> |
| `FIXED 500` | <> |
| `FIXED -1` | <> |
| `CURVE bogusmax 40:20,50:30` | <> |
| `AUTOO` | <> |

## C5 - overhead (recommended)

CPU is the process's CPU time over a fixed window: `ps -o time= -p <pid>` before and after 30 s, with the helper
controlling a curve. Memory is `footprint -p <pid>` after one open and close of the popover. Do not drive the popover
through the accessibility API (System Events, `osascript`) while measuring: an accessibility client inflates the
heap.

| process | state | CPU (ms in 30 s) | footprint |
|---|---|---|---|
| FreeFan | popover closed | <> | <> |
| FreeFan | popover open | <> | <> |
| FreeFanHelper | controlling | <> | <> |

## Not covered

<Everything you did not test and why: sleep and wake, long runs, other macOS versions, ...>

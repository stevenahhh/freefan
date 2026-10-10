## Mac

- Model identifier (`sysctl -n hw.model`):
- Chip:
- macOS (version and build):
- Fans:

## Evidence

Evidence file: `docs/hardware/<model identifier>.md`, copied from `docs/hardware/TEMPLATE.md` with every section
filled in. A check that was not run stays in the file, marked "not run", with the reason.

- [ ] `OpenFanProbe` output is in the file
- [ ] C1 telemetry is within 3 °C and 200 rpm of a second tool (which tool:)
- [ ] C2 control: the 100 % curve took the fans above 70 % of `Mx` within 20 s, and Auto put `md` back to 0 within a tick
- [ ] C3 persistence
- [ ] C4 safety: `kill -9` of the app, SIGTERM of the helper and the malformed commands, each with the numbers
- [ ] C5 overhead (recommended)
- [ ] The "Not covered" list is honest

## Code

- [ ] Catalogue changes, if any, are in a commit of their own and explain how each key was assigned to CPU, GPU or battery
- [ ] No safety constant was changed
- [ ] `SMCCheck`, `CoreCheck` and `ControlCheck` pass

## Risk

- [ ] I tested on a Mac I own, and I understand that OpenFan writes to the SMC and that the MIT license gives no warranty
- [ ] Nothing personal (serial number, hardware UUID, user name, host name, IP address) in the files or screenshots

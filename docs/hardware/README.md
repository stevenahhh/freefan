# Supported Macs

FreeFan is verified model by model. A Mac counts as supported when an evidence file for it is merged in this
folder. Anywhere else it may work, but the helper writes to the SMC on your behalf, so treat it as unverified.

| Model identifier | Chip | macOS | Fans | Evidence | Verified by |
|---|---|---|---|---|---|
| Mac17,9 (MacBook Pro) | Apple M5 Pro | 27.0.1 | 2 | [Mac17,9.md](Mac17,9.md) | @stevenahhh |

## How support works

FreeFan does not ship a table of Macs. At launch it asks the SMC which of the catalogued temperature keys exist
(`SensorCatalog` in `Sources/FreeFanSMC/Sensors.swift`) and reads each fan's real limits (`F{n}Mn`, `F{n}Mx`).
To control a fan the helper writes the target speed (`F{n}Tg`) and then switches the fan to manual
(`F{n}md = 1`); it gives control back with `md = 0`.

So a Mac whose keys are already catalogued may need nothing but proof that it behaves, and a Mac with other
temperature keys needs those keys added to the catalogue first (a few lines) and then the same proof.

## Adding your Mac

1. **Branch.** Fork the repository and branch from `main`, for example `hardware/Mac15-3`. One model per pull
   request.
2. **Probe, read-only.** `swift run --scratch-path build/scratch FreeFanProbe > probe.md`. It writes nothing to the
   SMC. If it cannot open the SMC, or finds no fans on a Mac that has them, stop and open an issue with its
   output instead of going on.
3. **Catalogue.** If a group shows `0 of N present`, or the probe lists temperature keys that are clearly CPU or
   GPU sensors but not catalogued, add them to `SensorCatalog` in a commit of their own. Say in the commit message
   how you decided which group a key belongs to (its position in the listing, how it moves under load).
4. **Checks.** Run `SMCCheck`, `CoreCheck` and `ControlCheck` (see the README). `SMCCheck`'s only write attempt is
   an unprivileged one that has to be refused.
5. **Verify on the hardware.** Build the app, install the helper from your own build and carry out the checks in
   [TEMPLATE.md](TEMPLATE.md): C1 to C4 are required, C5 is recommended. Copy the template to
   `docs/hardware/<model identifier>.md` and fill every section with what you measured. Numbers, not "works".
6. **Pull request.** Open it with the hardware template: add `?template=hardware-support.md` to the compare URL
   GitHub shows you. Commits are atomic: the catalogue change, the evidence file and anything else each get their
   own.

## Safety rules for testing

- Test only on a Mac you own, plugged in, on a hard surface, in a cool room, with a second tool open to watch the
  temperatures.
- Start with the probe. Do not install the helper until the probe shows plausible fan limits (a few thousand rpm,
  not 0) and sensors that read sensibly.
- Do not change the safety constants in a hardware pull request: the 95 °C panic latch, the 12 s lease, clamping
  to `[Mn, Mx]`, writing the target before manual mode. If your Mac needs different behaviour, open an issue.
- If a fan does not follow the system after a test, quit the app, run `scripts/uninstall-helper.sh` (it releases
  the fans) and restart the Mac if they still do not.

## What reviewers look for

- Every number traces to a command or a screenshot, and what you could not test is listed under "Not covered".
- Telemetry agrees with a second tool within 3 °C and 200 rpm.
- The 100 % curve takes the fans above 70 % of `Mx` within 20 s, and `AUTO` puts `md` back to 0 within a tick.
- `kill -9` of the app and SIGTERM of the helper both return the fans to the system within 20 s.
- Malformed commands are refused with a reason and no SMC write.
- Nothing personal: no serial number, hardware UUID, user name, host name or IP address, in text or screenshots.

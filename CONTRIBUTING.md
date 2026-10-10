# Contributing

OpenFan is a small menu-bar app plus a root helper that writes to the SMC, so the bar is correctness and safety
first and size second: nothing goes in that the app can do without.

## Build and check

```sh
swift build --scratch-path build/scratch
swift run --scratch-path build/scratch CoreCheck
swift run --scratch-path build/scratch ControlCheck
swift run --scratch-path build/scratch SMCCheck     # needs a real Mac; its only write attempt must be refused
bash scripts/build-app.sh                           # assembles and ad-hoc signs build/OpenFan.app
```

XCTest is not available with the Command Line Tools alone, so the tests are the `*Check` executables. A fix comes with
a check that fails without it.

## Ground rules

- **Safety first.** The helper must never leave a fan under manual control once its client is gone. Do not weaken the
  target-before-manual write order, the clamp to `[Mn, Mx]`, the 95 °C panic latch, the 12 s lease, the release on
  sleep and on SIGTERM, the peer-uid gate or the range checks on every accepted value. A change near them needs a
  check and a sentence in the pull request saying why it is safe.
- **Small.** No new dependency, and no framework linked for convenience: a SwiftUI header once cost about 50 MB in
  this app. Measure before you claim a gain, and say how you measured.
- **Atomic commits.** One logical change per commit, with a subject in the imperative and a prefix this repository
  already uses (`feat`, `fix`, `perf`, `refactor`, `docs`, `ci`), and the reason in the body.
- **Nothing personal.** No serial numbers, hardware UUIDs, user names, host names, IP addresses, tokens or private
  logs in code, commit messages, pull request text or screenshots. Write `~` for your home directory.

## Making OpenFan work on your Mac

This is the most useful contribution, and it has its own procedure with a measured, per-model evidence file: see
[docs/hardware](docs/hardware/README.md). In short: run the read-only `OpenFanProbe`, add your sensor keys to the
catalogue if they are missing, run the verification in [docs/hardware/TEMPLATE.md](docs/hardware/TEMPLATE.md) on your
own Mac, and open a pull request with the hardware template. One model per pull request.

## Pull requests

- Branch from `main`; keep the pull request small enough to review in one sitting.
- The description follows the template. CI builds the package and runs `CoreCheck` and `ControlCheck`; it has to pass.
- Say what you ran and what you saw. "Should work" is not a result.

## Versions and releases

Versions are `MAJOR.MINOR` and nothing else: 1.0, 1.1, 1.2, and 2.0 for a change that breaks something users have
(the preset file format, the helper protocol). A fix is a new minor version too; there is no patch number.

`Resources/Info.plist` is the only place the version lives. A release changes two keys there in its own commit:
`CFBundleShortVersionString` to the new version (it is what the footer menu shows) and `CFBundleVersion` to the
previous value plus one. The release is then the tag `v<version>` on that commit (`v1.1`) and a GitHub release
named `OpenFan <version>`; the app is source-only, so no binary is attached.

## Reporting a problem

Open an issue with your Mac model, macOS version and the `OpenFanProbe` output. For a security problem do not open a
public issue: see [SECURITY.md](SECURITY.md).

## License

By contributing you agree that your contribution is licensed under the [MIT License](LICENSE).

# Security policy

FreeFan includes a helper that runs as root and writes to the SMC on behalf of the logged-in user, so security
reports matter here.

## Reporting

Report vulnerabilities privately through GitHub: open the **Security** tab of the repository and choose **Report a
vulnerability**. Please do not open a public issue for one. Say which macOS version and Mac model you used, what you
did and what happened; a proof of concept helps.

This is a small project maintained in spare time. Expect an acknowledgement within a few days and a fix as soon as
it can be verified, but there is no guaranteed timeline.

## What counts

- Anyone other than root and the installing user being able to talk to the helper (the peer-uid check in
  `Sources/FreeFanHelper/SocketServer.swift`).
- Any way to make the helper write an SMC value outside the guarded set (`F{n}Tg` within `[Mn, Mx]`, `F{n}md`), or to
  leave a fan under manual control after its client is gone.
- Anything that turns the installer (`scripts/install-helper.sh`, or **Install Helper** in the app) into a privilege
  escalation.

## What does not

- Anything that needs root or physical access to the Mac already.
- Behaviour on a Mac that has not been verified; see [docs/hardware](docs/hardware/README.md).

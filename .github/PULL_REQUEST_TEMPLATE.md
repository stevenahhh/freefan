## What and why

<!-- What changes, and the reason. If it is a fix, what was wrong. -->

## How it was checked

<!-- What you ran and what you saw. A claim about speed or memory needs the numbers and the method. -->

- [ ] `CoreCheck` and `ControlCheck` pass (and `SMCCheck` if the SMC layer changed)
- [ ] I ran the app and looked at the change

## Checklist

- [ ] Atomic commits: one logical change each, the reason in the body
- [ ] No safety guard weakened, or the change is explained and covered by a check
- [ ] Nothing personal in the diff, the description or the screenshots

Adding support for a Mac? Use the hardware template: add `?template=hardware-support.md` to this page's URL, or see
[docs/hardware](../docs/hardware/README.md).

# Backlog — diskwarden

Single source of truth for what is planned. Items keep a stable `DW-n` id so commits,
the CHANGELOG and the issues can reference them.

[ROADMAP.md](ROADMAP.md) is a **generated** view of this file. Do not edit it by hand —
run the regenerate command after touching this file, or CI fails. The GitHub issues are
another generated view, synced one way.

## v0.1.0 — A tool that does not delete the wrong thing <!-- ms: phase=now -->

The first release: threshold tiers, a dry run you can trust, and tests that prove the
refusals rather than the deletions.

- [x] **DW-1 — Threshold tiers**: below the routine threshold do nothing at all,
  including logging; routine between the two; emergency at or above the second.
  <!-- dw: prio=high size=M labels=script ver=0.1.0 -->
- [x] **DW-2 — Dry run by default**: `--apply` is the only path to a destructive
  call, and it lives in the systemd unit rather than in any config key.
  <!-- dw: prio=high size=S labels=safety ver=0.1.0 -->
- [x] **DW-3 — Truncate active files, never delete them**: a process holding the
  inode keeps writing to it, so a delete does not return the space and `df` stays
  full while `du` looks fine. <!-- dw: prio=high size=S labels=safety ver=0.1.0 -->
- [x] **DW-4 — Behaviour tests against a fake tree**: 21 cases, proving what it
  refuses to do — below threshold nothing moves, a dry run modifies nothing at any
  usage, routine never removes an active log, emergency truncates without deleting.
  <!-- dw: prio=high size=M labels=safety ver=0.1.0 -->
- [x] **DW-5 — Ansible role**: installs the script by copy rather than template, so
  one file is the source of truth and the script stays runnable without Ansible;
  ships disarmed. <!-- dw: prio=high size=M labels=role ver=0.1.0 -->
- [x] **DW-6 — The role and the script agree**: a test that writes a config through
  the role and asserts the script honours the exact value, because a renamed variable
  fails silently into a default. <!-- dw: prio=high size=S labels=role ver=0.1.0 -->
- [x] **DW-7 — Generated project page**: defaults, modules and test counts read out
  of the source, so the page cannot document a default that does not exist.
  <!-- dw: prio=med size=M labels=docs ver=0.1.0 -->
- [x] **DW-8 — ansible-lint as a gate**: at the `production` profile, pinned in
  `.ansible-lint` so a new release cannot pass by lowering the bar.
  <!-- dw: prio=med size=S labels=role ver=0.1.0 -->

## v0.2.0 — The gaps v0.1.0 shipped with <!-- ms: phase=next -->

Three of these are honest limitations of 0.1.0 rather than new ideas, and they are
written down because a limitation nobody recorded becomes a surprise.

- [ ] **DW-9 — The dry run cannot estimate every module**: `journalctl --vacuum`,
  `apt-get clean` and `docker prune` report "would run" with no byte figure, because
  the only way to know is to run them. The file-based modules do give real numbers.
  Either find a per-tool estimate or say so in the output, which is honest but less
  useful. <!-- dw: prio=high size=M labels=safety -->
- [x] **DW-10 — The containers module is tested**: 17 cases against a fake
  container CLI that records invocations instead of performing them. They assert
  what is never issued — no `docker volume prune` in any mode — and that only
  `runner-*-cache-*` volumes are removed, with a data volume and a build volume
  in the fixture to prove it. The suite strips every real docker and podman from
  PATH and refuses to run if one is still reachable.
  <!-- dw: prio=high size=M labels=safety ver=main -->
- [ ] **DW-18 — Containers tested against a real daemon**: the fake CLI proves the
  decision logic, not that the commands are valid. A job with a real daemon, a
  throwaway data volume and a fake runner cache volume would prove both, and would
  catch a flag that a future Docker release stops accepting.
  <!-- dw: prio=med size=M labels=safety -->
- [ ] **DW-11 — `df` lies on copy-on-write filesystems**: on btrfs and ZFS, free
  space and reclaimable space are different questions, and snapshots hold deleted
  data. The thresholds would fire late or never. Detect the filesystem and either
  handle it or refuse it loudly. <!-- dw: prio=med size=L labels=script -->
- [ ] **DW-12 — Machine-readable output**: `--json` with what was freed per module,
  so a run can be scraped rather than grepped out of a log line.
  <!-- dw: prio=med size=S labels=script -->
- [ ] **DW-13 — Watch more than one filesystem**: `/` and `/var` are often separate,
  and today that means two timers and two configs.
  <!-- dw: prio=med size=M labels=script -->
- [ ] **DW-14 — Molecule tests for the role**: the role is tested by running it
  against localhost, which does not cover the systemd path at all.
  <!-- dw: prio=low size=M labels=role -->

## v0.3.0 — Easy to get <!-- ms: phase=later -->

- [ ] **DW-15 — Homebrew tap**: diskwarden is a single script with no dependencies,
  which is the easy case. <!-- dw: prio=low size=S labels=packaging -->
- [ ] **DW-16 — deb and rpm**: with the systemd units and a config in `/etc`, so a
  distribution install is one command. <!-- dw: prio=low size=M labels=packaging -->
- [ ] **DW-17 — Publish the role to Ansible Galaxy**: `meta/main.yml` is already
  shaped for it. <!-- dw: prio=low size=S labels=packaging -->

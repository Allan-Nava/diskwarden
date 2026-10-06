# Changelog

Notable changes, newest first. Keep a Changelog, SemVer.

## [0.1.0] — 2026-10-06

First release. Extracted from an Ansible role that had been running hourly on a
production fleet, rewritten as a standalone script with a safety default the
original did not have.

### Added
- Threshold tiers: below the routine threshold nothing happens at all, including
  logging; routine between the two; emergency at or above the second, where
  active files are truncated rather than deleted. (`DW-1`)
- Dry run by default. `--apply` is the only path to a destructive call and it
  lives in the systemd unit, not in any config key — there is no setting that
  turns deletion on. (`DW-2`)
- Six reclaimers — logs, journal, package caches, `/tmp`, crash dumps,
  containers — each a no-op when the thing it manages is absent, so one config
  works across a mixed fleet.
- Ansible role that **copies** the script rather than templating it, keeping one
  source of truth and leaving the script runnable and testable without Ansible.
  Ships disarmed. (`DW-5`)
- 21 behaviour tests and 9 role tests. They prove the refusals, not the
  deletions: below threshold nothing moves, a dry run modifies nothing at any
  usage level, routine never removes an active log, emergency truncates without
  deleting, and the role's variable names still match the script's config keys.
  (`DW-4`, `DW-6`)
- Project page generated from the source, so it cannot document a default that
  does not exist. (`DW-7`)
- `ansible-lint` as a gate at the `production` profile, pinned so a new release
  cannot pass by lowering the bar. (`DW-8`)

### Known limitations
Recorded rather than discovered later — all three are in the backlog for 0.2.0.
- The dry run cannot estimate what `journalctl --vacuum`, `apt-get clean` or
  `docker prune` would free; it reports *"would run"*. (`DW-9`)
- The containers module has no tests — the suite has no Docker daemon. (`DW-10`)
- `df` reports differently on copy-on-write filesystems, so on btrfs and ZFS the
  thresholds would fire late or never. (`DW-11`)

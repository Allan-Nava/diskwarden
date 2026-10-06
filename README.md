# diskwarden

Reclaim disk space on a Linux server when a filesystem crosses a threshold —
and not a moment before.

```
$ diskwarden --mountpoint /
2026-10-06T09:12:03Z [INFO] 62% of / used, below 70% — nothing to do
```

```
$ diskwarden
2026-10-06T14:40:11Z [INFO] === ROUTINE — 74% used, free 21GiB, DRY RUN ===
2026-10-06T14:40:11Z [INFO] would remove 1184 file(s), 6.1GiB — archived logs older than 5d
2026-10-06T14:40:12Z [INFO] would remove 61 file(s), 2.4GiB — rotated logs older than 7d
2026-10-06T14:40:12Z [INFO] would run: journalctl --vacuum-time=5d
2026-10-06T14:40:12Z [INFO] would run: docker image prune (older than 5d)
2026-10-06T14:40:12Z [INFO] === dry run complete — nothing was modified. Re-run with --apply ===
```

## It is not a logrotate

logrotate rotates **configured log files** on a **schedule**. diskwarden
watches a filesystem's **usage percentage** and acts only when it has to,
across everything that quietly fills a server:

| | logrotate | diskwarden |
|---|---|---|
| trigger | time, or a size you configured per file | the filesystem crossing a threshold |
| scope | log files you listed | logs, journal, package cache, `/tmp`, crash dumps, container images and build caches |
| active files | rotates them, carefully | leaves them alone — until an emergency threshold, where it **truncates** |
| unknown files | ignores them | `*.log.<suffix>` anywhere under `/var/log` is a rotated copy, no config needed |

They are complements, not alternatives. Keep logrotate. diskwarden is for the
night it was not enough.

## Two thresholds

```
      < 70 %   nothing happens. No logging, no work, no risk.

  70 – 79 %   ROUTINE
              archived and rotated logs, journal vacuum, package cache,
              old /tmp files, crash dumps, orphaned container images,
              CI runner cache volumes

      ≥ 80 %   ROUTINE, and then:
              truncate active log files over 300 MB
              truncate container JSON logs over 100 MB
```

Both numbers are configurable. The gap between them matters: routine work is
safe enough to run hourly and unattended, truncating a file somebody is
writing to is not, and the two should not share a trigger.

## Install

```bash
sudo install -m 0755 diskwarden /usr/local/sbin/diskwarden
sudo install -m 0644 diskwarden.conf.example /etc/diskwarden.conf
sudo $EDITOR /etc/diskwarden.conf

# Look at what it would do, on the real machine, before anything is scheduled.
sudo diskwarden

# Only when you agree with the plan:
sudo install -m 0644 systemd/diskwarden.* /etc/systemd/system/
sudo systemctl enable --now diskwarden.timer
```

`--apply` lives in the systemd unit and nowhere else. There is no config key
that turns deletion on, and no default that deletes. The only way diskwarden
removes a file is a unit you installed on purpose.

## Four things it knows that a one-line `find` does not

**Truncate active files, never delete them.** A process holding a log open
keeps writing to the inode after you delete it, so the space is not returned
until it restarts. `df` stays full while `du` looks fine, and only
`lsof +L1` explains why. Deleting a 40 GB log that a running service owns is
how you turn a disk alert into an outage.

**An active log ends in `.log`; anything with a suffix after it is a copy.**
`app.log` is being written. `app.log.2026-10-01`, `app.log.3`, `app.log.gz`
are not. That one rule removes rotated logs that no logrotate config covers
— the ones an application rotates itself, into a directory nobody declared —
without ever touching a live file.

**`docker volume prune` is too wide.** It is happy to take a database volume
with it. CI runner caches are removed **by name** instead
(`runner-*-cache-*`), and one attached to a running job simply fails to
remove, which is the correct outcome.

**Below the threshold, do nothing — including logging.** A cleanup tool that
writes a line every hour to say it had nothing to do is a cleanup tool that
fills the disk it is watching.

## Testing

```bash
bash test/run-tests.sh
```

The tests do not prove it deletes files. That is easy, and most people manage
it by accident. They prove the opposite:

- below the threshold, nothing is touched **and** nothing is logged
- without `--apply`, nothing is modified — ever, at any usage level
- routine mode removes rotated copies and leaves **every active log** intact
- emergency mode **truncates** active files and still never deletes one
- an explicit flag beats the config file

A cleanup tool whose dry run you cannot trust is worse than no cleanup tool.

Run it against a fake tree yourself:

```bash
diskwarden --root /tmp/fake-server --usage 95 --modules "logs tmp"
```

`--root` prefixes every path and `--usage` overrides the measurement, so you
can reproduce a full disk without having one.

## Modules

Each reclaimer is a no-op when the thing it manages is not installed, so one
config works across a mixed fleet.

| module | what it reclaims |
|---|---|
| `logs` | archived and rotated logs under `/var/log`, plus any `EXTRA_LOG_DIRS` |
| `journal` | `journalctl --vacuum-time` |
| `packages` | apt / dnf / yum caches |
| `tmp` | old files in `/tmp`, then empty directories |
| `crashdumps` | `/var/crash`, `/var/lib/systemd/coredump` |
| `containers` | Docker or Podman images, containers, build cache; CI runner cache volumes by name |

Adding one is a shell function called `reclaim_<name>` and a word in
`MODULES`.

## Status

Extracted from an Ansible role that has been running hourly on a production
fleet, rewritten as a standalone script with a dry-run default, a config file
instead of templating, and the test suite above.

The reclaim logic is the same logic. The packaging, the safety default and
the tests are new, and the fleet-specific parts (a particular CI server's
cache layout, a particular monitoring agent's logrotate) were dropped rather
than generalised — they belong in `EXTRA_LOG_DIRS` or in your own module.

MIT. Issues and pull requests welcome.

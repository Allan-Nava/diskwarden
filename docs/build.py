#!/usr/bin/env python3
"""
Build the project page into site/.

Every number and every module name on the page is read out of `diskwarden`
and the Ansible defaults, and the test counts come from actually running the
suites. A documentation page that restates a default by hand is wrong the
first time somebody changes one, and nobody notices because nothing fails.

Usage:  python3 docs/build.py [outdir]
"""

import html
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(ROOT, "diskwarden")
ROLE_DEFAULTS = os.path.join(ROOT, "ansible", "roles", "diskwarden",
                             "defaults", "main.yml")
LINT_CONFIG = os.path.join(ROOT, ".ansible-lint")
REPO = "https://github.com/Allan-Nava/diskwarden"


def e(x):
    return html.escape(str(x))


# ----------------------------------------------------------------- reading --
def script_defaults():
    """The defaults block, with the comment that explains each one."""
    text = open(SCRIPT, encoding="utf-8").read()
    block = text.split("# ---------------------------------------------------------------- defaults --", 1)[1]
    block = block.split("# Set by flags", 1)[0]
    out = []
    for line in block.splitlines():
        m = re.match(r'^(\w+)=(.*?)\s*(?:#\s*(.*))?$', line.strip())
        if not m:
            continue
        name, value, note = m.group(1), m.group(2).strip(), (m.group(3) or "")
        out.append((name, value.strip('"'), note))
    return out


def modules():
    """Module name -> the first comment line inside its function, if any."""
    text = open(SCRIPT, encoding="utf-8").read()
    found = []
    for m in re.finditer(r'^reclaim_(\w+)\(\)\s*\{', text, re.M):
        found.append(m.group(1))
    return found


def script_version():
    text = open(SCRIPT, encoding="utf-8").read()
    m = re.search(r'^VERSION="([^"]+)"', text, re.M)
    return m.group(1) if m else "?"


def role_vars():
    out = []
    for line in open(ROLE_DEFAULTS, encoding="utf-8"):
        m = re.match(r'^(diskwarden_\w+):\s*(.*?)\s*(?:#\s*(.*))?$', line.rstrip())
        if m:
            out.append((m.group(1), m.group(2), m.group(3) or ""))
    return out


def lint_profile():
    """The enforced ansible-lint profile, read rather than claimed."""
    try:
        for line in open(LINT_CONFIG, encoding="utf-8"):
            m = re.match(r'^profile:\s*(\w+)', line)
            if m:
                return m.group(1)
    except OSError:
        pass
    return None


def run_suite(path):
    """Run a test suite and return (passed, failed, ran)."""
    try:
        p = subprocess.run(["bash", path], cwd=ROOT, capture_output=True,
                           text=True, timeout=300)
    except Exception:
        return 0, 0, False
    m = re.search(r'RESULT: (\d+) passed, (\d+) failed', p.stdout)
    if not m:
        return 0, 0, False
    return int(m.group(1)), int(m.group(2)), True


# ------------------------------------------------------------------ markup --
CSS = """
:root{--bg:#fbfbfa;--panel:#fff;--ink:#1b1b19;--muted:#6b6b66;--line:#e4e3df;
  --accent:#2f6f4f;--warn:#8a4b2a;
  --mono:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace}
@media (prefers-color-scheme:dark){:root{--bg:#141413;--panel:#1c1c1a;
  --ink:#ecebe6;--muted:#9b9a93;--line:#2e2e2b;--accent:#78bd97;--warn:#d29468}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);
  font:16px/1.65 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;
  -webkit-font-smoothing:antialiased}
.wrap{max-width:900px;margin:0 auto;padding:0 20px}
header{border-bottom:1px solid var(--line);padding:56px 0 36px}
h1{font-size:2.2rem;margin:.3em 0 .25em;letter-spacing:-.02em}
h2{font-size:1.3rem;margin:2.4em 0 .4em;letter-spacing:-.01em}
h3{font-size:1rem;margin:1.8em 0 .3em}
p,li{max-width:66ch}
.sub{color:var(--muted);margin:0}
a{color:var(--accent)}
.bar{display:flex;gap:10px;flex-wrap:wrap;margin-top:22px}
.btn{display:inline-block;padding:7px 13px;border:1px solid var(--line);
  border-radius:7px;background:var(--panel);color:var(--ink);
  text-decoration:none;font-size:.86rem}
.btn:hover{border-color:var(--accent);color:var(--accent)}
.btn.primary{background:var(--accent);border-color:var(--accent);color:#fff}
pre{background:var(--panel);border:1px solid var(--line);border-radius:9px;
  padding:14px 16px;overflow:auto;font-family:var(--mono);font-size:.82rem;
  line-height:1.5}
code{font-family:var(--mono);font-size:.88em}
table{width:100%;border-collapse:collapse;margin:14px 0;font-size:.88rem}
th,td{text-align:left;padding:7px 12px 7px 0;border-bottom:1px solid var(--line);
  vertical-align:top}
th{color:var(--muted);font-weight:500;font-size:.8rem}
td.mono,td code{font-family:var(--mono);font-size:.82rem}
.tiers{background:var(--panel);border:1px solid var(--line);border-radius:9px;
  padding:4px 18px;margin:16px 0}
.tier{display:flex;gap:16px;padding:12px 0;border-bottom:1px solid var(--line)}
.tier:last-child{border-bottom:0}
.tier b{font-family:var(--mono);font-size:.84rem;white-space:nowrap;min-width:9em}
.note{border-left:3px solid var(--warn);padding:2px 0 2px 15px;margin:18px 0;
  color:var(--muted)}
.pill{display:inline-block;font-size:.74rem;padding:2px 9px;border-radius:20px;
  border:1px solid var(--accent);color:var(--accent)}
footer{border-top:1px solid var(--line);margin-top:60px;padding:24px 0 56px;
  color:var(--muted);font-size:.84rem}
"""


def build(outdir):
    defaults = dict((n, v) for n, v, _ in script_defaults())
    mods = modules()
    ver = script_version()
    rvars = role_vars()

    profile = lint_profile()
    sp, sf, sran = run_suite(os.path.join(ROOT, "test", "run-tests.sh"))
    ap, af, aran = run_suite(os.path.join(ROOT, "test", "run-ansible-tests.sh"))

    routine = defaults.get("ROUTINE_THRESHOLD", "?")
    emerg = defaults.get("EMERGENCY_THRESHOLD", "?")

    rows = "".join(
        f"<tr><td class='mono'>{e(n)}</td><td class='mono'>{e(v)}</td>"
        f"<td>{e(note)}</td></tr>"
        for n, v, note in script_defaults())

    rrows = "".join(
        f"<tr><td class='mono'>{e(n)}</td><td class='mono'>{e(v)}</td>"
        f"<td>{e(note)}</td></tr>"
        for n, v, note in rvars)

    mod_rows = "".join(f"<tr><td class='mono'>{e(m)}</td></tr>" for m in mods)

    badges = []
    if sran:
        badges.append(f'<span class="pill">{sp} behaviour tests passing</span>')
    if aran:
        badges.append(f'<span class="pill">{ap} role tests passing</span>')
    if profile:
        badges.append(f'<span class="pill">ansible-lint: {e(profile)}</span>')
    badge_html = " ".join(badges)

    page = f"""<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>diskwarden — threshold-driven disk reclaim</title>
<meta name="description" content="Reclaim disk space on a Linux server when a
filesystem crosses a threshold. Not a logrotate: usage-driven, covers logs,
journal, package caches and container images, and truncates active files
instead of deleting them.">
<style>{CSS}</style>
</head><body>

<header><div class="wrap">
<img src="logo.svg" width="64" height="64" alt="">
<h1>diskwarden</h1>
<p class="sub">Reclaim disk space on a Linux server when a filesystem crosses
a threshold — and not a moment before.</p>
<div class="bar">
<a class="btn primary" href="{REPO}">Repository</a>
<a class="btn" href="{REPO}#install">Install</a>
<a class="btn" href="{REPO}/blob/main/ROADMAP.md">Roadmap</a>
<a class="btn" href="{REPO}/blob/main/LICENSE">MIT</a>
</div>
<p style="margin-top:18px">{badge_html} <span class="pill">v{e(ver)}</span></p>
</div></header>

<div class="wrap">

<h2>It is not a logrotate</h2>
<p>logrotate rotates <strong>configured log files</strong> on a
<strong>schedule</strong>. diskwarden watches a filesystem's <strong>usage
percentage</strong> and acts only when it has to, across everything that
quietly fills a server: logs, the journal, package caches,
<code>/tmp</code>, crash dumps, orphaned container images and build caches.</p>
<p>They are complements, not alternatives. Keep logrotate. diskwarden is for
the night it was not enough.</p>

<h2>Two thresholds</h2>
<div class="tiers">
  <div class="tier"><b>&lt; {e(routine)}%</b><span>Nothing happens. No work,
  no logging, no risk — a cleanup tool that writes a line every hour fills
  the disk it is watching.</span></div>
  <div class="tier"><b>{e(routine)} – {int(emerg) - 1 if emerg.isdigit() else '?'}%</b><span><strong>Routine.</strong>
  Archived and rotated logs, journal vacuum, package caches, old
  <code>/tmp</code> files, crash dumps, orphaned container images, CI runner
  cache volumes. Safe enough to run unattended.</span></div>
  <div class="tier"><b>&ge; {e(emerg)}%</b><span><strong>Emergency.</strong>
  Routine, and then active log files over
  {e(defaults.get("ACTIVE_LOG_TRUNCATE_MB", "?"))} MB and container JSON logs
  over {e(defaults.get("CONTAINER_JSON_TRUNCATE_MB", "?"))} MB are
  <em>truncated</em> — never deleted.</span></div>
</div>

<h2>Dry run unless you ask</h2>
<pre>$ diskwarden
[INFO] === ROUTINE — 74% used, free 21GiB, DRY RUN ===
[INFO] would remove 1184 file(s), 6.1GiB — archived logs older than 5d
[INFO] would run: journalctl --vacuum-time=5d
[INFO] === dry run complete — nothing was modified. Re-run with --apply ===</pre>
<p><code>--apply</code> lives in the systemd unit and nowhere else. There is
no config key that turns deletion on, and no default that deletes.</p>

<h2>Four things it knows that a one-line <code>find</code> does not</h2>

<h3>Truncate active files, never delete them</h3>
<p>A process holding a log open keeps writing to the inode after you delete
it, so the space is not returned until it restarts. <code>df</code> stays
full while <code>du</code> looks fine, and only <code>lsof +L1</code>
explains why. Deleting a 40&nbsp;GB log that a running service owns turns a
disk alert into an outage.</p>

<h3>An active log ends in <code>.log</code></h3>
<p>Anything with a suffix after it — <code>app.log.2026-10-01</code>,
<code>app.log.3</code>, <code>app.log.gz</code> — is a copy. That one rule
removes rotated logs no logrotate config covers, the ones an application
rotates itself into a directory nobody declared, without ever touching a live
file.</p>

<h3><code>docker volume prune</code> is too wide</h3>
<p>It is happy to take a database volume with it. CI runner caches are removed
<strong>by name</strong> instead, and one attached to a running job simply
fails to remove — which is the correct outcome.</p>

<h3>Below the threshold, do nothing at all</h3>
<p>Including logging. The quietest tool on the box until the moment it is
needed.</p>

<h2>Modules</h2>
<p>Each reclaimer is a no-op when the thing it manages is not installed, so
one configuration works across a mixed fleet. Adding one is a shell function
called <code>reclaim_&lt;name&gt;</code> and a word in <code>MODULES</code>.</p>
<table><tr><th>module</th></tr>{mod_rows}</table>

<h2>Configuration</h2>
<p>Read out of the script, so this table cannot drift from the defaults it
documents.</p>
<table><tr><th>key</th><th>default</th><th>note</th></tr>{rows}</table>

<h2>Ansible</h2>
<p>The role installs the script, writes the config and optionally schedules
it. The script is <strong>copied, not templated</strong>: the file in the
repository is the file on the host, byte for byte, so it stays runnable and
testable without Ansible.</p>
<pre>- role: diskwarden
  vars:
    diskwarden_routine_threshold: 70
    diskwarden_extra_log_dirs: [/opt/myapp/logs]
    diskwarden_enabled: false   # install now, arm later</pre>
<p class="note">The role ships disarmed. Installing diskwarden and arming it
are two decisions, and the second one should follow a dry run on a real
host.</p>
<table><tr><th>variable</th><th>default</th><th>note</th></tr>{rrows}</table>

<h2>Tests</h2>
<p>They do not prove it deletes files — that is easy, and most people manage
it by accident. They prove the opposite: that below the threshold nothing is
touched, that without <code>--apply</code> nothing is modified at any usage
level, that routine mode never removes an active log, and that emergency mode
truncates without ever deleting one.</p>
<p>The role suite checks the thing that silently breaks: that the role's
variable names and the script's config keys still agree. Rename one side and
nothing errors — the config is written, the script sources it, and the
default quietly applies instead of your value.</p>
<pre>bash test/run-tests.sh          # {sp if sran else '?'} passing
bash test/run-ansible-tests.sh  # {ap if aran else '?'} passing
ansible-lint ansible/           # profile: {e(profile) if profile else '?'}</pre>
<p>ansible-lint is a gate rather than advice, and the profile is pinned in
<code>.ansible-lint</code>. Without pinning it, the strictness would be
whatever the installed version defaults to — a green run would then mean
&ldquo;the bar moved&rdquo;, not &ldquo;the code is fine&rdquo;.</p>

</div>
<footer><div class="wrap">
Generated from the source by
<a href="{REPO}/blob/main/docs/build.py">docs/build.py</a> — every default and
module on this page is read out of the script, and the test counts come from
running the suites. · <a href="{REPO}">source</a> · MIT
</div></footer>
</body></html>
"""

    os.makedirs(outdir, exist_ok=True)
    src_logo = os.path.join(ROOT, "assets", "logo.svg")
    if os.path.exists(src_logo):
        import shutil
        shutil.copy2(src_logo, os.path.join(outdir, "logo.svg"))
    with open(os.path.join(outdir, "index.html"), "w", encoding="utf-8") as fh:
        fh.write(page)
    open(os.path.join(outdir, ".nojekyll"), "w").close()
    print(f"wrote {outdir}/index.html — {len(mods)} modules, "
          f"{len(defaults)} defaults, {len(rvars)} role variables, "
          f"tests {sp}/{sp + sf} and {ap}/{ap + af}")
    return 0


if __name__ == "__main__":
    sys.exit(build(sys.argv[1] if len(sys.argv) > 1
                   else os.path.join(ROOT, "site")))

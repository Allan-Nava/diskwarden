#!/usr/bin/env bash
#
# Tests for the Ansible role.
#
# The one that matters is the last: that the role's variable names and the
# script's config keys still agree. Rename a variable on one side and nothing
# errors — the config is written, the script sources it, and the default
# silently applies instead of your value. Only running both catches it.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$HERE/.."
PASS=0; FAIL=0
ok()  { printf '  [PASS] %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  [FAIL] %s\n' "$1"; [[ -n "${2:-}" ]] && printf '         %s\n' "$2"; FAIL=$((FAIL+1)); }

command -v ansible-playbook >/dev/null 2>&1 || { echo "ansible-playbook not found — skipping"; exit 0; }

TMP="$(mktemp -d)"; PLAY="$TMP/play.yml"
trap 'rm -rf "$TMP"' EXIT

cat > "$PLAY" <<EOF
---
- hosts: localhost
  connection: local
  gather_facts: false
  become: false
  roles:
    - role: diskwarden
      vars:
        diskwarden_script_path: $TMP/diskwarden
        diskwarden_config_path: $TMP/diskwarden.conf
        diskwarden_log_path: $TMP/diskwarden.log
        diskwarden_scheduler: none
        diskwarden_owner: $(id -un)
        diskwarden_group: $(id -gn)
        diskwarden_routine_threshold: 65
        diskwarden_emergency_threshold: 77
        diskwarden_tmp_days: 3
        diskwarden_extra_log_dirs: ["/opt/app/logs", "/srv/x/log"]
EOF

echo "== the role runs clean =="
if ANSIBLE_ROLES_PATH="$REPO/ansible/roles" ansible-playbook "$PLAY" >"$TMP/out" 2>&1; then
    ok "playbook completed"
else
    bad "playbook completed" "$(tail -5 "$TMP/out")"
fi

echo "== what it installed =="
if diff -q "$TMP/diskwarden" "$REPO/diskwarden" >/dev/null 2>&1; then
    ok "installed script is byte-identical to the repository"
else
    bad "installed script is byte-identical to the repository" \
        "the role must copy the script, never template it"
fi
grep -q 'ROUTINE_THRESHOLD=65'   "$TMP/diskwarden.conf" && ok "threshold written" || bad "threshold written"
grep -q 'EMERGENCY_THRESHOLD=77' "$TMP/diskwarden.conf" && ok "emergency threshold written" || bad "emergency threshold written"
grep -q 'TMP_DAYS=3'             "$TMP/diskwarden.conf" && ok "retention written" || bad "retention written"
grep -q 'EXTRA_LOG_DIRS=("/opt/app/logs" "/srv/x/log")' "$TMP/diskwarden.conf" \
    && ok "extra log dirs rendered as a bash array" || bad "extra log dirs rendered as a bash array" "$(grep EXTRA "$TMP/diskwarden.conf")"

echo "== the script actually honours what the role wrote =="
# Below the role's threshold of 65 but above the script's default of 70:
# if the config were ignored, the script would say it has work to do.
out="$(bash "$TMP/diskwarden" --config "$TMP/diskwarden.conf" --usage 67 2>&1)"
if grep -q "ROUTINE" <<<"$out"; then
    ok "role threshold reached the script (67% > 65%)"
else
    bad "role threshold reached the script" "$out"
fi
out="$(bash "$TMP/diskwarden" --config "$TMP/diskwarden.conf" --usage 60 2>&1)"
if grep -q "below 65%" <<<"$out"; then
    ok "and the exact value, not a default"
else
    bad "and the exact value, not a default" "$out"
fi

echo "== nothing is armed unless asked =="
if grep -rq "diskwarden_enabled: false" "$REPO/ansible/roles/diskwarden/defaults/main.yml"; then
    ok "the role ships disarmed"
else
    bad "the role ships disarmed" "installing and arming must be two decisions"
fi

echo
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]

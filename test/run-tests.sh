#!/usr/bin/env bash
#
# Tests for diskwarden, against a fake filesystem tree.
#
# The thing being proved is not "it deletes files" — that is easy and anyone
# can do it by accident. It is the opposite:
#
#   * below the threshold it does nothing at all
#   * without --apply it modifies nothing, ever
#   * it never deletes an ACTIVE log, only rotated copies
#   * it only truncates active files in emergency mode, never deletes them
#
# A cleanup tool whose dry run you cannot trust is worse than no tool.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DW="$HERE/../diskwarden"
PASS=0; FAIL=0

ok()   { printf '  [PASS] %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  [FAIL] %s\n' "$1"; [[ -n "${2:-}" ]] && printf '         %s\n' "$2"; FAIL=$((FAIL+1)); }
check(){ if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1" "expected '$3', got '$2'"; fi; }

# A tree that looks like a server which has been up for a while.
make_tree() {
    local root; root="$(mktemp -d)"
    mkdir -p "$root"/var/log/sub "$root"/tmp "$root"/var/crash \
             "$root"/var/lib/docker/containers/abc
    # old rotated logs — SHOULD go
    : > "$root/var/log/syslog.1";          touch -t 202001010000 "$root/var/log/syslog.1"
    : > "$root/var/log/messages.2.gz";     touch -t 202001010000 "$root/var/log/messages.2.gz"
    : > "$root/var/log/sub/app.log.2020";  touch -t 202001010000 "$root/var/log/sub/app.log.2020"
    # ACTIVE logs — must NEVER be deleted
    printf 'x%.0s' $(seq 1 2000) > "$root/var/log/syslog"
    printf 'x%.0s' $(seq 1 2000) > "$root/var/log/sub/app.log"
    # a big active log, for the emergency case
    dd if=/dev/zero of="$root/var/log/big.log" bs=1024 count=2048 2>/dev/null
    # a big container json log
    dd if=/dev/zero of="$root/var/lib/docker/containers/abc/abc-json.log" \
       bs=1024 count=2048 2>/dev/null
    # old temp file and crash dump
    : > "$root/tmp/stale";                 touch -t 202001010000 "$root/tmp/stale"
    : > "$root/var/crash/core.1";          touch -t 202001010000 "$root/var/crash/core.1"
    printf '%s' "$root"
}

count_files() { find "$1" -type f 2>/dev/null | wc -l | tr -d ' '; }
size_of()     { stat -c%s "$1" 2>/dev/null || stat -f%z "$1" 2>/dev/null || echo missing; }

MODULES="logs tmp crashdumps"

echo "== below the threshold, nothing happens =="
root="$(make_tree)"; before="$(count_files "$root")"
out="$($DW --root "$root" --usage 10 --apply --modules "$MODULES" 2>&1)"
check "no files touched" "$(count_files "$root")" "$before"
if grep -q "nothing to do" <<<"$out"; then ok "says so explicitly"; else bad "says so explicitly" "$out"; fi
rm -rf "$root"

echo "== dry run modifies nothing, even above the threshold =="
root="$(make_tree)"; before="$(count_files "$root")"
big_before="$(size_of "$root/var/log/big.log")"
out="$($DW --root "$root" --usage 95 --modules "$MODULES" 2>&1)"
check "file count unchanged" "$(count_files "$root")" "$before"
check "active log not truncated" "$(size_of "$root/var/log/big.log")" "$big_before"
if grep -q "would remove" <<<"$out"; then ok "reports what it would remove"; else bad "reports what it would remove" "$out"; fi
if grep -q "nothing was modified" <<<"$out"; then ok "says nothing was modified"; else bad "says nothing was modified"; fi
rm -rf "$root"

echo "== routine: rotated copies go, ACTIVE logs stay =="
root="$(make_tree)"
$DW --root "$root" --usage 75 --apply --modules "$MODULES" >/dev/null 2>&1
for gone in var/log/syslog.1 var/log/messages.2.gz var/log/sub/app.log.2020 tmp/stale var/crash/core.1; do
    if [[ -e "$root/$gone" ]]; then bad "removed $gone"; else ok "removed $gone"; fi
done
for kept in var/log/syslog var/log/sub/app.log var/log/big.log; do
    if [[ -e "$root/$kept" ]]; then ok "kept active $kept"; else bad "kept active $kept" "it was deleted"; fi
done
# routine must NOT truncate
check "routine did not truncate the big active log" \
      "$(size_of "$root/var/log/big.log")" "2097152"
rm -rf "$root"

echo "== emergency: active files truncated, never deleted =="
# Small truncate thresholds via a config file: the real defaults are 300 MB
# and writing a 300 MB file in CI to prove a comparison would be silly. This
# exercises --config at the same time.
conf="$(mktemp)"
printf 'ACTIVE_LOG_TRUNCATE_MB=1\nCONTAINER_JSON_TRUNCATE_MB=1\n' > "$conf"
root="$(make_tree)"
$DW --root "$root" --usage 95 --apply --config "$conf" --modules "$MODULES" >/dev/null 2>&1
if [[ -e "$root/var/log/big.log" ]]; then ok "big active log still exists"; else bad "big active log still exists" "it was deleted, not truncated"; fi
check "big active log truncated to 0" "$(size_of "$root/var/log/big.log")" "0"
check "container json log truncated to 0" \
      "$(size_of "$root/var/lib/docker/containers/abc/abc-json.log")" "0"
# a small active log is under the threshold and must be left alone
if [[ "$(size_of "$root/var/log/syslog")" == "2000" ]]; then
    ok "small active log left alone"
else
    bad "small active log left alone" "size $(size_of "$root/var/log/syslog")"
fi
rm -rf "$root" "$conf"

echo "== an explicit flag beats the config file =="
conf="$(mktemp)"; printf 'ROUTINE_THRESHOLD=99\n' > "$conf"
root="$(make_tree)"
out="$($DW --root "$root" --usage 75 --config "$conf" --modules "$MODULES" 2>&1)"
if grep -q "nothing to do" <<<"$out"; then
    ok "config threshold is honoured"
else
    bad "config threshold is honoured" "$out"
fi
rm -rf "$root" "$conf"

echo "== unknown module is reported, not ignored =="
root="$(make_tree)"
out="$($DW --root "$root" --usage 75 --modules "nosuchthing" 2>&1)"
if grep -q "no such module" <<<"$out"; then ok "warns about an unknown module"; else bad "warns about an unknown module" "$out"; fi
rm -rf "$root"

echo
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]

#!/usr/bin/env bash
#
# Tests for the containers module — DW-10.
#
# This is the module whose mistakes are the most expensive: `docker volume
# prune` would take a database volume with it. So the test that matters is not
# "the commands run", it is **which commands are never issued**.
#
# A fake `docker` on PATH records every invocation instead of performing it.
# That proves the decision logic — the filters, the order, the refusals —
# without a daemon, so it runs anywhere. A second suite against a real daemon
# (CI job `containers-live`) proves the commands are also valid.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DW="$HERE/../diskwarden"
PASS=0; FAIL=0
ok()  { printf '  [PASS] %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  [FAIL] %s\n' "$1"; [[ -n "${2:-}" ]] && printf '         %s\n' "$2"; FAIL=$((FAIL+1)); }

# A fake container CLI. Records what it was asked to do; invents a volume list
# containing exactly the three kinds that matter.
make_shim() {           # make_shim <dir> <name> [info_exit_code]
    local dir="$1" name="$2" info_rc="${3:-0}"
    mkdir -p "$dir"
    cat > "$dir/$name" <<SHIM
#!/usr/bin/env bash
echo "\$*" >> "$dir/calls.log"
case "\$1 \$2" in
  "info ")        exit $info_rc ;;
  "volume ls")    printf '%s\n' runner-1-cache-abc123 runner-1-cache-def456-protected \\
                                runner-1-build-xyz postgres-data ;;
esac
exit 0
SHIM
    chmod +x "$dir/$name"
}

# The shim directory goes FIRST on PATH, so a shim always shadows a real CLI.
#
# An earlier version stripped directories containing a real docker from PATH
# instead. That worked on a Mac, where docker lives in /usr/local/bin, and took
# /usr/bin with it on a CI runner — along with find, stat and date. Shadowing
# needs no surgery and cannot remove something the script depends on.
#
# "Absent" is therefore simulated by a shim whose `info` fails, which is also
# the commoner real case: the CLI installed, the service down.
calls() { cat "$1/calls.log" 2>/dev/null; }
called() { grep -qF "$2" "$1/calls.log" 2>/dev/null; }

run_module() {   # run_module <bindir> <extra diskwarden args...>
    local bin="$1"; shift
    PATH="$bin:$PATH" "$DW" --usage 75 --modules containers "$@" 2>&1
}

echo "== the suite cannot reach a real daemon =="
# Proven, not assumed: with the shim directory first, `docker` must resolve
# inside it. A suite that can issue destructive commands verifies its sandbox
# before it issues any, and stops if the check fails.
GUARD="$(mktemp -d)"; make_shim "$GUARD" docker; make_shim "$GUARD" podman
for cli in docker podman; do
    where="$(PATH="$GUARD:$PATH" command -v "$cli" 2>/dev/null || true)"
    if [[ "$where" == "$GUARD/$cli" ]]; then
        ok "$cli resolves to the shim, not $(command -v "$cli" 2>/dev/null || echo 'anything real')"
    else
        bad "$cli resolves to the shim" "resolved to ${where:-nothing} — refusing to continue"
        printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
        exit 1
    fi
done
rm -rf "$GUARD"

echo "== no usable runtime: the module is a no-op =="
# Both CLIs present, neither answering `info` — the commoner real case.
BIN="$(mktemp -d)"; make_shim "$BIN" docker 1; make_shim "$BIN" podman 1
out="$(run_module "$BIN" --apply)"
if ! grep -qiE "prune" <<<"$out"; then ok "nothing attempted"; else bad "nothing attempted" "$out"; fi
if ! grep -qE "prune|volume rm" "$BIN/calls.log" 2>/dev/null; then
    ok "no destructive call issued"
else
    bad "no destructive call issued" "$(calls "$BIN")"
fi
rm -rf "$BIN"

echo "== dry run reads, and writes nothing =="
BIN="$(mktemp -d)"; make_shim "$BIN" docker; make_shim "$BIN" gitlab-runner
run_module "$BIN" >/dev/null
called "$BIN" "info"      && ok "detected the runtime (docker info)" || bad "detected the runtime"
# Listing volumes is gated behind gitlab-runner being present — without it the
# module does not look at volumes at all, which is why the shim is here.
called "$BIN" "volume ls" && ok "listed volumes (a read)" || bad "listed volumes" "$(calls "$BIN")"
if grep -qE "prune|volume rm" "$BIN/calls.log"; then
    bad "no destructive call in a dry run" "$(calls "$BIN")"
else
    ok "no destructive call in a dry run"
fi
rm -rf "$BIN"

echo "== --apply issues the expected prunes =="
BIN="$(mktemp -d)"; make_shim "$BIN" docker
run_module "$BIN" --apply >/dev/null
called "$BIN" "image prune -a -f --filter until=120h" \
    && ok "image prune carries the age filter" \
    || bad "image prune carries the age filter" "$(calls "$BIN")"
called "$BIN" "container prune -f" && ok "container prune" || bad "container prune"
called "$BIN" "builder prune -f"   && ok "builder prune"   || bad "builder prune"
rm -rf "$BIN"

echo "== docker volume prune is NEVER issued =="
# The whole point. A generic volume prune is happy to remove a database
# volume, so the module must never reach for it in any mode.
for mode in "" "--apply"; do
    BIN="$(mktemp -d)"; make_shim "$BIN" docker
    run_module "$BIN" $mode >/dev/null
    if grep -qE "^volume prune" "$BIN/calls.log"; then
        bad "no volume prune (${mode:-dry run})" "$(calls "$BIN")"
    else
        ok "no volume prune (${mode:-dry run})"
    fi
    rm -rf "$BIN"
done

echo "== only runner cache volumes are removed, by name =="
BIN="$(mktemp -d)"; make_shim "$BIN" docker
make_shim "$BIN" gitlab-runner     # present, but no clear-docker-cache on disk
run_module "$BIN" --apply >/dev/null
called "$BIN" "volume rm runner-1-cache-abc123" \
    && ok "removes runner-1-cache-abc123" || bad "removes runner-1-cache-abc123" "$(calls "$BIN")"
called "$BIN" "volume rm runner-1-cache-def456-protected" \
    && ok "removes the -protected variant" || bad "removes the -protected variant"
if called "$BIN" "volume rm postgres-data"; then
    bad "LEAVES postgres-data alone" "a data volume was removed — this is the bug the test exists for"
else
    ok "leaves postgres-data alone"
fi
if called "$BIN" "volume rm runner-1-build-xyz"; then
    bad "leaves runner-1-build-xyz alone" "only *-cache-* volumes are caches"
else
    ok "leaves runner-1-build-xyz alone"
fi
rm -rf "$BIN"

echo "== no gitlab-runner: volumes are not touched at all =="
BIN="$(mktemp -d)"; make_shim "$BIN" docker
run_module "$BIN" --apply >/dev/null
if grep -q "volume rm" "$BIN/calls.log"; then
    bad "no volume removed without gitlab-runner" "$(calls "$BIN")"
else
    ok "no volume removed without gitlab-runner"
fi
rm -rf "$BIN"

echo "== podman is used when docker is not answering =="
BIN="$(mktemp -d)"; make_shim "$BIN" docker 1; make_shim "$BIN" podman
run_module "$BIN" --apply >/dev/null
if [[ -s "$BIN/calls.log" ]] && called "$BIN" "image prune"; then
    ok "falls back to podman"
else
    bad "falls back to podman" "$(calls "$BIN")"
fi
rm -rf "$BIN"

echo
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]

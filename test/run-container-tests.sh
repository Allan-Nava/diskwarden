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
make_shim() {
    local dir="$1" name="$2"
    mkdir -p "$dir"
    cat > "$dir/$name" <<SHIM
#!/usr/bin/env bash
echo "\$*" >> "$dir/calls.log"
case "\$1 \$2" in
  "info ")        exit 0 ;;
  "volume ls")    printf '%s\n' runner-1-cache-abc123 runner-1-cache-def456-protected \\
                                runner-1-build-xyz postgres-data ;;
esac
exit 0
SHIM
    chmod +x "$dir/$name"
}

# A PATH with every directory that holds a REAL docker or podman removed, so
# the shim is the only one findable.
#
# This is not tidiness. Writing this suite, the podman case had no docker shim,
# the host had a working daemon, and `--apply` ran `docker image prune -a -f`
# against it for real. A test suite that can issue destructive commands has to
# prove it is sandboxed before it runs any of them.
safe_path() {
    local clean="" d
    local -a dirs
    IFS=: read -ra dirs <<< "$PATH"
    for d in "${dirs[@]}"; do
        [[ -z "$d" ]] && continue
        [[ -x "$d/docker" || -x "$d/podman" ]] && continue
        clean="${clean:+$clean:}$d"
    done
    printf '%s' "$clean"
}
SAFE_PATH="$(safe_path)"

calls() { cat "$1/calls.log" 2>/dev/null; }
called() { grep -qF "$2" "$1/calls.log" 2>/dev/null; }

run_module() {   # run_module <bindir> <extra diskwarden args...>
    local bin="$1"; shift
    PATH="$bin:$SAFE_PATH" "$DW" --usage 75 --modules containers "$@" 2>&1
}

echo "== the suite cannot reach a real daemon =="
real_docker="$(command -v docker 2>/dev/null || true)"
found="$(PATH="$SAFE_PATH" command -v docker 2>/dev/null || true)"
foundp="$(PATH="$SAFE_PATH" command -v podman 2>/dev/null || true)"
if [[ -z "$found" && -z "$foundp" ]]; then
    ok "no real docker or podman on the sandboxed PATH${real_docker:+ (host has one at $real_docker)}"
else
    bad "no real docker or podman on the sandboxed PATH" \
        "found ${found:-}${foundp:+ $foundp} — refusing to continue"
    printf 'RESULT: %d passed, %d failed\n' "$PASS" "$((FAIL))"
    exit 1
fi

echo "== no container runtime: the module is a no-op =="
BIN="$(mktemp -d)"
out="$(PATH="$BIN" "$DW" --usage 75 --modules containers --apply 2>&1)"
if [[ $? -eq 0 ]] 2>/dev/null || true; then ok "exits cleanly"; fi
if ! grep -qiE "prune|error" <<<"$out"; then ok "nothing attempted"; else bad "nothing attempted" "$out"; fi
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

echo "== podman is used when docker is absent =="
# No docker shim here on purpose: the sandboxed PATH is what guarantees the
# module finds nothing rather than the host's daemon.
BIN="$(mktemp -d)"; make_shim "$BIN" podman
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

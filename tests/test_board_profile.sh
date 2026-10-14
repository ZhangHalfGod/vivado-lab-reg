#!/usr/bin/env bash
# Board-profile load order, smoke skip, and xsdb.sh --profile wiring.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HARNESS="$ROOT/tests/profile_harness.tcl"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0
pass() { printf 'PASS %s\n' "$1"; }
die() { printf 'FAIL %s\n' "$1" >&2; fail=1; }

assert_eq() {
    local name="$1" got="$2" want="$3"
    if [[ "$got" == "$want" ]]; then
        pass "$name"
    else
        die "$name (got $(printf %q "$got") want $(printf %q "$want"))"
    fi
}

assert_contains() {
    local name="$1" hay="$2" needle="$3"
    if [[ "$hay" == *"$needle"* ]]; then
        pass "$name"
    else
        die "$name (missing $(printf %q "$needle"))"
    fi
}

assert_not_contains() {
    local name="$1" hay="$2" needle="$3"
    if [[ "$hay" == *"$needle"* ]]; then
        die "$name (unexpected $(printf %q "$needle"))"
    else
        pass "$name"
    fi
}

run_harness() {
    # Remaining args are env assignments consumed by `env`, then optional harness arg via HARNESS_ARG.
    env -u VIVADO_LAB_REG_PROFILE -u XSDB_PROFILE "$@" tclsh "$HARNESS" ${HARNESS_ARG:-}
}

field() {
    local text="$1" key="$2"
    printf '%s\n' "$text" | sed -n "s/^RESULT ${key}=//p" | tail -n 1
}

# tool.tcl / reg.tcl must not keep the old lab constants.
if grep -E '11080000|116BCC00' "$ROOT/tool.tcl" "$ROOT/reg.tcl" >/dev/null; then
    die "lab smoke constants still present in tool.tcl or reg.tcl"
else
    pass "no lab smoke constants in tool.tcl or reg.tcl"
fi

out="$(HARNESS_ARG= run_harness)"
assert_eq "default mb" "$(field "$out" mb)" "0x0"
assert_eq "default jtag" "$(field "$out" jtag)" "0x0"
assert_eq "default loaded" "$(field "$out" loaded)" ""
assert_eq "default err" "$(field "$out" err)" "0"
assert_contains "default announces none" "$out" "board profile: (none)"
assert_contains "default skip hint" "$out" "Master Base Address is 0x0"

norm="$(tclsh <<EOF
puts [file normalize "$ROOT/profiles/example.tcl"]
EOF
)"
out="$(HARNESS_ARG= run_harness VIVADO_LAB_REG_PROFILE="$ROOT/profiles/example.tcl")"
assert_eq "example name" "$(field "$out" name)" "example"
assert_eq "example mb" "$(field "$out" mb)" "0x00000000"
assert_eq "example jtag" "$(field "$out" jtag)" "0x00000000"
assert_eq "example loaded" "$(field "$out" loaded)" "$norm"
assert_eq "example err" "$(field "$out" err)" "0"

# Relative path resolves next to tool.tcl, not the caller's cwd.
out="$(cd "$TMP" && HARNESS_ARG= run_harness VIVADO_LAB_REG_PROFILE=profiles/example.tcl)"
assert_eq "relative loaded" "$(field "$out" loaded)" "$norm"
assert_eq "relative err" "$(field "$out" err)" "0"

out="$(HARNESS_ARG= run_harness XSDB_PROFILE="$ROOT/profiles/example.tcl")"
assert_eq "XSDB_PROFILE name" "$(field "$out" name)" "example"

other="$TMP/other.tcl"
cat >"$other" <<'EOF'
set ::PROFILE_NAME "other"
set ::MB_SMOKE_ADDR 0x1111
set ::JTAG_SMOKE_ADDR 0x2222
EOF
out="$(HARNESS_ARG= run_harness \
    VIVADO_LAB_REG_PROFILE="$other" \
    XSDB_PROFILE="$ROOT/profiles/example.tcl")"
assert_eq "VIVADO wins over XSDB_PROFILE" "$(field "$out" name)" "other"
assert_eq "VIVADO mb" "$(field "$out" mb)" "0x1111"

# Global sets without :: still apply (profile is sourced at global scope).
plain="$TMP/plain.tcl"
cat >"$plain" <<'EOF'
set PROFILE_NAME "plain"
set MB_SMOKE_ADDR 0x10
set JTAG_SMOKE_ADDR 0x20
EOF
out="$(HARNESS_ARG= run_harness VIVADO_LAB_REG_PROFILE="$plain")"
assert_eq "plain name" "$(field "$out" name)" "plain"
assert_eq "plain mb" "$(field "$out" mb)" "0x10"
assert_eq "plain jtag" "$(field "$out" jtag)" "0x20"

space="$TMP/board profile.tcl"
cat >"$space" <<'EOF'
set ::PROFILE_NAME "spaced"
set ::MB_SMOKE_ADDR 0x0000_1000
set ::JTAG_SMOKE_ADDR 0x2000
EOF
out="$(HARNESS_ARG= run_harness VIVADO_LAB_REG_PROFILE="$space")"
assert_eq "space name" "$(field "$out" name)" "spaced"
assert_eq "space mb keeps underscores until normalize" "$(field "$out" mb)" "0x0000_1000"

out="$(HARNESS_ARG= run_harness VIVADO_LAB_REG_PROFILE="$TMP/missing.tcl")"
assert_eq "missing err" "$(field "$out" err)" "1"
assert_eq "missing mb" "$(field "$out" mb)" "0x0"
assert_contains "missing message" "$out" "ERROR: board profile not found:"
assert_contains "missing not loaded" "$out" "board profile: NOT LOADED"
assert_not_contains "missing does not use lab constant" "$out" "11080000"

bad="$TMP/bad.tcl"
printf 'set ::MB_SMOKE_ADDR [\n' >"$bad"
out="$(HARNESS_ARG= run_harness VIVADO_LAB_REG_PROFILE="$bad")"
assert_eq "syntax err" "$(field "$out" err)" "1"
assert_eq "syntax mb reset" "$(field "$out" mb)" "0x0"
assert_contains "syntax message" "$out" "ERROR: board profile failed:"

hex="$TMP/hex.tcl"
cat >"$hex" <<'EOF'
set ::PROFILE_NAME "hex"
set ::MB_SMOKE_ADDR not-hex
set ::JTAG_SMOKE_ADDR 0x20
EOF
out="$(HARNESS_ARG= run_harness VIVADO_LAB_REG_PROFILE="$hex")"
assert_eq "bad hex err" "$(field "$out" err)" "1"
assert_contains "bad hex message" "$out" "ERROR: MB_SMOKE_ADDR is not a hex Master Base Address"

partial="$TMP/partial.tcl"
cat >"$partial" <<'EOF'
set ::PROFILE_NAME "partial"
set ::MB_SMOKE_ADDR 0x44
EOF
out="$(HARNESS_ARG= run_harness VIVADO_LAB_REG_PROFILE="$partial")"
assert_eq "partial mb" "$(field "$out" mb)" "0x44"
assert_eq "partial jtag default" "$(field "$out" jtag)" "0x0"
assert_eq "partial err" "$(field "$out" err)" "0"

# Pre-set variables survive when no profile is requested.
preset_out="$(env -u VIVADO_LAB_REG_PROFILE -u XSDB_PROFILE tclsh <<EOF
set ::XSDB_QUIET 1
set ::MB_SMOKE_ADDR 0xABC
set ::JTAG_SMOKE_ADDR 0x0
source "$ROOT/tool.tcl"
puts "RESULT mb=\$::MB_SMOKE_ADDR"
puts "RESULT jtag=\$::JTAG_SMOKE_ADDR"
puts "RESULT loaded=[expr {[info exists ::LOADED_PROFILE] ? \$::LOADED_PROFILE : {}}]"
EOF
)"
assert_eq "preset mb kept" "$(field "$preset_out" mb)" "0xABC"
assert_eq "preset jtag kept" "$(field "$preset_out" jtag)" "0x0"
assert_eq "preset no file" "$(field "$preset_out" loaded)" ""

# Tcl var wins over the environment.
tclvar="$TMP/tclvar.tcl"
cat >"$tclvar" <<'EOF'
set ::PROFILE_NAME "from-tcl-var"
set ::MB_SMOKE_ADDR 0x55
set ::JTAG_SMOKE_ADDR 0x66
EOF
var_out="$(env -u XSDB_PROFILE VIVADO_LAB_REG_PROFILE="$ROOT/profiles/example.tcl" tclsh <<EOF
set ::XSDB_QUIET 1
set ::VIVADO_LAB_REG_PROFILE "$tclvar"
source "$ROOT/tool.tcl"
puts "RESULT name=\$::PROFILE_NAME"
puts "RESULT mb=\$::MB_SMOKE_ADDR"
EOF
)"
assert_eq "tcl var wins" "$(field "$var_out" name)" "from-tcl-var"
assert_eq "tcl var mb" "$(field "$var_out" mb)" "0x55"

# 0x0 profile: probe targets, do not mrd.
out="$(HARNESS_ARG=smoke run_harness VIVADO_LAB_REG_PROFILE="$ROOT/profiles/example.tcl")"
assert_contains "zero probes mb" "$out" "PROBE mb"
assert_contains "zero probes jtag" "$out" "PROBE jtag"
assert_contains "zero enumerates ids" "$out" "ids=7 8"
assert_contains "zero skip mb" "$out" "SKIP MicroBlaze mrd"
assert_contains "zero skip jtag" "$out" "SKIP JTAG2AXI #1 mrd"
assert_not_contains "zero does not mrd" "$out" "MRD "
assert_eq "zero smoke rc" "$(field "$out" smoke_rc)" "0"
assert_eq "zero jsmoke rc" "$(field "$out" jsmoke_rc)" "0"

# Non-zero Master Base addresses are what mrd receives.
live="$TMP/live.tcl"
cat >"$live" <<'EOF'
set ::PROFILE_NAME "live"
set ::MB_SMOKE_ADDR 0x0000_1000
set ::JTAG_SMOKE_ADDR 0x2000
EOF
out="$(HARNESS_ARG=smoke run_harness VIVADO_LAB_REG_PROFILE="$live")"
assert_contains "live mb mrd" "$out" "MRD 0x00001000 10"
assert_contains "live jtag mrd" "$out" "MRD 0x00002000 4"
assert_not_contains "live no skip" "$out" "SKIP "
assert_eq "live smoke rc" "$(field "$out" smoke_rc)" "0"

# Address kind helper. tool.tcl prints a banner before PASS.
kind_out="$(env -u VIVADO_LAB_REG_PROFILE -u XSDB_PROFILE tclsh <<EOF
set ::XSDB_QUIET 1
source "$ROOT/tool.tcl"
foreach sample {0x0 0x00000000 0 {} 00000000} {
    if {[_smoke_addr_kind \$sample] ne "zero"} {
        puts "FAIL kind zero \$sample -> [_smoke_addr_kind \$sample]"
        exit 1
    }
}
if {[_smoke_addr_kind 0x0000_1000] ne "ok"} { puts FAIL; exit 1 }
if {[_ax 0x0000_1000] ne "0x00001000"} { puts FAIL; exit 1 }
if {[_smoke_addr_kind nope] ne "bad"} { puts FAIL; exit 1 }
puts PASS
EOF
)"
assert_eq "addr kinds pass" "$(printf '%s\n' "$kind_out" | tail -n 1)" "PASS"

# gitignore: private profiles stay untracked; the folder markers do not.
if git -C "$ROOT" check-ignore -q profiles/private/secret.tcl; then
    pass "private tcl is ignored"
else
    die "private tcl is not ignored"
fi
if git -C "$ROOT" check-ignore -q --no-index profiles/private/nested/board.tcl; then
    pass "nested private tcl is ignored"
else
    die "nested private tcl is not ignored"
fi
if git -C "$ROOT" check-ignore -q profiles/private/README.md; then
    die "private README should be tracked"
else
    pass "private README is not ignored"
fi
if git -C "$ROOT" check-ignore -q profiles/private/.gitkeep; then
    die "private gitkeep should be tracked"
else
    pass "private gitkeep is not ignored"
fi
if git -C "$ROOT" check-ignore -q profiles/example.tcl; then
    die "example profile should be tracked"
else
    pass "example profile is not ignored"
fi

# xsdb.sh accepts --profile without requiring a real xsdb.
FAKE="$TMP/xsdb"
cat >"$FAKE" <<'EOF'
#!/usr/bin/env bash
printf 'XSDB_ARGS:%s\n' "$*"
if [[ -n "${VIVADO_LAB_REG_PROFILE+x}" ]]; then
    printf 'VIVADO_LAB_REG_PROFILE:%s\n' "$VIVADO_LAB_REG_PROFILE"
else
    printf 'VIVADO_LAB_REG_PROFILE:<unset>\n'
fi
exit 0
EOF
chmod +x "$FAKE"

sh_out="$(env -u VIVADO_LAB_REG_PROFILE -u XSDB_PROFILE XSDB="$FAKE" "$ROOT/xsdb.sh" verify)"
assert_contains "verify no profile runs reg.tcl" "$sh_out" "XSDB_ARGS:$ROOT/reg.tcl"
assert_contains "verify no profile leaves env unset" "$sh_out" "VIVADO_LAB_REG_PROFILE:<unset>"

sh_out="$(env -u VIVADO_LAB_REG_PROFILE -u XSDB_PROFILE XSDB="$FAKE" \
    "$ROOT/xsdb.sh" verify --profile "$space")"
assert_contains "verify --profile passes reg.tcl" "$sh_out" "XSDB_ARGS:$ROOT/reg.tcl"
assert_contains "verify --profile exports path" "$sh_out" "VIVADO_LAB_REG_PROFILE:$space"
assert_contains "verify --profile echoes path" "$sh_out" "board profile: $space"

sh_out="$(env -u VIVADO_LAB_REG_PROFILE -u XSDB_PROFILE XSDB="$FAKE" \
    "$ROOT/xsdb.sh" --profile "$other" verify)"
assert_contains "leading --profile verify" "$sh_out" "VIVADO_LAB_REG_PROFILE:$other"

sh_out="$(env -u VIVADO_LAB_REG_PROFILE -u XSDB_PROFILE XSDB="$FAKE" \
    "$ROOT/xsdb.sh" --profile="$plain")"
assert_contains "interactive --profile= form" "$sh_out" "VIVADO_LAB_REG_PROFILE:$plain"
assert_contains "interactive still sources tool.tcl" "$sh_out" "source {$ROOT/tool.tcl}"

sh_out="$(env -u VIVADO_LAB_REG_PROFILE XSDB_PROFILE="$other" XSDB="$FAKE" "$ROOT/xsdb.sh" verify)"
assert_contains "wrapper copies XSDB_PROFILE" "$sh_out" "VIVADO_LAB_REG_PROFILE:$other"

sh_out="$(env VIVADO_LAB_REG_PROFILE="$other" XSDB_PROFILE="$plain" XSDB="$FAKE" \
    "$ROOT/xsdb.sh" verify --profile "$space")"
assert_contains "--profile overrides both env vars" "$sh_out" "VIVADO_LAB_REG_PROFILE:$space"

set +e
sh_out="$(env -u VIVADO_LAB_REG_PROFILE -u XSDB_PROFILE XSDB="$FAKE" "$ROOT/xsdb.sh" verify extra 2>&1)"
sh_rc=$?
set -e
assert_eq "verify rejects a bare extra arg" "$sh_rc" "1"
assert_contains "verify usage hint" "$sh_out" "--profile"

set +e
sh_out="$(env -u VIVADO_LAB_REG_PROFILE -u XSDB_PROFILE XSDB="$FAKE" "$ROOT/xsdb.sh" verify --profile 2>&1)"
sh_rc=$?
set -e
assert_eq "verify --profile needs a path" "$sh_rc" "1"

sh_out="$(env -u VIVADO_LAB_REG_PROFILE -u XSDB_PROFILE XSDB="$FAKE" "$ROOT/xsdb.sh" rd 00001000 4)"
assert_contains "rd still passes the address" "$sh_out" "rd 00001000 4"
assert_contains "rd still selects mb" "$sh_out" "xconnect; mb;"

help_out="$(env -u VIVADO_LAB_REG_PROFILE -u XSDB_PROFILE XSDB="$FAKE" "$ROOT/xsdb.sh" help)"
assert_contains "help documents --profile" "$help_out" "verify --profile"

if [[ "$fail" -ne 0 ]]; then
    exit 1
fi
echo "all board-profile checks passed"

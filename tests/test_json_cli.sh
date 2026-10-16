#!/usr/bin/env bash
# JSON CLI without a board: Tcl stubs plus xsdb.sh --json stdout filtering.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HARNESS="$ROOT/tests/json_harness.tcl"
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

line_of() {
    local text="$1" key="$2"
    printf '%s\n' "$text" | sed -n "s/^${key} //p" | tail -n 1
}

side_field() {
    local text="$1" key="$2"
    printf '%s\n' "$text" | sed -n "s/^SIDE ${key}=//p" | tail -n 1
}

word_field() {
    local text="$1" key="$2"
    printf '%s\n' "$text" | sed -n "s/^WORDS ${key} //p" | tail -n 1
}

run_h() {
    local scenario=$1
    shift
    env -u VIVADO_LAB_REG_PROFILE -u XSDB_PROFILE -u VIVADO_LAB_REG_JSON -u VIVADO_LAB_REG_JSON_FILE \
        "$@" tclsh "$HARNESS" "$scenario"
}

py_ok() {
    local name="$1" doc="$2" prog="$3"
    if DOC="$doc" python3 -c "$prog"; then
        pass "$name"
    else
        die "$name"
        printf '%s\n' "$doc" >&2
    fi
}

one_json() {
    local name="$1" text="$2"
    if printf '%s' "$text" | python3 -c '
import json, sys
text = sys.stdin.read()
dec = json.JSONDecoder()
obj, end = dec.raw_decode(text)
rest = text[end:]
if rest.strip() != "":
    raise SystemExit("trailing " + repr(rest))
if not isinstance(obj, dict) or "ok" not in obj:
    raise SystemExit("not a result object")
'; then
        pass "$name"
    else
        die "$name"
        printf '%s\n' "$text" >&2
    fi
}

MEM_KEYS='["ok","command","operation","error","skipped","reason","target","address","length","data","written"]'

# Human command text stays in place.
if grep -q 'puts "TGT $id $nm"' "$ROOT/tool.tcl" && grep -q 'puts \[mrd' "$ROOT/tool.tcl"; then
    pass "human TGT and rd procs still print"
else
    die "human TGT or rd output changed"
fi

out="$(run_h targets-ok)"
doc="$(line_of "$out" DOC)"
assert_eq "targets rc" "$(line_of "$out" RC)" "0"
py_ok "targets shape" "$doc" '
import json, os
d = json.loads(os.environ["DOC"])
assert list(d) == ["ok", "command", "operation", "error", "targets"]
assert d["ok"] is True and d["command"] == "targets" and d["operation"] == "targets"
assert d["error"] is None
assert [t["id"] for t in d["targets"]] == [2, 3, 5, 6]
assert [t["class"] for t in d["targets"]] == ["microblaze", "microblaze", "jtag2axi", "jtag2axi"]
assert d["targets"][0]["name"] == "MicroBlaze #1"
assert d["targets"][1]["name"] == "MicroBlaze #0"
assert d["targets"][2]["name"] == "JTAG2AXI"
assert d["targets"][3]["name"] == "Jtag Master"
assert all("Debug Module" not in t["name"] for t in d["targets"])
'

out="$(run_h targets-empty)"
doc="$(line_of "$out" DOC)"
assert_eq "empty targets rc" "$(line_of "$out" RC)" "0"
py_ok "empty targets" "$doc" '
import json, os
d = json.loads(os.environ["DOC"])
assert d["ok"] is True and d["error"] is None and d["targets"] == []
'

out="$(run_h targets-connect-fail)"
doc="$(line_of "$out" DOC)"
assert_eq "connect fail rc" "$(line_of "$out" RC)" "1"
py_ok "connect fail json" "$doc" '
import json, os
d = json.loads(os.environ["DOC"])
assert d["ok"] is False and d["targets"] == []
assert "connect failed" in d["error"] and "no cable" in d["error"]
'

out="$(run_h targets-props-fail)"
doc="$(line_of "$out" DOC)"
assert_eq "props fail rc" "$(line_of "$out" RC)" "1"
py_ok "props fail json" "$doc" '
import json, os
d = json.loads(os.environ["DOC"])
assert d["ok"] is False and "properties unavailable" in d["error"] and d["targets"] == []
'

out="$(run_h targets-quote)"
doc="$(line_of "$out" DOC)"
py_ok "quoted target name" "$doc" '
import json, os
d = json.loads(os.environ["DOC"])
assert d["ok"] is True
assert d["targets"][0]["name"] == "MicroBlaze #0 " + chr(34) + "q" + chr(34) + " " + chr(92) + " z"
assert d["targets"][0]["class"] == "microblaze"
'

out="$(run_h read-ok)"
doc="$(line_of "$out" DOC)"
assert_eq "read rc" "$(line_of "$out" RC)" "0"
assert_eq "read selects mb #0" "$(side_field "$out" selected)" "3"
assert_eq "read mrd once" "$(side_field "$out" mrd_count)" "1"
assert_eq "read does not mwr" "$(side_field "$out" mwr)" ""
py_ok "read shape" "$doc" '
import json, os
d = json.loads(os.environ["DOC"])
assert list(d) == '"$MEM_KEYS"'
assert d["ok"] is True and d["command"] == "rd" and d["operation"] == "read"
assert d["error"] is None and d["skipped"] is False and d["reason"] is None
assert d["address"] == "0x00001000" and d["length"] == 1
assert d["data"] == ["0x00000001"] and d["written"] == []
assert d["target"] == {"id": 3, "name": "MicroBlaze #0", "class": "microblaze"}
'

out="$(run_h read-multi)"
doc="$(line_of "$out" DOC)"
py_ok "read several words" "$doc" '
import json, os
d = json.loads(os.environ["DOC"])
assert d["length"] == 4
assert d["data"] == ["0x00000001", "0x00000002", "0x00000003", "0x00000004"]
'

out="$(run_h read-len-pad)"
doc="$(line_of "$out" DOC)"
py_ok "read length 08 is eight" "$doc" '
import json, os
d = json.loads(os.environ["DOC"])
assert d["ok"] is True and d["length"] == 8 and len(d["data"]) == 8
'

out="$(run_h read-jtag2)"
doc="$(line_of "$out" DOC)"
assert_eq "jrd2 selects second jtag" "$(side_field "$out" selected)" "6"
py_ok "jrd2 target" "$doc" '
import json, os
d = json.loads(os.environ["DOC"])
assert d["command"] == "jrd2" and d["operation"] == "read" and d["length"] == 2
assert d["target"]["id"] == 6 and d["target"]["class"] == "jtag2axi"
assert d["target"]["name"] == "Jtag Master"
assert d["address"] == "0x00002000"
'

out="$(run_h read-no-mb)"
doc="$(line_of "$out" DOC)"
assert_eq "no mb rc" "$(line_of "$out" RC)" "1"
py_ok "no mb error" "$doc" '
import json, os
d = json.loads(os.environ["DOC"])
assert d["ok"] is False and d["target"] is None
assert "MicroBlaze not found" in d["error"]
assert d["data"] == [] and d["address"] == "0x00001000"
'

out="$(run_h read-bad-addr)"
doc="$(line_of "$out" DOC)"
assert_eq "bad addr rc" "$(line_of "$out" RC)" "1"
py_ok "bad addr" "$doc" '
import json, os
d = json.loads(os.environ["DOC"])
assert d["ok"] is False and d["address"] is None and "bad address" in d["error"]
'

out="$(run_h read-bad-len)"
doc="$(line_of "$out" DOC)"
assert_eq "bad len rc" "$(line_of "$out" RC)" "1"
py_ok "bad len" "$doc" '
import json, os
d = json.loads(os.environ["DOC"])
assert d["ok"] is False and d["length"] is None
assert "positive integer" in d["error"]
'

out="$(run_h read-mrd-fail)"
doc="$(line_of "$out" DOC)"
assert_eq "mrd fail rc" "$(line_of "$out" RC)" "1"
py_ok "mrd fail" "$doc" '
import json, os
d = json.loads(os.environ["DOC"])
assert d["ok"] is False and "mrd failed: timeout" in d["error"]
assert d["target"]["id"] == 3 and d["data"] == []
'

out="$(run_h read-empty)"
doc="$(line_of "$out" DOC)"
py_ok "empty mrd" "$doc" '
import json, os
d = json.loads(os.environ["DOC"])
assert d["ok"] is False and "no data" in d["error"]
'

out="$(run_h write-ok)"
doc="$(line_of "$out" DOC)"
assert_eq "write rc" "$(line_of "$out" RC)" "0"
assert_eq "write mwr" "$(side_field "$out" mwr)" "0x00001000 0x00000001"
assert_eq "write does not mrd" "$(side_field "$out" mrd_count)" "0"
py_ok "write shape" "$doc" '
import json, os
d = json.loads(os.environ["DOC"])
assert d["ok"] is True and d["command"] == "wr" and d["operation"] == "write"
assert d["address"] == "0x00001000" and d["length"] == 1
assert d["data"] == ["0x00000001"] and d["written"] == ["0x00000001"]
assert d["target"]["class"] == "microblaze"
'

out="$(run_h write-fail)"
doc="$(line_of "$out" DOC)"
assert_eq "mwr fail rc" "$(line_of "$out" RC)" "1"
py_ok "mwr fail" "$doc" '
import json, os
d = json.loads(os.environ["DOC"])
assert d["ok"] is False and "mwr failed: protected" in d["error"]
assert d["written"] == ["0x000000AB"] and d["data"] == ["0x000000AB"]
'

out="$(run_h write-bad-data)"
doc="$(line_of "$out" DOC)"
py_ok "bad write data" "$doc" '
import json, os
d = json.loads(os.environ["DOC"])
assert d["ok"] is False and "bad data" in d["error"] and d["written"] == []
'

out="$(run_h wrd-ok)"
doc="$(line_of "$out" DOC)"
assert_eq "wrd rc" "$(line_of "$out" RC)" "0"
assert_eq "wrd selected jtag 1" "$(side_field "$out" selected)" "5"
assert_eq "wrd mwr" "$(side_field "$out" mwr)" "0x00002008 0x00000002"
assert_eq "wrd mrd once" "$(side_field "$out" mrd_count)" "1"
py_ok "wrd shape" "$doc" '
import json, os
d = json.loads(os.environ["DOC"])
assert d["command"] == "jwrd" and d["operation"] == "write_read"
assert d["data"] == ["0x00000001"] and d["written"] == ["0x00000002"]
assert d["target"]["name"] == "JTAG2AXI" and d["length"] == 1
'

out="$(run_h wrd-read-fail)"
doc="$(line_of "$out" DOC)"
assert_eq "wrd read fail rc" "$(line_of "$out" RC)" "1"
py_ok "wrd read fail keeps payload" "$doc" '
import json, os
d = json.loads(os.environ["DOC"])
assert d["ok"] is False and "readback timeout" in d["error"]
assert d["data"] == [] and d["written"] == ["0x00000003"]
'

out="$(run_h verify-skip)"
doc="$(line_of "$out" DOC)"
assert_eq "verify skip rc" "$(line_of "$out" RC)" "0"
assert_eq "verify skip does not mrd" "$(side_field "$out" mrd_count)" "0"
py_ok "verify skip" "$doc" '
import json, os
d = json.loads(os.environ["DOC"])
assert list(d) == ["ok", "command", "operation", "error", "results"]
assert d["ok"] is True and d["command"] == "verify" and d["error"] is None
assert len(d["results"]) == 3
assert [r["command"] for r in d["results"]] == ["smoke", "jsmoke", "jsmoke"]
assert all(r["skipped"] is True and r["ok"] is True and r["data"] == [] for r in d["results"])
assert d["results"][0]["target"]["class"] == "microblaze"
assert d["results"][0]["length"] == 10 and d["results"][1]["length"] == 4
assert "0x0" in d["results"][0]["reason"]
assert d["results"][1]["target"]["id"] == 5
assert d["results"][2]["target"]["id"] == 6
'

out="$(run_h verify-read)"
doc="$(line_of "$out" DOC)"
assert_eq "verify read rc" "$(line_of "$out" RC)" "0"
assert_eq "verify read mrd count" "$(side_field "$out" mrd_count)" "3"
py_ok "verify read" "$doc" '
import json, os
d = json.loads(os.environ["DOC"])
assert d["ok"] is True
mb, j1, j2 = d["results"]
assert mb["skipped"] is False and mb["address"] == "0x00001000" and mb["length"] == 10
assert len(mb["data"]) == 10 and mb["data"][0] == "0x00000001"
assert j1["address"] == "0x00002000" and j1["length"] == 4 and len(j1["data"]) == 4
assert j2["target"]["id"] == 6 and j2["length"] == 4
'

out="$(run_h verify-no-jtag)"
doc="$(line_of "$out" DOC)"
assert_eq "verify no jtag rc" "$(line_of "$out" RC)" "1"
py_ok "verify no jtag" "$doc" '
import json, os
d = json.loads(os.environ["DOC"])
assert d["ok"] is False and d["error"] == "no JTAG2AXI"
assert len(d["results"]) == 1 and d["results"][0]["skipped"] is True
'

out="$(run_h verify-no-mb)"
doc="$(line_of "$out" DOC)"
assert_eq "verify no mb rc" "$(line_of "$out" RC)" "0"
py_ok "verify no mb still skips" "$doc" '
import json, os
d = json.loads(os.environ["DOC"])
assert d["ok"] is True
assert d["results"][0]["reason"] == "MicroBlaze not found"
assert d["results"][0]["target"] is None and d["results"][0]["skipped"] is True
assert d["results"][1]["skipped"] is True and d["results"][1]["target"]["id"] == 5
'

out="$(run_h verify-bad)"
doc="$(line_of "$out" DOC)"
assert_eq "verify bad addr rc" "$(line_of "$out" RC)" "1"
py_ok "verify bad addr" "$doc" '
import json, os
d = json.loads(os.environ["DOC"])
assert d["ok"] is False and "MB_SMOKE_ADDR" in d["error"]
assert d["results"][0]["ok"] is False
assert d["results"][1]["ok"] is True and d["results"][1]["length"] == 4
'

out="$(run_h verify-connect-fail)"
doc="$(line_of "$out" DOC)"
assert_eq "verify connect rc" "$(line_of "$out" RC)" "1"
py_ok "verify connect" "$doc" '
import json, os
d = json.loads(os.environ["DOC"])
assert d["ok"] is False and d["results"] == [] and "connect failed" in d["error"]
'

out="$(run_h verify-profile VIVADO_LAB_REG_PROFILE="$TMP/missing.tcl")"
doc="$(line_of "$out" DOC)"
assert_eq "verify profile rc" "$(line_of "$out" RC)" "1"
py_ok "verify profile" "$doc" '
import json, os
d = json.loads(os.environ["DOC"])
assert d["ok"] is False and d["results"] == []
assert "board profile did not load" in d["error"]
'

words="$(run_h parse)"
assert_eq "parse grouped" "$(word_field "$words" grouped)" "0xDEADBEEF,0x00000002,0x00000003"
assert_eq "parse prefixed" "$(word_field "$words" prefixed)" "0x00000010,0x00000002"
assert_eq "parse bare" "$(word_field "$words" bare)" "0xDEADBEEF,0x00000002"
assert_eq "parse empty" "$(word_field "$words" empty)" ""

pub="$TMP/out.json"
pub_out="$(run_h publish VIVADO_LAB_REG_JSON_FILE="$pub")"
assert_contains "publish sentinel" "$pub_out" "VIVADO_LAB_REG_JSON {\"ok\":true"
assert_eq "publish file" "$(cat "$pub")" '{"ok":true,"command":"targets","operation":"targets","error":null,"targets":[]}'

# Wrapper: fake xsdb records the eval and can drop a JSON file.
FAKE="$TMP/xsdb"
cat >"$FAKE" <<'EOF'
#!/usr/bin/env bash
printf 'XSDB_ARGS:%s\n' "$*"
if [[ -n "${VIVADO_LAB_REG_PROFILE+x}" ]]; then
    printf 'VIVADO_LAB_REG_PROFILE:%s\n' "$VIVADO_LAB_REG_PROFILE"
else
    printf 'VIVADO_LAB_REG_PROFILE:<unset>\n'
fi
if [[ -n "${VIVADO_LAB_REG_JSON_FILE+x}" ]]; then
    printf 'VIVADO_LAB_REG_JSON_FILE:set\n'
else
    printf 'VIVADO_LAB_REG_JSON_FILE:<unset>\n'
fi
echo "BANNER xsdb"
mode="${FAKE_XSDB_MODE:-json}"
if [[ "$mode" == "json" && -n "${VIVADO_LAB_REG_JSON_FILE:-}" ]]; then
    printf '%s\n' '{"ok":true,"command":"targets","operation":"targets","error":null,"targets":[]}' \
        > "$VIVADO_LAB_REG_JSON_FILE"
    printf '%s\n' 'VIVADO_LAB_REG_JSON {"ok":true,"command":"targets","operation":"targets","error":null,"targets":[]}'
fi
exit "${FAKE_XSDB_RC:-0}"
EOF
chmod +x "$FAKE"

run_sh() {
    env -u VIVADO_LAB_REG_PROFILE -u XSDB_PROFILE -u VIVADO_LAB_REG_JSON -u VIVADO_LAB_REG_JSON_FILE \
        XSDB="$FAKE" "$ROOT/xsdb.sh" "$@"
}

sh_out="$(run_sh rd 00001000 4 2>"$TMP/human.err")"
assert_contains "human rd eval" "$sh_out" "set ::XSDB_QUIET 1; source {$ROOT/tool.tcl}; xconnect; mb; catch {rd 00001000 4}; exit"
assert_not_contains "human rd is not json" "$sh_out" "json_cli_main"
assert_contains "human rd leaves json file unset" "$sh_out" "VIVADO_LAB_REG_JSON_FILE:<unset>"

sh_out="$(run_sh targets)"
assert_contains "human targets eval" "$sh_out" "-eval connect; targets; exit"
assert_not_contains "human targets is not json" "$sh_out" "json_cli_main"

sh_out="$(run_sh verify)"
assert_contains "human verify still runs reg.tcl" "$sh_out" "XSDB_ARGS:$ROOT/reg.tcl"
assert_not_contains "human verify is not json" "$sh_out" "json_cli_main"

help_out="$(run_sh help)"
assert_contains "help documents --json" "$help_out" "--json"

stdout="$(run_sh --json targets 2>"$TMP/json.err")"
one_json "json targets stdout is one object" "$stdout"
assert_not_contains "json targets stdout has no banner" "$stdout" "BANNER"
assert_contains "json targets stderr keeps banner" "$(cat "$TMP/json.err")" "BANNER"
assert_contains "json targets eval" "$(cat "$TMP/json.err")" "json_cli_main targets"
assert_contains "json targets sets XSDB_JSON" "$(cat "$TMP/json.err")" "set ::XSDB_JSON 1"
py_ok "json targets body" "$stdout" '
import json, os
d = json.loads(os.environ["DOC"])
assert d == {"ok": True, "command": "targets", "operation": "targets", "error": None, "targets": []}
'

stdout="$(run_sh targets --json 2>"$TMP/json2.err")"
one_json "json flag after command" "$stdout"
assert_contains "flag after command still json eval" "$(cat "$TMP/json2.err")" "json_cli_main targets"

set +e
stdout="$(run_sh --json rd 2>"$TMP/miss.err")"
rc=$?
set -e
assert_eq "missing addr rc" "$rc" "1"
one_json "missing addr is json" "$stdout"
assert_not_contains "missing addr does not start xsdb" "$(cat "$TMP/miss.err")" "XSDB_ARGS"
py_ok "missing addr error" "$stdout" '
import json, os
d = json.loads(os.environ["DOC"])
assert d["ok"] is False and d["command"] == "rd" and d["operation"] == "read"
assert "Missing addr" in d["error"] and d["data"] == []
'

stdout="$(run_sh --json rd 00001000 4 2>"$TMP/rd.err")"
assert_contains "json rd eval" "$(cat "$TMP/rd.err")" "json_cli_main read {00001000} {4} mb 0 rd"
assert_not_contains "json rd does not xconnect" "$(cat "$TMP/rd.err")" "xconnect"

stdout="$(run_sh rd --json 00001000 2>"$TMP/rd1.err")"
assert_contains "json rd default len" "$(cat "$TMP/rd1.err")" "json_cli_main read {00001000} {1} mb 0 rd"

stdout="$(run_sh --json wr 00001000 1 2>"$TMP/wr.err")"
assert_contains "json wr eval" "$(cat "$TMP/wr.err")" "json_cli_main write {00001000} {1} mb 0 wr"

stdout="$(run_sh --json wrd 00001000 1 2>"$TMP/wrd.err")"
assert_contains "json wrd eval" "$(cat "$TMP/wrd.err")" "json_cli_main write_read {00001000} {1} mb 0 wrd"

stdout="$(run_sh --json jrd 00002000 4 2>"$TMP/jrd.err")"
assert_contains "json jrd eval" "$(cat "$TMP/jrd.err")" "json_cli_main read {00002000} {4} jtag 1 jrd"

stdout="$(run_sh --json jwr 00002008 1 2>"$TMP/jwr.err")"
assert_contains "json jwr eval" "$(cat "$TMP/jwr.err")" "json_cli_main write {00002008} {1} jtag 1 jwr"

stdout="$(run_sh --json jrd2 00002000 2>"$TMP/jrd2.err")"
assert_contains "json jrd2 eval" "$(cat "$TMP/jrd2.err")" "json_cli_main read {00002000} {1} jtag 2 jrd2"

space="$TMP/board profile.tcl"
echo 'set ::MB_SMOKE_ADDR 0x0' >"$space"
stdout="$(run_sh --json --profile "$space" verify 2>"$TMP/ver.err")"
assert_contains "json verify eval" "$(cat "$TMP/ver.err")" "json_cli_main verify"
assert_contains "json verify profile" "$(cat "$TMP/ver.err")" "VIVADO_LAB_REG_PROFILE:$space"
stdout="$(run_sh verify --profile "$space" --json 2>"$TMP/ver2.err")"
assert_contains "json verify flag order" "$(cat "$TMP/ver2.err")" "json_cli_main verify"
assert_contains "json verify flag order profile" "$(cat "$TMP/ver2.err")" "VIVADO_LAB_REG_PROFILE:$space"

set +e
stdout="$(FAKE_XSDB_MODE=nojson run_sh --json targets 2>"$TMP/nojson.err")"
rc=$?
set -e
assert_eq "no json file rc" "$rc" "1"
one_json "no json file still prints json" "$stdout"
assert_contains "no json file stderr has banner" "$(cat "$TMP/nojson.err")" "BANNER"
py_ok "no json file error" "$stdout" '
import json, os
d = json.loads(os.environ["DOC"])
assert d["ok"] is False and "no JSON result" in d["error"] and d["targets"] == []
'

set +e
stdout="$(FAKE_XSDB_RC=7 run_sh --json targets 2>"$TMP/rc.err")"
rc=$?
set -e
assert_eq "json exit code propagates" "$rc" "7"
one_json "json exit still prints the document" "$stdout"

set +e
stdout="$(run_sh --json 2>"$TMP/inter.err")"
rc=$?
set -e
assert_eq "json interactive rc" "$rc" "1"
one_json "json interactive" "$stdout"
assert_not_contains "json interactive does not start xsdb" "$(cat "$TMP/inter.err")" "XSDB_ARGS"

set +e
stdout="$(run_sh --json rd 00001000 0 2>"$TMP/zero.err")"
rc=$?
set -e
assert_eq "json len 0 rc" "$rc" "1"
py_ok "json len 0" "$stdout" '
import json, os
d = json.loads(os.environ["DOC"])
assert d["ok"] is False and "positive integer" in d["error"]
'
assert_not_contains "json len 0 does not start xsdb" "$(cat "$TMP/zero.err")" "XSDB_ARGS"

if [[ "$fail" -ne 0 ]]; then
    exit 1
fi
echo "all json cli checks passed"

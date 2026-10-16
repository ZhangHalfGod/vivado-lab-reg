#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

find_xsdb() {
    if [[ -n "${XSDB:-}" && -x "$XSDB" ]]; then
        echo "$XSDB"
        return
    fi
    if [[ -n "${XSDB_PATH:-}" && -x "$XSDB_PATH" ]]; then
        echo "$XSDB_PATH"
        return
    fi
    if command -v xsdb >/dev/null 2>&1; then
        command -v xsdb
        return
    fi
    if [[ -n "${XILINX_VIVADO:-}" && -x "$XILINX_VIVADO/bin/xsdb" ]]; then
        echo "$XILINX_VIVADO/bin/xsdb"
        return
    fi
    local v d
    for v in 2024.2 2024.1 2023.2 2023.1 2022.2 2022.1 2021.2 2021.1; do
        for d in \
            "/opt/Xilinx/Vivado_Lab/$v/bin/xsdb" \
            "/opt/Xilinx/Vivado/$v/bin/xsdb" \
            "/tools/Xilinx/Vivado_Lab/$v/bin/xsdb" \
            "$HOME/Xilinx/Vivado_Lab/$v/bin/xsdb"
        do
            if [[ -x "$d" ]]; then
                echo "$d"
                return
            fi
        done
    done
    return 1
}

usage() {
    cat <<EOF

Vivado Lab XSDB tool
xsdb : ${XSDB:-not found}

Two paths:
  MB   : JTAG -> XSDB -> MicroBlaze
  JTAG : JTAG -> XSDB -> Jtag Master (JTAG2AXI / hw_axi)

Usage:
  ./xsdb.sh                 interactive
  ./xsdb.sh verify          both paths then exit
  ./xsdb.sh verify --profile <file.tcl>
  ./xsdb.sh --profile <file.tcl> [command]
  ./xsdb.sh targets         list JTAG targets
  ./xsdb.sh rd   <addr> [len]
  ./xsdb.sh wr   <addr> <data>
  ./xsdb.sh wrd  <addr> <data>
  ./xsdb.sh jrd  <addr> [len]     JTAG2AXI #1
  ./xsdb.sh jrd2 <addr> [len]     JTAG2AXI #2
  ./xsdb.sh jwr  <addr> <data>
  ./xsdb.sh jwrd <addr> <data>
  --json                   one JSON object on stdout (targets, rd/wr, verify)

Board profile (Master Base Address), optional:
  --profile <file.tcl>     source before tool.tcl (also: VIVADO_LAB_REG_PROFILE or XSDB_PROFILE)
  0x0 or no profile skips that smoke read.

Examples:
  ./xsdb.sh verify --profile /lab/vivado-lab-reg/profiles/private/board.tcl
  ./xsdb.sh rd   00001000 10
  ./xsdb.sh jrd  00002000 4
  ./xsdb.sh jwr  00002008 1
  ./xsdb.sh --json targets
  ./xsdb.sh --json rd 00001000 4
  ./xsdb.sh --json wr 00001000 1
  ./xsdb.sh --json verify --profile <file.tcl>

EOF
}

# Early failures in --json mode stay a single JSON object on stdout.
MEM_JSON_EMPTY=',"skipped":false,"reason":null,"target":null,"address":null,"length":null,"data":[],"written":[]'
TGT_JSON_EMPTY=',"targets":[]'
VER_JSON_EMPTY=',"results":[]'

json_quote() {
    local s=$1
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/\\n}
    s=${s//$'\r'/\\r}
    s=${s//$'\t'/\\t}
    printf '%s' "$s"
}

json_early() {
    local command=$1
    local operation=$2
    local error=$3
    local extra=${4:-}
    printf '{"ok":false,"command":"%s","operation":"%s","error":"%s"%s}\n' \
        "$(json_quote "$command")" \
        "$(json_quote "$operation")" \
        "$(json_quote "$error")" \
        "$extra"
}

json_hex_ok() {
    [[ "$1" =~ ^[0-9A-Fa-f_]+$ || "$1" =~ ^0[xX][0-9A-Fa-f_]+$ ]]
}

# Run one XSDB eval. Stdout of this process is only the JSON document.
# XSDB's own banner and tool.tcl chatter go to stderr.
run_xsdb_json() {
    local script=$1
    local command=$2
    local operation=$3
    local fail_extra=$4
    local tmp out rc line
    tmp="$(mktemp)"
    out="$(mktemp)"
    export VIVADO_LAB_REG_JSON=1
    export VIVADO_LAB_REG_JSON_FILE="$out"
    set +e
    "$XSDB" -eval "set ::XSDB_QUIET 1; set ::XSDB_JSON 1; source {$HERE/tool.tcl}; $script" >"$tmp"
    rc=$?
    set -e
    if [[ -s "$tmp" ]]; then
        grep -v '^VIVADO_LAB_REG_JSON ' "$tmp" >&2 || true
    fi
    if [[ -s "$out" ]]; then
        cat "$out"
        if [[ "$(tail -c 1 "$out" || true)" != $'\n' ]]; then
            printf '\n'
        fi
        rm -f "$tmp" "$out"
        exit "$rc"
    fi
    line="$(grep -m1 '^VIVADO_LAB_REG_JSON ' "$tmp" || true)"
    rm -f "$tmp" "$out"
    if [[ -n "$line" ]]; then
        printf '%s\n' "${line#VIVADO_LAB_REG_JSON }"
        exit "$rc"
    fi
    json_early "$command" "$operation" "xsdb produced no JSON result" "$fail_extra"
    exit 1
}

json_require_hex() {
    local label=$1 value=$2 command=$3 operation=$4 extra=$5
    if ! json_hex_ok "$value"; then
        json_early "$command" "$operation" "bad $label: $value" "$extra"
        exit 1
    fi
}

json_require_len() {
    local len=$1 command=$2 extra=$3
    local n
    if [[ ! "$len" =~ ^[0-9]+$ ]]; then
        json_early "$command" read "length must be a positive integer" "$extra"
        exit 1
    fi
    n=$((10#$len))
    if [[ "$n" -lt 1 ]]; then
        json_early "$command" read "length must be a positive integer" "$extra"
        exit 1
    fi
}

json_cli_cmd() {
    local cmd=$1
    shift
    local addr="" data="" len="" extra=""
    case "$cmd" in
        help|-h|--help)
            usage
            exit 0
            ;;
        interactive|"")
            json_early interactive error "interactive has no JSON result. Use targets, rd, wr, wrd, jrd, jwr, jwrd, or verify."
            exit 1
            ;;
        targets)
            if [[ -n "${1:-}" ]]; then
                json_early targets targets "Unknown argument: $1" "$TGT_JSON_EMPTY"
                exit 1
            fi
            run_xsdb_json "json_cli_main targets" targets targets "$TGT_JSON_EMPTY"
            ;;
        verify)
            if [[ -n "${1:-}" ]]; then
                json_early verify verify "Unknown argument: $1" "$VER_JSON_EMPTY"
                exit 1
            fi
            run_xsdb_json "json_cli_main verify" verify verify "$VER_JSON_EMPTY"
            ;;
        rd|jrd|jrd2)
            addr="${1:-}"
            len="${2:-1}"
            extra="${3:-}"
            if [[ -z "$addr" ]]; then
                json_early "$cmd" read "Missing addr. Example: ./xsdb.sh $cmd 00001000 10" "$MEM_JSON_EMPTY"
                exit 1
            fi
            if [[ -n "$extra" ]]; then
                json_early "$cmd" read "Unknown argument: $extra" "$MEM_JSON_EMPTY"
                exit 1
            fi
            json_require_hex address "$addr" "$cmd" read "$MEM_JSON_EMPTY"
            json_require_len "$len" "$cmd" "$MEM_JSON_EMPTY"
            case "$cmd" in
                rd)   run_xsdb_json "json_cli_main read {$addr} {$len} mb 0 rd" rd read "$MEM_JSON_EMPTY" ;;
                jrd)  run_xsdb_json "json_cli_main read {$addr} {$len} jtag 1 jrd" jrd read "$MEM_JSON_EMPTY" ;;
                jrd2) run_xsdb_json "json_cli_main read {$addr} {$len} jtag 2 jrd2" jrd2 read "$MEM_JSON_EMPTY" ;;
            esac
            ;;
        wr|wrd|jwr|jwr2|jwrd|jwrd2)
            addr="${1:-}"
            data="${2:-}"
            extra="${3:-}"
            local operation="write"
            if [[ "$cmd" == "wrd" || "$cmd" == "jwrd" || "$cmd" == "jwrd2" ]]; then
                operation="write_read"
            fi
            if [[ -z "$addr" || -z "$data" ]]; then
                json_early "$cmd" "$operation" "Missing args. Example: ./xsdb.sh $cmd 00001000 1" "$MEM_JSON_EMPTY"
                exit 1
            fi
            if [[ -n "$extra" ]]; then
                json_early "$cmd" "$operation" "Unknown argument: $extra" "$MEM_JSON_EMPTY"
                exit 1
            fi
            json_require_hex address "$addr" "$cmd" "$operation" "$MEM_JSON_EMPTY"
            json_require_hex data "$data" "$cmd" "$operation" "$MEM_JSON_EMPTY"
            case "$cmd" in
                wr)    run_xsdb_json "json_cli_main write {$addr} {$data} mb 0 wr" wr write "$MEM_JSON_EMPTY" ;;
                wrd)   run_xsdb_json "json_cli_main write_read {$addr} {$data} mb 0 wrd" wrd write_read "$MEM_JSON_EMPTY" ;;
                jwr)   run_xsdb_json "json_cli_main write {$addr} {$data} jtag 1 jwr" jwr write "$MEM_JSON_EMPTY" ;;
                jwr2)  run_xsdb_json "json_cli_main write {$addr} {$data} jtag 2 jwr2" jwr2 write "$MEM_JSON_EMPTY" ;;
                jwrd)  run_xsdb_json "json_cli_main write_read {$addr} {$data} jtag 1 jwrd" jwrd write_read "$MEM_JSON_EMPTY" ;;
                jwrd2) run_xsdb_json "json_cli_main write_read {$addr} {$data} jtag 2 jwrd2" jwrd2 write_read "$MEM_JSON_EMPTY" ;;
            esac
            ;;
        *)
            json_early "$cmd" "$cmd" "Unknown command: $cmd" "$TGT_JSON_EMPTY"
            exit 1
            ;;
    esac
}

JSON_FLAG=0
for _arg in "$@"; do
    if [[ "$_arg" == "--json" ]]; then
        JSON_FLAG=1
    fi
done
if ! XSDB="$(find_xsdb)"; then
    if [[ "$JSON_FLAG" -eq 1 ]]; then
        json_early xsdb error "xsdb not found. Add Vivado Lab bin to PATH, or set XSDB." "$TGT_JSON_EMPTY"
        exit 1
    fi
    echo "ERROR: xsdb not found. Add Vivado Lab bin to PATH, or set XSDB."
    usage
    exit 1
fi

# --profile <file.tcl> may appear before the command or after verify.
# --json may appear anywhere. It selects machine-readable output.
# VIVADO_LAB_REG_PROFILE wins over XSDB_PROFILE unless --profile is passed.
PROFILE="${VIVADO_LAB_REG_PROFILE:-${XSDB_PROFILE:-}}"
JSON=0
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --json)
            JSON=1
            shift
            ;;
        --profile)
            if [[ $# -lt 2 || -z "${2:-}" ]]; then
                if [[ "$JSON_FLAG" -eq 1 ]]; then
                    json_early xsdb error "--profile needs a .tcl board profile." "$TGT_JSON_EMPTY"
                    exit 1
                fi
                echo "ERROR: --profile needs a .tcl board profile."
                echo "Example: ./xsdb.sh verify --profile $HERE/profiles/private/board.tcl"
                exit 1
            fi
            PROFILE="$2"
            shift 2
            ;;
        --profile=*)
            PROFILE="${1#--profile=}"
            if [[ -z "$PROFILE" ]]; then
                if [[ "$JSON_FLAG" -eq 1 ]]; then
                    json_early xsdb error "--profile needs a .tcl board profile." "$TGT_JSON_EMPTY"
                    exit 1
                fi
                echo "ERROR: --profile needs a .tcl board profile."
                exit 1
            fi
            shift
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done
if [[ ${#POSITIONAL[@]} -gt 0 ]]; then
    set -- "${POSITIONAL[@]}"
else
    set --
fi
if [[ -n "$PROFILE" ]]; then
    export VIVADO_LAB_REG_PROFILE="$PROFILE"
fi

cmd="${1:-interactive}"
if [[ "$JSON" -eq 1 ]]; then
    if [[ $# -eq 0 ]]; then
        json_cli_cmd interactive
    else
        json_cli_cmd "$@"
    fi
fi
case "$cmd" in
    help|-h|--help)
        usage
        ;;
    interactive|"")
        if [[ -n "${2:-}" ]]; then
            echo "Unknown argument: $2"
            echo "Usage: ./xsdb.sh [--profile file.tcl]"
            exit 1
        fi
        echo
        echo "  XSDB: JTAG -> MicroBlaze  and  JTAG -> Jtag Master"
        echo "  script: $HERE/tool.tcl"
        echo "  xsdb : $XSDB"
        if [[ -n "${VIVADO_LAB_REG_PROFILE:-}" ]]; then
            echo "  profile: $VIVADO_LAB_REG_PROFILE"
        fi
        echo
        exec "$XSDB" -interactive -eval "source {$HERE/tool.tcl}"
        ;;
    verify)
        if [[ -n "${2:-}" ]]; then
            echo "Unknown argument: $2"
            echo "Usage: ./xsdb.sh verify [--profile file.tcl]"
            echo "Example: ./xsdb.sh verify --profile $HERE/profiles/private/board.tcl"
            exit 1
        fi
        echo "verify both paths: $HERE/reg.tcl"
        if [[ -n "${VIVADO_LAB_REG_PROFILE:-}" ]]; then
            echo "board profile: $VIVADO_LAB_REG_PROFILE"
        fi
        exec "$XSDB" "$HERE/reg.tcl"
        ;;
    targets)
        exec "$XSDB" -eval "connect; targets; exit"
        ;;
    rd)
        addr="${2:-}"; len="${3:-1}"
        if [[ -z "$addr" ]]; then
            echo "Missing addr. Example: ./xsdb.sh rd 00001000 10"
            exit 1
        fi
        exec "$XSDB" -eval "set ::XSDB_QUIET 1; source {$HERE/tool.tcl}; xconnect; mb; catch {rd $addr $len}; exit"
        ;;
    wr)
        addr="${2:-}"; data="${3:-}"
        if [[ -z "$addr" || -z "$data" ]]; then
            echo "Missing args. Example: ./xsdb.sh wr 00001000 12345678"
            exit 1
        fi
        exec "$XSDB" -eval "set ::XSDB_QUIET 1; source {$HERE/tool.tcl}; xconnect; mb; catch {wr $addr $data}; exit"
        ;;
    wrd)
        addr="${2:-}"; data="${3:-}"
        if [[ -z "$addr" || -z "$data" ]]; then
            echo "Missing args. Example: ./xsdb.sh wrd 00001000 1"
            exit 1
        fi
        exec "$XSDB" -eval "set ::XSDB_QUIET 1; source {$HERE/tool.tcl}; xconnect; mb; catch {wrd $addr $data}; exit"
        ;;
    jrd)
        addr="${2:-}"; len="${3:-1}"
        if [[ -z "$addr" ]]; then
            echo "Missing addr. Example: ./xsdb.sh jrd 00002000 4"
            exit 1
        fi
        exec "$XSDB" -eval "set ::XSDB_QUIET 1; source {$HERE/tool.tcl}; xconnect; jtag 1; catch {rd $addr $len}; exit"
        ;;
    jrd2)
        addr="${2:-}"; len="${3:-1}"
        if [[ -z "$addr" ]]; then
            echo "Missing addr. Example: ./xsdb.sh jrd2 00002000 4"
            exit 1
        fi
        exec "$XSDB" -eval "set ::XSDB_QUIET 1; source {$HERE/tool.tcl}; xconnect; jtag 2; catch {rd $addr $len}; exit"
        ;;
    jwr)
        addr="${2:-}"; data="${3:-}"
        if [[ -z "$addr" || -z "$data" ]]; then
            echo "Missing args. Example: ./xsdb.sh jwr 00002008 1"
            exit 1
        fi
        exec "$XSDB" -eval "set ::XSDB_QUIET 1; source {$HERE/tool.tcl}; xconnect; jtag 1; catch {wr $addr $data}; exit"
        ;;
    jwr2)
        addr="${2:-}"; data="${3:-}"
        if [[ -z "$addr" || -z "$data" ]]; then
            echo "Missing args. Example: ./xsdb.sh jwr2 00002008 1"
            exit 1
        fi
        exec "$XSDB" -eval "set ::XSDB_QUIET 1; source {$HERE/tool.tcl}; xconnect; jtag 2; catch {wr $addr $data}; exit"
        ;;
    jwrd)
        addr="${2:-}"; data="${3:-}"
        if [[ -z "$addr" || -z "$data" ]]; then
            echo "Missing args. Example: ./xsdb.sh jwrd 00002008 1"
            exit 1
        fi
        exec "$XSDB" -eval "set ::XSDB_QUIET 1; source {$HERE/tool.tcl}; xconnect; jtag 1; catch {wrd $addr $data}; exit"
        ;;
    jwrd2)
        addr="${2:-}"; data="${3:-}"
        if [[ -z "$addr" || -z "$data" ]]; then
            echo "Missing args. Example: ./xsdb.sh jwrd2 00002008 1"
            exit 1
        fi
        exec "$XSDB" -eval "set ::XSDB_QUIET 1; source {$HERE/tool.tcl}; xconnect; jtag 2; catch {wrd $addr $data}; exit"
        ;;
    *)
        echo "Unknown command: $cmd"
        usage
        exit 1
        ;;
esac

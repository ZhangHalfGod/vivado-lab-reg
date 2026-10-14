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
  ./xsdb.sh targets         list JTAG targets
  ./xsdb.sh rd   <addr> [len]
  ./xsdb.sh wr   <addr> <data>
  ./xsdb.sh wrd  <addr> <data>
  ./xsdb.sh jrd  <addr> [len]     JTAG2AXI #1
  ./xsdb.sh jrd2 <addr> [len]     JTAG2AXI #2
  ./xsdb.sh jwr  <addr> <data>
  ./xsdb.sh jwrd <addr> <data>

Examples:
  ./xsdb.sh rd   11080000 10
  ./xsdb.sh jrd  116BCC00 4
  ./xsdb.sh jwr  116BCC08 1

EOF
}

if ! XSDB="$(find_xsdb)"; then
    echo "ERROR: xsdb not found. Add Vivado Lab bin to PATH, or set XSDB."
    usage
    exit 1
fi

cmd="${1:-interactive}"
case "$cmd" in
    help|-h|--help)
        usage
        ;;
    interactive|"")
        echo
        echo "  XSDB: JTAG -> MicroBlaze  and  JTAG -> Jtag Master"
        echo "  script: $HERE/tool.tcl"
        echo "  xsdb : $XSDB"
        echo
        exec "$XSDB" -interactive -eval "source {$HERE/tool.tcl}"
        ;;
    verify)
        echo "verify both paths: $HERE/reg.tcl"
        exec "$XSDB" "$HERE/reg.tcl"
        ;;
    targets)
        exec "$XSDB" -eval "connect; targets; exit"
        ;;
    rd)
        addr="${2:-}"; len="${3:-1}"
        if [[ -z "$addr" ]]; then
            echo "Missing addr. Example: ./xsdb.sh rd 11080000 10"
            exit 1
        fi
        exec "$XSDB" -eval "set ::XSDB_QUIET 1; source {$HERE/tool.tcl}; xconnect; mb; catch {rd $addr $len}; exit"
        ;;
    wr)
        addr="${2:-}"; data="${3:-}"
        if [[ -z "$addr" || -z "$data" ]]; then
            echo "Missing args. Example: ./xsdb.sh wr 11080000 12345678"
            exit 1
        fi
        exec "$XSDB" -eval "set ::XSDB_QUIET 1; source {$HERE/tool.tcl}; xconnect; mb; catch {wr $addr $data}; exit"
        ;;
    wrd)
        addr="${2:-}"; data="${3:-}"
        if [[ -z "$addr" || -z "$data" ]]; then
            echo "Missing args. Example: ./xsdb.sh wrd 11080000 1"
            exit 1
        fi
        exec "$XSDB" -eval "set ::XSDB_QUIET 1; source {$HERE/tool.tcl}; xconnect; mb; catch {wrd $addr $data}; exit"
        ;;
    jrd)
        addr="${2:-}"; len="${3:-1}"
        if [[ -z "$addr" ]]; then
            echo "Missing addr. Example: ./xsdb.sh jrd 116BCC00 4"
            exit 1
        fi
        exec "$XSDB" -eval "set ::XSDB_QUIET 1; source {$HERE/tool.tcl}; xconnect; jtag 1; catch {rd $addr $len}; exit"
        ;;
    jrd2)
        addr="${2:-}"; len="${3:-1}"
        if [[ -z "$addr" ]]; then
            echo "Missing addr. Example: ./xsdb.sh jrd2 116BCC00 4"
            exit 1
        fi
        exec "$XSDB" -eval "set ::XSDB_QUIET 1; source {$HERE/tool.tcl}; xconnect; jtag 2; catch {rd $addr $len}; exit"
        ;;
    jwr)
        addr="${2:-}"; data="${3:-}"
        if [[ -z "$addr" || -z "$data" ]]; then
            echo "Missing args. Example: ./xsdb.sh jwr 116BCC08 1"
            exit 1
        fi
        exec "$XSDB" -eval "set ::XSDB_QUIET 1; source {$HERE/tool.tcl}; xconnect; jtag 1; catch {wr $addr $data}; exit"
        ;;
    jwr2)
        addr="${2:-}"; data="${3:-}"
        if [[ -z "$addr" || -z "$data" ]]; then
            echo "Missing args. Example: ./xsdb.sh jwr2 116BCC08 1"
            exit 1
        fi
        exec "$XSDB" -eval "set ::XSDB_QUIET 1; source {$HERE/tool.tcl}; xconnect; jtag 2; catch {wr $addr $data}; exit"
        ;;
    jwrd)
        addr="${2:-}"; data="${3:-}"
        if [[ -z "$addr" || -z "$data" ]]; then
            echo "Missing args. Example: ./xsdb.sh jwrd 116BCC08 1"
            exit 1
        fi
        exec "$XSDB" -eval "set ::XSDB_QUIET 1; source {$HERE/tool.tcl}; xconnect; jtag 1; catch {wrd $addr $data}; exit"
        ;;
    jwrd2)
        addr="${2:-}"; data="${3:-}"
        if [[ -z "$addr" || -z "$data" ]]; then
            echo "Missing args. Example: ./xsdb.sh jwrd2 116BCC08 1"
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

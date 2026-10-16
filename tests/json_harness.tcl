# Stubbed XSDB for json_cli.tcl. No cable, no hw_server.
#   tclsh tests/json_harness.tcl <scenario>
# Prints RC, DOC, SIDE, and WORDS lines. Profile chatter on stdout is ignored
# by the shell test.
set ::XSDB_QUIET 1
set ::XSDB_JSON 1
set here [file dirname [file normalize [info script]]]
set root [file dirname $here]
source [file join $root tool.tcl]

set ::MRD_COUNT 0
set ::CHAIN [list \
    [list 1 "MicroBlaze Debug Module at USER2"] \
    [list 2 "MicroBlaze #1"] \
    [list 3 "MicroBlaze #0"] \
    [list 5 "JTAG2AXI"] \
    [list 6 "Jtag Master"] \
]

proc connect {} {
    if {[info exists ::CONNECT_FAIL]} {
        error $::CONNECT_FAIL
    }
    return ""
}

proc targets {args} {
    if {[llength $args] == 0} {
        return ""
    }
    set opt [lindex $args 0]
    if {$opt eq "-target-properties"} {
        if {[info exists ::PROPS_FAIL]} {
            error $::PROPS_FAIL
        }
        if {[info exists ::CHAIN_EMPTY]} {
            return {}
        }
        set recs {}
        foreach pair $::CHAIN {
            lappend recs [dict create target_id [lindex $pair 0] name [lindex $pair 1]]
        }
        return $recs
    }
    if {[info exists ::TARGET_FAIL]} {
        error $::TARGET_FAIL
    }
    set ::SELECTED_STUB $opt
    return ""
}

proc mrd {addr len} {
    incr ::MRD_COUNT
    if {[info exists ::MRD_FAIL]} {
        error $::MRD_FAIL
    }
    if {[info exists ::MRD_EMPTY]} {
        return ""
    }
    set words {}
    for {set i 0} {$i < $len} {incr i} {
        lappend words [format %08X [expr {$i + 1}]]
    }
    set bare $addr
    regsub -nocase {^0x} $bare {} bare
    return " $bare:   [join $words { }]"
}

proc mwr {addr data} {
    if {[info exists ::MWR_FAIL]} {
        error $::MWR_FAIL
    }
    set ::MWR_LOG "$addr $data"
    return ""
}

proc emit {pair} {
    lassign $pair rc doc
    puts "RC $rc"
    puts "DOC $doc"
    if {[info exists ::MWR_LOG]} {
        puts "SIDE mwr=$::MWR_LOG"
    } else {
        puts "SIDE mwr="
    }
    puts "SIDE mrd_count=$::MRD_COUNT"
    if {[info exists ::SELECTED_STUB]} {
        puts "SIDE selected=$::SELECTED_STUB"
    } else {
        puts "SIDE selected="
    }
}

proc show_words {label raw} {
    puts "WORDS $label [join [_json_parse_mrd $raw] {,}]"
}

set scenario [lindex $argv 0]
switch -- $scenario {
    targets-ok {
        emit [json_dispatch targets]
    }
    targets-empty {
        set ::CHAIN_EMPTY 1
        emit [json_dispatch targets]
    }
    targets-connect-fail {
        set ::CONNECT_FAIL "no cable"
        emit [json_dispatch targets]
    }
    targets-props-fail {
        set ::PROPS_FAIL "properties unavailable"
        emit [json_dispatch targets]
    }
    targets-quote {
        set ::CHAIN [list [list 4 "MicroBlaze #0 \"q\" \\ z"]]
        emit [json_dispatch targets]
    }
    read-ok {
        emit [json_dispatch read 0000_1000 1 mb 0 rd]
    }
    read-multi {
        emit [json_dispatch read 0x1000 4 mb 0 rd]
    }
    read-len-pad {
        emit [json_dispatch read 1000 08 mb 0 rd]
    }
    read-jtag2 {
        emit [json_dispatch read 00002000 2 jtag 2 jrd2]
    }
    read-no-mb {
        set ::CHAIN [list [list 5 "JTAG2AXI"]]
        emit [json_dispatch read 1000 1 mb 0 rd]
    }
    read-bad-addr {
        emit [json_dispatch read nope 1 mb 0 rd]
    }
    read-bad-len {
        emit [json_dispatch read 1000 0 mb 0 rd]
    }
    read-mrd-fail {
        set ::MRD_FAIL "timeout"
        emit [json_dispatch read 1000 1 mb 0 rd]
    }
    read-empty {
        set ::MRD_EMPTY 1
        emit [json_dispatch read 1000 1 mb 0 rd]
    }
    write-ok {
        emit [json_dispatch write 00001000 1 mb 0 wr]
    }
    write-fail {
        set ::MWR_FAIL "protected"
        emit [json_dispatch write 00001000 AB mb 0 wr]
    }
    write-bad-data {
        emit [json_dispatch write 00001000 zz mb 0 wr]
    }
    wrd-ok {
        emit [json_dispatch write_read 00002008 2 jtag 1 jwrd]
    }
    wrd-read-fail {
        set ::MRD_FAIL "readback timeout"
        emit [json_dispatch write_read 00001000 3 mb 0 wrd]
    }
    verify-skip {
        emit [json_dispatch verify]
    }
    verify-read {
        set ::MB_SMOKE_ADDR 0x0000_1000
        set ::JTAG_SMOKE_ADDR 0x2000
        set ::PROFILE_LOAD_ERROR 0
        emit [json_dispatch verify]
    }
    verify-no-jtag {
        set ::CHAIN [list \
            [list 1 "MicroBlaze Debug Module at USER2"] \
            [list 3 "MicroBlaze #0"] \
        ]
        emit [json_dispatch verify]
    }
    verify-no-mb {
        set ::CHAIN [list [list 5 "JTAG2AXI"] [list 6 "Jtag Master"]]
        emit [json_dispatch verify]
    }
    verify-bad {
        set ::MB_SMOKE_ADDR not-hex
        set ::JTAG_SMOKE_ADDR 0x20
        set ::PROFILE_LOAD_ERROR 0
        emit [json_dispatch verify]
    }
    verify-connect-fail {
        set ::CONNECT_FAIL "no cable"
        emit [json_dispatch verify]
    }
    verify-profile {
        emit [json_dispatch verify]
    }
    parse {
        show_words grouped "       00001000:   DEADBEEF 00000002\n       00001008:   00000003\r\n"
        show_words prefixed " 0x00001000:   0x10 2\n"
        show_words bare "DEADBEEF 00000002"
        show_words empty ""
    }
    publish {
        _json_publish "{\"ok\":true,\"command\":\"targets\",\"operation\":\"targets\",\"error\":null,\"targets\":\[\]}"
        puts "PUBLISHED"
    }
    default {
        puts "RC 1"
        puts "DOC \{\"ok\":false,\"error\":\"unknown scenario $scenario\"\}"
        exit 1
    }
}

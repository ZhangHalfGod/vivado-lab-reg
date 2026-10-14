# Scheme B: interactive short commands
# Windows:  xsdb.cmd
# Linux:    ./xsdb.sh
# or in xsdb%:  source {this_dir/tool.tcl}
#
# Two JTAG paths (same xsdb session, switch target then mrd/mwr):
#   JTAG -> XSDB -> MDM -> MicroBlaze
#   JTAG -> XSDB -> Legacy Debug Hub -> JTAG2AXI (Jtag Master / hw_axi)

# EXAMPLE board defaults — override before source, or use profiles/
if {![info exists ::MB_SMOKE_ADDR]}   { set ::MB_SMOKE_ADDR   0x11080000 }
if {![info exists ::JTAG_SMOKE_ADDR]} { set ::JTAG_SMOKE_ADDR 0x116BCC00 }
if {![info exists ::PATH]}            { set ::PATH "" }
if {![info exists ::JTAG_N]}          { set ::JTAG_N 0 }

proc _ax {a} {
    set a [string map {_ "" 0x "" 0X ""} $a]
    return [format 0x%08X [expr 0x$a]]
}

proc _j2a_ids {} {
    set ids {}
    if {[catch {set recs [targets -target-properties]}]} {
        return $ids
    }
    foreach rec $recs {
        if {[catch {set nm [dict get $rec name]}]} {
            continue
        }
        if {[string equal -nocase $nm "JTAG2AXI"]} {
            lappend ids [dict get $rec target_id]
        }
    }
    return [lsort -integer $ids]
}

proc _select_mb {} {
    if {![catch {targets -set -nocase -filter {name =~ "*MicroBlaze #0*"}}]} {
        set ::PATH mb
        set ::JTAG_N 0
        return 0
    }
    if {![catch {targets -set -nocase -filter {name =~ "*MicroBlaze*"}}]} {
        set ::PATH mb
        set ::JTAG_N 0
        return 0
    }
    return 1
}

proc xconnect {} {
    if {[catch {connect} err]} {
        puts "ERROR: connect failed: $err"
        puts "Power the board, program bitstream; close Hardware Manager if it holds JTAG."
        return 1
    }
    targets
    set ::PATH ""
    set ::JTAG_N 0
    set jids [_j2a_ids]
    puts "paths:"
    puts "  MicroBlaze : JTAG -> XSDB -> MDM -> MicroBlaze"
    puts "  JTAG2AXI   : JTAG -> XSDB -> Jtag Master   count=[llength $jids] ids=$jids"

    if {![_select_mb]} {
        puts "current = MicroBlaze   (cmd: mb)"
    } elseif {[llength $jids]} {
        jtag 1
    } else {
        puts "ERROR: no MicroBlaze and no JTAG2AXI. Use:  targets <id>"
        return 1
    }
    return 0
}

proc mb {} {
    if {[_select_mb]} {
        puts "ERROR: MicroBlaze not found. Run:  xconnect"
        return 1
    }
    puts "path = JTAG -> XSDB -> MDM -> MicroBlaze"
    return 0
}

# Select nth JTAG2AXI (1-based). Same cores as Hardware Manager hw_axi_1 / hw_axi_2.
proc jtag {{n 1}} {
    set ids [_j2a_ids]
    if {![llength $ids]} {
        puts "ERROR: no JTAG2AXI (Jtag Master) on this scan chain"
        return 1
    }
    set idx [expr {$n - 1}]
    if {$idx < 0 || $idx >= [llength $ids]} {
        puts "ERROR: JTAG2AXI #$n not found. available ids: $ids"
        return 1
    }
    set id [lindex $ids $idx]
    if {[catch {targets $id} err]} {
        puts "ERROR: targets $id: $err"
        return 1
    }
    set ::PATH jtag
    set ::JTAG_N $n
    puts "path = JTAG -> XSDB -> Jtag Master  JTAG2AXI #$n  (target $id)"
    return 0
}

proc axi {n} {
    return [jtag $n]
}

proc path {} {
    if {$::PATH eq "mb"} {
        puts "current path = JTAG -> XSDB -> MDM -> MicroBlaze"
    } elseif {$::PATH eq "jtag"} {
        puts "current path = JTAG -> XSDB -> Jtag Master  JTAG2AXI #$::JTAG_N"
    } else {
        puts "current path = (none)  run:  xconnect"
    }
}

proc rd {addr {len 1}} {
    puts [mrd [_ax $addr] $len]
}

proc wr {addr data} {
    puts [mwr [_ax $addr] [_ax $data]]
}

proc wrd {addr data} {
    wr $addr $data
    rd $addr
}

proc smoke {} {
    puts "===== MB  mrd $::MB_SMOKE_ADDR 10 ====="
    if {[mb]} { return 1 }
    puts [mrd $::MB_SMOKE_ADDR 10]
}

proc jsmoke {{n 1}} {
    puts "===== JTAG2AXI #$n  mrd $::JTAG_SMOKE_ADDR 4 ====="
    if {[jtag $n]} { return 1 }
    puts [mrd $::JTAG_SMOKE_ADDR 4]
}

proc verify_all {} {
    puts "========== verify both paths =========="
    smoke
    set ids [_j2a_ids]
    set i 1
    foreach id $ids {
        jsmoke $i
        incr i
    }
    puts "========== verify done =========="
}

proc help_xsdb {} {
    puts "tool.tcl  (Vivado Lab XSDB, two paths)"
    puts "  xconnect              connect hw_server, list both paths"
    puts "  mb                    path: JTAG -> XSDB -> MicroBlaze"
    puts "  jtag \[n\]              path: JTAG -> XSDB -> Jtag Master  (n=1|2)"
    puts "  axi n                 same as jtag n  (hw_axi_1 / hw_axi_2)"
    puts "  path                  show current path"
    puts "  rd <addr> \[len\]       read current target"
    puts "  wr <addr> <data>      write current target"
    puts "  wrd <addr> <data>     write then read back"
    puts "  smoke                 MB: mrd 0x11080000 10"
    puts "  jsmoke \[n\]            JTAG2AXI: mrd 0x116BCC00 4"
    puts "  verify_all            smoke both paths"
    puts "  targets               list JTAG targets"
    puts "  help_xsdb             this help"
}

if {![info exists ::XSDB_QUIET]} {
    xconnect
    help_xsdb
    puts "tool.tcl ready."
}

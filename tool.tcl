# Scheme B: interactive short commands
# Windows:  xsdb.cmd
# Linux:    ./xsdb.sh
# or in xsdb%:  source {this_dir/tool.tcl}
#
# Two JTAG paths (same xsdb session, switch target then mrd/mwr):
#   JTAG -> XSDB -> MDM -> MicroBlaze
#   JTAG -> XSDB -> Legacy Debug Hub -> JTAG2AXI (Jtag Master / hw_axi)
#
# GUI scan (gui.py), no fixed path slots:
#   gui_connect / enum_targets  ->  TGT <id> <name>
#   select_id <id>              ->  targets <id>, then rd / wr / wrd

# Smoke addresses come from a board profile (Master Base Address).
#   xsdb.cmd verify --profile <file.tcl>
#   set VIVADO_LAB_REG_PROFILE / set XSDB_PROFILE
# Unset or 0x0 skips that mrd. No lab address is built in.
if {![info exists ::PATH]}   { set ::PATH "" }
if {![info exists ::JTAG_N]} { set ::JTAG_N 0 }
set ::TOOL_TCL_DIR [file dirname [file normalize [info script]]]

proc _ax {a} {
    set a [string trim $a]
    set a [string map {_ "" 0x "" 0X ""} $a]
    return [format 0x%08X [expr 0x$a]]
}

proc _smoke_addr_kind {addr} {
    set t [string trim $addr]
    if {$t eq ""} {
        return zero
    }
    if {[catch {set norm [_ax $t]}]} {
        return bad
    }
    if {$norm eq "0x00000000"} {
        return zero
    }
    return ok
}

proc _resolve_profile_path {path} {
    set path [string trim $path]
    if {$path eq ""} {
        return ""
    }
    if {[file isfile $path]} {
        return [file normalize $path]
    }
    if {[info exists ::TOOL_TCL_DIR] && $::TOOL_TCL_DIR ne ""} {
        set candidate [file join $::TOOL_TCL_DIR $path]
        if {[file isfile $candidate]} {
            return [file normalize $candidate]
        }
    }
    set candidate [file join [pwd] $path]
    if {[file isfile $candidate]} {
        return [file normalize $candidate]
    }
    return ""
}

proc _requested_profile_path {} {
    if {[info exists ::VIVADO_LAB_REG_PROFILE]} {
        set p [string trim $::VIVADO_LAB_REG_PROFILE]
        if {$p ne ""} {
            return $p
        }
    }
    foreach name {VIVADO_LAB_REG_PROFILE XSDB_PROFILE} {
        if {[info exists ::env($name)]} {
            set p [string trim $::env($name)]
            if {$p ne ""} {
                return $p
            }
        }
    }
    return ""
}

proc _apply_smoke_defaults {} {
    if {![info exists ::MB_SMOKE_ADDR] || [string trim $::MB_SMOKE_ADDR] eq ""} {
        set ::MB_SMOKE_ADDR 0x0
    }
    if {![info exists ::JTAG_SMOKE_ADDR] || [string trim $::JTAG_SMOKE_ADDR] eq ""} {
        set ::JTAG_SMOKE_ADDR 0x0
    }
}

proc _announce_profile {} {
    if {[info exists ::PROFILE_LOAD_ERROR] && $::PROFILE_LOAD_ERROR} {
        puts "board profile: NOT LOADED"
    } elseif {[info exists ::LOADED_PROFILE]} {
        puts "board profile: $::PROFILE_NAME ($::LOADED_PROFILE)"
    } else {
        puts "board profile: (none)"
    }
    puts "MB_SMOKE_ADDR=$::MB_SMOKE_ADDR JTAG_SMOKE_ADDR=$::JTAG_SMOKE_ADDR"
    foreach {var label} {::MB_SMOKE_ADDR MB_SMOKE_ADDR ::JTAG_SMOKE_ADDR JTAG_SMOKE_ADDR} {
        set kind [_smoke_addr_kind [set $var]]
        if {$kind eq "bad"} {
            puts "ERROR: $label is not a hex Master Base Address: [set $var]"
            set ::PROFILE_LOAD_ERROR 1
        }
    }
    set mb_kind [_smoke_addr_kind $::MB_SMOKE_ADDR]
    set jtag_kind [_smoke_addr_kind $::JTAG_SMOKE_ADDR]
    if {$mb_kind eq "zero" || $jtag_kind eq "zero"} {
        puts "smoke/verify skips a path whose Master Base Address is 0x0."
    }
}

# Source a profile Tcl file (global scope) and fill any address still unset with 0x0.
# Returns 0 on success or when no profile was requested, 1 when the file is missing,
# fails to source, or sets a non-hex address.
proc load_board_profile {{path ""}} {
    if {[info exists ::_LOADING_PROFILE] && $::_LOADING_PROFILE} {
        return 0
    }
    set ::_LOADING_PROFILE 1
    set ::PROFILE_LOAD_ERROR 0
    unset -nocomplain ::LOADED_PROFILE
    set rc 0
    if {$path eq ""} {
        set path [_requested_profile_path]
    }
    if {$path eq ""} {
        _apply_smoke_defaults
        _announce_profile
        set ::_LOADING_PROFILE 0
        return 0
    }
    set resolved [_resolve_profile_path $path]
    if {$resolved eq ""} {
        puts "ERROR: board profile not found: $path"
        set ::PROFILE_LOAD_ERROR 1
        unset -nocomplain ::MB_SMOKE_ADDR ::JTAG_SMOKE_ADDR ::PROFILE_NAME
        _apply_smoke_defaults
        _announce_profile
        set ::_LOADING_PROFILE 0
        return 1
    }
    unset -nocomplain ::MB_SMOKE_ADDR ::JTAG_SMOKE_ADDR ::PROFILE_NAME
    if {[catch {uplevel #0 [list source $resolved]} err]} {
        puts "ERROR: board profile failed: $resolved"
        puts "ERROR: $err"
        set ::PROFILE_LOAD_ERROR 1
        unset -nocomplain ::MB_SMOKE_ADDR ::JTAG_SMOKE_ADDR ::PROFILE_NAME ::LOADED_PROFILE
        set rc 1
    } else {
        set ::LOADED_PROFILE $resolved
        if {![info exists ::PROFILE_NAME] || [string trim $::PROFILE_NAME] eq ""} {
            set ::PROFILE_NAME [file rootname [file tail $resolved]]
        }
    }
    _apply_smoke_defaults
    _announce_profile
    set ::_LOADING_PROFILE 0
    if {$::PROFILE_LOAD_ERROR} {
        return 1
    }
    return $rc
}

proc _skip_smoke_msg {which var} {
    puts "SKIP $which mrd: $var is 0x0 or unset, so this read is not issued."
    puts "  Set the Master Base Address from Vivado Address Editor (not Slave Base 0x0)."
    puts "  Example: xsdb.cmd verify --profile D:/lab/vivado-lab-reg/profiles/private/board.tcl"
    puts "  or set VIVADO_LAB_REG_PROFILE (XSDB_PROFILE is also read)."
}

proc _clean_target_name {nm} {
    return [string trim [string map {\r " " \n " "} $nm]]
}

# Memory masters the GUI can mrd/mwr. MDM parents match "MicroBlaze" but are not cores.
proc _is_mb_target {nm} {
    if {![string match -nocase "*MicroBlaze*" $nm]} {
        return 0
    }
    if {[string match -nocase "*Debug Module*" $nm]} {
        return 0
    }
    return 1
}

# JTAG-to-AXI class: XSDB "JTAG2AXI", Hardware Manager "Jtag Master", and the same IP's other names.
proc _is_j2a_target {nm} {
    if {[string equal -nocase $nm "JTAG2AXI"]} {
        return 1
    }
    if {[string match -nocase "*Jtag*Master*" $nm]} {
        return 1
    }
    if {[string match -nocase "*jtag_axi*" $nm]} {
        return 1
    }
    if {[string match -nocase "*jtag*to*axi*" $nm]} {
        return 1
    }
    return 0
}

proc _is_access_target {nm} {
    if {[_is_mb_target $nm]} {
        return 1
    }
    return [_is_j2a_target $nm]
}

proc _access_target_recs {} {
    set pairs {}
    if {[catch {set recs [targets -target-properties]}]} {
        return {}
    }
    foreach rec $recs {
        if {[catch {set nm [dict get $rec name]}]} {
            continue
        }
        if {[catch {set id [dict get $rec target_id]}]} {
            continue
        }
        set nm [_clean_target_name $nm]
        if {$nm eq ""} {
            continue
        }
        if {![string is integer -strict $id] || $id < 0} {
            continue
        }
        if {![_is_access_target $nm]} {
            continue
        }
        dict set rec name $nm
        lappend pairs [list $id $rec]
    }
    set pairs [lsort -integer -index 0 $pairs]
    set out {}
    foreach pair $pairs {
        lappend out [lindex $pair 1]
    }
    return $out
}

proc _j2a_ids {} {
    set ids {}
    foreach rec [_access_target_recs] {
        if {[catch {set nm [dict get $rec name]}]} {
            continue
        }
        if {[_is_j2a_target $nm]} {
            lappend ids [dict get $rec target_id]
        }
    }
    return $ids
}

# Machine-readable scan for the GUI.
#   TGT <id> <name>     one line per MicroBlaze / JTAG2AXI / Jtag Master
#   TGT_NONE            nothing on the chain matched
proc enum_targets {} {
    set recs [_access_target_recs]
    if {![llength $recs]} {
        puts "No register targets found."
        puts "TGT_NONE"
    } else {
        set n [llength $recs]
        if {$n == 1} {
            puts "Scanned 1 register target."
        } else {
            puts "Scanned $n register targets."
        }
        foreach rec $recs {
            set id [dict get $rec target_id]
            set nm [dict get $rec name]
            puts "TGT $id $nm"
        }
    }
    # Full chain after the machine-readable lines, so the log shows what XSDB enumerated.
    catch {targets}
    return 0
}

proc select_id {id} {
    if {![string is integer -strict $id] || $id < 0} {
        puts "ERROR: bad target id: $id"
        return 1
    }
    if {[catch {targets $id} err]} {
        puts "ERROR: targets $id: $err"
        return 1
    }
    set nm ""
    if {![catch {set recs [targets -target-properties]}]} {
        foreach rec $recs {
            if {[catch {set tid [dict get $rec target_id]}]} {
                continue
            }
            if {$tid == $id} {
                catch {set nm [_clean_target_name [dict get $rec name]]}
                break
            }
        }
    }
    set ::SELECTED_ID $id
    if {[_is_mb_target $nm]} {
        set ::PATH mb
        set ::JTAG_N 0
    } elseif {[_is_j2a_target $nm]} {
        set ::PATH jtag
        set ids [_j2a_ids]
        set idx [lsearch -exact $ids $id]
        if {$idx >= 0} {
            set ::JTAG_N [expr {$idx + 1}]
        } else {
            set ::JTAG_N 0
        }
    } else {
        set ::PATH ""
        set ::JTAG_N 0
    }
    if {$nm eq ""} {
        puts "selected target $id"
    } else {
        puts "selected target $id $nm"
    }
    return 0
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

# Connect for the GUI. Does not pick a hard-coded path; the list comes from the scan.
proc gui_connect {} {
    if {[catch {connect} err]} {
        puts "ERROR: connect failed: $err"
        puts "Power the board, program bitstream; close Hardware Manager if it holds JTAG."
        return 1
    }
    puts "CONNECT_OK"
    enum_targets
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
    set addr $::MB_SMOKE_ADDR
    set kind [_smoke_addr_kind $addr]
    puts "===== MB smoke ====="
    if {$kind eq "bad"} {
        puts "ERROR: MB_SMOKE_ADDR is not a hex Master Base Address: $addr"
        return 1
    }
    if {[mb]} { return 1 }
    if {$kind eq "zero"} {
        _skip_smoke_msg "MicroBlaze" MB_SMOKE_ADDR
        return 0
    }
    set norm [_ax [string trim $addr]]
    puts "mrd $norm 10"
    puts [mrd $norm 10]
    return 0
}

proc jsmoke {{n 1}} {
    set addr $::JTAG_SMOKE_ADDR
    set kind [_smoke_addr_kind $addr]
    set ids [_j2a_ids]
    puts "===== JTAG2AXI #$n smoke ids=$ids ====="
    if {$kind eq "bad"} {
        puts "ERROR: JTAG_SMOKE_ADDR is not a hex Master Base Address: $addr"
        return 1
    }
    if {[jtag $n]} { return 1 }
    if {$kind eq "zero"} {
        _skip_smoke_msg "JTAG2AXI #$n" JTAG_SMOKE_ADDR
        return 0
    }
    set norm [_ax [string trim $addr]]
    puts "mrd $norm 4"
    puts [mrd $norm 4]
    return 0
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
    puts "  jtag \[n\]              path: JTAG -> XSDB -> Jtag Master  (nth match)"
    puts "  enum_targets          list register targets as: TGT <id> <name>"
    puts "  select_id <id>        select a scanned target by id"
    puts "  axi n                 same as jtag n  (hw_axi_1 / hw_axi_2)"
    puts "  path                  show current path"
    puts "  rd <addr> \[len\]       read current target"
    puts "  wr <addr> <data>      write current target"
    puts "  wrd <addr> <data>     write then read back"
    puts "  smoke                 MB: mrd MB_SMOKE_ADDR 10 (skip if 0x0)"
    puts "  jsmoke \[n\]            JTAG2AXI: mrd JTAG_SMOKE_ADDR 4 (skip if 0x0)"
    puts "  verify_all            smoke both paths (addresses from the board profile)"
    puts "  load_board_profile \[f\]  source a profile Tcl (or the env path)"
    puts "  MB_SMOKE_ADDR=$::MB_SMOKE_ADDR  JTAG_SMOKE_ADDR=$::JTAG_SMOKE_ADDR"
    puts "  targets               list JTAG targets"
    puts "  help_xsdb             this help"
}

load_board_profile

if {![info exists ::XSDB_QUIET]} {
    xconnect
    help_xsdb
    puts "tool.tcl ready."
}

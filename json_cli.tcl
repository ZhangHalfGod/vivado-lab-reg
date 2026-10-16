# Machine-readable results for xsdb.sh --json / xsdb.cmd --json.
# Sourced by tool.tcl. Human commands (rd, enum_targets, xconnect, ...) stay as they are.
#
# One compact JSON object per invocation. The shell wrapper also writes it to
# VIVADO_LAB_REG_JSON_FILE when that path is set, and prints a sentinel line:
#   VIVADO_LAB_REG_JSON { ... }
# so a chatty XSDB banner can be stripped off stdout.
#
# Shared status fields: ok, command, operation, error.
# Target object: id, name, class. class is microblaze or jtag2axi.
# Memory fields: skipped, reason, target, address, length, data, written.

proc _json_escape {s} {
    return [string map [list \\ \\\\ \" \\\" \b \\b \f \\f \n \\n \r \\r \t \\t] $s]
}

proc _json_bool {v} {
    if {$v} {
        return true
    }
    return false
}

proc _json_string {s} {
    return "\"[_json_escape $s]\""
}

proc _json_str_or_null {s} {
    if {$s eq ""} {
        return null
    }
    return [_json_string $s]
}

proc _json_string_array {items} {
    set parts {}
    foreach item $items {
        lappend parts [_json_string $item]
    }
    return "\[[join $parts ,]\]"
}

proc _json_status {ok command operation error} {
    return "\"ok\":[_json_bool $ok],\"command\":[_json_string $command],\"operation\":[_json_string $operation],\"error\":[_json_str_or_null $error]"
}

proc _json_target {id name class} {
    set class_json [_json_str_or_null $class]
    return "\{\"id\":$id,\"name\":[_json_string $name],\"class\":$class_json\}"
}

proc _json_class {nm} {
    if {[_is_mb_target $nm]} {
        return microblaze
    }
    if {[_is_j2a_target $nm]} {
        return jtag2axi
    }
    return ""
}

proc _json_targets_doc {ok error items} {
    return "\{[_json_status $ok targets targets $error],\"targets\":\[[join $items ,]\]\}"
}

proc _json_verify_doc {ok error results} {
    return "\{[_json_status $ok verify verify $error],\"results\":\[[join $results ,]\]\}"
}

proc _json_mem_doc {ok command operation error skipped reason id name class address length data written} {
    if {$id eq "" || ![regexp {^(?:0|[1-9][0-9]*)$} $id]} {
        set target null
    } else {
        set target [_json_target $id $name $class]
    }
    if {![regexp {^(?:0|[1-9][0-9]*)$} $length]} {
        set length_json null
    } else {
        set length_json $length
    }
    return "\{[_json_status $ok $command $operation $error],\"skipped\":[_json_bool $skipped],\"reason\":[_json_str_or_null $reason],\"target\":$target,\"address\":[_json_str_or_null $address],\"length\":$length_json,\"data\":[_json_string_array $data],\"written\":[_json_string_array $written]\}"
}

proc _json_word {tok} {
    set tok [string trim $tok]
    if {[string match -nocase 0x* $tok]} {
        set tok [string range $tok 2 end]
    }
    if {![regexp {^[0-9A-Fa-f]+$} $tok]} {
        return ""
    }
    if {[catch {format 0x%08X 0x$tok} out]} {
        return ""
    }
    return $out
}

# XSDB mrd text looks like " 00001000:   DEADBEEF 00000002". A stub or a
# bare return may also be a list of hex words with no address column.
proc _json_parse_mrd {raw} {
    set raw [string map {\r ""} $raw]
    set words {}
    set matched 0
    foreach line [split $raw \n] {
        set line [string trim $line]
        if {$line eq ""} {
            continue
        }
        regsub -nocase {^0x} $line {} line
        if {[regexp {^([0-9A-Fa-f]+):\s*(.*)$} $line -> _addr rest]} {
            set matched 1
            foreach tok $rest {
                set w [_json_word $tok]
                if {$w ne ""} {
                    lappend words $w
                }
            }
        }
    }
    if {$matched} {
        return $words
    }
    foreach tok $raw {
        set w [_json_word $tok]
        if {$w ne ""} {
            lappend words $w
        }
    }
    return $words
}

proc _json_publish {body} {
    set path ""
    if {[info exists ::env(VIVADO_LAB_REG_JSON_FILE)]} {
        set path [string trim $::env(VIVADO_LAB_REG_JSON_FILE)]
    }
    if {$path ne ""} {
        if {[catch {
            set fh [open $path w]
            puts $fh $body
            close $fh
        } err]} {
            puts stderr "ERROR: could not write JSON result: $err"
        }
    }
    puts "VIVADO_LAB_REG_JSON $body"
}

proc _json_connect {} {
    if {[info exists ::JSON_CONNECTED] && $::JSON_CONNECTED} {
        return ""
    }
    if {[catch {connect} err]} {
        return "connect failed: $err. Power the board, program bitstream; close Hardware Manager if it holds JTAG."
    }
    set ::JSON_CONNECTED 1
    return ""
}

# Returns {rc id name class err}. rc 0 means the target is selected.
# MicroBlaze prefers a name matching "*MicroBlaze #0*", then any other core.
# JTAG index n is 1-based in the current scan, same as `jtag n`.
proc _json_select {path n} {
    set cerr [_json_connect]
    if {$cerr ne ""} {
        return [list 1 "" "" "" $cerr]
    }
    if {$path eq "mb"} {
        set chosen ""
        set fallback ""
        foreach rec [_access_target_recs] {
            if {[catch {set nm [dict get $rec name]}]} {
                continue
            }
            if {![_is_mb_target $nm]} {
                continue
            }
            if {[string match -nocase "*MicroBlaze #0*" $nm]} {
                set chosen $rec
                break
            }
            if {$fallback eq ""} {
                set fallback $rec
            }
        }
        if {$chosen eq ""} {
            set chosen $fallback
        }
        if {$chosen eq ""} {
            return [list 1 "" "" "" "MicroBlaze not found"]
        }
        set id [dict get $chosen target_id]
        set nm [dict get $chosen name]
        if {[catch {targets $id} terr]} {
            return [list 1 $id $nm microblaze "targets $id: $terr"]
        }
        set ::PATH mb
        set ::JTAG_N 0
        set ::SELECTED_ID $id
        return [list 0 $id $nm microblaze ""]
    }
    if {$path eq "jtag"} {
        set ids [_j2a_ids]
        if {![llength $ids]} {
            return [list 1 "" "" "" "no JTAG2AXI (Jtag Master) on this scan chain"]
        }
        if {![string is integer -strict $n]} {
            return [list 1 "" "" "" "bad JTAG2AXI index: $n"]
        }
        set idx [expr {$n - 1}]
        if {$idx < 0 || $idx >= [llength $ids]} {
            return [list 1 "" "" "" "JTAG2AXI #$n not found. available ids: $ids"]
        }
        set id [lindex $ids $idx]
        set nm ""
        foreach rec [_access_target_recs] {
            if {[catch {set tid [dict get $rec target_id]}]} {
                continue
            }
            if {$tid == $id} {
                set nm [dict get $rec name]
                break
            }
        }
        if {[catch {targets $id} terr]} {
            return [list 1 $id $nm jtag2axi "targets $id: $terr"]
        }
        set ::PATH jtag
        set ::JTAG_N $n
        set ::SELECTED_ID $id
        return [list 0 $id $nm jtag2axi ""]
    }
    return [list 1 "" "" "" "unknown path: $path"]
}

proc _json_capture_read {address length} {
    if {[catch {set raw [mrd $address $length]} err]} {
        return [list 1 "mrd failed: $err" {}]
    }
    set words [_json_parse_mrd $raw]
    if {![llength $words]} {
        return [list 1 "mrd returned no data" {}]
    }
    return [list 0 "" $words]
}

proc _json_norm_len {len} {
    if {![regexp {^[0-9]+$} [string trim $len]]} {
        return ""
    }
    if {[catch {scan [string trim $len] %d n}]} {
        return ""
    }
    if {$n eq "" || $n < 1} {
        return ""
    }
    return $n
}

proc json_do_targets {} {
    set cerr [_json_connect]
    if {$cerr ne ""} {
        return [list 1 [_json_targets_doc 0 $cerr {}]]
    }
    if {[catch {targets -target-properties} err]} {
        return [list 1 [_json_targets_doc 0 "targets failed: $err" {}]]
    }
    set items {}
    foreach rec [_access_target_recs] {
        if {[catch {set id [dict get $rec target_id]}]} {
            continue
        }
        if {[catch {set nm [dict get $rec name]}]} {
            continue
        }
        lappend items [_json_target $id $nm [_json_class $nm]]
    }
    return [list 0 [_json_targets_doc 1 "" $items]]
}

proc json_do_access {operation command addr len data path n} {
    set written {}
    set wnorm ""
    if {$operation eq "read"} {
        set len [_json_norm_len $len]
    } else {
        set len 1
    }
    set norm ""
    if {[catch {set norm [_ax $addr]} err]} {
        return [list 1 [_json_mem_doc 0 $command $operation "bad address: $addr" 0 "" "" "" "" "" $len {} {}]]
    }
    if {$operation eq "read" && $len eq ""} {
        return [list 1 [_json_mem_doc 0 $command $operation "length must be a positive integer" 0 "" "" "" "" $norm "" {} {}]]
    }
    if {$operation ne "read"} {
        if {[catch {set wnorm [_ax $data]} err]} {
            return [list 1 [_json_mem_doc 0 $command $operation "bad data: $data" 0 "" "" "" "" $norm "" {} {}]]
        }
        set written [list $wnorm]
    }
    lassign [_json_select $path $n] src sid sname sclass serr
    if {$src != 0} {
        set data_out {}
        if {$operation eq "write"} {
            set data_out $written
        }
        return [list 1 [_json_mem_doc 0 $command $operation $serr 0 "" $sid $sname $sclass $norm $len $data_out $written]]
    }
    if {$operation eq "read"} {
        lassign [_json_capture_read $norm $len] rrc rerr words
        if {$rrc != 0} {
            return [list 1 [_json_mem_doc 0 $command read $rerr 0 "" $sid $sname $sclass $norm $len {} {}]]
        }
        return [list 0 [_json_mem_doc 1 $command read "" 0 "" $sid $sname $sclass $norm $len $words {}]]
    }
    if {[catch {mwr $norm $wnorm} err]} {
        set data_out {}
        if {$operation eq "write"} {
            set data_out $written
        }
        return [list 1 [_json_mem_doc 0 $command $operation "mwr failed: $err" 0 "" $sid $sname $sclass $norm 1 $data_out $written]]
    }
    if {$operation eq "write"} {
        return [list 0 [_json_mem_doc 1 $command write "" 0 "" $sid $sname $sclass $norm 1 $written $written]]
    }
    lassign [_json_capture_read $norm 1] rrc rerr words
    if {$rrc != 0} {
        return [list 1 [_json_mem_doc 0 $command write_read $rerr 0 "" $sid $sname $sclass $norm 1 {} $written]]
    }
    return [list 0 [_json_mem_doc 1 $command write_read "" 0 "" $sid $sname $sclass $norm 1 $words $written]]
}

proc _json_smoke_addr {addr} {
    set kind [_smoke_addr_kind $addr]
    if {$kind eq "zero"} {
        return 0x00000000
    }
    if {$kind eq "ok"} {
        return [_ax [string trim $addr]]
    }
    return ""
}

# Returns {rc err doc}. A missing MicroBlaze is a skip (rc 0), matching reg.tcl.
proc _json_smoke_result {command which var length} {
    set addr [set $var]
    if {$which eq "jtag"} {
        lassign [_json_select jtag $::JSON_JTAG_N] src sid sname sclass serr
    } else {
        lassign [_json_select mb 0] src sid sname sclass serr
    }
    if {$src != 0} {
        if {$which eq "mb" && $serr eq "MicroBlaze not found"} {
            return [list 0 "" [_json_mem_doc 1 $command read "" 1 "MicroBlaze not found" "" "" "" [_json_smoke_addr $addr] $length {} {}]]
        }
        return [list 1 $serr [_json_mem_doc 0 $command read $serr 0 "" $sid $sname $sclass "" $length {} {}]]
    }
    set kind [_smoke_addr_kind $addr]
    set label $var
    regsub {^::} $label {} label
    if {$kind eq "bad"} {
        set msg "$label is not a hex Master Base Address: $addr"
        return [list 1 $msg [_json_mem_doc 0 $command read $msg 0 "" $sid $sname $sclass "" $length {} {}]]
    }
    if {$kind eq "zero"} {
        set msg "$label is 0x0 or unset, so this read is not issued."
        return [list 0 "" [_json_mem_doc 1 $command read "" 1 $msg $sid $sname $sclass 0x00000000 $length {} {}]]
    }
    set norm [_ax [string trim $addr]]
    lassign [_json_capture_read $norm $length] rrc rerr words
    if {$rrc != 0} {
        return [list 1 $rerr [_json_mem_doc 0 $command read $rerr 0 "" $sid $sname $sclass $norm $length {} {}]]
    }
    return [list 0 "" [_json_mem_doc 1 $command read "" 0 "" $sid $sname $sclass $norm $length $words {}]]
}

proc json_do_verify {} {
    if {[info exists ::PROFILE_LOAD_ERROR] && $::PROFILE_LOAD_ERROR} {
        return [list 1 [_json_verify_doc 0 "verify aborted because the board profile did not load." {}]]
    }
    set cerr [_json_connect]
    if {$cerr ne ""} {
        return [list 1 [_json_verify_doc 0 $cerr {}]]
    }
    set results {}
    set fail ""
    lassign [_json_smoke_result smoke mb ::MB_SMOKE_ADDR 10] src serr doc
    lappend results $doc
    if {$src != 0} {
        set fail $serr
    }
    set ids [_j2a_ids]
    if {![llength $ids]} {
        if {$fail eq ""} {
            set fail "no JTAG2AXI"
        } else {
            append fail "; no JTAG2AXI"
        }
    } else {
        set n 1
        foreach _id $ids {
            set ::JSON_JTAG_N $n
            lassign [_json_smoke_result jsmoke jtag ::JTAG_SMOKE_ADDR 4] jrc jerr jdoc
            lappend results $jdoc
            if {$jrc != 0 && $fail eq ""} {
                set fail $jerr
            }
            incr n
        }
    }
    if {$fail ne ""} {
        return [list 1 [_json_verify_doc 0 $fail $results]]
    }
    return [list 0 [_json_verify_doc 1 "" $results]]
}

proc json_dispatch {op args} {
    switch -- $op {
        targets {
            return [json_do_targets]
        }
        read {
            if {[llength $args] < 5} {
                return [list 1 [_json_mem_doc 0 read read "missing arguments" 0 "" "" "" "" "" "" {} {}]]
            }
            lassign $args addr len path n command
            if {$command eq ""} {
                set command rd
            }
            return [json_do_access read $command $addr $len "" $path $n]
        }
        write {
            if {[llength $args] < 5} {
                return [list 1 [_json_mem_doc 0 write write "missing arguments" 0 "" "" "" "" "" "" {} {}]]
            }
            lassign $args addr data path n command
            if {$command eq ""} {
                set command wr
            }
            return [json_do_access write $command $addr 1 $data $path $n]
        }
        write_read {
            if {[llength $args] < 5} {
                return [list 1 [_json_mem_doc 0 wrd write_read "missing arguments" 0 "" "" "" "" "" "" {} {}]]
            }
            lassign $args addr data path n command
            if {$command eq ""} {
                set command wrd
            }
            return [json_do_access write_read $command $addr 1 $data $path $n]
        }
        verify {
            return [json_do_verify]
        }
        default {
            return [list 1 [_json_targets_doc 0 "unknown JSON command: $op" {}]]
        }
    }
}

proc json_cli_main {args} {
    if {[catch {set pair [json_dispatch {*}$args]} err]} {
        set cmd [lindex $args 0]
        if {$cmd eq ""} {
            set cmd "xsdb"
        }
        set pair [list 1 "\{[_json_status 0 $cmd error $err]\}"]
    }
    lassign $pair rc body
    _json_publish $body
    exit $rc
}

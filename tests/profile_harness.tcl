# Child helper for board-profile checks. Prints RESULT lines after tool.tcl loads.
#   tclsh tests/profile_harness.tcl
#   tclsh tests/profile_harness.tcl smoke
set ::XSDB_QUIET 1
set here [file dirname [file normalize [info script]]]
set root [file dirname $here]
source [file join $root tool.tcl]

puts "RESULT name=[expr {[info exists ::PROFILE_NAME] ? $::PROFILE_NAME : {}}]"
puts "RESULT mb=$::MB_SMOKE_ADDR"
puts "RESULT jtag=$::JTAG_SMOKE_ADDR"
puts "RESULT loaded=[expr {[info exists ::LOADED_PROFILE] ? $::LOADED_PROFILE : {}}]"
puts "RESULT err=[expr {[info exists ::PROFILE_LOAD_ERROR] ? $::PROFILE_LOAD_ERROR : 0}]"

if {[lindex $argv 0] eq "smoke"} {
    proc mb {} {
        puts "PROBE mb"
        return 0
    }
    proc mrd {args} {
        puts "MRD $args"
    }
    proc jtag {n} {
        puts "PROBE jtag $n"
        return 0
    }
    proc _j2a_ids {} {
        return {7 8}
    }
    set smoke_rc [smoke]
    set jsmoke_rc [jsmoke 1]
    puts "RESULT smoke_rc=$smoke_rc"
    puts "RESULT jsmoke_rc=$jsmoke_rc"
}

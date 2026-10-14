# Scheme A: batch verify BOTH JTAG paths then exit.
#   xsdb.cmd verify
#   xsdb.cmd verify --profile <file.tcl>
#   xsdb <this-file>
# Smoke addresses come from the board profile loaded by tool.tcl.
# 0x0 or unset skips that mrd. A missing profile file aborts verify.
#
# Path 1: JTAG -> XSDB -> MDM -> MicroBlaze
# Path 2: JTAG -> XSDB -> Jtag Master (JTAG2AXI, same cores as hw_axi)

set ::XSDB_QUIET 1
set here [file dirname [file normalize [info script]]]
source [file join $here tool.tcl]

if {[info exists ::PROFILE_LOAD_ERROR] && $::PROFILE_LOAD_ERROR} {
    puts "ERROR: verify aborted because the board profile did not load."
    exit 1
}

if {[xconnect]} {
    exit 1
}

puts ""
puts "========== [1] JTAG -> XSDB -> MicroBlaze =========="
if {[mb]} {
    puts "SKIP MicroBlaze"
} else {
    smoke
}

puts ""
puts "========== [2] JTAG -> XSDB -> Jtag Master =========="
set ids [_j2a_ids]
if {![llength $ids]} {
    puts "ERROR: no JTAG2AXI"
    exit 1
}
set n 1
foreach id $ids {
    jsmoke $n
    incr n
}

puts ""
puts "verify done."
exit

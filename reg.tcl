# Scheme A: batch verify BOTH JTAG paths then exit.
#   xsdb.cmd verify
#   xsdb <this-file>
#
# Path 1: JTAG -> XSDB -> MDM -> MicroBlaze
# Path 2: JTAG -> XSDB -> Jtag Master (JTAG2AXI, same cores as hw_axi)

set ::XSDB_QUIET 1
set here [file dirname [file normalize [info script]]]
source [file join $here tool.tcl]

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

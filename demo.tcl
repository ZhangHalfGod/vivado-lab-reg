# Direct XSDB baseline for GUI comparison.
# Addresses are the fictional reference map in examples/address.xlsx.
# They are not a lab board. Replace them locally to mirror your Address Editor.
# Do not commit a real map. smoke / verify use a board profile (profiles/README.md).
#
#   xsdb.cmd demo.tcl
set ::XSDB_QUIET 1
source [file join [file dirname [file normalize [info script]]] tool.tcl]
if {[xconnect]} { exit 1 }

puts "===== DEMO1 MB  mrd 0x10000000 1  (example_ip_a) ====="
mb
puts [mrd 0x10000000 1]

puts "===== DEMO2 JTAG2AXI#1  mrd 0x20000000 1  (example_ip_b Lite window) ====="
jtag 1
puts [mrd 0x20000000 1]

puts "===== DEMO3 JTAG2AXI#2  mrd 0x20000000 1  (same Lite window; confirm the row) ====="
jtag 2
puts [mrd 0x20000000 1]

puts "===== DEMO4 mismatch  JTAG2AXI#1  mrd 0x10000000 1 ====="
jtag 1
puts [mrd 0x10000000 1]
exit

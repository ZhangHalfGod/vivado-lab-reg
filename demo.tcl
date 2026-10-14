# Direct XSDB baseline for GUI comparison.
#   D:\vivdao_down\Vivado_Lab\2022.2\bin\xsdb.bat demo.tcl
# The addresses below are explicit reads for this script, not smoke defaults.
# smoke / verify use a board profile (see profiles/README.md).
set ::XSDB_QUIET 1
source [file join [file dirname [file normalize [info script]]] tool.tcl]
if {[xconnect]} { exit 1 }

puts "===== DEMO1 MB  mrd 0x11080000 8 ====="
mb
puts [mrd 0x11080000 8]

puts "===== DEMO2 JTAG2AXI#1  mrd 0x116BCC00 4 ====="
jtag 1
puts [mrd 0x116BCC00 4]

puts "===== DEMO3 JTAG2AXI#1  mrd 0x116B0000 4 ====="
puts [mrd 0x116B0000 4]

puts "===== DEMO4 JTAG2AXI#2  mrd 0x116BCC00 4 ====="
jtag 2
puts [mrd 0x116BCC00 4]

puts "===== DEMO5 mismatch  JTAG2AXI#1  mrd 0x11080000 1 ====="
jtag 1
puts [mrd 0x11080000 1]
exit

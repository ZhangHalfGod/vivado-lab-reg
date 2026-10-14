# Persistent stdin loop for the Windows GUI.
# Started as:  xsdb.bat gui.tcl
# Protocol: Python writes one Tcl line, we eval it, then print __XSDB_DONE__.

set ::XSDB_QUIET 1
set here [file dirname [file normalize [info script]]]
# tool.tcl loads VIVADO_LAB_REG_PROFILE or XSDB_PROFILE when the GUI or
# xsdb.cmd / xsdb.sh set that variable before this process starts.
source [file join $here tool.tcl]

catch {fconfigure stdout -buffering none}
catch {fconfigure stdin -buffering line}

puts "GUI_READY"
flush stdout

while {[gets stdin line] >= 0} {
    set line [string trim $line]
    if {$line eq ""} {
        continue
    }
    if {$line eq "GUI_EXIT"} {
        catch {disconnect}
        exit 0
    }
    if {[catch {uplevel #0 $line} err]} {
        puts "ERROR: $err"
    }
    puts "__XSDB_DONE__"
    flush stdout
}
exit 0

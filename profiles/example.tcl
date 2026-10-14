# Board profile for vivado-lab-reg smoke / verify.
#
# Copy this file to profiles/private/<name>.tcl (that directory is gitignored)
# and set the Master Base Address for each path.
#
# In Vivado Address Editor, use the master's "Master Base Address" — the
# address where that master sees offset 0. Do not put the slave's own base
# of 0x0 here. 0x0 means smoke / verify skip that read.
#
# Load it with either of:
#   xsdb.cmd verify --profile D:/lab/vivado-lab-reg/profiles/private/<name>.tcl
#   ./xsdb.sh verify --profile /lab/vivado-lab-reg/profiles/private/<name>.tcl
# or set VIVADO_LAB_REG_PROFILE (XSDB_PROFILE is also accepted).

set ::PROFILE_NAME "example"

# Placeholder. Replace with your Master Base Address, or leave 0x0 to skip.
set ::MB_SMOKE_ADDR   0x00000000
set ::JTAG_SMOKE_ADDR 0x00000000

# Board profiles

Put board-specific smoke addresses and Address Map imports here.

Do not commit customer or employer-only maps. Keep private files under `profiles/private/` (gitignored).

Example overrides before sourcing `tool.tcl`:

```tcl
set ::MB_SMOKE_ADDR   0x00000000
set ::JTAG_SMOKE_ADDR 0x00000000
```

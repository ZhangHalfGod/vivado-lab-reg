# vivado-lab-reg — Vivado Lab XSDB Register Peek/Poke

**Language / 语言:** [English](README.md) | [中文](README.zh-CN.md)

> **Register peek/poke over Vivado Lab XSDB — MicroBlaze & JTAG-to-AXI — without installing full Vivado/Vitis.**

[![GitHub](https://img.shields.io/badge/GitHub-ZhangHalfGod%2Fvivado--lab--reg-blue?logo=github)](https://github.com/ZhangHalfGod/vivado-lab-reg)
[![Python](https://img.shields.io/badge/Python-3.10%2B-3776AB?logo=python&logoColor=white)](https://www.python.org/downloads/)
[![Vivado Lab](https://img.shields.io/badge/Vivado_Lab-2022.2-EAE93F?logo=xilinx&logoColor=black)](https://www.xilinx.com/)
[![XSDB](https://img.shields.io/badge/XSDB-hw__server%20%2F%20JTAG-0A7EA4)](#how-it-works--board-support)
[![MicroBlaze](https://img.shields.io/badge/MicroBlaze-mrd%20%2F%20mwr-6B4FBB)](#access-paths)
[![JTAG2AXI](https://img.shields.io/badge/JTAG--to--AXI-Jtag%20Master-C72C48)](#access-paths)
[![GUI](https://img.shields.io/badge/GUI-Tk%20%2F%20pythonw-informational)](#windows-gui-recommended)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

> **What this repo is**: Windows GUI + CLI that keep a resident **XSDB** session, **scan** the JTAG chain, and let you pick a register target from the list (id + name), then `mrd` / `mwr` / write-and-read-back.  
> **Validated**: `xcvu37p` + Vivado Lab 2022.2 (example smoke bases in `tool.tcl` are board-specific — override with a [board profile](profiles/README.md)).  
> **Not**: full Vivado/Vitis, bitstream download, ILA, or Hardware Manager replacement. You must install **Vivado Lab** yourself (not redistributed here).

---

## Daily lab process

1. **Prep.** Board powered, bitstream loaded, Hardware Manager closed. On the setup page, pick `xsdb.bat` if it is not already saved. CLI can also use Lab `bin` on `PATH` or `XSDB`. [Before you start](#before-you-start)
2. **GUI.** Run `gui.cmd` (or `pythonw gui.py`). **Connect** scans the chain; select one row from **Targets**; then Read/Write. [Windows GUI](#windows-gui-recommended)
3. **CLI verify.** `xsdb.cmd verify` (or `./xsdb.sh verify`) reads the MicroBlaze smoke base and each JTAG2AXI the scan finds. [Quick verify](#quick-verify)
4. **Interactive.** `xsdb.cmd` then `mb` / `jtag 1` / `smoke` / `rd` / `wr`. [CLI](#cli)
5. **Board change.** Click **Refresh targets** and select again; replace smoke bases via profile. [How it works](#how-it-works--board-support)

Chinese GUI walkthrough: [docs/usage-zh.md](docs/usage-zh.md).

---

## Table of contents

- [Daily lab process](#daily-lab-process)
- [How it works / board support](#how-it-works--board-support)
- [Windows GUI (recommended)](#windows-gui-recommended)
- [Before you start](#before-you-start)
- [Access paths](#access-paths)
- [Quick verify](#quick-verify)
- [CLI](#cli)
- [Packaging](#packaging)
- [License](#license)

---

## How it works / board support

```text
User script / GUI  →  XSDB  →  hw_server  →  FPGA
                              ├─ MDM → MicroBlaze → fabric     (mb)
                              └─ Debug Hub → JTAG2AXI          (jtag / Jtag Master)
```

This tool does **not** hard-code VU37P. It uses **Vivado Lab XSDB → hw_server → JTAG**, then `mrd` / `mwr` on targets found on the scan chain. The GUI lists those register targets with id and name; you select a row from that scan.

**VU37P** is the board used for validation. On other Xilinx/AMD FPGAs the same flow usually works when Vivado Lab can see the cable and the design exposes MicroBlaze and/or JTAG-to-AXI. After changing boards or bitstreams, click **Refresh targets** and select again, and replace smoke base addresses with that board's Address Map (use a board profile). Non-Xilinx vendors and full Hardware Manager / ILA / bitstream flows are out of scope for phase 1.

What stays the same across boards: no full Vivado/Vitis install — only a Lab JTAG session for register peek/poke.

---

## Windows GUI (recommended)

Double-click:

```text
gui.cmd
```

Or:

```bat
pythonw gui.py
```

Typical flow:

1. **Prep.** Board powered, bitstream loaded, Hardware Manager closed. On the setup page, pick `xsdb.bat` if needed (for example `D:\vivdao_down\Vivado_Lab\2022.2\bin\xsdb.bat`), then **Continue**.
2. Click **Connect** — starts XSDB and **scans** the JTAG chain.
3. The **Targets** list shows whatever register targets were found (for example MicroBlaze #0, JTAG2AXI, …) with id and name. These are **not hard-coded slots**. If the list is empty, power the board, load the bitstream, then **Refresh targets**.
4. **Select** a row. That only switches the XSDB target; no address is required yet.
5. Enter address, length, and data, then **Read / Write / Write + Readback**.
6. After changing the board or bitstream, click **Refresh targets** and select again.

History keeps the last 100 read/write rows. Address and Data there are shown as 8 hex digits; XSDB’s own log may still print short addresses without leading zeros.

Needs Python 3 (3.10 verified). Core logic matches `tool.tcl`.

---

## Before you start

1. Board powered; bitstream loaded so MicroBlaze and/or JTAG2AXI are present.
2. If Vivado Hardware Manager is attached, close it first to free JTAG.
3. For the GUI, choose `xsdb.bat` on the setup page. For the CLI, if `xsdb` is missing, add Lab `bin` to `PATH`, or set user env `XSDB`.

Example paths:

- Windows: `D:\vivdao_down\Vivado_Lab\2022.2\bin\xsdb.bat` or `C:\Xilinx\Vivado_Lab\<version>\bin\xsdb.bat`
- Linux: `/opt/Xilinx/Vivado_Lab/<version>/bin/xsdb`

---

## Access paths

After **Connect**, **Targets** lists the register targets from that scan (id + name). Select the row, then use the address map that belongs to it. MicroBlaze and JTAG-to-AXI still have different maps.

| Target class | CLI commands | Address basis | Example smoke (VU37P lab) |
| --- | --- | --- | --- |
| MicroBlaze | `rd` / `wr` / `smoke` | **microblaze_0 / Data** Address Map | `0x11080000` |
| JTAG-to-AXI (Jtag Master) | `jrd` / `jwr` / `jsmoke` | Address Map behind that JTAG2AXI | `0x116BCC00` |

Do not poke an MB address through JTAG2AXI (often `DEC0DE1C` decode fail). Do not poke `0x116BCxxx` through MicroBlaze if that window is Jtag Master only.

A `JTAG2AXI` row is the same class as Hardware Manager `hw_axi` (Jtag Master). One VU37P scan showed two of them; the ids change when the chain changes. In the GUI, select the scanned row. CLI `jtag n` still means the nth JTAG2AXI in that scan.

Lab only speaks JTAG/debug. This repo only uses `connect` / `targets` / `mrd` / `mwr`.

---

## Quick verify

```bat
xsdb.cmd verify
```

Linux:

```bash
./xsdb.sh verify
```

That CLI run:

1. Selects MicroBlaze and `mrd` of the MB smoke base.
2. Selects each JTAG2AXI the scan finds and `mrd` of the JTAG smoke base.

---

## CLI

Windows: double-click `xsdb.cmd`. Linux: `./xsdb.sh`. Then:

```tcl
mb
smoke
rd 11080000 10

jtag 1
jsmoke
rd 116BCC00 4
wr 116BCC08 1
```

Override example smoke bases before sourcing `tool.tcl` (see [profiles/README.md](profiles/README.md)):

```tcl
set ::MB_SMOKE_ADDR   0x00000000
set ::JTAG_SMOKE_ADDR 0x00000000
```

---

## Packaging

Optional Windows exe (not committed):

```bat
build_exe.bat
```

Produces `VivadoLabReg.exe` under `dist/` (gitignored). Prefer `gui.cmd` + Python for development.

---

## License

MIT. See [LICENSE](LICENSE). Not an AMD/Xilinx product; Vivado Lab must be obtained separately.

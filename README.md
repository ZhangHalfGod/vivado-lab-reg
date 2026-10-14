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

> **What this repo is**: Windows GUI + CLI that keep a resident **XSDB** session, switch **MicroBlaze** / **JTAG2AXI #1** / **JTAG2AXI #2** by target **name**, then `mrd` / `mwr` / write-and-read-back.  
> **Validated**: `xcvu37p` + Vivado Lab 2022.2 (example smoke bases in `tool.tcl` are board-specific — override with a [board profile](profiles/README.md)).  
> **Not**: full Vivado/Vitis, bitstream download, ILA, or Hardware Manager replacement. You must install **Vivado Lab** yourself (not redistributed here).

---

## Daily lab process

1. **Prep.** Cable up, bitstream already loaded with MicroBlaze and/or JTAG2AXI. Close Hardware Manager so it does not hold JTAG. Put Lab `bin` on `PATH` or set `XSDB`. [Before you start](#before-you-start)
2. **GUI.** Run `gui.cmd` (or `pythonw gui.py`). Connect, pick a path, read/write. [Windows GUI](#windows-gui-recommended)
3. **CLI verify.** `xsdb.cmd verify` (or `./xsdb.sh verify`) exercises MB + both JTAG2AXI paths. [Quick verify](#quick-verify)
4. **Interactive.** `xsdb.cmd` then `mb` / `jtag 1` / `smoke` / `rd` / `wr`. [CLI](#cli)
5. **Board change.** Re-enumerate targets; replace smoke bases via profile. [How it works](#how-it-works--board-support)

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

This tool does **not** hard-code VU37P. It uses **Vivado Lab XSDB → hw_server → JTAG**, then `mrd` / `mwr` on targets found on the scan chain. Targets are selected by **name** (MicroBlaze / JTAG2AXI / Jtag Master), not by fixed target numbers.

**VU37P** is the board used for validation. On other Xilinx/AMD FPGAs the same flow usually works when Vivado Lab can see the cable and the design exposes MicroBlaze and/or JTAG-to-AXI. After changing boards, re-enumerate targets (indices change) and replace smoke base addresses with that board's Address Map (use a board profile). Non-Xilinx vendors and full Hardware Manager / ILA / bitstream flows are out of scope for phase 1.

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

1. Click **Connect** — starts a resident XSDB session (do not share JTAG with Hardware Manager).
2. Pick a path: MicroBlaze / JTAG2AXI #1 / JTAG2AXI #2. **Path switch only changes target; it does not need an address.**
3. Enter address and data; **Read / Write / Write+Readback**.
4. Keeps the last 100 read/write history rows.

Needs Python 3 (3.10 verified). Core logic matches `tool.tcl`.

---

## Before you start

1. Board powered; bitstream loaded so MicroBlaze and/or JTAG2AXI are present.
2. If Vivado Hardware Manager is attached, close it first to free JTAG.
3. If `xsdb` is missing, add Lab `bin` to `PATH`, or set user env `XSDB`.

Example paths:

- Windows: `D:\vivdao_down\Vivado_Lab\2022.2\bin\xsdb.bat` or `C:\Xilinx\Vivado_Lab\<version>\bin\xsdb.bat`
- Linux: `/opt/Xilinx/Vivado_Lab/<version>/bin/xsdb`

---

## Access paths

| Path | Commands | Address basis | Example smoke (VU37P lab) |
| --- | --- | --- | --- |
| MicroBlaze | `rd` / `wr` / `smoke` | **microblaze_0 / Data** Address Map | `0x11080000` |
| Jtag Master | `jrd` / `jwr` / `jsmoke` | Address Map behind that JTAG2AXI | `0x116BCC00` |

Do not poke an MB address through JTAG2AXI (often `DEC0DE1C` decode fail). Do not poke `0x116BCxxx` through MB if that window is Jtag Master only.

`JTAG2AXI` is the same class as Hardware Manager `hw_axi_1` / `hw_axi_2`. On the VU37P lab, targets **5** / **6** were JTAG2AXI #1 / #2 — indices change with the scan chain; scripts enumerate by name.

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

That run:

1. Selects MicroBlaze and `mrd` of the MB smoke base.
2. Selects JTAG2AXI #1 and #2 and `mrd` of the JTAG smoke base.

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

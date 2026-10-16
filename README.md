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
> **Validated**: Virtex UltraScale+ + Vivado Lab 2022.2. Smoke bases come from a [board profile](profiles/README.md) (Master Base Address). With no profile they stay `0x0` and that read is skipped.  
> **Not**: full Vivado/Vitis, bitstream download, ILA, or Hardware Manager replacement. You must install **Vivado Lab** yourself (not redistributed here).

---

## Daily lab process

1. **Prep.** Board powered, bitstream loaded, Hardware Manager closed. On the setup page, pick `xsdb.bat` if it is not already saved. CLI can also use Lab `bin` on `PATH` or `XSDB`. [Before you start](#before-you-start)
2. **GUI.** Run `gui.cmd` (or `pythonw gui.py`). **Connect** scans the chain; select one row from **Targets**; then Read/Write. [Windows GUI](#windows-gui-recommended)
3. **CLI verify.** `xsdb.cmd verify --profile <file.tcl>` (or `./xsdb.sh verify --profile <file.tcl>`) reads the MicroBlaze Master Base and each JTAG2AXI the scan finds. No profile, or an address of `0x0`, skips that read. [Quick verify](#quick-verify)
4. **Interactive.** `xsdb.cmd` then `mb` / `jtag 1` / `smoke` / `rd` / `wr`. [CLI](#cli)
5. **Board change.** Click **Refresh targets** and select again; replace smoke bases via profile. [How it works](#how-it-works--board-support)

Chinese GUI walkthrough: [docs/usage-zh.md](docs/usage-zh.md). Doc index: [docs/README.md](docs/README.md). Local Cursor Agent on a lab PC: [Local Cursor Agent](#local-cursor-agent).

---

## Table of contents

- [Daily lab process](#daily-lab-process)
- [How it works / board support](#how-it-works--board-support)
- [Windows GUI (recommended)](#windows-gui-recommended)
- [Before you start](#before-you-start)
- [Access paths](#access-paths)
- [Quick verify](#quick-verify)
- [CLI](#cli)
- [Machine-readable JSON](#machine-readable-json)
- [Agents / Skill](#agents--skill)
  - [Local Cursor Agent](#local-cursor-agent)
- [Packaging](#packaging)
- [License](#license)

---

## How it works / board support

```text
User script / GUI  →  XSDB  →  hw_server  →  FPGA
                              ├─ MDM → MicroBlaze → fabric     (mb)
                              └─ Debug Hub → JTAG2AXI          (jtag / Jtag Master)
```

This tool is **not** tied to one board. It uses **Vivado Lab XSDB → hw_server → JTAG**, then `mrd` / `mwr` on targets found on the scan chain. The GUI lists those register targets with id and name; you select a row from that scan.

Validation used a **Virtex UltraScale+** FPGA. On other Xilinx/AMD FPGAs the same flow usually works when Vivado Lab can see the cable and the design exposes MicroBlaze and/or JTAG-to-AXI. After changing boards or bitstreams, click **Refresh targets** and select again, and point smoke at that board's Master Base Addresses with a [board profile](profiles/README.md). Non-Xilinx vendors and full Hardware Manager / ILA / bitstream flows are out of scope.

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

1. **Prep.** Board powered, bitstream loaded, Hardware Manager closed. On the setup page, pick `xsdb.bat` if needed (for example `C:\Xilinx\Vivado_Lab\2022.2\bin\xsdb.bat`), then **Continue**.
2. Click **Connect** — starts XSDB and **scans** the JTAG chain.
3. The **Targets** list shows whatever register targets were found (for example MicroBlaze #0, JTAG2AXI, …) with id and name. These are **not hard-coded slots**. If the list is empty, power the board, load the bitstream, then **Refresh targets**.
4. **Select** a row. That only switches the XSDB target; no address is required yet.
5. Enter address, length, and data, then **Read / Write / Write + Readback**.
6. After changing the board or bitstream, click **Refresh targets** and select again.

### GUI walkthrough

One session, five steps. **Connect** and **Targets** are the JTAG scan. They are not filled in from the workbook. The address map only lists Master Base Address values and can fill the Address field. **Read** and **Write** use the target row you selected.

![1. Connect](docs/images/gui-walkthrough/01-connect.png)

Click **Connect**. That starts XSDB and scans the JTAG chain.

![2. Display Targets](docs/images/gui-walkthrough/02-targets.png)

**Targets** lists the register targets from that scan (id and name).

![3. Choose target](docs/images/gui-walkthrough/03-choose-target.png)

Select one row, for example MicroBlaze #0. That switches the XSDB target. Read and Write use this row.

![4. Import map](docs/images/gui-walkthrough/04-import-map.png)

Type an address, or **Load / Import map**. A selected map row fills Address from that Master Base Address. The workbook does not select a JTAG target.

![5. Read](docs/images/gui-walkthrough/05-read.png)

Click **Read**. History and the log show the data for the selected target.

**Address map (optional)** is on the setup page and the main window. Browse a workbook (prefer `address.xlsx`), then **Load / Import map**. The list is the **reference** Vivado layout (Master Base Address; Slave Base `0x0` is ignored). Select a row to fill the address field. **Suggest profile** / **Write private profile** build `::MB_SMOKE_ADDR` and `::JTAG_SMOKE_ADDR` from the rows you select, or from the CLI first match and its warning. Save starts at `profiles/private/lab.tcl` and does not overwrite without confirmation. The workbook path is stored in `%APPDATA%\VivadoLabReg\config.json`. Other spreadsheet formats: [use AI to adapt](docs/address-map-import.md).

History keeps the last 100 read/write rows. Address and Data there are shown as 8 hex digits; XSDB’s own log may still print short addresses without leading zeros.

Needs Python 3 (3.10 verified). Core logic matches `tool.tcl`.

---

## Before you start

1. Board powered; bitstream loaded so MicroBlaze and/or JTAG2AXI are present.
2. If Vivado Hardware Manager is attached, close it first to free JTAG.
3. For the GUI, choose `xsdb.bat` on the setup page. For the CLI, if `xsdb` is missing, add Lab `bin` to `PATH`, or set user env `XSDB`.

Example paths:

- Windows: `C:\Xilinx\Vivado_Lab\<version>\bin\xsdb.bat`
- Linux: `/opt/Xilinx/Vivado_Lab/<version>/bin/xsdb`

---

## Access paths

After **Connect**, **Targets** lists the register targets from that scan (id + name). Select the row, then use the address map that belongs to it. MicroBlaze and JTAG-to-AXI still have different maps.

| Target class | CLI commands | Address basis | Smoke address |
| --- | --- | --- | --- |
| MicroBlaze | `rd` / `wr` / `smoke` | **microblaze_0 / Data** Master Base Address | `::MB_SMOKE_ADDR` in the board profile |
| JTAG-to-AXI (Jtag Master) | `jrd` / `jwr` / `jsmoke` | Master Base Address behind that JTAG2AXI | `::JTAG_SMOKE_ADDR` in the board profile |

These smoke values are the **Master Base Address** from Vivado Address Editor (where that master sees offset 0), not the slave's own base of `0x0`. `0x0` in the profile means skip that smoke read.

`python addr_map.py examples/address.xlsx` lists those Master Base Addresses for one Vivado export layout. The workbook in `examples/` is fictional. A different spreadsheet is a different format — [use AI to adapt](docs/address-map-import.md) the parser. `--suggest-profile` prints a snippet for `profiles/private/` and does not write the file.

Do not poke a MicroBlaze address through JTAG2AXI (often `DEC0DE1C` decode fail). Do not poke a JTAG-to-AXI-only window through MicroBlaze.

A `JTAG2AXI` row is the same class as Hardware Manager `hw_axi` (Jtag Master). One scan on a Virtex UltraScale+ FPGA showed two of them; the ids change when the chain changes. In the GUI, select the scanned row. CLI `jtag n` still means the nth JTAG2AXI in that scan.

Lab only speaks JTAG/debug. This repo only uses `connect` / `targets` / `mrd` / `mwr`.

---

## Quick verify

```bat
xsdb.cmd verify --profile D:\lab\vivado-lab-reg\profiles\private\board.tcl
```

Linux:

```bash
./xsdb.sh verify --profile /lab/vivado-lab-reg/profiles/private/board.tcl
```

`verify` with no profile still connects and scans. Both smoke addresses stay `0x0`, and those `mrd`s are skipped. `VIVADO_LAB_REG_PROFILE` (or `XSDB_PROFILE`) points at the same `.tcl` file if you omit `--profile`.

That CLI run:

1. Selects MicroBlaze and `mrd` of `MB_SMOKE_ADDR` (skipped when that address is `0x0`).
2. Selects each JTAG2AXI the scan finds and `mrd` of `JTAG_SMOKE_ADDR` (skipped when that address is `0x0`).

---

## CLI

Windows: double-click `xsdb.cmd`. Linux: `./xsdb.sh`. Then:

```tcl
mb
smoke

jtag 1
jsmoke
rd 00001000 1
```

`smoke` / `jsmoke` use the board profile loaded with `tool.tcl`. Copy `profiles/example.tcl` to `profiles/private/`, fill in Master Base Addresses, then:

```bat
xsdb.cmd --profile D:\lab\vivado-lab-reg\profiles\private\board.tcl
xsdb.cmd verify --profile D:\lab\vivado-lab-reg\profiles\private\board.tcl
```

```bash
./xsdb.sh --profile /lab/vivado-lab-reg/profiles/private/board.tcl
./xsdb.sh verify --profile /lab/vivado-lab-reg/profiles/private/board.tcl
```

The GUI setup page stores that path in `%APPDATA%\VivadoLabReg\config.json` and passes it into the XSDB session on Connect, so **Verify paths** matches the CLI. See [profiles/README.md](profiles/README.md).

### Machine-readable JSON

`--json` makes `xsdb.sh` / `xsdb.cmd` print one JSON object on stdout for scripts and agents. Leave it off and the human text is unchanged. The flag may come before or after the command.

```bash
./xsdb.sh --json targets
./xsdb.sh targets --json
./xsdb.sh --json rd 00001000 1
./xsdb.sh --json wr 00001000 1
./xsdb.sh --json wrd 00001000 1
./xsdb.sh --json jrd 00002000 4
./xsdb.sh --json jwr 00002008 1
./xsdb.sh --json verify --profile /lab/vivado-lab-reg/profiles/private/board.tcl
```

```bat
xsdb.cmd --json targets
xsdb.cmd --json rd 00001000 4
xsdb.cmd --json wr 00001000 1
xsdb.cmd --json verify --profile D:\lab\vivado-lab-reg\profiles\private\board.tcl
```

Stdout is only that object. The XSDB banner and other chatter go to stderr. Exit status is 0 when `ok` is true, and non-zero when `ok` is false or XSDB produced no document. `help` stays human text.

`targets` lists the register targets from the scan (same set as the GUI): MicroBlaze cores, and JTAG-to-AXI under the names JTAG2AXI, Jtag Master, `jtag_axi`, or jtag-to-axi. The MicroBlaze Debug Module is not included. `class` is `microblaze` or `jtag2axi`. Ids are whatever this scan returned.

`rd` / `wr` / `wrd` select the MicroBlaze the interactive `mb` command would select (`MicroBlaze #0` when that name is present, otherwise the first MicroBlaze core). `jrd` / `jwr` / `jwrd` use JTAG-to-AXI #1 in that scan; `jrd2` / `jwr2` / `jwrd2` use #2.

These checks do not open a cable:

```bash
bash tests/test_json_cli.sh
```

On a lab PC, close Hardware Manager, power the board, and load the bitstream before the commands above. `python3 -m json.tool` pretty-prints stdout.

Every object has `ok`, `command`, `operation`, and `error` (`null` on success).

Targets. An empty scan is still success (`ok` true, `targets` `[]`). Connect failure is `ok` false, `targets` `[]`, and `error` set.

```json
{
  "ok": true,
  "command": "targets",
  "operation": "targets",
  "error": null,
  "targets": [
    {"id": 3, "name": "MicroBlaze #0", "class": "microblaze"},
    {"id": 5, "name": "JTAG2AXI", "class": "jtag2axi"}
  ]
}
```

Read, write, and write-then-read share one shape. `operation` is `read`, `write`, or `write_read`. `data` is the words read back, or the write payload when the command does not read. `written` is that payload when the command writes, otherwise `[]`. Words look like `0x` plus eight hex digits. `target` is null when nothing was selected.

```json
{
  "ok": true,
  "command": "rd",
  "operation": "read",
  "error": null,
  "skipped": false,
  "reason": null,
  "target": {"id": 3, "name": "MicroBlaze #0", "class": "microblaze"},
  "address": "0x00001000",
  "length": 1,
  "data": ["0x00000001"],
  "written": []
}
```

```json
{
  "ok": true,
  "command": "wr",
  "operation": "write",
  "error": null,
  "skipped": false,
  "reason": null,
  "target": {"id": 3, "name": "MicroBlaze #0", "class": "microblaze"},
  "address": "0x00001000",
  "length": 1,
  "data": ["0x00000001"],
  "written": ["0x00000001"]
}
```

```json
{
  "ok": true,
  "command": "jwrd",
  "operation": "write_read",
  "error": null,
  "skipped": false,
  "reason": null,
  "target": {"id": 5, "name": "JTAG2AXI", "class": "jtag2axi"},
  "address": "0x00002008",
  "length": 1,
  "data": ["0x00000001"],
  "written": ["0x00000001"]
}
```

`verify` runs the same smoke reads as the human command: MicroBlaze (`length` 10) and each JTAG-to-AXI the scan found (`length` 4). Each entry uses the read shape, with `command` `smoke` or `jsmoke`. A Master Base of `0x0` sets `skipped` true and does not call `mrd`. A missing MicroBlaze is skipped. No JTAG-to-AXI, a profile that failed to load, a connect failure, or a failed read sets top-level `ok` to false.

```json
{
  "ok": true,
  "command": "verify",
  "operation": "verify",
  "error": null,
  "results": [
    {
      "ok": true,
      "command": "smoke",
      "operation": "read",
      "error": null,
      "skipped": true,
      "reason": "MB_SMOKE_ADDR is 0x0 or unset, so this read is not issued.",
      "target": {"id": 3, "name": "MicroBlaze #0", "class": "microblaze"},
      "address": "0x00000000",
      "length": 10,
      "data": [],
      "written": []
    }
  ]
}
```

List the fictional reference map, or print a profile snippet (copy it into `profiles/private/`; the command does not write the file). Other spreadsheet layouts: [use AI to adapt](docs/address-map-import.md).

```bat
python addr_map.py D:\lab\vivado-lab-reg\examples\address.xlsx
python addr_map.py --xlsx D:\lab\vivado-lab-reg\examples\address.xlsx --suggest-profile
```

### Agents / Skill

Human setup, the GUI, and the interactive CLI stay in this README. Agents and scripts follow [skills/vivado-lab-reg/SKILL.md](skills/vivado-lab-reg/SKILL.md): call `xsdb.cmd --json` or `./xsdb.sh --json`, parse the one JSON object on stdout, and stay on `targets`, `rd` / `jrd` / `jrd2`, and `verify` unless the user explicitly asked to write. `wr`, `jwr`, `wrd`, `jwrd`, and the `#2` write forms change the board. An `ok` of false is a stop.

**L3.** An agent or CI job can enumerate targets and peek with `--json` and no board (`bash tests/test_json_cli.sh`). The Skill is what constrains writes. The optional Windows exe (`build_exe.bat` → `dist/VivadoLabReg.exe`) is the same GUI as `gui.cmd`. It is not committed, and it does not include Vivado Lab or a board profile.

#### Local Cursor Agent

On the lab PC, open this checkout in Cursor and use the local Agent. The Agent reads [skills/vivado-lab-reg/SKILL.md](skills/vivado-lab-reg/SKILL.md), then runs the JSON CLI from that folder. The same steps in Chinese: [本机 Cursor Agent](README.zh-CN.md#本机-cursor-agent) and [docs/usage-zh.md](docs/usage-zh.md#本机-cursor-agent).

1. **Open the checkout.** Clone the repo, or open the folder you already use. Paths in this README are `D:\lab\vivado-lab-reg` on Windows and `/lab/vivado-lab-reg` on Linux. Another folder is fine when that folder is the Agent workspace.
2. **Have the Agent read the Skill.** The file is `skills/vivado-lab-reg/SKILL.md`. One of these is enough:
   - Repo skill: with this checkout as the workspace, tell the Agent to follow the `vivado-lab-reg` skill in that file.
   - Attach `skills/vivado-lab-reg/SKILL.md` to the Agent message.
   - Tell the Agent to read that file and follow it before any XSDB command.
3. **Board prep is unchanged.** Power the board, load the bitstream, and close Hardware Manager. [Before you start](#before-you-start). Step 6 runs with no cable.
4. **Example prompts.** Send one at a time, and read the Agent's report of `ok`, `command`, and `error`. The addresses below are the fictional examples in this README. On a live board, name the register you mean. The write prompt changes that register; send it when you intend the write.
   - Enumerate targets only:

     ```text
     Read skills/vivado-lab-reg/SKILL.md and follow it. Run targets only. List id, name, and class. Do not read or write registers.
     ```

   - Peek a named address, read-only:

     ```text
     Follow skills/vivado-lab-reg/SKILL.md. Read 4 words at 0x00001000 on MicroBlaze. Read only.
     ```

   - Write only when you name both the address and the data:

     ```text
     Follow skills/vivado-lab-reg/SKILL.md. Write 0x00000001 to MicroBlaze address 0x00001000.
     ```

     A prompt that omits the address or the data stays on a read.
5. **What the Agent runs.** From the checkout, Windows runs `xsdb.cmd --json targets`, then `xsdb.cmd --json rd <addr> <len>` or `xsdb.cmd --json jrd <addr> <len>` (`jrd2` for the second JTAG-to-AXI). Linux runs the same subcommands with `./xsdb.sh --json …`. The Agent parses the one JSON object on stdout. `ok: false` is a stop: report `error` and wait, with no retry and no write after that result. A write (`wr`, `jwr`, `wrd`, `jwrd`, or a `#2` write) runs only after a prompt that names the address and the data, as in the third example.
6. **Offline check, no board.** `bash tests/test_json_cli.sh` checks the JSON contract with no cable. The live prompts in step 4 still use the board from step 3.

---

## Packaging

Optional Windows GUI exe for a lab PC. The build stays on that PC. `dist/` and `*.exe` are gitignored, so this repo does not commit binaries.

**Build PC** (64-bit Windows):

- Python 3.10+ with tkinter (the interpreter you already use for `gui.py`)
- PyInstaller (`pip install pyinstaller`, or let `build_exe.bat` install it)
- `openpyxl` if that exe should open `.xlsx` (`pip install openpyxl` before the build). CSV with the same columns works without it.

```bat
build_exe.bat
build_exe.bat --nopause
```

The script runs [VivadoLabReg.spec](VivadoLabReg.spec) and writes `dist\VivadoLabReg.exe`. It does not copy the exe onto the repo root. `--nopause` skips the final keypress.

**Inside the exe:** `gui.py`, `addr_map.py`, `gui.tcl`, `tool.tcl`, and the Python runtime. **Not inside the exe:**

- Vivado Lab, `xsdb.bat`, and cable drivers. Install Lab yourself and pick `xsdb.bat` on the setup page.
- Board profiles. Keep them in `profiles/private/` (gitignored) and point the GUI or `--profile` at that file.
- `%APPDATA%\VivadoLabReg\config.json` (xsdb path, profile path, address-map path).

`gui.cmd` runs `gui.py` when Python is installed. On a PC without Python, double-click `dist\VivadoLabReg.exe`. After you change `gui.py` or the Tcl files, run `build_exe.bat` again. Editing Tcl next to an already-built exe does not change that exe. Copy `profiles/example.tcl` to `profiles/private/` for a real board.

---

## License

MIT. See [LICENSE](LICENSE). Not an AMD/Xilinx product; Vivado Lab must be obtained separately.

---
name: vivado-lab-reg
description: >-
  Drive the local vivado-lab-reg XSDB CLI with --json and parse the single
  JSON object on stdout. Use when an agent scans JTAG targets, reads
  MicroBlaze or JTAG-to-AXI registers, or runs verify against a board
  profile. Stay on targets, rd, jrd, jrd2, and verify unless the user
  explicitly asked to write. wr, jwr, wrd, jwrd, and the #2 write forms
  change hardware. Stop when ok is false.
---

# vivado-lab-reg JSON CLI

Agents and scripts call `xsdb.cmd` or `./xsdb.sh` with `--json`, then parse one JSON object from stdout. The human walkthrough (GUI, interactive CLI, board prep) is [README.md](../../README.md), [README.zh-CN.md](../../README.zh-CN.md), and [docs/usage-zh.md](../../docs/usage-zh.md).

## Safety

Read-only is the default. These commands only read or scan:

- `targets`
- `rd`, `jrd`, `jrd2`
- `verify` (smoke `mrd` only)

A write runs only after the user explicitly asks to write, and names the address and the data word. That includes write-then-readback. These commands issue `mwr` on the board:

| Command | Path | What it writes |
| --- | --- | --- |
| `wr` | MicroBlaze | one word |
| `wrd` | MicroBlaze | one word, then reads it back |
| `jwr` | JTAG-to-AXI #1 | one word |
| `jwrd` | JTAG-to-AXI #1 | one word, then reads it back |
| `jwr2` | JTAG-to-AXI #2 | one word |
| `jwrd2` | JTAG-to-AXI #2 | one word, then reads it back |

If the request is ambiguous ("check", "poke", "debug", "try that address"), run a read. Ask before any command in the write table.

`ok: false` is a stop. Report `error` and wait. Do not retry, and do not follow a failed call with a write. On `wrd` / `jwrd` / `jwrd2`, read `error` before you tell the user what happened: `mwr failed` means the write was rejected; `mrd failed` or `mrd returned no data` means the write was issued and the readback failed (`written` holds the payload, `data` is `[]`). Leave that address alone until the user asks for another write.

## Prerequisites

1. Vivado Lab is installed (this repo does not ship it). XSDB talks to `hw_server` over JTAG. Validated with Vivado Lab 2022.2. Example binaries:
   - Windows: `C:\Xilinx\Vivado_Lab\<version>\bin\xsdb.bat`
   - Linux: `/opt/Xilinx/Vivado_Lab/<version>/bin/xsdb`
2. The board is powered and the bitstream is loaded, so MicroBlaze and/or JTAG-to-AXI are on the chain.
3. Vivado Hardware Manager is closed. It holds JTAG. Connect failures say to power the board, program the bitstream, and close Hardware Manager.
4. Invoke the wrapper in the repo checkout. Documented checkout paths: `D:\lab\vivado-lab-reg` and `/lab/vivado-lab-reg`. The wrapper finds `tool.tcl` beside itself.
5. A board profile is optional. It only supplies smoke Master Base Addresses for `verify`. Pass `--profile`, or set `VIVADO_LAB_REG_PROFILE` (that wins over `XSDB_PROFILE`). `0x0` or no profile skips that smoke read. The connect and the scan still run.
   - Windows: `D:\lab\vivado-lab-reg\profiles\private\board.tcl`
   - Linux: `/lab/vivado-lab-reg/profiles/private/board.tcl`

If XSDB is not on `PATH`, set `XSDB` to `xsdb.bat` (Windows) or the `xsdb` binary (Linux). A missing toolchain is still one JSON object: `ok` false, `command` `xsdb`, `operation` `error`, `error` starting with `xsdb not found`, `targets` `[]`.

## Invoke

`--json` may appear before or after the subcommand. `--profile <file.tcl>` may appear before the subcommand or after `verify`. Stdout is one JSON object. The XSDB banner goes to stderr. Exit status is 0 when `ok` is true, and non-zero when `ok` is false or XSDB printed no document.

Parse stdout only. `help` stays human text. Interactive mode with `--json` returns `ok: false` and does not open a session.

Windows, from the checkout:

```bat
cd /d D:\lab\vivado-lab-reg
xsdb.cmd --json targets
xsdb.cmd --json rd 00001000 4
xsdb.cmd --json jrd 00002000 4
xsdb.cmd --json verify --profile D:\lab\vivado-lab-reg\profiles\private\board.tcl
```

Linux, from the checkout:

```bash
cd /lab/vivado-lab-reg
./xsdb.sh --json targets
./xsdb.sh targets --json
./xsdb.sh --json rd 00001000 4
./xsdb.sh --json jrd 00002000 4
./xsdb.sh --json verify --profile /lab/vivado-lab-reg/profiles/private/board.tcl
```

## Procedure

1. Confirm the board is powered, the bitstream is loaded, and Hardware Manager is closed.
2. Run `--json targets`.
3. If `ok` is false, stop and report `error`.
4. If `ok` is true and `targets` is `[]`, the scan succeeded and found no register targets. Report that. Ask the user to check power, bitstream, and Hardware Manager. Do not invent a target id.
5. Read with the command that matches the target the user named. Take ids and names from this scan. Ids change when the chain changes. The numbers in the README examples are illustrations.
6. For a write, require an explicit user request that includes address and data, then run one write command. Parse the result. Stop if `ok` is false.

MicroBlaze reads and writes select the core interactive `mb` would select: a name matching `MicroBlaze #0` when present, otherwise the first MicroBlaze core. The MicroBlaze Debug Module is not a register target. `jrd` / `jwr` / `jwrd` use JTAG-to-AXI #1 in this scan (1-based). `jrd2` / `jwr2` / `jwrd2` use #2. Count only JTAG-to-AXI names: `JTAG2AXI`, `Jtag Master`, `jtag_axi`, or jtag-to-axi. There is no JSON command that takes a raw target id.

Use a MicroBlaze address with `rd` / `wr` / `wrd`. Use a JTAG-to-AXI Master Base with `jrd` / `jwr` / `jwrd`. Crossing those maps often returns `DEC0DE1C`.

Addresses are hex (`00001000`, `0x00001000`, or with underscores). `address` in the result is `0x` plus eight uppercase hex digits. Read length defaults to 1 and must be a positive integer. `0` fails with `ok: false` and does not open the cable. Writes take one data word.

## Commands

| Command | Operation | Arguments | Target |
| --- | --- | --- | --- |
| `targets` | `targets` | none | current scan |
| `rd` | `read` | `<addr> [len]` | MicroBlaze |
| `jrd` | `read` | `<addr> [len]` | JTAG-to-AXI #1 |
| `jrd2` | `read` | `<addr> [len]` | JTAG-to-AXI #2 |
| `wr` | `write` | `<addr> <data>` | MicroBlaze |
| `wrd` | `write_read` | `<addr> <data>` | MicroBlaze |
| `jwr` | `write` | `<addr> <data>` | JTAG-to-AXI #1 |
| `jwrd` | `write_read` | `<addr> <data>` | JTAG-to-AXI #1 |
| `jwr2` | `write` | `<addr> <data>` | JTAG-to-AXI #2 |
| `jwrd2` | `write_read` | `<addr> <data>` | JTAG-to-AXI #2 |
| `verify` | `verify` | `--profile` optional | smoke reads |

`verify` runs the same smoke reads as the human command. Results are memory objects with `operation` `read`:

- MicroBlaze, `command` `smoke`, `length` 10, address `MB_SMOKE_ADDR`.
- Each JTAG-to-AXI on the scan, `command` `jsmoke`, `length` 4, address `JTAG_SMOKE_ADDR`.

A Master Base of `0x0` sets `skipped` true and does not call `mrd`. A missing MicroBlaze is skipped (`reason` `MicroBlaze not found`) and does not by itself fail the run. No JTAG-to-AXI, a profile that failed to load, a connect failure, or a failed read sets top-level `ok` to false. `results` may already hold earlier entries. Stop on that top-level failure.

Copy `profiles/example.tcl` to `profiles/private/board.tcl` only when the user wants a profile. Do not overwrite an existing private profile unless the user asked. See [profiles/README.md](../../profiles/README.md).

## JSON contract

Every object has:

| Field | Meaning |
| --- | --- |
| `ok` | `true` only when this object succeeded |
| `command` | CLI name, or `smoke` / `jsmoke` inside `verify` results |
| `operation` | `targets`, `read`, `write`, `write_read`, `verify`, or `error` |
| `error` | string, or `null` on success |

`targets` adds `targets`: an array of `{id, name, class}`. `id` is a number from this scan. `class` is `microblaze` or `jtag2axi`. An empty scan is success (`ok` true, `targets` `[]`). Connect failure is `ok` false, `targets` `[]`, and `error` set.

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

Read, write, and write-then-read share one shape:

| Field | Meaning |
| --- | --- |
| `skipped` | `true` when this read was not issued |
| `reason` | why it was skipped, or `null` |
| `target` | `{id, name, class}`, or `null` when nothing was selected |
| `address` | `0x` plus eight hex digits, or `null` |
| `length` | word count, or `null` when the length was rejected |
| `data` | words read back; on a pure write, the payload that was written |
| `written` | the payload when the command writes, otherwise `[]` |

Each word is `0x` plus eight uppercase hex digits.

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

`verify` adds `results`, an array of those memory objects:

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

A skipped smoke entry can have `ok: true`. Judge the run by the top-level `ok`. Early failures are still one object with `ok: false`. Missing XSDB and an unknown command include `"targets": []`. A bad `verify` argument includes `"results": []`. A bad address, length, or data word includes the memory fields (`target` and `address` null, `data` and `written` empty) and does not open the cable. If the process exits non-zero and stdout is not one JSON object, stop and report stderr.

Field examples in the README match this contract. Offline check, no cable: `bash tests/test_json_cli.sh`.

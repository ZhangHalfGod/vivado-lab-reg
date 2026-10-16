# vivado-lab-reg — Vivado Lab XSDB 寄存器读写

**Language / 语言:** [English](README.md) | [中文](README.zh-CN.md)

> **在已安装 Vivado Lab 的前提下，用 XSDB 对 MicroBlaze 与 JTAG-to-AXI 做寄存器 peek/poke，不必装完整 Vivado/Vitis。**

[![GitHub](https://img.shields.io/badge/GitHub-ZhangHalfGod%2Fvivado--lab--reg-blue?logo=github)](https://github.com/ZhangHalfGod/vivado-lab-reg)
[![Python](https://img.shields.io/badge/Python-3.10%2B-3776AB?logo=python&logoColor=white)](https://www.python.org/downloads/)
[![Vivado Lab](https://img.shields.io/badge/Vivado_Lab-2022.2-EAE93F?logo=xilinx&logoColor=black)](https://www.xilinx.com/)
[![XSDB](https://img.shields.io/badge/XSDB-hw__server%20%2F%20JTAG-0A7EA4)](#原理与板型适配)
[![MicroBlaze](https://img.shields.io/badge/MicroBlaze-mrd%20%2F%20mwr-6B4FBB)](#访问路径)
[![JTAG2AXI](https://img.shields.io/badge/JTAG--to--AXI-Jtag%20Master-C72C48)](#访问路径)
[![GUI](https://img.shields.io/badge/GUI-Tk%20%2F%20pythonw-informational)](#windows-图形界面推荐)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

> **本仓做什么**：Windows GUI + CLI，常驻 **XSDB** 会话，**扫描** JTAG 链，从列表里选一个寄存器 target（id + 名字），再 `mrd` / `mwr` / 写后读回。  
> **验证过**：Virtex UltraScale+ + Vivado Lab 2022.2。smoke 基址来自 [board profile](profiles/README.md)（Master Base Address）。不加载 profile 时保持 `0x0`，对应的读会跳过。  
> **不是**：完整 Vivado/Vitis、下 bitstream、ILA，或替代 Hardware Manager。需自备 **Vivado Lab**（本仓不分发）。

---

## 日常实验流程

1. **准备。** 板上电，bitstream 已加载，关掉 Hardware Manager。设置页里若还没保存路径，先选好 `xsdb.bat`。命令行也可以把 Lab 的 `bin` 放进 `PATH`，或设 `XSDB`。[使用前](#使用前)
2. **GUI。** 运行 `gui.cmd`（或 `pythonw gui.py`）。**Connect** 扫描链路，在 **Targets** 里选一行，再读写。[Windows 图形界面](#windows-图形界面推荐)
3. **CLI 自检。** `xsdb.cmd verify --profile <file.tcl>`（或 `./xsdb.sh verify --profile <file.tcl>`）读 MicroBlaze 的 Master Base，以及扫描到的每条 JTAG2AXI。没有 profile，或地址为 `0x0`，就跳过这次读。[快速验证](#快速验证)
4. **交互。** `xsdb.cmd` 后 `mb` / `jtag 1` / `smoke` / `rd` / `wr`。[命令行](#命令行)
5. **换板。** 点 **Refresh targets** 再重新选择；smoke 基址用 profile 换掉。[原理与板型适配](#原理与板型适配)

更细的中文 GUI 说明：[docs/usage-zh.md](docs/usage-zh.md)。文档索引：[docs/README.md](docs/README.md)。

---

## 目录

- [日常实验流程](#日常实验流程)
- [原理与板型适配](#原理与板型适配)
- [Windows 图形界面（推荐）](#windows-图形界面推荐)
- [使用前](#使用前)
- [访问路径](#访问路径)
- [快速验证](#快速验证)
- [命令行](#命令行)
- [机器可读 JSON](#机器可读-json)
- [Agents / Skill](#agents--skill)
- [打包](#打包)
- [许可证](#许可证)

---

## 原理与板型适配

```text
用户脚本 / GUI  →  XSDB  →  hw_server  →  FPGA
                              ├─ MDM → MicroBlaze → 外设     （mb）
                              └─ Debug Hub → JTAG2AXI       （jtag / Jtag Master）
```

原理不绑死某一块板：走的是 **Vivado Lab 的 XSDB → hw_server → JTAG**，对扫描链上枚举到的 target 做 `mrd` / `mwr`。GUI 按 id 和名字列出当次扫描到的寄存器 target，由你点选。

验证用的是 **Virtex UltraScale+** FPGA。对其它 FPGA：**同一套 Xilinx/AMD + Vivado Lab + 链上有 MB 和/或 JTAG-to-AXI 时，一般能用**。换板或换 bitstream 后点 **Refresh targets** 再选一次，smoke 基址也要换成那块板的 Master Base Address（用 [board profile](profiles/README.md)）。没有这两类通路、或厂商不是这套工具链（例如 Intel），不在本工具范围内。

和板型无关、真正通用的是：不装完整 Vivado/Vitis，只借 Lab 的 JTAG 会话做寄存器 peek/poke。

---

## Windows 图形界面（推荐）

双击：

```text
gui.cmd
```

或：

```bat
pythonw gui.py
```

典型用法：

1. **准备。** 板上电，bitstream 已加载，关掉 Hardware Manager。设置页若还没选过，先指定 `xsdb.bat`（例如 `C:\Xilinx\Vivado_Lab\2022.2\bin\xsdb.bat`），再点 **Continue**。
2. 点 **Connect**。启动 XSDB，并**扫描** JTAG 链。
3. **Targets** 列出这次扫到的寄存器 target（例如 MicroBlaze #0、JTAG2AXI），每行是 id 和名字，**不是写死的档位**。列表为空：确认上电并已下载 bitstream，再点 **Refresh targets**。
4. **选中**一行。这一步只切换 XSDB target，还不需要填地址。
5. 填地址、长度和数据，再点 **Read** / **Write** / **Write + Readback**。
6. 换板或换 bitstream 之后，点 **Refresh targets**，再重新选择。

### 图形界面分步

下面五张图是同一次操作。**Connect** 和 **Targets** 来自 JTAG 扫描，不是从 xlsx 自动识别。地址表只提供 Master Base Address，并可以填进 Address。**Read** / **Write** 用的是当前选中的 target。

![1. Connect](docs/images/gui-walkthrough/01-connect.png)

点 **Connect**，启动 XSDB 并扫描 JTAG 链。

![2. 显示 Targets](docs/images/gui-walkthrough/02-targets.png)

**Targets** 显示这次扫描到的寄存器 target（id 和名字）。

![3. 选 target 并连接](docs/images/gui-walkthrough/03-choose-target.png)

选中一行（例如 MicroBlaze #0）。这一步切换 XSDB target。之后的读写都走这一行。

![4. 手填或导入 address.xlsx](docs/images/gui-walkthrough/04-import-map.png)

手填地址，或点 **Load / Import map** 导入 `address.xlsx`。选中地址表一行会把该行的 Master Base Address 填进 Address。地址表不会替你选 JTAG target。

![5. Read 取数](docs/images/gui-walkthrough/05-read.png)

点 **Read**。History 和日志里是当前选中 target 的读回数据。

设置页和主窗口都有 **Address map (optional)**。浏览工作簿（建议文件名 `address.xlsx`），再点 **Load / Import map**。列表用的是 **reference** Vivado 布局（Master Base Address，忽略 Slave Base `0x0`）。选中一行会把该地址填进输入框。**Suggest profile** / **Write private profile** 根据选中的行生成 `::MB_SMOKE_ADDR` 和 `::JTAG_SMOKE_ADDR`；没选行时与命令行一样取第一条并给出警告。保存对话框默认 `profiles/private/lab.tcl`，已有文件需确认才覆盖。工作簿路径记在 `%APPDATA%\VivadoLabReg\config.json`。别的表格格式：[请使用 AI 进行适配](docs/address-map-import.md)。

History 最多保留最近 100 次读写。里面的 Address / Data 显示为 8 位十六进制；XSDB 自己的日志里，短地址仍可能不补前导零。

需要本机 Python 3（建议 3.10）。核心逻辑与 `tool.tcl` 相同。

---

## 使用前

1. 板上电，bitstream 已加载，链上能看到 MicroBlaze 和/或 JTAG2AXI。
2. 若 Vivado Hardware Manager 已连板，先关掉，释放 JTAG。
3. GUI 在设置页选择 `xsdb.bat`。命令行找不到 `xsdb` 时，把 Lab 的 `bin` 加进 PATH，或设用户环境变量 `XSDB`。

常见路径：

- Windows：`C:\Xilinx\Vivado_Lab\<version>\bin\xsdb.bat`
- Linux：`/opt/Xilinx/Vivado_Lab/<version>/bin/xsdb`

---

## 访问路径

**Connect** 之后，**Targets** 列出当次扫描到的寄存器 target（id + 名字）。选中一行，再用属于这个 target 的地址表。MicroBlaze 和 JTAG-to-AXI 的地址空间仍然不同。

| Target 类型 | 命令行 | 地址依据 | Smoke 地址 |
| --- | --- | --- | --- |
| MicroBlaze | `rd` / `wr` / `smoke` | **microblaze_0 / Data** 的 Master Base Address | profile 里的 `::MB_SMOKE_ADDR` |
| JTAG-to-AXI（Jtag Master） | `jrd` / `jwr` / `jsmoke` | 该 JTAG2AXI 后面的 Master Base Address | profile 里的 `::JTAG_SMOKE_ADDR` |

这两个值是 Vivado Address Editor 里 master 的 **Master Base Address**（该 master 看到偏移 0 的地址），不是从机自己的 Slave Base `0x0`。profile 里写成 `0x0` 表示跳过这次 smoke 读。

`python addr_map.py examples/address.xlsx` 可以列出一种 Vivado 导出表里的 Master Base Address。`examples/` 里的工作簿是虚构的。别的表格是别的格式——[请使用 AI 进行适配](docs/address-map-import.md)。`--suggest-profile` 把 profile 片段打印到终端，不写文件。

不要把 MB 地址用到 JTAG2AXI 上（常见 `DEC0DE1C` 译码失败）。不要把只属于 Jtag Master 窗口的地址用到 MicroBlaze 上。

列表里的 `JTAG2AXI` 与 Hardware Manager 的 `hw_axi`（Jtag Master）是同一类。Virtex UltraScale+ 某次扫描里出现过两条；链一变，id 就会变。GUI 里选扫描出来的那一行即可。命令行的 `jtag n` 仍表示当次扫描里的第 n 条 JTAG2AXI。

Lab 只谈 JTAG/调试协议。本仓只用：`connect` / `targets` / `mrd` / `mwr`。

---

## 快速验证

```bat
xsdb.cmd verify --profile D:\lab\vivado-lab-reg\profiles\private\board.tcl
```

Linux：

```bash
./xsdb.sh verify --profile /lab/vivado-lab-reg/profiles/private/board.tcl
```

不带 profile 的 `verify` 仍会连接并扫描。两个 smoke 地址保持 `0x0`，对应的 `mrd` 会跳过。也可以用环境变量 `VIVADO_LAB_REG_PROFILE`（或 `XSDB_PROFILE`）指向同一个 `.tcl` 文件。

这条命令行会依次：

1. 选 MicroBlaze，对 `MB_SMOKE_ADDR` 做 `mrd`（地址为 `0x0` 时跳过）
2. 对扫描到的每条 JTAG2AXI，对 `JTAG_SMOKE_ADDR` 做 `mrd`（地址为 `0x0` 时跳过）

---

## 命令行

Windows 双击 `xsdb.cmd`，或 Linux `./xsdb.sh`，连接后：

```tcl
mb
smoke

jtag 1
jsmoke
rd 00001000 1
```

`smoke` / `jsmoke` 用的是随 `tool.tcl` 一起加载的 board profile。把 `profiles/example.tcl` 复制到 `profiles/private/`，填上 Master Base Address，然后：

```bat
xsdb.cmd --profile D:\lab\vivado-lab-reg\profiles\private\board.tcl
xsdb.cmd verify --profile D:\lab\vivado-lab-reg\profiles\private\board.tcl
```

```bash
./xsdb.sh --profile /lab/vivado-lab-reg/profiles/private/board.tcl
./xsdb.sh verify --profile /lab/vivado-lab-reg/profiles/private/board.tcl
```

GUI 设置页把该路径记在 `%APPDATA%\VivadoLabReg\config.json`，Connect 时传给 XSDB 会话，因此 **Verify paths** 与命令行使用同一组地址。见 [profiles/README.md](profiles/README.md)。

### 机器可读 JSON

`--json` 让 `xsdb.sh` / `xsdb.cmd` 在 stdout 上只打一个 JSON 对象，给脚本和 Agent 解析。不加这个参数时，给人看的文本和原来一样。参数可以写在子命令前面或后面。

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

stdout 只有这一个对象。XSDB 横幅和其它过程信息走 stderr。`ok` 为 true 时进程退出码为 0；`ok` 为 false，或 XSDB 没有打出结果时，退出码非 0。`help` 仍是给人看的文本。

`targets` 列出这次扫描到的寄存器 target（和 GUI 同一范围）：MicroBlaze 核，以及名字为 JTAG2AXI、Jtag Master、`jtag_axi` 或 jtag-to-axi 的 JTAG-to-AXI。MicroBlaze Debug Module 不算寄存器 target。`class` 为 `microblaze` 或 `jtag2axi`。id 来自当次扫描，不是写死的档位。

`rd` / `wr` / `wrd` 选交互命令 `mb` 会选中的那颗 MicroBlaze（名字里有 `MicroBlaze #0` 时优先它，否则用第一颗 MicroBlaze 核）。`jrd` / `jwr` / `jwrd` 用当次扫描的第 1 条 JTAG-to-AXI；`jrd2` / `jwr2` / `jwrd2` 用第 2 条。

下面这条检查不需要板子、也不需要电缆：

```bash
bash tests/test_json_cli.sh
```

实验机上先关掉 Hardware Manager，板上电并下载 bitstream，再跑上面的命令。`python3 -m json.tool` 可以把 stdout 排版后看。

每个对象都有 `ok`、`command`、`operation`、`error`（成功时 `error` 为 `null`）。

Targets。扫到空链也是成功（`ok` 为 true，`targets` 为 `[]`）。连接失败则 `ok` 为 false，`targets` 为 `[]`，并带上 `error`。

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

读、写、写后读用同一套字段。`operation` 为 `read`、`write` 或 `write_read`。`data` 是读回的字；命令本身不读时，`data` 就是写入的数据。`written` 在有写操作时是写入内容，否则为 `[]`。每个字是 `0x` 加 8 位十六进制。没有选中 target 时 `target` 为 null。

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

`verify` 和给人看的命令做同一组 smoke 读：MicroBlaze（`length` 10）以及扫描到的每条 JTAG-to-AXI（`length` 4）。每一项都是上面的读结果，`command` 为 `smoke` 或 `jsmoke`。Master Base 为 `0x0` 时 `skipped` 为 true，不会发 `mrd`。没有 MicroBlaze 也记为跳过。没有 JTAG-to-AXI、profile 加载失败、连接失败，或某次读失败时，最外层 `ok` 为 false。

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

列出虚构的参考地址表，或打印一段 profile（抄进 `profiles/private/`；命令不会写文件）。别的表格请 [使用 AI 适配](docs/address-map-import.md)。

```bat
python addr_map.py D:\lab\vivado-lab-reg\examples\address.xlsx
python addr_map.py --xlsx D:\lab\vivado-lab-reg\examples\address.xlsx --suggest-profile
```

### Agents / Skill

给人看的准备步骤、图形界面和交互命令行仍以本 README 为准。Agent 和脚本按 [skills/vivado-lab-reg/SKILL.md](skills/vivado-lab-reg/SKILL.md) 操作：调用 `xsdb.cmd --json` 或 `./xsdb.sh --json`，解析 stdout 上的那一个 JSON 对象，默认只跑 `targets`、`rd` / `jrd` / `jrd2` 和 `verify`。只有用户明确要求写入时，才使用 `wr`、`jwr`、`wrd`、`jwrd` 以及对应的 `#2` 写命令。这些写命令会改板上的寄存器。`ok` 为 false 就停。

**L3。** Agent 或 CI 可以在没有板子的情况下用 `--json` 枚举 target 并读寄存器（`bash tests/test_json_cli.sh`）。写操作由 Skill 约束。可选的 Windows exe（`build_exe.bat` → `dist/VivadoLabReg.exe`）和 `gui.cmd` 是同一个 GUI。exe 不提交，里面也不含 Vivado Lab 或 board profile。

---

## 打包

可选的 Windows 图形界面 exe，给实验机用。打包在那台机器上做。`dist/` 和 `*.exe` 已被 gitignore，本仓不提交二进制。

**打包机**（64 位 Windows）：

- Python 3.10+，带 tkinter（和跑 `gui.py` 的是同一个解释器）
- PyInstaller（`pip install pyinstaller`，或让 `build_exe.bat` 安装）
- 若这个 exe 要打开 `.xlsx`，先 `pip install openpyxl` 再打包。同样列名的 CSV 不需要它。

```bat
build_exe.bat
build_exe.bat --nopause
```

脚本按 [VivadoLabReg.spec](VivadoLabReg.spec) 生成 `dist\VivadoLabReg.exe`，不会把 exe 复制到仓库根目录。`--nopause` 跳过最后的按键。

**打进 exe 的：** `gui.py`、`addr_map.py`、`gui.tcl`、`tool.tcl` 和 Python 运行时。**不打进 exe 的：**

- Vivado Lab、`xsdb.bat` 和电缆驱动。Lab 自己装，在设置页选择 `xsdb.bat`。
- Board profile。放在 `profiles/private/`（已被 gitignore），GUI 或 `--profile` 指向该文件。
- `%APPDATA%\VivadoLabReg\config.json`（xsdb 路径、profile 路径、地址表路径）。

装了 Python 时，`gui.cmd` 跑的是 `gui.py`。没有 Python 的机器双击 `dist\VivadoLabReg.exe`。改过 `gui.py` 或 Tcl 之后要重新跑 `build_exe.bat`。已经生成的 exe 旁边改 Tcl，不会进到那个 exe 里。真实板子把 `profiles/example.tcl` 复制到 `profiles/private/`。

---

## 许可证

MIT。见 [LICENSE](LICENSE)。非 AMD/Xilinx 附属产品；Vivado Lab 需另行安装。

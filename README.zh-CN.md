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

> **本仓做什么**：Windows GUI + CLI，常驻 **XSDB** 会话，按 **名字** 切换 **MicroBlaze** / **JTAG2AXI #1** / **JTAG2AXI #2**，再 `mrd` / `mwr` / 写后读回。  
> **验证过**：`xcvu37p` + Vivado Lab 2022.2（`tool.tcl` 里的 smoke 基址是板相关示例，请用 [board profile](profiles/README.md) 覆盖）。  
> **不是**：完整 Vivado/Vitis、下 bitstream、ILA，或替代 Hardware Manager。需自备 **Vivado Lab**（本仓不分发）。

---

## 日常实验流程

1. **准备。** 板上电，bitstream 已含 MicroBlaze 和/或 JTAG2AXI。关掉 Hardware Manager，避免占 JTAG。Lab 的 `bin` 进 `PATH`，或设 `XSDB`。[使用前](#使用前)
2. **GUI。** 运行 `gui.cmd`（或 `pythonw gui.py`）。连接、选路径、读写。[Windows 图形界面](#windows-图形界面推荐)
3. **CLI 自检。** `xsdb.cmd verify`（或 `./xsdb.sh verify`）跑 MB + 两条 JTAG2AXI。[快速验证](#快速验证)
4. **交互。** `xsdb.cmd` 后 `mb` / `jtag 1` / `smoke` / `rd` / `wr`。[命令行](#命令行)
5. **换板。** 重新枚举 target；smoke 基址用 profile 换掉。[原理与板型适配](#原理与板型适配)

更细的中文 GUI 说明：[docs/usage-zh.md](docs/usage-zh.md)。

---

## 目录

- [日常实验流程](#日常实验流程)
- [原理与板型适配](#原理与板型适配)
- [Windows 图形界面（推荐）](#windows-图形界面推荐)
- [使用前](#使用前)
- [访问路径](#访问路径)
- [快速验证](#快速验证)
- [命令行](#命令行)
- [打包](#打包)
- [许可证](#许可证)

---

## 原理与板型适配

```text
用户脚本 / GUI  →  XSDB  →  hw_server  →  FPGA
                              ├─ MDM → MicroBlaze → 外设     （mb）
                              └─ Debug Hub → JTAG2AXI       （jtag / Jtag Master）
```

原理不绑死 VU37P：走的是 **Vivado Lab 的 XSDB → hw_server → JTAG**，对扫描链上枚举到的 target 做 `mrd` / `mwr`。VU37P 只是验证过的一块板；工具按 **名字** 找 MicroBlaze / JTAG2AXI（Jtag Master），不按写死的 target 编号。

对其它 FPGA：**同一套 Xilinx/AMD + Vivado Lab + 链上有 MB 和/或 JTAG-to-AXI 时，一般能用**；换板后 target 序号会变，要重新枚举，smoke 基址也要换成那块板的 Address Map（所以才要 board profile）。没有这两类通路、或厂商不是这套工具链（例如 Intel），当前第一期不做。

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

1. 点 **连接**，内部常驻一个 XSDB 会话（不要和 Hardware Manager 同时占 JTAG）。
2. 选路径：MicroBlaze / JTAG2AXI #1 / JTAG2AXI #2。**选路径只切换 target，不要求先填地址。**
3. 自己填地址和数据，点 **读 / 写 / 写+读回**。
4. 最多保留最近 100 次读写历史。

需要本机 Python 3（建议 3.10）。核心逻辑与 `tool.tcl` 相同。

---

## 使用前

1. 板上电，bitstream 已加载，链上能看到 MicroBlaze 和/或 JTAG2AXI。
2. 若 Vivado Hardware Manager 已连板，先关掉，释放 JTAG。
3. 找不到 `xsdb` 时，把 Lab 的 `bin` 加进 PATH，或设用户环境变量 `XSDB`。

常见路径：

- Windows：`D:\vivdao_down\Vivado_Lab\2022.2\bin\xsdb.bat` 或 `C:\Xilinx\Vivado_Lab\<version>\bin\xsdb.bat`
- Linux：`/opt/Xilinx/Vivado_Lab/<version>/bin/xsdb`

---

## 访问路径

| 路径 | 命令 | 地址依据 | 示例 smoke（VU37P 实验） |
| --- | --- | --- | --- |
| MicroBlaze | `rd` / `wr` / `smoke` | **microblaze_0 / Data** Address Map | `0x11080000` |
| Jtag Master | `jrd` / `jwr` / `jsmoke` | 该 JTAG2AXI 后面的 Address Map | `0x116BCC00` |

不要把 MB 地址用到 JTAG2AXI 上（常见 `DEC0DE1C` 译码失败）。不要把仅属于 Jtag Master 窗口的 `0x116BCxxx` 用到 MB 上。

`JTAG2AXI` 对应 Hardware Manager 里的 `hw_axi_1` / `hw_axi_2`。VU37P 实验里 target **5** / **6** 曾是 JTAG2AXI #1 / #2——编号随扫描链变，脚本按名字枚举。

Lab 只谈 JTAG/调试协议。本仓只用：`connect` / `targets` / `mrd` / `mwr`。

---

## 快速验证

```bat
xsdb.cmd verify
```

Linux：

```bash
./xsdb.sh verify
```

会依次：

1. 选 MicroBlaze，对 MB smoke 基址做 `mrd`
2. 选 JTAG2AXI #1、#2，对 JTAG smoke 基址做 `mrd`

---

## 命令行

Windows 双击 `xsdb.cmd`，或 Linux `./xsdb.sh`，连接后：

```tcl
mb
smoke
rd 11080000 10

jtag 1
jsmoke
rd 116BCC00 4
wr 116BCC08 1
```

在 `source tool.tcl` 之前覆盖示例基址（见 [profiles/README.md](profiles/README.md)）：

```tcl
set ::MB_SMOKE_ADDR   0x00000000
set ::JTAG_SMOKE_ADDR 0x00000000
```

---

## 打包

可选 Windows exe（不提交）：

```bat
build_exe.bat
```

产物在 `dist/VivadoLabReg.exe`（已 gitignore）。开发优先用 `gui.cmd` + Python。

---

## 许可证

MIT。见 [LICENSE](LICENSE)。非 AMD/Xilinx 附属产品；Vivado Lab 需另行安装。

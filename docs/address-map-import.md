# Address Map import (reference)

[English](#english) · [中文](#zh)

<a id="english"></a>

## English

`addr_map.py` is a **reference parser** for one Vivado Address Editor export. It is not a universal spreadsheet reader. Boards, Vivado versions, and engineers do not share one table.

**Use AI to adapt.** Give the model this document (the principle and the reference columns) together with **your** export, and ask it to change `addr_map.py` or to draft a profile snippet. Do not assume every file has these columns.

### Principle

XSDB `mrd` / `mwr` need the address at which **that master** sees the slave.

| Column | Use it? |
| --- | --- |
| **Master Base Address** | Yes. This is the poke address for that master. Copy it into `::MB_SMOKE_ADDR` or `::JTAG_SMOKE_ADDR`. |
| **Slave Base Address** | No. Many slaves report their own base as `0x0`. Poking `0x0` does not land on that peripheral. |
| **Range** | Window size. A register is `master base + 0x0 / 0x4 / 0x8 …`. |
| **Excluded** / **Incomplete** groups | Not reachable from that master. The reference parser drops them. |

MicroBlaze (`M_AXI_DP` or a parent row named `Data`) and JTAG-to-AXI do not share a map. JTAG-to-AXI often has **no row of its own**. On many designs its window is the same **M_AXI_LITE** map as an xdma master. Which JTAG2AXI target you talk to is still the scan list in the GUI or `jtag n` — this importer only supplies addresses. `j1` and `j2` therefore show the same Lite slaves.

Smoke addresses live in a board profile under `profiles/private/` (gitignored). See [profiles/README.md](../profiles/README.md). This tool does not write that directory and does not commit a profile.

### Reference column layout

Header row (names matter; order does not, once the header is present):

| Name | Interface | Slave Segment | Master Base Address | Range | Slave Base Address |
| --- | --- | --- | --- | --- | --- |

The sheet is a **tree**, not a flat list. Group rows leave **Master Base Address** empty. Slave rows fill it.

1. A row whose name does not start with `/`, `M_`, `m_axi`, `Network `, `Excluded`, or `Incomplete`, and is not `Data` / `Instruction` / `DLMB` / `ILMB`, starts a **master**. Example: `microblaze_0`.
2. `M_…`, `m_axi…`, `Data`, `Instruction`, `DLMB`, or `ILMB` starts a **master interface** under that master. Example: `M_AXI_DP`.
3. The next rows whose Master Base Address is filled in are **slaves** of that master and interface. The `Name` cell is the slave path (`/example_ip_a/S00_AXI`). The `Interface` cell on that row is the slave port, not the master port. The CLI column `iface` is the parent master interface (`M_AXI_DP`).
4. `Excluded…` or `Incomplete…` drops following slave rows until the next master, interface, `Network …`, or a `/…` group row.
5. `Network …` ends that master.

A **flat** sheet (a master name and a base on every row, no parent rows) does not match this tree. The reference parser returns no slaves. That is a different export. Adapt the parser; do not force the file into this shape by hand unless you want to.

The active worksheet is read. Pass `--sheet` to choose another. `.csv` with the same columns is accepted. `.xlsx` needs `openpyxl` (`pip install openpyxl`).

### Sample file

[`examples/address.xlsx`](../examples/address.xlsx) is **fiction**:

| Master | Interface | Slave | Master Base Address |
| --- | --- | --- | --- |
| `microblaze_0` | `M_AXI_DP` | `/example_ip_a/S00_AXI` | `0x1000_0000` |
| `microblaze_0` | `M_AXI_DP` | `/example_ip_c/S00_AXI` | `0x1800_0000` |
| `xdma_0` | `M_AXI_LITE` | `/example_ip_b/S_AXI_LITE` | `0x2000_0000` |

An excluded row at `0x3000_0000` is in the file and must not appear in the listing. Each slave's Slave Base Address is `0x0000_0000` and is ignored. These are not board addresses. Keep your real export out of git. A file named `address.xlsx` at the repo root is gitignored; the only tracked sample is `examples/address.xlsx`.

### CLI

List master, master interface, slave name, and Master Base Address:

```bat
python addr_map.py D:\lab\vivado-lab-reg\examples\address.xlsx
python addr_map.py --xlsx D:\lab\vivado-lab-reg\examples\address.xlsx --path mb
python addr_map.py --xlsx D:\lab\vivado-lab-reg\examples\address.xlsx --path jtag
```

```bash
python addr_map.py examples/address.xlsx
python -m addr_map --xlsx examples/address.xlsx --path mb
```

`--path mb` keeps `M_AXI_DP` / `Data` slaves. If any master name contains `microblaze`, only those are shown; otherwise every data-port slave is shown and a warning is printed.

`--path jtag` (aliases `j1`, `j2`) keeps `M_AXI_LITE` slaves. If any master name contains `xdma`, only those are shown; otherwise every Lite slave is shown and a warning is printed.

`--mb-name` / `--jtag-name` are substrings of the slave path or the master name. They search the whole data port or the whole Lite set, so a renamed master is still reachable. Example:

```bat
python addr_map.py --xlsx D:\lab\vivado-lab-reg\examples\address.xlsx --path mb --mb-name example_ip_c
```

### Profile snippet

`--suggest-profile` prints Tcl to the terminal. Copy it into `profiles/private/<name>.tcl`. Nothing is written for you.

```bat
python addr_map.py --xlsx D:\lab\vivado-lab-reg\examples\address.xlsx --suggest-profile
```

```bash
python addr_map.py --xlsx examples/address.xlsx --suggest-profile --mb-name example_ip_a --jtag-name example_ip_b
```

With no name filter the snippet uses an **example rule**: the first MicroBlaze `M_AXI_DP` slave, and the first xdma `M_AXI_LITE` slave. A warning names the row that was picked and how many others were skipped. That rule is not a lab convention. If it picks the wrong peripheral, pass a name filter or edit the two `set` lines. `0x0` means smoke / verify skip that read.

`--path` only filters a listing. The snippet still fills both `::MB_SMOKE_ADDR` and `::JTAG_SMOKE_ADDR`.

### What to hand an AI

1. This file.
2. Your export (xlsx or csv). Do not commit it.
3. Ask for either a patched `load_slaves` / `parse_table`, or a finished `profiles/private` snippet.

Tell it to keep using **Master Base Address** for XSDB, to keep ignoring Slave Base `0x0`, and not to hard-code project-specific IP names into the shared parser. Selection stays generic (`microblaze` / `xdma` / `M_AXI_DP` / `M_AXI_LITE`) or an explicit `--mb-name` / `--jtag-name`.

---

<a id="zh"></a>

## 中文

`addr_map.py` 是 **参考解析器**，只认 Vivado Address Editor 的一种导出。它不是万能表格阅读器。不同的板、不同的 Vivado 版本、不同的人，表都不一样。

**请使用 AI 进行适配。** 把本说明（原理和参考列）和**你自己的导出文件**一起交给 AI，让它改 `addr_map.py`，或者直接起草一段 profile。不要假设全世界同一张表。

### 原理

XSDB 的 `mrd` / `mwr` 要用**这个 master 看到该从机的地址**。

| 列 | 能不能拿来 poke |
| --- | --- |
| **Master Base Address** | 能。这就是该 master 的访问地址。抄进 `::MB_SMOKE_ADDR` 或 `::JTAG_SMOKE_ADDR`。 |
| **Slave Base Address** | 不能。很多从机自己的基址是 `0x0`。对 master 去 poke `0x0` 打不中这块外设。 |
| **Range** | 窗口大小。寄存器在 `master base + 0x0 / 0x4 / 0x8 …`。 |
| **Excluded** / **Incomplete** 分组 | 这个 master 到不了。参考解析器会丢掉。 |

MicroBlaze（`M_AXI_DP`，或父行名叫 `Data`）和 JTAG-to-AXI 不是同一张图。JTAG-to-AXI **常常没有自己的一行**。很多设计里，它和某个 xdma master 共用 **M_AXI_LITE** 窗口。你到底连的是哪一条 JTAG2AXI，仍由 GUI 的扫描列表或 `jtag n` 决定。这个导入器只提供地址。所以 `j1` 和 `j2` 列出的是同一组 Lite 从机。

smoke 地址放在 `profiles/private/` 的 board profile 里（已被 gitignore）。见 [profiles/README.md](../profiles/README.md)。本工具不写这个目录，也不替你提交 profile。

### 参考列

表头（认的是名字；有表头时，列的左右顺序无所谓）：

| Name | Interface | Slave Segment | Master Base Address | Range | Slave Base Address |
| --- | --- | --- | --- | --- | --- |

这是一棵**树**，不是每行都写全的扁表。分组行的 **Master Base Address** 是空的。从机行才填这个格子。

1. 名字不以 `/`、`M_`、`m_axi`、`Network `、`Excluded`、`Incomplete` 开头，并且不是 `Data` / `Instruction` / `DLMB` / `ILMB` 的行，开始一个 **master**。例如 `microblaze_0`。
2. `M_…`、`m_axi…`、`Data`、`Instruction`、`DLMB`、`ILMB` 是这个 master 下的**接口**。例如 `M_AXI_DP`。
3. 后面 Master Base Address 有值的行，是该 master、该接口下的**从机**。`Name` 是从机路径（`/example_ip_a/S00_AXI`）。这一行的 `Interface` 格是从机端口，不是 master 端口。命令行列出来的 `iface` 是上一层的 master 接口（`M_AXI_DP`）。
4. `Excluded…` 或 `Incomplete…` 会丢掉后面的从机行，直到下一个 master、接口、`Network …`，或一行 `/…` 分组。
5. `Network …` 结束当前 master。

**扁表**（每一行自己带 master 名字和基址，没有父行）不是这棵树。参考解析器会得到零条从机。那是另一种导出。去改解析器，不要为了凑这个形状去手改你的表，除非你本来就想整理它。

默认读当前工作表。用 `--sheet` 指定别的表。同样列名的 `.csv` 也能读。`.xlsx` 需要 `openpyxl`（`pip install openpyxl`）。

### 示例文件

[`examples/address.xlsx`](../examples/address.xlsx) 是**虚构**的：

| Master | 接口 | 从机 | Master Base Address |
| --- | --- | --- | --- |
| `microblaze_0` | `M_AXI_DP` | `/example_ip_a/S00_AXI` | `0x1000_0000` |
| `microblaze_0` | `M_AXI_DP` | `/example_ip_c/S00_AXI` | `0x1800_0000` |
| `xdma_0` | `M_AXI_LITE` | `/example_ip_b/S_AXI_LITE` | `0x2000_0000` |

文件里还有一条被 Excluded 的 `0x3000_0000`，列表里不应该出现。每条从机的 Slave Base Address 都是 `0x0000_0000`，解析时忽略。这些不是某块板的地址。真实导出不要放进 git。仓库根目录的 `address.xlsx` 已被忽略；唯一跟踪的样本是 `examples/address.xlsx`。

### 命令行

列出 master、master 接口、从机名字和 Master Base Address：

```bat
python addr_map.py D:\lab\vivado-lab-reg\examples\address.xlsx
python addr_map.py --xlsx D:\lab\vivado-lab-reg\examples\address.xlsx --path mb
python addr_map.py --xlsx D:\lab\vivado-lab-reg\examples\address.xlsx --path jtag
```

```bash
python addr_map.py examples/address.xlsx
python -m addr_map --xlsx examples/address.xlsx --path mb
```

`--path mb` 保留 `M_AXI_DP` / `Data`。只要有 master 名字里带 `microblaze`，就只显示那些；否则显示全部数据口从机，并打印警告。

`--path jtag`（`j1`、`j2` 是别名）保留 `M_AXI_LITE`。只要有 master 名字里带 `xdma`，就只显示那些；否则显示全部 Lite 从机，并打印警告。

`--mb-name` / `--jtag-name` 是从机路径或 master 名字的子串。它们会搜整组数据口或整组 Lite，因此 master 改过名也能点到。例如：

```bat
python addr_map.py --xlsx D:\lab\vivado-lab-reg\examples\address.xlsx --path mb --mb-name example_ip_c
```

### profile 片段

`--suggest-profile` 把 Tcl **打印到终端**。你自己抄进 `profiles/private/<名字>.tcl`。命令不会写文件。

```bat
python addr_map.py --xlsx D:\lab\vivado-lab-reg\examples\address.xlsx --suggest-profile
```

```bash
python addr_map.py --xlsx examples/address.xlsx --suggest-profile --mb-name example_ip_a --jtag-name example_ip_b
```

不写名字过滤时，用的是一条**示例规则**：第一条 MicroBlaze `M_AXI_DP` 从机，以及第一条 xdma `M_AXI_LITE` 从机。警告里会写出选中了哪一行、还跳过了几条。这不是实验室约定。选错了就加上名字过滤，或改那两行 `set`。写成 `0x0` 时，smoke / verify 会跳过这一次读。

`--path` 只过滤列表。片段里仍然会同时填 `::MB_SMOKE_ADDR` 和 `::JTAG_SMOKE_ADDR`。

### 交给 AI 的材料

1. 本文件。
2. 你的导出（xlsx 或 csv）。不要提交进仓库。
3. 让它改 `load_slaves` / `parse_table`，或者直接给出一份 `profiles/private` 片段。

请它继续用 **Master Base Address** 作为 XSDB 地址，继续忽略 Slave Base `0x0`，不要把某个工程的 IP 名字写进公共解析器。选择规则保持通用（`microblaze` / `xdma` / `M_AXI_DP` / `M_AXI_LITE`），或用明确的 `--mb-name` / `--jtag-name`。

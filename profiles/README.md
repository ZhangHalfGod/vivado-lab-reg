# Board profiles

Smoke and `verify` read two **Master Base Address** values:

| Variable | Path |
| --- | --- |
| `::MB_SMOKE_ADDR` | MicroBlaze (`microblaze_0` / Data) |
| `::JTAG_SMOKE_ADDR` | JTAG-to-AXI (Jtag Master) |
| `::PROFILE_NAME` | Optional label printed at load |

In Vivado, open **Address Editor** and copy the master's **Master Base Address** (the address at which that master sees offset 0). Do not use the slave's own base of `0x0`. A value of `0x0`, or leaving the variable unset, makes `smoke` / `jsmoke` / `verify` **skip that read** and print why. The tool does not ship a lab address as a silent default.

## Use one on your machine

1. Copy the example into the private directory (gitignored):

   ```bash
   cp profiles/example.tcl profiles/private/board.tcl
   ```

   Windows:

   ```bat
   copy profiles\example.tcl profiles\private\board.tcl
   ```

2. Edit `profiles/private/board.tcl` and set the two Master Base Addresses.
3. Pass that file when you verify or start an interactive session:

   ```bat
   xsdb.cmd verify --profile D:\lab\vivado-lab-reg\profiles\private\board.tcl
   xsdb.cmd --profile D:\lab\vivado-lab-reg\profiles\private\board.tcl
   ```

   ```bash
   ./xsdb.sh verify --profile /lab/vivado-lab-reg/profiles/private/board.tcl
   ./xsdb.sh --profile /lab/vivado-lab-reg/profiles/private/board.tcl
   ```

`--profile` may appear before the command or after `verify`. The same file is used if you set `VIVADO_LAB_REG_PROFILE` (preferred) or `XSDB_PROFILE`.

The Windows GUI setup page can remember the `.tcl` path in `%APPDATA%\VivadoLabReg\config.json`. Connect starts XSDB with that path, so **Verify paths** in the GUI uses the same addresses as the CLI.

`verify` with no profile still connects and scans. Both addresses stay `0x0`, and both reads are skipped.

## Draft the two addresses from a spreadsheet

`addr_map.py` reads one Vivado-style export (`Name`, `Interface`, `Slave Segment`, `Master Base Address`, …). It prints the **Master Base Address** (what XSDB uses) and ignores Slave Base `0x0`.

That parser is a reference for this column layout. Other exports differ. **Use AI to adapt:** give it [the import note](../docs/address-map-import.md) and your own file, and ask it to change the adapter or to fill these two variables. Do not assume every board shares one table.

```bat
python addr_map.py D:\lab\vivado-lab-reg\examples\address.xlsx
python addr_map.py --xlsx D:\lab\vivado-lab-reg\examples\address.xlsx --suggest-profile
```

```bash
python addr_map.py examples/address.xlsx --path mb
python addr_map.py --xlsx examples/address.xlsx --suggest-profile --mb-name example_ip_a --jtag-name example_ip_b
```

`--suggest-profile` prints Tcl on the terminal. Copy it into `profiles/private/`. The command does not write that directory and does not commit anything. `examples/address.xlsx` is fictional (`/example_ip_a` at `0x1000_0000`, `/example_ip_b` at `0x2000_0000`).

The Windows GUI can write the same snippet. **Write private profile** starts at `profiles/private/lab.tcl` and does not replace an existing file unless you confirm. That window uses this **reference** layout. Other formats: **use AI to adapt** ([import note](../docs/address-map-import.md)).

## 中文

`smoke` 和 `verify` 只用两个 **Master Base Address**：

| 变量 | 路径 |
| --- | --- |
| `::MB_SMOKE_ADDR` | MicroBlaze（`microblaze_0` / Data） |
| `::JTAG_SMOKE_ADDR` | JTAG-to-AXI（Jtag Master） |
| `::PROFILE_NAME` | 可选，加载时打印的名字 |

在 Vivado **Address Editor** 里复制该 master 的 **Master Base Address**（这个 master 看到偏移 0 的地址）。不要填从机自己的 Slave Base `0x0`。写成 `0x0` 或不写该变量时，`smoke` / `jsmoke` / `verify` 会**跳过这一次读**并说明原因。工具不再把某块实验板的地址当成静默默认值。

1. 把示例复制到私有目录（已被 gitignore）：

   ```bash
   cp profiles/example.tcl profiles/private/board.tcl
   ```

2. 编辑 `profiles/private/board.tcl`，填上两个 Master Base Address。
3. 自检或交互启动时传入该文件：

   ```bat
   xsdb.cmd verify --profile D:\lab\vivado-lab-reg\profiles\private\board.tcl
   ```

   ```bash
   ./xsdb.sh verify --profile /lab/vivado-lab-reg/profiles/private/board.tcl
   ```

`--profile` 可以写在子命令前面，也可以紧跟在 `verify` 后面。也可以改设环境变量 `VIVADO_LAB_REG_PROFILE`（优先）或 `XSDB_PROFILE`。

Windows GUI 的设置页会把这个 `.tcl` 路径记在 `%APPDATA%\VivadoLabReg\config.json`。Connect 启动 XSDB 时带上它，因此 GUI 里的 **Verify paths** 与命令行使用同一组地址。

不带 profile 的 `verify` 仍会连接并扫描；两个地址保持 `0x0`，两次 `mrd` 都会跳过。

## 从表格起草这两个地址

`addr_map.py` 读取一种 Vivado 导出（`Name`、`Interface`、`Slave Segment`、`Master Base Address` 等）。它打印的是 **Master Base Address**（XSDB 用这个），并忽略 Slave Base `0x0`。

这个解析器只是该列布局的参考实现。别人的导出不一定一样。**请使用 AI 进行适配：** 把 [导入说明](../docs/address-map-import.md) 和你自己的文件交给 AI，让它改适配器，或填上这两个变量。不要假设每块板都是同一张表。

```bat
python addr_map.py D:\lab\vivado-lab-reg\examples\address.xlsx
python addr_map.py --xlsx D:\lab\vivado-lab-reg\examples\address.xlsx --suggest-profile
```

`--suggest-profile` 把 Tcl 打印到终端。抄进 `profiles/private/`。命令不会写这个目录，也不会提交。`examples/address.xlsx` 是虚构的（`/example_ip_a` 为 `0x1000_0000`，`/example_ip_b` 为 `0x2000_0000`）。

Windows GUI 的 **Write private profile** 可以写入同一段 Tcl。保存对话框从 `profiles/private/lab.tcl` 开始，已有文件需确认才替换。该窗口使用这份 **reference** 布局。别的格式：**请使用 AI 进行适配**（[导入说明](../docs/address-map-import.md)）。

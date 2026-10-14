# Private board profiles

Put real lab profiles here (`*.tcl`). They are gitignored.

Copy `../example.tcl` to a name you choose, then set `::MB_SMOKE_ADDR` and `::JTAG_SMOKE_ADDR` to the **Master Base Address** from Vivado Address Editor (not Slave Base `0x0`).

`python addr_map.py --suggest-profile` can print those two lines for one reference spreadsheet. It writes nothing here. The Windows GUI **Write private profile** button can save into this folder after you pick the path (default `lab.tcl`); it asks before replacing a file. Other export layouts: use AI to adapt ([import note](../../docs/address-map-import.md)).

```bat
xsdb.cmd verify --profile D:\lab\vivado-lab-reg\profiles\private\board.tcl
```

```bash
./xsdb.sh verify --profile /lab/vivado-lab-reg/profiles/private/board.tcl
```

中文：把真实实验用的 profile（`*.tcl`）放在这个目录，不会被 git 跟踪。从 `../example.tcl` 复制一份，把 `::MB_SMOKE_ADDR` 和 `::JTAG_SMOKE_ADDR` 填成 Vivado Address Editor 里的 **Master Base Address**（不是从机自己的 Slave Base `0x0`）。`python addr_map.py --suggest-profile` 可以按一种参考表格把这两行打印出来，但不会往本目录写文件。GUI 的 **Write private profile** 在你选定路径后可以写到这里（默认 `lab.tcl`），覆盖前会询问。别的导出格式请使用 AI 进行适配（[导入说明](../../docs/address-map-import.md)）。

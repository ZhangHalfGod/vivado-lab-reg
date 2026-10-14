# Windows 图形化寄存器调试工具用法

给 **Ubuntu 上开发、Windows 上连板调试** 用的说明。  
图形界面只在 Windows 上跑；Ubuntu 侧改代码、看 Address Map，把要查的地址拿到这台 Windows 上填进工具即可。

| 项 | 值 |
|----|----|
| 工具目录 | `.` |
| 启动 | 双击 `VivadoLabReg.exe` 或 `gui.cmd` |
| 板卡 | VCU128 / `xcvu37p` |
| 软件 | Vivado Lab 2022.2 |
| XSDB | `D:\vivdao_down\Vivado_Lab\2022.2\bin\xsdb.bat` |
| 地址表 | 同目录 `address_top.xlsx`（Address Editor 导出） |

---

## 1. 开发时怎么配合

```text
Ubuntu：写 RTL / 驱动 / 看 Address Map，记下要访问的基址
    ↓
Windows：bitstream 下到 FPGA → 打开本 GUI → Connect 扫描 → 在 Targets 里选一行 → 手填地址 → 读/写
```

- **不要**指望在 Ubuntu 上开这个窗口。`gui.py` 调的是 Windows 的 `xsdb.bat` + JTAG 线。
- Ubuntu 上如果也装了 Vivado Lab / Vitis，可以用同目录 `xsdb.sh` 做命令行读写，和 GUI 一样走 `tool.tcl`。
- 新 IP 的地址以工程 **Address Editor** 为准，不要沿用过期的 `0x44A00000` 一类示例。

---

## 2. 两条地址空间（先在 Targets 里选对）

同一根 JTAG 上可以有多个 Master，**地址空间不同**。选错 target，读出来是废数据。

点 **Connect** 之后，**Targets** 列出这次扫描到的寄存器 target，每行是 id 和名字（例如 `MicroBlaze #0`、`JTAG2AXI`）。点哪一行，就切到哪个 XSDB target。

```text
GUI / XSDB
    └─ hw_server（JTAG）
           ├─ MicroBlaze     JTAG → XSDB → MDM → MB
           └─ JTAG2AXI       JTAG → XSDB → Jtag Master
```

| 扫描到的 target | 对应 | 用哪套地址 | 本板例子 |
|-----------------|------|------------|----------|
| 名字含 MicroBlaze（如 MicroBlaze #0） | `microblaze_0` / **M_AXI_DP** | `0x110xxxxx`、`0x11Axxxxx` 等 | `11080000` = `ext_reg_if` |
| 某一条 JTAG2AXI（本板常对应 Hardware Manager 的 `hw_axi_1`） | Jtag Master | **xdma_0 / M_AXI_LITE**，`0x116Bxxxx` | `0x116BCC00` = example Lite window register (replace with your map) |
| 另一条 JTAG2AXI（本板常对应 `hw_axi_2`） | 另一条 Jtag Master | xlsx **没有**单独 map，需自己确认 | 同一 `116BCC00` 会读到 `0000DEAD` |

在列表里选一行 **只切换 target**，成功即已选中，**还不需要地址**。  
填地址、点 **Read** / **Write**，才是访问寄存器。

列表为空：板上电、下载 bitstream，再点 **Refresh targets**。换板或换 bitstream 之后同样要刷新，再重新选择。

交叉读写的典型错误值：`DEC0DE1C`（AXI 译码失败，地址在这条总线上不存在）。

---

## 3. 启动前检查

1. 板子上电，bitstream 已下载。
2. **关掉** Vivado Hardware Manager（和 GUI 抢同一条 JTAG）。
3. 本机有 Python 3（已用 3.10 验证）和 Vivado Lab。
4. 双击 `VivadoLabReg.exe` 或 `gui.cmd`。**先出现选择 `xsdb.bat` 的设置页**，没选到有效文件就不能进主窗口。浏览从「此电脑」打开，默认文件类型为 `*.bat`。第一次路径为空；点 **Continue** 后写入 `%APPDATA%\VivadoLabReg\config.json`，下次打开自动填入该路径。本机例子：`D:\vivdao_down\Vivado_Lab\2022.2\bin\xsdb.bat`。

---

## 3.1 打成 exe 的前提（打包 / 运行分开）

**打包机（做一次即可）**

- Windows 64 位
- Python 3.10+（含 tkinter）
- `pip install pyinstaller`
- 在 `vivado_lab` 目录执行 `build_exe.bat`

产物：`VivadoLabReg.exe`（已打进 `gui.py` / `gui.tcl` / `tool.tcl` 和 Python 运行时）。

**运行机（日常连板）——不需要 Python**

- Windows 64 位
- **Vivado Lab 或完整 Vivado**（本机是 2022.2，`xsdb.bat` 必须存在）
- 对应版本的 **JTAG 电缆驱动**（装 Lab 时一般已装）
- 板子上电、bitstream 已下载
- **不要**同时开 Hardware Manager
- GUI 记住的 `xsdb.bat` 路径在 `%APPDATA%\VivadoLabReg\config.json`（与 exe 位置无关）

打不开或提示找不到 xsdb：先确认 Lab 已装，并在设置页选择本机的 `xsdb.bat`（例如 `D:\vivdao_down\Vivado_Lab\2022.2\bin\xsdb.bat`）。

重新打包：改完 `gui.py` / `tool.tcl` 后再跑一次 `build_exe.bat`。`tool.tcl` 已打进 exe，只改目录里的 tcl **不会**自动进已生成的 exe。

---

## 4. 窗口怎么用

1. **准备。** 板上电，bitstream 已加载，关掉 Hardware Manager。设置页若还没选过，先指定 `xsdb.bat`（例如 `D:\vivdao_down\Vivado_Lab\2022.2\bin\xsdb.bat`），再点 **Continue**。
2. 点 **Connect**。工具启动 XSDB，并**扫描** JTAG 链。
3. **Targets** 列出扫到的寄存器 target（例如 MicroBlaze #0、JTAG2AXI），每行是 id 和名字，**不是写死的档位**。列表为空：确认上电并已下载 bitstream，再点 **Refresh targets**。
4. **选中**一行。这一步只切换 XSDB target，还不需要填地址。日志会出现 `Selected … (registers not read). Enter an address for Read / Write.`
5. **自己填**，再点 **Read** / **Write** / **Write + Readback**：
   - 地址：十六进制，可带或不带 `0x`，如 `11080000` 或 `0x116B_CC00`
   - 长度：连续读几个 32-bit word，默认 `1`，**最大 256**（工具限制；一次读太多会占满历史条数）
   - 数据：写操作用，如 `00000001`
6. 换板或换 bitstream 后，点 **Refresh targets**，再重新选一行。

左侧 **History (last 100)**（新的在上，读/写都会记）；右侧是日志。History 的 Address / Data 显示为 8 位十六进制；XSDB 自己的日志里，短地址仍可能不补前导零。

点历史里的一行，会把该行的地址和数据填回输入框（方便改完再写）。

**Clear**：同时清空日志和历史。不断开 JTAG。  
**Disconnect**：结束 XSDB 会话。

---

## 5. Ubuntu 开发时如何选地址

打开 `address_top.xlsx`（或 Ubuntu 工程里 Address Editor）。

### 走 MicroBlaze（Targets 里选 MicroBlaze 那一行）

用 **microblaze_0 → M_AXI_DP** 里 **未 Excluded** 的 **Master Base Address**。

常用：

| 基址 | 从机 |
|------|------|
| `0x1108_0000` | `/ext_reg_if/S00_AXI` |

不要用标了 **Excluded** 的段（例如部分 `0x44A0_0000`）。那些地址 MB 到不了。

### 走 Jtag Master（Targets 里选对应的 JTAG2AXI）

用 **xdma_0 → M_AXI_LITE** 的基址（PCIe Lite 窗，本板是 `0x116Bxxxx`）。本板这条通常对应 Hardware Manager 的 `hw_axi_1`，在 **Targets** 里选对应的 `JTAG2AXI` 那一行。

JTAG-to-AXI IP **不会**作为从机出现在 xlsx 里，它是和 xdma 一样的 **Master**。和 Lite 窗共用地址的那一条，用下表。

| 基址 | Range | 从机 |
|------|-------|------|
| `116B0000` | 4K | mb_pcie_exchange_ram / axi_bram_ctrl_0 |
| `116B1000` | 4K | pcie_external_interface |
| `116B2000` | 4K | audio_to_ext_memory / axi_dma_0 S_AXI_LITE |
| `116B8000` | 1K | Generator / axi4_stream_jitter_inserted |
| `116B8400` | 1K | anc_trouble_maker_sfp0 |
| `116B8800` | 1K | anc_trouble_maker_sfp1 |
| `116B8C00` | 1K | audio_trouble_maker_sfp0 |
| `116B9000` | 1K | audio_trouble_maker_sfp1 |
| `116B9400` | 1K | vid_st22_trouble_make_sfp1 |
| `116B9800` | 1K | vid_st22_trouble_maker_sfp0 |
| `116B9C00` | 1K | st2110_20 jitter_inserted |
| `116BA000` | 1K | st2110_20 trouble_sfp1 |
| `116BA400` | 1K | st2110_20 trouble_sfp0 |
| `116BA800` | 1K | dummy_udp / axi4_stream_generator_0 |
| `116BAC00` | 1K | dummy_udp / udp_ip_encap_sfp0 |
| `116BB000` | 1K | dummy_udp / udp_ip_encap_sfp1 |
| `116BB400` | 1K | phase_detect |
| `116BB800` | 1K | av_delay / sdi_audio_extract_0 |
| `116BBC00` | 1K | av_delay / audio_video_delay_0 |
| `116BC000` | 1K | av_delay / internal_path_delay |
| `116BC400` | 1K | audio_extract_fm_sdi_rx |
| `116BC800` | 1K | sdi_analysis / formatted_s2mm_0 |
| `116BCC00` | 1K | sdi_analysis / link0 |
| `116BD000` | 1K | sdi_analysis / link1 |
| `116BD400` | 1K | sdi_analysis / link2 |
| `116BD800` | 1K | sdi_analysis / link3 |

寄存器偏移：在基址上加 `+0x0 / +0x4 / +0x8 …`（按该 IP 的寄存器手册）。GUI 的「长度」是从该地址起连续几个 word。

工程若重综合导致 Address Map 变了，以 **新的** Address Editor / 新导出的 xlsx 为准，不要死记上表。

---

## 6. 对照 Demo（GUI 应与直接 XSDB 一致）

先 **Connect**，在 **Targets** 里选好 target，再填地址。下列为某次 XSDB 实测，计数器类寄存器允许轻微变化。

**Demo 1** Targets 里选 MicroBlaze（如 MicroBlaze #0），地址 `11080000`，长度 `8`

| 地址 | 参考值 | 备注 |
|------|--------|------|
| `11080000` | `000F0000` | 较稳 |
| `11080004` | `0000D8C5` | 较稳 |
| `11080008` / `0C` | 会变 | 像计数器 |
| `11080010` | `00000001` | 较稳 |
| `11080014` | `00000001` | 较稳 |
| `11080018` | `00000000` | 较稳 |

**Demo 2** Targets 里选本板对应 `hw_axi_1` 的那条 JTAG2AXI，地址 `116BCC00`，长度 `4`  
`00000000 / 00000001 / 00000001 / 00000000`

**Demo 3** 仍是这一条，地址 `116B0000`，长度 `4`  
`55AA55AA / AA55AA55 / 00000000 / 00000000`

**Demo 4** Targets 里改选另一条 JTAG2AXI（本板对应 `hw_axi_2`），地址 `116BCC00`，长度 `4`  
四个 word 均为 `0000DEAD`（说明切到了另一条 Master）

**Demo 5** 仍停在 Lite 窗那条 JTAG2AXI，地址 `11080000`，长度 `1`  
`DEC0DE1C`（MB 地址拿到 Jtag Master 上，译码失败）

Windows 上重跑 XSDB 基准：

```bat
D:\vivdao_down\Vivado_Lab\2022.2\bin\xsdb.bat .\demo.tcl
```

---

## 7. 读回值怎么判断

| 读回 | 含义 |
|------|------|
| 稳定、符合 IP 手册 | 选中的 target 和地址都对 |
| `DEC0DE1C` | 当前 Master 的总线上 **没有这个地址**（选错 target，或地址不在这条总线上） |
| `0000DEAD` | 本板另一条 JTAG2AXI（对应 `hw_axi_2`）在 `116BCC00` 上的表现；不要当成 link0 状态 |
| 写显示成功但读回不变 | 只读寄存器，或写没落到从机（再核对选中的 target） |
| 连接失败 / 超时 | 板未上电、未下载 bit、或 Hardware Manager 占着 JTAG |

`WRITE DATA is: …` / 工具里写成功，只表示主机发出了写；**以读回为准**。

---

## 8. Ubuntu 侧没有 GUI 时

同目录命令行与 GUI 走同一套 `mrd` / `mwr`（先关 Hardware Manager）。命令行用 `mb` / `jtag n` 切 target；Windows GUI 在 **Targets** 里点选扫描到的 id。

```bash
cd /path/to/vivado_lab
./xsdb.sh                # 交互，然后 mb / jtag 1 / rd / wr
./xsdb.sh verify
./xsdb.sh rd  11080000 8
./xsdb.sh jrd 116BCC00 4
./xsdb.sh jwr 116BCC08 1
```

Windows 命令行：`xsdb.cmd` 参数相同。

交互短命令（`tool.tcl`）：

| 命令 | 作用 |
|------|------|
| `xconnect` | 连接并列出路径（命令行） |
| `mb` / `jtag 1` / `jtag 2` | 命令行切到 MicroBlaze，或第 n 条 JTAG2AXI |
| `rd <addr> [len]` | 读 |
| `wr <addr> <data>` | 写 |
| `wrd <addr> <data>` | 写完读回 |

---

## 9. 目录文件

| 文件 | 用途 |
|------|------|
| **本文档** | Ubuntu 开发时对照、Windows 上操作 GUI |
| `VivadoLabReg.exe` | Windows 图形界面（不需要 Python） |
| `build_exe.bat` | 重新打包 exe |
| `gui.cmd` `gui.py` `gui.tcl` | 源码启动 / 开发调试 |
| `tool.tcl` | 真正的 `mrd`/`mwr` 逻辑 |
| `xsdb.cmd` / `xsdb.sh` | Windows / Linux 命令行 |
| `demo.tcl` | 与 GUI 对照的 XSDB 基准 |
| `address_top.xlsx` | Address Map 导出 |
| `reg.tcl` | `verify` 批处理 |

---

## 10. 本机 JTAG 链（编号会变，以当次扫描为准）

下面是某次 VU37P 扫描的例子。下次连接，id 可能不同。**Targets** 显示的就是当次扫到的 id 和名字。

```text
1  xcvu37p
   2  MicroBlaze Debug Module at USER2
      3  MicroBlaze #0     ← 会出现在 Targets
   4  Legacy Debug Hub
      5  JTAG2AXI          ← 会出现在 Targets
      6  JTAG2AXI          ← 另一条，单独成行
```

**Targets** 收录能做寄存器读写的 MicroBlaze 和 JTAG2AXI（Jtag Master）。点一行即选中该 id。不要把 target 编号写死进脚本；换板或换 bitstream 后点 **Refresh targets** 再选。

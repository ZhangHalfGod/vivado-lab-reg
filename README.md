# Vivado Lab XSDB 独立工具

**完整用法（Ubuntu 开发 + Windows GUI 对照）：**  
[Windows图形化调试工具用法.md](docs/usage-zh.md)

适用：本机已安装 **Vivado Lab**（或完整 Vivado，自带同样的 `xsdb`）。

同一条 JTAG 上有两条访问寄存器的路径，工具里用 `mb` / `jtag` 切换 target，然后都走 `mrd` / `mwr`：

```text
用户脚本 → XSDB → hw_server → FPGA
                         ├─ MDM → MicroBlaze → 外设          （mb）
                         └─ Legacy Debug Hub → JTAG2AXI      （jtag / Jtag Master）
```

`JTAG2AXI` 就是 Hardware Manager 里的 `hw_axi_1` / `hw_axi_2`（JTAG-to-AXI Master）。  
本机 VU37P 实测：target **5** = JTAG2AXI #1，target **6** = JTAG2AXI #2（编号会随扫描链变，脚本按名字枚举）。

Lab 负责 JTAG/调试协议。工具只发：`connect` / `targets` / `mrd` / `mwr`。

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

窗口里可以：

1. 点 **连接**（内部启动一条常驻 XSDB 会话，不要和 Hardware Manager 同时占 JTAG）
2. 选路径：MicroBlaze / JTAG2AXI #1 / JTAG2AXI #2  
   **选路径只切换 target，成功即“已选中”，不需要地址。**
3. 自己填写地址、长度、数据，点 **读 / 写 / 写+读回**
4. 左侧保留最近 100 次读写（含读和写）

依赖本机 Python 3（已用 3.10 验证）。逻辑与 `tool.tcl` 相同。

---

## 使用前

1. 板子上电，bitstream 已下载（链上能看到 MicroBlaze 和/或 JTAG2AXI）。
2. 若 Vivado Hardware Manager 已连着板子，先关掉，避免抢 JTAG。
3. 找不到 `xsdb` 时，把 Lab 的 `bin` 加进 PATH，或设置环境变量 `XSDB`。

常见路径：

- Windows：`D:\vivdao_down\Vivado_Lab\2022.2\bin\xsdb.bat` 或 `C:\Xilinx\Vivado_Lab\<version>\bin\xsdb.bat`
- Linux：`/opt/Xilinx/Vivado_Lab/<version>/bin/xsdb`

---

## 两条路径用哪套地址

| 路径 | 命令 | 地址从哪来 | 本板验证地址 |
|------|------|------------|--------------|
| MicroBlaze | `rd` / `wr` / `smoke` | **microblaze_0 / Data** Address Map | `0x11080000` |
| Jtag Master | `jrd` / `jwr` / `jsmoke` | 该 JTAG2AXI 所连 AXI 互联的 Address Map（如 PCIe xdma Lite 窗） | `0x116BCC00` |

不要把 MB 地址拿到 JTAG2AXI 上读：本板 `0x11080000` 在 JTAG2AXI #1 上返回 `DEC0DE1C`（译码失败）。  
不要把 `0x116BCxxx` 拿到 MB 上读（那是 Jtag Master 侧窗）。

---

## 方案 A：批处理（两条路径都验证）

```bat
xsdb.cmd verify
```

Linux：

```bash
./xsdb.sh verify
```

会依次：

1. 选 MicroBlaze，`mrd 0x11080000 10`
2. 选 JTAG2AXI #1、#2，各 `mrd 0x116BCC00 4`

---

## 方案 B：交互

Windows 双击 `xsdb.cmd`，或 Linux `./xsdb.sh`。连上后：

```tcl
mb
smoke
rd 11080000 10

jtag 1
jsmoke
rd 116BCC00 4
wr 116BCC08 1
wrd 116BCC08 1

jtag 2
rd 116BCC00 4
path
```

| 命令 | 作用 |
|------|------|
| `xconnect` | 重新 connect，列出两条路径 |
| `mb` | 切到 MicroBlaze |
| `jtag [n]` | 切到 Jtag Master（n=1 或 2，默认 1） |
| `axi n` | 同 `jtag n`（对应 hw_axi_1 / hw_axi_2） |
| `path` | 显示当前路径 |
| `rd <addr> [len]` | 在**当前** target 上读 |
| `wr <addr> <data>` | 在当前 target 上写 |
| `wrd <addr> <data>` | 写完读回 |
| `smoke` | MB：`mrd 0x11080000 10` |
| `jsmoke [n]` | JTAG2AXI：`mrd 0x116BCC00 4` |
| `verify_all` | 两条路径都跑一遍 |
| `help_xsdb` | 帮助 |

也可在已打开的 xsdb 里：

```tcl
source {./tool.tcl}
```

Windows 路径请用**正斜杠**。

---

## 单次命令（给别的程序调用）

```bat
xsdb.cmd rd    11080000 10
xsdb.cmd wr    11080000 12345678
xsdb.cmd wrd   11080000 1
xsdb.cmd jrd   116BCC00 4
xsdb.cmd jrd2  116BCC00 4
xsdb.cmd jwr   116BCC08 1
xsdb.cmd jwrd  116BCC08 1
xsdb.cmd targets
xsdb.cmd verify
```

---

## 文件

| 文件 | 对应 |
|------|------|
| `gui.cmd` / `gui.py` / `gui.tcl` | Windows 交互窗口 |
| `reg.tcl` | 方案 A：两条路径批处理验证 |
| `tool.tcl` | 方案 B：交互短命令（含 `mb` / `jtag`） |
| `xsdb.cmd` | Windows 命令行启动器 |
| `xsdb.sh` | Linux 启动器 |

---

## 本板实测摘要（xcvu37p）

```text
1  xcvu37p
   2  MicroBlaze Debug Module at USER2
      3  MicroBlaze #0
   4  Legacy Debug Hub
      5  JTAG2AXI     ← jtag 1  （能读 0x116BCC00，对应 hw_axi_1）
      6  JTAG2AXI     ← jtag 2  （另一条 master，0x116BCC00 读回 0000DEAD）
```

# -*- coding: utf-8 -*-
"""Vivado Lab XSDB register GUI: MicroBlaze + JTAG2AXI."""

from __future__ import annotations

import json
import os
import queue
import re
import sys
import threading
import time
import tkinter as tk
from pathlib import Path
from subprocess import PIPE, STDOUT, STARTF_USESHOWWINDOW, STARTUPINFO, Popen, SW_HIDE
from tkinter import filedialog, messagebox, ttk

def app_dir() -> Path:
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent


def resource_dir() -> Path:
    """Folder that contains gui.tcl / tool.tcl (PyInstaller extract dir or next to exe)."""
    candidates = []
    meipass = getattr(sys, "_MEIPASS", None)
    if meipass:
        candidates.append(Path(meipass))
    candidates.append(app_dir())
    candidates.append(Path(__file__).resolve().parent)
    for d in candidates:
        if (d / "gui.tcl").is_file() and (d / "tool.tcl").is_file():
            return d
    return candidates[0]


HERE = resource_dir()
DONE = "__XSDB_DONE__"
READY = "GUI_READY"
HEX_RE = re.compile(r"^(?:0x)?[0-9A-Fa-f_]+$", re.I)
MRD_RE = re.compile(r"^\s*([0-9A-Fa-f]+):\s+([0-9A-Fa-f]+)\s*$", re.I)
HISTORY_MAX = 100
APP_NAME = "VivadoLabReg"
# Windows 文件对话框中的「此电脑」
THIS_PC = "::{20D04FE0-3AEA-1069-A2D8-08002B30309D}"

PATH_NAME = {
    "mb": "MicroBlaze",
    "j1": "JTAG2AXI #1（Jtag Master）",
    "j2": "JTAG2AXI #2（Jtag Master）",
}


def validate_xsdb(raw: str) -> Path | None:
    text = (raw or "").strip().strip('"')
    if not text:
        return None
    p = Path(text)
    if not p.is_file():
        return None
    if p.suffix.lower() != ".bat":
        return None
    if p.name.lower() != "xsdb.bat":
        return None
    return p.resolve()


def config_file() -> Path:
    base = os.environ.get("APPDATA")
    if not base:
        base = str(Path.home() / "AppData" / "Roaming")
    return Path(base) / APP_NAME / "config.json"


def load_saved_xsdb() -> str:
    cfg = config_file()
    if not cfg.is_file():
        return ""
    try:
        data = json.loads(cfg.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return ""
    if not isinstance(data, dict):
        return ""
    return str(data.get("xsdb_bat") or "").strip()


def save_xsdb_path(xsdb: Path) -> None:
    cfg = config_file()
    cfg.parent.mkdir(parents=True, exist_ok=True)
    payload = {"xsdb_bat": str(xsdb)}
    cfg.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def norm_hex(token: str, name: str) -> str:
    raw = token.strip().replace("_", "")
    if not HEX_RE.match(raw):
        raise ValueError(f"{name} 不是十六进制: {token}")
    if raw.lower().startswith("0x"):
        raw = raw[2:]
    if not raw:
        raise ValueError(f"{name} 为空")
    return raw


class XsdbSession:
    def __init__(self, xsdb: Path, script: Path) -> None:
        self.xsdb = xsdb
        self.script = script
        self.proc: Popen[str] | None = None
        self._q: queue.Queue[str] = queue.Queue()
        self._reader: threading.Thread | None = None

    @property
    def alive(self) -> bool:
        return self.proc is not None and self.proc.poll() is None

    def start(self, timeout: float = 20.0) -> str:
        self.close()
        si = STARTUPINFO()
        si.dwFlags |= STARTF_USESHOWWINDOW
        si.wShowWindow = SW_HIDE
        self.proc = Popen(
            [str(self.xsdb), str(self.script)],
            stdin=PIPE,
            stdout=PIPE,
            stderr=STDOUT,
            cwd=str(self.script.parent),
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
            startupinfo=si,
        )
        self._reader = threading.Thread(target=self._pump, daemon=True)
        self._reader.start()
        lines: list[str] = []
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                line = self._q.get(timeout=0.2)
            except queue.Empty:
                if not self.alive:
                    extra = self._drain()
                    raise RuntimeError("xsdb 已退出。\n" + "\n".join(lines + extra))
                continue
            if line.strip() == READY:
                return "\n".join(lines)
            lines.append(line.rstrip("\n"))
        raise TimeoutError("等待 XSDB GUI_READY 超时。请确认 xsdb 可用。")

    def call(self, cmd: str, timeout: float = 30.0) -> str:
        if not self.alive or self.proc is None or self.proc.stdin is None:
            raise RuntimeError("尚未启动 XSDB 会话")
        self.proc.stdin.write(cmd.strip() + "\n")
        self.proc.stdin.flush()
        out: list[str] = []
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                line = self._q.get(timeout=0.2)
            except queue.Empty:
                if not self.alive:
                    raise RuntimeError("xsdb 已退出。\n" + "\n".join(out))
                continue
            if line.strip() == DONE:
                return "\n".join(out).strip()
            out.append(line.rstrip("\n"))
        raise TimeoutError(f"命令超时: {cmd}")

    def close(self) -> None:
        proc = self.proc
        self.proc = None
        if proc is None:
            return
        try:
            if proc.poll() is None and proc.stdin:
                proc.stdin.write("GUI_EXIT\n")
                proc.stdin.flush()
                proc.wait(timeout=3)
        except Exception:
            pass
        try:
            if proc.poll() is None:
                proc.kill()
        except Exception:
            pass

    def _pump(self) -> None:
        proc = self.proc
        if proc is None or proc.stdout is None:
            return
        try:
            for line in proc.stdout:
                self._q.put(line)
        except Exception:
            pass

    def _drain(self) -> list[str]:
        extra: list[str] = []
        while True:
            try:
                extra.append(self._q.get_nowait().rstrip("\n"))
            except queue.Empty:
                break
        return extra


class App(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("选择 xsdb.bat  ·  Vivado Lab")
        self.geometry("720x300")
        self.minsize(640, 260)
        self.xsdb_path: Path | None = None
        self.session: XsdbSession | None = None
        self.connected = False
        self.busy = False
        self.path_var = tk.StringVar(value="mb")
        self.addr_var = tk.StringVar(value="")
        self.len_var = tk.StringVar(value="1")
        self.data_var = tk.StringVar(value="00000001")
        self.status_var = tk.StringVar(value="未连接")
        self.xsdb_var = tk.StringVar(value="")
        self.setup_path_var = tk.StringVar(value="")
        self.setup_msg_var = tk.StringVar(
            value="请选择本机 Vivado Lab 中的 xsdb.bat，未选择将不能进入调试页面。"
        )
        saved = load_saved_xsdb()
        if saved:
            self.setup_path_var.set(saved)
            self.setup_msg_var.set("已载入上次保存的路径，确认后点「进入调试」。")
        self.setup_frame = ttk.Frame(self)
        self.main_frame = ttk.Frame(self)
        self._build_setup()
        self._build()
        self.setup_frame.pack(fill="both", expand=True)
        self.protocol("WM_DELETE_WINDOW", self._on_close)

    def _build_setup(self) -> None:
        box = ttk.LabelFrame(self.setup_frame, text="导入 xsdb.bat")
        box.pack(fill="both", expand=True, padx=16, pady=16)
        ttk.Label(
            box,
            text="本工具通过 Vivado Lab 的 xsdb.bat 访问 JTAG。\n"
                 "请选择：...\\Vivado_Lab\\<版本>\\bin\\xsdb.bat",
            justify="left",
        ).pack(anchor="w", padx=12, pady=(12, 8))
        row = ttk.Frame(box)
        row.pack(fill="x", padx=12, pady=6)
        ttk.Label(row, text="路径").pack(side="left")
        ttk.Entry(row, textvariable=self.setup_path_var).pack(
            side="left", fill="x", expand=True, padx=8
        )
        ttk.Button(row, text="浏览…", command=self._browse_xsdb).pack(side="left")
        ttk.Label(box, textvariable=self.setup_msg_var, wraplength=640).pack(
            anchor="w", padx=12, pady=(4, 8)
        )
        btns = ttk.Frame(box)
        btns.pack(fill="x", padx=12, pady=(0, 12))
        ttk.Button(btns, text="进入调试", command=self._enter_main).pack(side="right", padx=4)
        ttk.Button(btns, text="退出", command=self._on_close).pack(side="right")

    def _browse_xsdb(self) -> None:
        path = filedialog.askopenfilename(
            parent=self,
            title="选择 Vivado Lab 的 xsdb.bat",
            defaultextension=".bat",
            filetypes=[("批处理文件 (*.bat)", "*.bat"), ("所有文件", "*.*")],
            initialdir=THIS_PC,
            initialfile="xsdb.bat",
        )
        if path:
            self.setup_path_var.set(path)
            self.setup_msg_var.set("已选择文件，点「进入调试」确认。")

    def _enter_main(self) -> None:
        picked = validate_xsdb(self.setup_path_var.get())
        if picked is None:
            self.setup_msg_var.set(
                "未输入或路径无效：必须是本机存在的 xsdb.bat。不能进入调试页面。"
            )
            messagebox.showwarning(
                "xsdb.bat 未就绪",
                "请先选择有效的 xsdb.bat（文件类型 .bat，文件名须为 xsdb.bat）。",
            )
            return
        self.xsdb_path = picked
        self.xsdb_var.set(str(picked))
        try:
            save_xsdb_path(picked)
        except OSError as exc:
            messagebox.showwarning(
                "路径未保存",
                f"xsdb 可用，但未能写入配置文件：\n{config_file()}\n{exc}",
            )
        if self.session:
            self.session.close()
        self.session = XsdbSession(picked, HERE / "gui.tcl")
        self.setup_frame.pack_forget()
        self.title("Vivado Lab 寄存器调试  ·  XSDB")
        self.geometry("1080x720")
        self.minsize(900, 600)
        self.main_frame.pack(fill="both", expand=True)
        self._log(f"xsdb = {picked}")

    def _back_setup(self) -> None:
        if self.busy:
            return
        if self.session:
            self._disconnect()
            self.session.close()
            self.session = None
        self.main_frame.pack_forget()
        self.title("选择 xsdb.bat  ·  Vivado Lab")
        self.geometry("720x300")
        self.minsize(640, 260)
        self.setup_frame.pack(fill="both", expand=True)

    def _build(self) -> None:
        root = self.main_frame
        pad = {"padx": 8, "pady": 6}
        top = ttk.Frame(root)
        top.pack(fill="x", **pad)
        ttk.Label(top, text="状态").pack(side="left")
        ttk.Label(top, textvariable=self.status_var).pack(side="left", padx=(6, 16))
        ttk.Button(top, text="连接", command=self._connect).pack(side="left", padx=2)
        ttk.Button(top, text="断开", command=self._disconnect).pack(side="left", padx=2)
        ttk.Button(top, text="刷新 targets", command=self._targets).pack(side="left", padx=2)
        ttk.Button(top, text="验证两条路径", command=self._verify).pack(side="left", padx=2)
        ttk.Button(top, text="更换 xsdb", command=self._back_setup).pack(side="left", padx=12)

        xs = ttk.Frame(root)
        xs.pack(fill="x", padx=8)
        ttk.Label(xs, text="xsdb").pack(side="left")
        ttk.Label(xs, textvariable=self.xsdb_var).pack(side="left", padx=6)

        pathf = ttk.LabelFrame(root, text="路径（选中即连接该 Master，不需要地址）")
        pathf.pack(fill="x", padx=8, pady=6)
        ttk.Radiobutton(
            pathf, text="MicroBlaze     JTAG → XSDB → MDM → MB",
            value="mb", variable=self.path_var, command=self._on_path,
        ).pack(anchor="w", padx=8, pady=2)
        ttk.Radiobutton(
            pathf, text="JTAG2AXI #1    JTAG → XSDB → Jtag Master（hw_axi_1）",
            value="j1", variable=self.path_var, command=self._on_path,
        ).pack(anchor="w", padx=8, pady=2)
        ttk.Radiobutton(
            pathf, text="JTAG2AXI #2    JTAG → XSDB → Jtag Master（hw_axi_2）",
            value="j2", variable=self.path_var, command=self._on_path,
        ).pack(anchor="w", padx=8, pady=2)
        ttk.Label(
            pathf,
            text="选路径只切换 target，成功即“已选中”。读/写请自己在下面填写十六进制地址。",
            wraplength=980,
        ).pack(anchor="w", padx=8, pady=(0, 6))

        ops = ttk.LabelFrame(root, text="读写（需要具体地址）")
        ops.pack(fill="x", padx=8, pady=4)
        row = ttk.Frame(ops)
        row.pack(fill="x", padx=8, pady=6)
        ttk.Label(row, text="地址").pack(side="left")
        ttk.Entry(row, textvariable=self.addr_var, width=14).pack(side="left", padx=4)
        ttk.Label(row, text="长度(1–256)").pack(side="left")
        ttk.Entry(row, textvariable=self.len_var, width=5).pack(side="left", padx=4)
        ttk.Label(row, text="数据").pack(side="left")
        ttk.Entry(row, textvariable=self.data_var, width=12).pack(side="left", padx=4)
        ttk.Button(row, text="读", command=self._rd).pack(side="left", padx=3)
        ttk.Button(row, text="写", command=self._wr).pack(side="left", padx=3)
        ttk.Button(row, text="写+读回", command=self._wrd).pack(side="left", padx=3)
        ttk.Button(row, text="Clear", command=self._clear).pack(side="left", padx=12)

        mid = ttk.Frame(root)
        mid.pack(fill="both", expand=True, padx=8, pady=4)
        mid.columnconfigure(0, weight=1)
        mid.columnconfigure(1, weight=2)
        mid.rowconfigure(0, weight=1)

        last = ttk.LabelFrame(mid, text="最近 100 次读写（新的在上）")
        last.grid(row=0, column=0, sticky="nsew", padx=(0, 6))
        rcols = ("op", "addr", "data")
        self.tree = ttk.Treeview(last, columns=rcols, show="headings", height=16)
        self.tree.heading("op", text="操作")
        self.tree.heading("addr", text="地址")
        self.tree.heading("data", text="数据")
        self.tree.column("op", width=50, anchor="w")
        self.tree.column("addr", width=120, anchor="w")
        self.tree.column("data", width=120, anchor="w")
        syh = ttk.Scrollbar(last, orient="vertical", command=self.tree.yview)
        self.tree.configure(yscrollcommand=syh.set)
        self.tree.pack(side="left", fill="both", expand=True, padx=(4, 0), pady=4)
        syh.pack(side="right", fill="y", pady=4)
        self.tree.bind("<<TreeviewSelect>>", self._from_tree)

        right = ttk.LabelFrame(mid, text="日志")
        right.grid(row=0, column=1, sticky="nsew")
        self.log = tk.Text(right, wrap="word", height=12, font=("Consolas", 10))
        sy = ttk.Scrollbar(right, orient="vertical", command=self.log.yview)
        self.log.configure(yscrollcommand=sy.set)
        self.log.pack(side="left", fill="both", expand=True)
        sy.pack(side="right", fill="y")

        hint = ttk.Label(
            root,
            text="板子先上电并已下载 bitstream。Hardware Manager 不要占着 JTAG。",
        )
        hint.pack(fill="x", padx=8, pady=(0, 8))

    def _path_name(self) -> str:
        return PATH_NAME.get(self.path_var.get(), self.path_var.get())

    def _log(self, text: str) -> None:
        self.log.insert("end", text.rstrip() + "\n")
        self.log.see("end")

    def _set_busy(self, busy: bool) -> None:
        self.busy = busy
        if busy:
            self.status_var.set("工作中…")
        elif self.connected:
            self.status_var.set(f"已连接 · {self._path_name()} 已选中")
        else:
            self.status_var.set("未连接")

    def _need_session(self) -> bool:
        if not self.session or not self.connected or not self.session.alive:
            messagebox.showwarning("未连接", "请先点「连接」。")
            return False
        if self.busy:
            return False
        return True

    def _run(self, title: str, cmd: str, timeout: float = 30.0, kind: str = "cmd",
             hist: list[tuple[str, str, str]] | None = None) -> None:
        if not self._need_session():
            return

        def work() -> None:
            err = None
            out = ""
            try:
                out = self.session.call(cmd, timeout=timeout)
            except Exception as exc:
                err = str(exc)
            self.after(0, lambda: self._done(title, cmd, out, err, kind, hist))

        self._set_busy(True)
        self._log(f"> {cmd}")
        threading.Thread(target=work, daemon=True).start()

    def _done(self, title: str, cmd: str, out: str, err: str | None, kind: str = "cmd",
              hist: list[tuple[str, str, str]] | None = None) -> None:
        self._set_busy(False)
        if err or (out and out.startswith("ERROR")):
            self.connected = bool(self.session and self.session.alive)
            msg = err or out
            self._log(msg)
            if not self.session or not self.session.alive:
                self.status_var.set("未连接")
            messagebox.showerror(title, msg)
            return
        if kind == "select":
            extra = ""
            if self.path_var.get() == "j2":
                extra = " 该 Master 请自行填写地址。"
            self._log(
                f"连接成功：{self._path_name()} 已选中（未读寄存器）。读/写请手动填写地址。{extra}"
            )
            if out:
                self._log(out)
            return
        if out:
            self._log(out)
            self._record_hist(out, hist)
        else:
            self._log("(无输出)")
            if hist:
                self._record_hist("", hist)

    def _fill_tree(self, out: str) -> None:
        self._record_hist(out, None)

    def _push_hist(self, op: str, addr: str, data: str) -> None:
        self.tree.insert("", 0, values=(op, addr, data))
        extra = len(self.tree.get_children()) - HISTORY_MAX
        if extra > 0:
            for item in self.tree.get_children()[-extra:]:
                self.tree.delete(item)

    def _record_hist(self, out: str, hist: list[tuple[str, str, str]] | None) -> None:
        reads: list[tuple[str, str]] = []
        for line in out.splitlines():
            m = MRD_RE.match(line.strip())
            if m:
                reads.append((m.group(1).upper(), m.group(2).upper()))
        if hist:
            for op, addr, data in hist:
                self._push_hist(op, addr, data)
        if reads:
            for addr, data in reversed(reads):
                self._push_hist("读", addr, data)

    def _from_tree(self, _evt=None) -> None:
        sel = self.tree.selection()
        if not sel:
            return
        vals = self.tree.item(sel[0], "values")
        if len(vals) >= 3:
            self.addr_var.set(vals[1])
            self.data_var.set(vals[2])
        elif len(vals) >= 2:
            self.addr_var.set(vals[0])
            self.data_var.set(vals[1])

    def _switch_cmd(self) -> str:
        p = self.path_var.get()
        if p == "j1":
            return "jtag 1"
        if p == "j2":
            return "jtag 2"
        return "mb"

    def _on_path(self) -> None:
        if self.connected:
            self._run("切换路径", self._switch_cmd(), kind="select")

    def _connect(self) -> None:
        if self.busy:
            return
        if not self.session or not self.xsdb_path:
            messagebox.showwarning("xsdb.bat 未就绪", "请先在导入页选择 xsdb.bat。")
            self._back_setup()
            return
        sess = self.session

        def work() -> None:
            err = None
            out = ""
            try:
                sess.start()
                out = sess.call("xconnect", timeout=40)
            except Exception as exc:
                err = str(exc)
                sess.close()
            self.after(0, lambda: self._connected(out, err))

        self._set_busy(True)
        self._log("启动 XSDB 并 connect …")
        threading.Thread(target=work, daemon=True).start()

    def _connected(self, out: str, err: str | None) -> None:
        self._set_busy(False)
        if err:
            self.connected = False
            self.status_var.set("未连接")
            self._log(err)
            messagebox.showerror("连接失败", err)
            return
        self.connected = True
        if out:
            self._log(out)
        self._run("切换路径", self._switch_cmd(), kind="select")

    def _disconnect(self) -> None:
        if self.session:
            self.session.close()
        self.connected = False
        self.status_var.set("未连接")
        self._log("已断开")

    def _clear(self) -> None:
        for item in self.tree.get_children():
            self.tree.delete(item)
        self.log.delete("1.0", "end")
        self._log("已清除日志和最近 100 次读写")

    def _targets(self) -> None:
        self._run("targets", "targets")

    def _verify(self) -> None:
        self._run("验证", "verify_all", timeout=40)

    def _rd(self) -> None:
        try:
            addr = norm_hex(self.addr_var.get(), "地址")
            n = int(self.len_var.get().strip() or "1")
        except Exception as exc:
            messagebox.showinfo("需要地址", "请先填写十六进制地址，再点读。")
            return
        if n < 1 or n > 256:
            messagebox.showerror("参数", "长度范围 1–256")
            return
        self._run("读", f"{self._switch_cmd()}; rd {addr} {n}")

    def _wr(self) -> None:
        try:
            addr = norm_hex(self.addr_var.get(), "地址")
            data = norm_hex(self.data_var.get(), "数据")
        except Exception as exc:
            messagebox.showinfo("需要地址", "写寄存器需要地址和数据，请手动填写。")
            return
        self._run("写", f"{self._switch_cmd()}; wr {addr} {data}",
                  hist=[("写", addr, data)])

    def _wrd(self) -> None:
        try:
            addr = norm_hex(self.addr_var.get(), "地址")
            data = norm_hex(self.data_var.get(), "数据")
        except Exception as exc:
            messagebox.showinfo("需要地址", "写+读回需要地址和数据，请手动填写。")
            return
        self._run("写+读回", f"{self._switch_cmd()}; wrd {addr} {data}",
                  hist=[("写", addr, data)])

    def _on_close(self) -> None:
        if self.session:
            self.session.close()
        self.destroy()


def main() -> None:
    try:
        from ctypes import windll
        windll.shcore.SetProcessDpiAwareness(1)
    except Exception:
        pass
    app = App()
    app.mainloop()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        messagebox.showerror("启动失败", str(exc))
        sys.exit(1)

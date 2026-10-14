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
# Windows file dialog label for This PC
THIS_PC = "::{20D04FE0-3AEA-1069-A2D8-08002B30309D}"

PATH_NAME = {
    "mb": "MicroBlaze",
    "j1": "JTAG2AXI #1 (Jtag Master)",
    "j2": "JTAG2AXI #2 (Jtag Master)",
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
        raise ValueError(f"{name} is not hex: {token}")
    if raw.lower().startswith("0x"):
        raw = raw[2:]
    if not raw:
        raise ValueError(f"{name} is empty")
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
                    raise RuntimeError("xsdb exited.\n" + "\n".join(lines + extra))
                continue
            if line.strip() == READY:
                return "\n".join(lines)
            lines.append(line.rstrip("\n"))
        raise TimeoutError("Timed out waiting for XSDB GUI_READY. Confirm xsdb is available.")

    def call(self, cmd: str, timeout: float = 30.0) -> str:
        if not self.alive or self.proc is None or self.proc.stdin is None:
            raise RuntimeError("XSDB session not started")
        self.proc.stdin.write(cmd.strip() + "\n")
        self.proc.stdin.flush()
        out: list[str] = []
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                line = self._q.get(timeout=0.2)
            except queue.Empty:
                if not self.alive:
                    raise RuntimeError("xsdb exited.\n" + "\n".join(out))
                continue
            if line.strip() == DONE:
                return "\n".join(out).strip()
            out.append(line.rstrip("\n"))
        raise TimeoutError(f"Command timed out: {cmd}")

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
        self.title("Vivado Lab Reg — Select xsdb.bat")
        self.geometry("720x360")
        self.minsize(640, 300)
        self.xsdb_path: Path | None = None
        self.session: XsdbSession | None = None
        self.connected = False
        self.busy = False
        self.path_var = tk.StringVar(value="mb")
        self.addr_var = tk.StringVar(value="")
        self.len_var = tk.StringVar(value="1")
        self.data_var = tk.StringVar(value="00000001")
        self.status_var = tk.StringVar(value="Disconnected")
        self.xsdb_var = tk.StringVar(value="")
        self.setup_path_var = tk.StringVar(value="")
        self.setup_msg_var = tk.StringVar(
            value="Choose xsdb.bat from Vivado Lab. Continue opens the main window."
        )
        saved = load_saved_xsdb()
        if saved:
            self.setup_path_var.set(saved)
            self.setup_msg_var.set("Loaded last saved path. Click Continue when ready.")
        self.setup_frame = ttk.Frame(self)
        self.main_frame = ttk.Frame(self)
        self._build_setup()
        self._build()
        self.setup_frame.pack(fill="both", expand=True)
        self.protocol("WM_DELETE_WINDOW", self._on_close)


    def _build_setup(self) -> None:
        outer = ttk.Frame(self.setup_frame, padding=24)
        outer.pack(fill="both", expand=True)

        ttk.Label(outer, text="Vivado Lab Reg", font=("Segoe UI", 16, "bold")).pack(anchor="w")
        ttk.Label(
            outer,
            text="Register peek/poke via Vivado Lab XSDB (MicroBlaze / JTAG-to-AXI)",
            foreground="#555555",
        ).pack(anchor="w", pady=(4, 16))

        box = ttk.LabelFrame(outer, text="XSDB", padding=12)
        box.pack(fill="x")
        ttk.Label(
            box,
            text="Select the xsdb.bat from your Vivado Lab install, for example:\n"
                 r"... \Vivado_Lab\<version>\bin\xsdb.bat",
            justify="left",
        ).pack(anchor="w", pady=(0, 8))

        row = ttk.Frame(box)
        row.pack(fill="x")
        ttk.Label(row, text="Path", width=8).pack(side="left")
        ttk.Entry(row, textvariable=self.setup_path_var).pack(
            side="left", fill="x", expand=True, padx=(0, 8)
        )
        ttk.Button(row, text="Browse…", command=self._browse_xsdb).pack(side="left")

        ttk.Label(box, textvariable=self.setup_msg_var, wraplength=640, foreground="#555555").pack(
            anchor="w", pady=(10, 0)
        )

        btns = ttk.Frame(outer)
        btns.pack(fill="x", pady=(20, 0))
        ttk.Button(btns, text="Exit", command=self._on_close).pack(side="right")
        ttk.Button(btns, text="Continue", command=self._enter_main).pack(side="right", padx=(0, 8))

    def _browse_xsdb(self) -> None:
        path = filedialog.askopenfilename(
            parent=self,
            title="Select Vivado Lab xsdb.bat",
            defaultextension=".bat",
            filetypes=[("Batch files (*.bat)", "*.bat"), ("All files", "*.*")],
            initialdir=THIS_PC,
            initialfile="xsdb.bat",
        )
        if path:
            self.setup_path_var.set(path)
            self.setup_msg_var.set("File selected. Click Continue to open the tool.")

    def _enter_main(self) -> None:
        picked = validate_xsdb(self.setup_path_var.get())
        if picked is None:
            self.setup_msg_var.set(
                "Path invalid. Choose an existing xsdb.bat on this PC."
            )
            messagebox.showwarning(
                "xsdb.bat required",
                "Select a valid xsdb.bat (name must be xsdb.bat, extension .bat).",
            )
            return
        self.xsdb_path = picked
        self.xsdb_var.set(str(picked))
        try:
            save_xsdb_path(picked)
        except OSError as exc:
            messagebox.showwarning(
                "Could not save path",
                f"xsdb is usable, but config was not written:\n{config_file()}\n{exc}",
            )
        if self.session:
            self.session.close()
        self.session = XsdbSession(picked, HERE / "gui.tcl")
        self.setup_frame.pack_forget()
        self.title("Vivado Lab Reg")
        self.geometry("1100x720")
        self.minsize(920, 600)
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
        self.title("Vivado Lab Reg — Select xsdb.bat")
        self.geometry("720x360")
        self.minsize(640, 300)
        self.setup_frame.pack(fill="both", expand=True)

    def _build(self) -> None:
        root = self.main_frame
        root.columnconfigure(0, weight=1)
        root.rowconfigure(2, weight=1)

        # menu
        menubar = tk.Menu(self)
        file_m = tk.Menu(menubar, tearoff=0)
        file_m.add_command(label="Change xsdb…", command=self._back_setup)
        file_m.add_separator()
        file_m.add_command(label="Exit", command=self._on_close)
        menubar.add_cascade(label="File", menu=file_m)
        help_m = tk.Menu(menubar, tearoff=0)
        help_m.add_command(
            label="About",
            command=lambda: messagebox.showinfo(
                "About",
                "Vivado Lab Reg\nXSDB register peek/poke\nMicroBlaze & JTAG-to-AXI\nMIT License",
            ),
        )
        menubar.add_cascade(label="Help", menu=help_m)
        self.config(menu=menubar)

        # toolbar
        bar = ttk.Frame(root, padding=(10, 8))
        bar.grid(row=0, column=0, sticky="ew")
        ttk.Label(bar, text="Status").pack(side="left")
        self.status_label = ttk.Label(bar, textvariable=self.status_var, width=28)
        self.status_label.pack(side="left", padx=(6, 16))
        ttk.Separator(bar, orient="vertical").pack(side="left", fill="y", padx=8)
        ttk.Button(bar, text="Connect", command=self._connect).pack(side="left", padx=2)
        ttk.Button(bar, text="Disconnect", command=self._disconnect).pack(side="left", padx=2)
        ttk.Button(bar, text="Refresh targets", command=self._targets).pack(side="left", padx=2)
        ttk.Button(bar, text="Verify paths", command=self._verify).pack(side="left", padx=2)
        ttk.Button(bar, text="Clear", command=self._clear).pack(side="left", padx=2)

        # connection strip
        conn = ttk.LabelFrame(root, text="Connection", padding=8)
        conn.grid(row=1, column=0, sticky="ew", padx=10, pady=(0, 6))
        ttk.Label(conn, text="xsdb").grid(row=0, column=0, sticky="w")
        ttk.Label(conn, textvariable=self.xsdb_var).grid(row=0, column=1, sticky="w", padx=8)

        # body
        body = ttk.Frame(root, padding=(10, 0, 10, 0))
        body.grid(row=2, column=0, sticky="nsew")
        body.columnconfigure(0, weight=1)
        body.columnconfigure(1, weight=2)
        body.rowconfigure(1, weight=1)

        pathf = ttk.LabelFrame(body, text="Access path", padding=8)
        pathf.grid(row=0, column=0, sticky="nsew", padx=(0, 6), pady=(0, 6))
        ttk.Label(
            pathf,
            text="Selecting a path only switches the XSDB target (no address required).",
            wraplength=360,
            foreground="#555555",
        ).pack(anchor="w", pady=(0, 6))
        ttk.Radiobutton(
            pathf,
            text="MicroBlaze — JTAG → XSDB → MDM → MB",
            value="mb",
            variable=self.path_var,
            command=self._on_path,
        ).pack(anchor="w", pady=2)
        ttk.Radiobutton(
            pathf,
            text="JTAG2AXI #1 — Jtag Master (hw_axi_1)",
            value="j1",
            variable=self.path_var,
            command=self._on_path,
        ).pack(anchor="w", pady=2)
        ttk.Radiobutton(
            pathf,
            text="JTAG2AXI #2 — Jtag Master (hw_axi_2)",
            value="j2",
            variable=self.path_var,
            command=self._on_path,
        ).pack(anchor="w", pady=2)
        ttk.Label(
            pathf,
            text="Listed paths match this lab bitstream. Other boards may differ — use Refresh targets.",
            wraplength=360,
            foreground="#555555",
        ).pack(anchor="w", pady=(8, 0))

        ops = ttk.LabelFrame(body, text="Register access", padding=8)
        ops.grid(row=0, column=1, sticky="nsew", pady=(0, 6))
        form = ttk.Frame(ops)
        form.pack(fill="x")
        ttk.Label(form, text="Address").grid(row=0, column=0, sticky="w", pady=2)
        ttk.Entry(form, textvariable=self.addr_var, width=18).grid(row=0, column=1, sticky="w", padx=6, pady=2)
        ttk.Label(form, text="Length (1–256)").grid(row=0, column=2, sticky="w", padx=(12, 0), pady=2)
        ttk.Entry(form, textvariable=self.len_var, width=6).grid(row=0, column=3, sticky="w", padx=6, pady=2)
        ttk.Label(form, text="Data").grid(row=1, column=0, sticky="w", pady=2)
        ttk.Entry(form, textvariable=self.data_var, width=18).grid(row=1, column=1, sticky="w", padx=6, pady=2)
        bt = ttk.Frame(ops)
        bt.pack(fill="x", pady=(10, 0))
        ttk.Button(bt, text="Read", command=self._rd).pack(side="left", padx=(0, 6))
        ttk.Button(bt, text="Write", command=self._wr).pack(side="left", padx=(0, 6))
        ttk.Button(bt, text="Write + Readback", command=self._wrd).pack(side="left")

        last = ttk.LabelFrame(body, text="History (last 100)", padding=4)
        last.grid(row=1, column=0, sticky="nsew", padx=(0, 6))
        rcols = ("op", "addr", "data")
        self.tree = ttk.Treeview(last, columns=rcols, show="headings", height=16)
        self.tree.heading("op", text="Op")
        self.tree.heading("addr", text="Address")
        self.tree.heading("data", text="Data")
        self.tree.column("op", width=48, anchor="w")
        self.tree.column("addr", width=120, anchor="w")
        self.tree.column("data", width=120, anchor="w")
        syh = ttk.Scrollbar(last, orient="vertical", command=self.tree.yview)
        self.tree.configure(yscrollcommand=syh.set)
        self.tree.pack(side="left", fill="both", expand=True)
        syh.pack(side="right", fill="y")
        self.tree.bind("<<TreeviewSelect>>", self._from_tree)

        right = ttk.LabelFrame(body, text="Log", padding=4)
        right.grid(row=1, column=1, sticky="nsew")
        self.log = tk.Text(right, wrap="word", height=12, font=("Consolas", 10), relief="flat")
        sy = ttk.Scrollbar(right, orient="vertical", command=self.log.yview)
        self.log.configure(yscrollcommand=sy.set)
        self.log.pack(side="left", fill="both", expand=True)
        sy.pack(side="right", fill="y")

        # status bar
        foot = ttk.Frame(root, padding=(10, 6))
        foot.grid(row=3, column=0, sticky="ew")
        ttk.Label(
            foot,
            text="Power the board and load the bitstream first. Do not leave Hardware Manager holding JTAG.",
            foreground="#555555",
        ).pack(side="left")

    def _path_name(self) -> str:
        return PATH_NAME.get(self.path_var.get(), self.path_var.get())

    def _log(self, text: str) -> None:
        self.log.insert("end", text.rstrip() + "\n")
        self.log.see("end")

    def _set_busy(self, busy: bool) -> None:
        self.busy = busy
        if busy:
            self.status_var.set("Busy…")
        elif self.connected:
            self.status_var.set(f"Connected · {self._path_name()} selected")
        else:
            self.status_var.set("Disconnected")

    def _need_session(self) -> bool:
        if not self.session or not self.connected or not self.session.alive:
            messagebox.showwarning("Not connected", "Click Connect first.")
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
                self.status_var.set("Disconnected")
            messagebox.showerror(title, msg)
            return
        if kind == "select":
            extra = ""
            if self.path_var.get() == "j2":
                extra = " For Master, enter the address yourself."
            self._log(
                f"Connected: {self._path_name()} selected (registers not read). For R/W, enter the address manually.{extra}"
            )
            if out:
                self._log(out)
            return
        if out:
            self._log(out)
            self._record_hist(out, hist)
        else:
            self._log("(no output)")
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
                self._push_hist("Read", addr, data)

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
            self._run("Switch path", self._switch_cmd(), kind="select")

    def _connect(self) -> None:
        if self.busy:
            return
        if not self.session or not self.xsdb_path:
            messagebox.showwarning("xsdb.bat not ready", "Select xsdb.bat on the setup page first.")
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
        self._log("Starting XSDB and connect …")
        threading.Thread(target=work, daemon=True).start()

    def _connected(self, out: str, err: str | None) -> None:
        self._set_busy(False)
        if err:
            self.connected = False
            self.status_var.set("Disconnected")
            self._log(err)
            messagebox.showerror("Connect failed", err)
            return
        self.connected = True
        if out:
            self._log(out)
        self._run("Switch path", self._switch_cmd(), kind="select")

    def _disconnect(self) -> None:
        if self.session:
            self.session.close()
        self.connected = False
        self.status_var.set("Disconnected")
        self._log("Disconnected")

    def _clear(self) -> None:
        for item in self.tree.get_children():
            self.tree.delete(item)
        self.log.delete("1.0", "end")
        self._log("Cleared log and last 100 R/W entries")

    def _targets(self) -> None:
        self._run("targets", "targets")

    def _verify(self) -> None:
        self._run("Verify", "verify_all", timeout=40)

    def _rd(self) -> None:
        try:
            addr = norm_hex(self.addr_var.get(), "Address")
            n = int(self.len_var.get().strip() or "1")
        except Exception as exc:
            messagebox.showinfo("Address required", "Enter a hex address before Read.")
            return
        if n < 1 or n > 256:
            messagebox.showerror("Input", "Length must be 1–256")
            return
        self._run("Read", f"{self._switch_cmd()}; rd {addr} {n}")

    def _wr(self) -> None:
        try:
            addr = norm_hex(self.addr_var.get(), "Address")
            data = norm_hex(self.data_var.get(), "Data")
        except Exception as exc:
            messagebox.showinfo("Address required", "Write needs address and data; fill them in manually.")
            return
        self._run("Write", f"{self._switch_cmd()}; wr {addr} {data}",
                  hist=[("Write", addr, data)])

    def _wrd(self) -> None:
        try:
            addr = norm_hex(self.addr_var.get(), "Address")
            data = norm_hex(self.data_var.get(), "Data")
        except Exception as exc:
            messagebox.showinfo("Address required", "Write+Readback needs address and data; fill them in manually.")
            return
        self._run("Write+Readback", f"{self._switch_cmd()}; wrd {addr} {data}",
                  hist=[("Write", addr, data)])

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
        messagebox.showerror("Start failed", str(exc))
        sys.exit(1)

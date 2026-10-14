# -*- coding: utf-8 -*-
"""Vivado Lab XSDB register GUI: scan targets, then peek/poke the one you select."""

from __future__ import annotations

import json
import os
import queue
import re
import subprocess
import sys
import threading
import time
import tkinter as tk
from pathlib import Path
from subprocess import PIPE, STDOUT, Popen
from tkinter import filedialog, messagebox, ttk

import addr_map

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
TGT_RE = re.compile(r"^TGT\s+(\d+)\s+(.+)$")
HISTORY_MAX = 100
# History Address/Data columns: 32-bit hex, same width as 110B0000.
HIST_HEX_WIDTH = 8
APP_NAME = "VivadoLabReg"
# Windows file dialog label for This PC
THIS_PC = "::{20D04FE0-3AEA-1069-A2D8-08002B30309D}"
_LOG_SKIP = {"CONNECT_OK", "TGT_NONE"}


def parse_target_lines(text: str) -> list[tuple[str, str]]:
    """Pull `TGT <id> <name>` rows out of an XSDB scan. Other lines are ignored."""
    rows: list[tuple[str, str]] = []
    for line in (text or "").splitlines():
        match = TGT_RE.match(line.strip())
        if not match:
            continue
        rows.append((match.group(1), match.group(2).strip()))
    return rows


def normalize_targets(rows: list[tuple[str, str]]) -> list[tuple[str, str]]:
    cleaned: list[tuple[str, str]] = []
    seen: set[str] = set()
    for tid, name in rows:
        tid_s = str(tid).strip()
        name_s = str(name).strip()
        if not tid_s.isdigit() or not name_s or tid_s in seen:
            continue
        seen.add(tid_s)
        cleaned.append((tid_s, name_s))
    return cleaned


def connect_ok(text: str) -> bool:
    return any(line.strip() == "CONNECT_OK" for line in (text or "").splitlines())


def target_iid(tid: str) -> str:
    return f"t{tid}"


def log_body(text: str) -> str:
    lines = [line for line in (text or "").splitlines() if line.strip() not in _LOG_SKIP]
    return "\n".join(lines).strip()


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


def load_config() -> dict:
    cfg = config_file()
    if not cfg.is_file():
        return {}
    try:
        data = json.loads(cfg.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    if not isinstance(data, dict):
        return {}
    return data


def save_config(updates: dict) -> None:
    cfg = config_file()
    cfg.parent.mkdir(parents=True, exist_ok=True)
    data = load_config()
    data.update(updates)
    cfg.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def load_saved_xsdb() -> str:
    return str(load_config().get("xsdb_bat") or "").strip()


def initial_profile_text() -> str:
    """Profile path for the setup field.

    A saved ``profile`` key, including an empty string, wins. The environment
    is only a hint the first time the key is absent.
    """
    data = load_config()
    if "profile" in data:
        return str(data.get("profile") or "").strip()
    return (
        os.environ.get("VIVADO_LAB_REG_PROFILE")
        or os.environ.get("XSDB_PROFILE")
        or ""
    ).strip()


def save_xsdb_path(xsdb: Path) -> None:
    save_config({"xsdb_bat": str(xsdb)})


def validate_profile(raw: str) -> tuple[Path | None, str | None]:
    """Return ``(path, error)``. Empty input is ``(None, None)`` so smoke stays 0x0."""
    text = (raw or "").strip().strip('"')
    if not text:
        return None, None
    path = Path(text)
    if not path.is_file():
        return None, f"Board profile not found:\n{text}"
    if path.suffix.lower() != ".tcl":
        return None, "Board profile must be a .tcl file."
    return path.resolve(), None


def session_environ(profile: Path | None) -> dict[str, str]:
    """Environment for an XSDB child. The chosen profile replaces inherited vars."""
    env = os.environ.copy()
    if profile is not None:
        env["VIVADO_LAB_REG_PROFILE"] = str(profile)
    else:
        env.pop("VIVADO_LAB_REG_PROFILE", None)
        env.pop("XSDB_PROFILE", None)
    return env


def profile_browse_dir() -> str:
    private = HERE / "profiles" / "private"
    if private.is_dir():
        return str(private)
    profiles = HERE / "profiles"
    if profiles.is_dir():
        return str(profiles)
    return str(HERE)


# Address-map filter labels. Keys match addr_map.for_path ("mb" / "jtag").
MAP_FILTERS = (
    ("all", "All"),
    ("mb", "MicroBlaze path"),
    ("jtag", "JTAG-Lite path"),
)
MAP_FILTER_BY_LABEL = {label: key for key, label in MAP_FILTERS}
ADDRESS_MAP_SUFFIXES = {".xlsx", ".csv"}


def initial_address_map_text() -> str:
    """Saved workbook path. Absent key and empty string both mean none."""
    data = load_config()
    if "address_map" in data:
        return str(data.get("address_map") or "").strip()
    return ""


def address_map_browse_dir(current: str = "") -> str:
    text = (current or "").strip().strip('"')
    if text:
        parent = Path(text).expanduser().parent
        if parent.is_dir():
            return str(parent)
    examples = HERE / "examples"
    if examples.is_dir():
        return str(examples)
    return str(HERE)


def private_profile_save_dir() -> str:
    """Save-as starts in profiles/private when that folder exists."""
    return profile_browse_dir()


def validate_address_map(raw: str) -> tuple[Path | None, str | None]:
    """Return ``(path, error)``. Empty input is ``(None, None)``."""
    text = (raw or "").strip().strip('"')
    if not text:
        return None, None
    path = Path(text)
    if not path.is_file():
        return None, f"Address map not found:\n{text}"
    if path.suffix.lower() not in ADDRESS_MAP_SUFFIXES:
        return None, "Address map must be a .xlsx or .csv file."
    return path.resolve(), None


def filter_imported_slaves(
    slaves: list[addr_map.Slave], key: str
) -> tuple[list[addr_map.Slave], list[str]]:
    """All rows, or the MicroBlaze / JTAG-Lite subset from ``for_path``."""
    if key == "mb":
        rows = addr_map.for_path(slaves, "mb")
        _matched, notes = addr_map.select_mb(slaves)
        return rows, notes
    if key in {"jtag", "j1", "j2"}:
        rows = addr_map.for_path(slaves, "jtag")
        _matched, notes = addr_map.select_jtag(slaves)
        return rows, notes
    return list(slaves), []


def profile_name_filters(
    selected: list[addr_map.Slave],
) -> tuple[str | None, str | None]:
    """``--mb-name`` / ``--jtag-name`` from rows the user picked.

    The first MicroBlaze data slave and the first Lite slave win. An empty
    selection leaves both ``None`` so suggest-profile uses the CLI first match.
    """
    mb_name = None
    jtag_name = None
    for slave in selected:
        iface = slave.iface.upper()
        if mb_name is None and iface in {"M_AXI_DP", "DATA"}:
            mb_name = slave.name
        elif jtag_name is None and "LITE" in iface:
            jtag_name = slave.name
    return mb_name, jtag_name


def build_profile_suggestion(
    slaves: list[addr_map.Slave],
    selected: list[addr_map.Slave],
    source: str,
) -> tuple[str, list[str]]:
    """Same Tcl snippet as ``addr_map --suggest-profile``."""
    mb_name, jtag_name = profile_name_filters(selected)
    return addr_map.suggest_profile(
        slaves,
        source=source,
        mb_name=mb_name,
        jtag_name=jtag_name,
    )


def openpyxl_message(exc: BaseException) -> str:
    text = str(exc).strip() or "Could not read the address map."
    if "openpyxl" in text.lower():
        return (
            "reading .xlsx needs openpyxl.\n"
            "Install it with: pip install openpyxl\n"
            "A CSV with the same reference columns is also accepted."
        )
    return text


def _hidden_startupinfo():
    if os.name != "nt":
        return None
    si = subprocess.STARTUPINFO()
    si.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    si.wShowWindow = subprocess.SW_HIDE
    return si


def norm_hex(token: str, name: str) -> str:
    raw = token.strip().replace("_", "")
    if not HEX_RE.match(raw):
        raise ValueError(f"{name} is not hex: {token}")
    if raw.lower().startswith("0x"):
        raw = raw[2:]
    if not raw:
        raise ValueError(f"{name} is empty")
    return raw


def fmt_hist_hex(token: str) -> str:
    """Uppercase hex for History (and fields filled from a row), zero-padded to 8 digits.

    Display only. rd/wr/wrd still send the norm_hex() token, so a short address
    such as 1000 stays 1000 on the wire and shows as 00001000 in the table.
    Values longer than 8 digits are kept.
    """
    raw = (token or "").strip().replace("_", "")
    if raw.lower().startswith("0x"):
        raw = raw[2:]
    if not raw:
        return ""
    return raw.upper().zfill(HIST_HEX_WIDTH)


class XsdbSession:
    def __init__(self, xsdb: Path, script: Path, profile: Path | None = None) -> None:
        self.xsdb = xsdb
        self.script = script
        self.profile = profile
        self.proc: Popen[str] | None = None
        self._q: queue.Queue[str] = queue.Queue()
        self._reader: threading.Thread | None = None

    @property
    def alive(self) -> bool:
        return self.proc is not None and self.proc.poll() is None

    def start(self, timeout: float = 20.0) -> str:
        self.close()
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
            env=session_environ(self.profile),
            startupinfo=_hidden_startupinfo(),
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
        self.title("Vivado Lab Reg — Setup")
        self.geometry("780x760")
        self.minsize(680, 640)
        self.xsdb_path: Path | None = None
        self.profile_path: Path | None = None
        self.session: XsdbSession | None = None
        self.connected = False
        self.busy = False
        self.targets: list[tuple[str, str]] = []
        self.selected_id: str | None = None
        self.selected_name: str | None = None
        self._pending_id: str | None = None
        self._pending_name: str | None = None
        self._filling_targets = False
        self.addr_var = tk.StringVar(value="")
        self.len_var = tk.StringVar(value="1")
        self.data_var = tk.StringVar(value="00000001")
        self.status_var = tk.StringVar(value="Disconnected")
        self.xsdb_var = tk.StringVar(value="")
        self.profile_var = tk.StringVar(value="(none)")
        self.setup_path_var = tk.StringVar(value="")
        self.setup_profile_var = tk.StringVar(value="")
        self.setup_address_map_var = tk.StringVar(value="")
        self.setup_msg_var = tk.StringVar(
            value="Choose xsdb.bat from Vivado Lab. A board profile is optional. Continue opens the main window."
        )
        self.target_msg = tk.StringVar(value="Connect to scan targets on the JTAG chain.")
        self.map_filter_var = tk.StringVar(value=MAP_FILTERS[0][1])
        self.map_msg = tk.StringVar(
            value="Optional. Load a reference Address Map (.xlsx) to browse Master Base addresses."
        )
        self.map_slaves: list[addr_map.Slave] = []
        self._map_by_iid: dict[str, addr_map.Slave] = {}
        self._filling_map = False
        saved = load_saved_xsdb()
        saved_profile = initial_profile_text()
        saved_map = initial_address_map_text()
        if saved:
            self.setup_path_var.set(saved)
            self.setup_msg_var.set("Loaded last saved path. Click Continue when ready.")
        if saved_profile:
            self.setup_profile_var.set(saved_profile)
        if saved_map:
            self.setup_address_map_var.set(saved_map)
        self.setup_frame = ttk.Frame(self)
        self.main_frame = ttk.Frame(self)
        self._build_setup()
        self._build()
        self.setup_frame.pack(fill="both", expand=True)
        self._fit_setup_window()
        self.protocol("WM_DELETE_WINDOW", self._on_close)

    def _fit_setup_window(self) -> None:
        """Keep Continue on screen after the optional address-map row."""
        self.update_idletasks()
        req_w = max(780, self.setup_frame.winfo_reqwidth() + 16)
        req_h = self.setup_frame.winfo_reqheight() + 28
        req_h = max(req_h, 640)
        self.minsize(680, req_h)
        self.geometry(f"{req_w}x{req_h}")

    def _fit_main_window(self) -> None:
        """Size the main window so the address-map list stays clickable."""
        self.update_idletasks()
        screen_h = max(self.winfo_screenheight(), 800)
        screen_w = max(self.winfo_screenwidth(), 1100)
        req_w = max(1100, self.main_frame.winfo_reqwidth() + 8)
        req_h = max(900, self.main_frame.winfo_reqheight() + 8)
        width = min(req_w, screen_w - 40)
        height = min(req_h, screen_h - 80)
        self.minsize(min(920, width), min(760, height))
        self.geometry(f"{width}x{height}")


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

        prof = ttk.LabelFrame(outer, text="Board profile (optional)", padding=12)
        prof.pack(fill="x", pady=(16, 0))
        ttk.Label(
            prof,
            text="Tcl file of Master Base Addresses for smoke / verify "
                 "(Vivado Address Editor, not Slave Base 0x0).\n"
                 "Leave empty to keep those addresses at 0x0 so those reads are skipped.\n"
                 r"Copy profiles\example.tcl to profiles\private\ and edit it.",
            justify="left",
        ).pack(anchor="w", pady=(0, 8))
        prow = ttk.Frame(prof)
        prow.pack(fill="x")
        ttk.Label(prow, text="Profile", width=8).pack(side="left")
        ttk.Entry(prow, textvariable=self.setup_profile_var).pack(
            side="left", fill="x", expand=True, padx=(0, 8)
        )
        ttk.Button(prow, text="Browse…", command=self._browse_profile).pack(side="left")
        ttk.Button(prow, text="Clear", command=self._clear_profile).pack(side="left", padx=(8, 0))

        amap = ttk.LabelFrame(outer, text="Address map (optional)", padding=12)
        amap.pack(fill="x", pady=(16, 0))
        ttk.Label(
            amap,
            text="Workbook of Master Base Addresses (prefer address.xlsx). "
                 "This GUI reads the reference Vivado layout and ignores Slave Base 0x0.\n"
                 "Other formats: use AI to adapt. See docs/address-map-import.md.",
            justify="left",
            wraplength=680,
        ).pack(anchor="w", pady=(0, 8))
        arow = ttk.Frame(amap)
        arow.pack(fill="x")
        ttk.Label(arow, text="Map", width=8).pack(side="left")
        ttk.Entry(arow, textvariable=self.setup_address_map_var).pack(
            side="left", fill="x", expand=True, padx=(0, 8)
        )
        ttk.Button(arow, text="Browse…", command=self._browse_address_map).pack(side="left")
        ttk.Button(arow, text="Clear", command=self._clear_address_map).pack(side="left", padx=(8, 0))

        ttk.Label(outer, textvariable=self.setup_msg_var, wraplength=680, foreground="#555555").pack(
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

    def _browse_profile(self) -> None:
        path = filedialog.askopenfilename(
            parent=self,
            title="Select board profile",
            defaultextension=".tcl",
            filetypes=[("Tcl profile (*.tcl)", "*.tcl"), ("All files", "*.*")],
            initialdir=profile_browse_dir(),
        )
        if path:
            self.setup_profile_var.set(path)
            self.setup_msg_var.set("Profile selected. Click Continue to open the tool.")

    def _clear_profile(self) -> None:
        self.setup_profile_var.set("")
        self.setup_msg_var.set(
            "Profile cleared. Smoke addresses stay 0x0 until you pick a file."
        )

    def _browse_address_map(self) -> None:
        path = filedialog.askopenfilename(
            parent=self,
            title="Select address map",
            defaultextension=".xlsx",
            filetypes=[
                ("Excel workbook (*.xlsx)", "*.xlsx"),
                ("CSV (*.csv)", "*.csv"),
                ("All files", "*.*"),
            ],
            initialdir=address_map_browse_dir(self.setup_address_map_var.get()),
            initialfile="address.xlsx",
        )
        if path:
            self.setup_address_map_var.set(path)
            self.setup_msg_var.set(
                "Address map selected. Load / Import map lists Master Base rows."
            )
            self.map_msg.set("Address map selected. Click Load / Import map.")
            self._persist_address_map(Path(path))

    def _clear_address_map(self) -> None:
        self.setup_address_map_var.set("")
        self.map_slaves = []
        if getattr(self, "map_tree", None) is not None:
            self._fill_map_tree()
        self.map_msg.set("Address map cleared.")
        self.setup_msg_var.set("Address map cleared.")
        self._persist_address_map(None)

    def _persist_address_map(self, path: Path | None) -> None:
        try:
            save_config({"address_map": str(path) if path else ""})
        except OSError as exc:
            messagebox.showwarning(
                "Could not save path",
                f"The map path was not written:\n{config_file()}\n{exc}",
            )

    def _on_map_filter(self, _evt=None) -> None:
        notes = self._fill_map_tree()
        if notes:
            self.map_msg.set(" ".join(notes))

    def _fill_map_tree(self) -> list[str]:
        label = self.map_filter_var.get()
        key = MAP_FILTER_BY_LABEL.get(label, "all")
        rows, notes = filter_imported_slaves(self.map_slaves, key)
        self._filling_map = True
        try:
            children = self.map_tree.get_children()
            if children:
                self.map_tree.delete(*children)
            self._map_by_iid = {}
            for index, slave in enumerate(rows):
                iid = f"m{index}"
                self._map_by_iid[iid] = slave
                self.map_tree.insert(
                    "",
                    "end",
                    iid=iid,
                    values=(slave.master, slave.iface, slave.name, slave.base, slave.rng),
                )
        finally:
            self._filling_map = False
        if self.map_slaves and not notes:
            self.map_msg.set(
                f"Showing {len(rows)} of {len(self.map_slaves)} imported slave(s). "
                "Select a row to copy its Master Base Address."
            )
        return notes

    def _selected_map_slaves(self) -> list[addr_map.Slave]:
        picked: list[addr_map.Slave] = []
        for iid in self.map_tree.selection():
            slave = self._map_by_iid.get(str(iid))
            if slave is not None:
                picked.append(slave)
        return picked

    def _on_map_pick(self, _evt=None) -> None:
        if self._filling_map:
            return
        slave = self._map_by_iid.get(str(self.map_tree.focus() or ""))
        if slave is None:
            return
        self.addr_var.set(fmt_hist_hex(slave.addr))

    def _load_address_map(self) -> None:
        path, err = validate_address_map(self.setup_address_map_var.get())
        if err:
            self.map_msg.set(err.replace("\n", " "))
            messagebox.showwarning("Address map", err)
            return
        if path is None:
            self.map_msg.set("Choose an address map (.xlsx). A typical name is address.xlsx.")
            messagebox.showinfo(
                "Address map",
                "Choose an address map file first. A typical name is address.xlsx.",
            )
            return
        try:
            slaves = addr_map.load_slaves(path)
        except addr_map.AddressMapError as exc:
            msg = openpyxl_message(exc)
            self.map_msg.set(" ".join(msg.splitlines()))
            title = "openpyxl required" if "openpyxl" in msg.lower() else "Address map"
            messagebox.showerror(title, msg)
            return
        except Exception as exc:
            msg = openpyxl_message(exc)
            self.map_msg.set(" ".join(msg.splitlines()))
            messagebox.showerror("Address map", msg)
            return
        self.map_slaves = slaves
        self.setup_address_map_var.set(str(path))
        self._persist_address_map(path)
        notes = self._fill_map_tree()
        if not slaves:
            empty = (
                "No slaves imported. This GUI uses the reference Vivado layout "
                "(Name, Interface, Slave Segment, Master Base Address, Range). "
                "Other formats: use AI to adapt. See docs/address-map-import.md."
            )
            self.map_msg.set(empty)
            messagebox.showwarning("Address map", empty)
            self._log(f"address map = {path} (0 slaves)")
            return
        if notes:
            self.map_msg.set(" ".join(notes))
            for note in notes:
                self._log(note)
        self._log(f"address map = {path} ({len(slaves)} slaves)")

    def _current_suggestion(self) -> tuple[str, list[str]] | None:
        if not self.map_slaves:
            messagebox.showinfo("Address map", "Click Load / Import map first.")
            return None
        source = self.setup_address_map_var.get().strip() or "(address map)"
        return build_profile_suggestion(
            self.map_slaves, self._selected_map_slaves(), source
        )

    def _suggest_profile(self) -> None:
        built = self._current_suggestion()
        if built is None:
            return
        snippet, warnings = built
        self._show_suggestion(snippet, warnings)

    def _show_suggestion(self, snippet: str, warnings: list[str]) -> None:
        win = tk.Toplevel(self)
        win.title("Suggest profile")
        win.transient(self)
        win.geometry("760x480")
        win.minsize(640, 360)
        outer = ttk.Frame(win, padding=12)
        outer.pack(fill="both", expand=True)
        ttk.Label(
            outer,
            text="Reference Vivado layout. Nothing is written until you choose Save as…. "
                 "Other formats: use AI to adapt (docs/address-map-import.md).",
            wraplength=720,
        ).pack(anchor="w")
        if warnings:
            ttk.Label(
                outer,
                text="\n".join(warnings),
                wraplength=720,
                foreground="#8a4b08",
            ).pack(anchor="w", pady=(8, 0))
        box = tk.Text(outer, wrap="word", height=16, font=("Consolas", 10))
        box.pack(fill="both", expand=True, pady=(8, 8))
        box.insert("1.0", snippet)
        box.configure(state="disabled")
        buttons = ttk.Frame(outer)
        buttons.pack(fill="x")
        ttk.Button(buttons, text="Close", command=win.destroy).pack(side="right")
        ttk.Button(
            buttons,
            text="Save as…",
            command=lambda: self._save_profile_as(snippet, warnings),
        ).pack(side="right", padx=(0, 8))
        self._suggestion_win = win

    def _write_private_profile(self) -> None:
        built = self._current_suggestion()
        if built is None:
            return
        self._save_profile_as(*built)

    def _save_profile_as(self, snippet: str, warnings: list[str] | None = None) -> None:
        chosen = filedialog.asksaveasfilename(
            parent=self,
            title="Save private profile",
            defaultextension=".tcl",
            filetypes=[("Tcl profile (*.tcl)", "*.tcl"), ("All files", "*.*")],
            initialdir=private_profile_save_dir(),
            initialfile="lab.tcl",
        )
        if not chosen:
            return
        dest = Path(chosen)
        if dest.suffix.lower() != ".tcl":
            messagebox.showwarning("Board profile", "Board profile must be a .tcl file.")
            return
        if dest.exists():
            replace = messagebox.askyesno(
                "Overwrite profile",
                f"Replace the existing file?\n{dest}",
                default=messagebox.NO,
            )
            if not replace:
                self._log(f"Did not overwrite {dest}")
                return
        try:
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_text(snippet, encoding="utf-8")
        except OSError as exc:
            messagebox.showerror(
                "Write private profile",
                f"Could not write:\n{dest}\n{exc}",
            )
            return
        notes = list(warnings or [])
        for note in notes:
            self._log(note)
        self._log(f"Wrote private profile {dest}")
        detail = f"Saved:\n{dest}"
        if notes:
            detail += "\n\n" + "\n".join(notes)
        detail += "\n\nUse this file as the board profile on the next Connect?"
        if messagebox.askyesno("Write private profile", detail):
            self._adopt_profile(dest)

    def _adopt_profile(self, path: Path) -> None:
        self.profile_path = path
        self.profile_var.set(str(path))
        self.setup_profile_var.set(str(path))
        if self.session is not None:
            self.session.profile = path
        try:
            save_config({"profile": str(path)})
        except OSError as exc:
            messagebox.showwarning(
                "Could not save path",
                f"The profile file was written, but config was not:\n{config_file()}\n{exc}",
            )
            return
        if self.connected:
            self._log("Profile path saved. Disconnect and Connect to load it.")
        else:
            self._log(f"profile = {path}")

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
        profile, profile_err = validate_profile(self.setup_profile_var.get())
        if profile_err:
            self.setup_msg_var.set(profile_err.replace("\n", " "))
            messagebox.showwarning("Board profile", profile_err)
            return
        amap, amap_err = validate_address_map(self.setup_address_map_var.get())
        if amap_err:
            self.setup_msg_var.set(amap_err.replace("\n", " "))
            messagebox.showwarning("Address map", amap_err)
            return
        self.xsdb_path = picked
        self.xsdb_var.set(str(picked))
        self.profile_path = profile
        self.profile_var.set(str(profile) if profile else "(none)")
        if amap is not None:
            self.setup_address_map_var.set(str(amap))
        try:
            save_config({
                "xsdb_bat": str(picked),
                "profile": str(profile) if profile else "",
                "address_map": str(amap) if amap else "",
            })
        except OSError as exc:
            messagebox.showwarning(
                "Could not save path",
                f"xsdb is usable, but config was not written:\n{config_file()}\n{exc}",
            )
        if self.session:
            self.session.close()
        self.session = XsdbSession(picked, HERE / "gui.tcl", profile=profile)
        self.setup_frame.pack_forget()
        self.title("Vivado Lab Reg")
        self.main_frame.pack(fill="both", expand=True)
        self._fit_main_window()
        self._log(f"xsdb = {picked}")
        if profile:
            self._log(f"profile = {profile}")
        else:
            self._log("profile = (none) — smoke addresses stay 0x0 until a profile is set")
        if amap:
            self._log(f"address map = {amap}")
        else:
            self._log("address map = (none)")

    def _back_setup(self) -> None:
        if self.busy:
            return
        if self.session:
            self._disconnect()
            self.session.close()
            self.session = None
        self.main_frame.pack_forget()
        self.title("Vivado Lab Reg — Setup")
        self.setup_frame.pack(fill="both", expand=True)
        self._fit_setup_window()

    def _build(self) -> None:
        root = self.main_frame
        root.columnconfigure(0, weight=1)
        root.rowconfigure(2, weight=1)

        # menu
        menubar = tk.Menu(self)
        file_m = tk.Menu(menubar, tearoff=0)
        file_m.add_command(label="Setup…", command=self._back_setup)
        file_m.add_separator()
        file_m.add_command(label="Exit", command=self._on_close)
        menubar.add_cascade(label="File", menu=file_m)
        help_m = tk.Menu(menubar, tearoff=0)
        help_m.add_command(
            label="About",
            command=lambda: messagebox.showinfo(
                "About",
                "Vivado Lab Reg\nXSDB register peek/poke\nScanned MicroBlaze and JTAG-to-AXI targets\nSmoke addresses come from a board profile\nMIT License",
            ),
        )
        menubar.add_cascade(label="Help", menu=help_m)
        self.config(menu=menubar)

        # toolbar
        bar = ttk.Frame(root, padding=(10, 8))
        bar.grid(row=0, column=0, sticky="ew")
        ttk.Label(bar, text="Status").pack(side="left")
        self.status_label = ttk.Label(bar, textvariable=self.status_var)
        self.status_label.pack(side="left", padx=(6, 16))
        ttk.Separator(bar, orient="vertical").pack(side="left", fill="y", padx=8)
        ttk.Button(bar, text="Connect", command=self._connect).pack(side="left", padx=2)
        ttk.Button(bar, text="Disconnect", command=self._disconnect).pack(side="left", padx=2)
        ttk.Button(bar, text="Refresh targets", command=self._refresh_targets).pack(side="left", padx=2)
        ttk.Button(bar, text="Verify paths", command=self._verify).pack(side="left", padx=2)
        ttk.Button(bar, text="Clear", command=self._clear).pack(side="left", padx=2)

        # connection strip
        conn = ttk.LabelFrame(root, text="Connection", padding=8)
        conn.grid(row=1, column=0, sticky="ew", padx=10, pady=(0, 6))
        ttk.Label(conn, text="xsdb").grid(row=0, column=0, sticky="w")
        ttk.Label(conn, textvariable=self.xsdb_var).grid(row=0, column=1, sticky="w", padx=8)
        ttk.Label(conn, text="profile").grid(row=1, column=0, sticky="nw", pady=(4, 0))
        ttk.Label(conn, textvariable=self.profile_var, wraplength=900).grid(
            row=1, column=1, sticky="w", padx=8, pady=(4, 0)
        )

        # body
        body = ttk.Frame(root, padding=(10, 0, 10, 0))
        body.grid(row=2, column=0, sticky="nsew")
        body.columnconfigure(0, weight=1)
        body.columnconfigure(1, weight=2)
        # The map list must keep a clickable height; history can take the rest.
        body.rowconfigure(1, weight=2, minsize=250)
        body.rowconfigure(2, weight=1, minsize=120)

        pathf = ttk.LabelFrame(body, text="Targets", padding=8)
        pathf.grid(row=0, column=0, sticky="nsew", padx=(0, 6), pady=(0, 6))
        ttk.Label(
            pathf,
            text="Selecting a target only switches the XSDB target (no address required).",
            wraplength=360,
            foreground="#555555",
        ).pack(anchor="w", pady=(0, 6))
        list_wrap = ttk.Frame(pathf)
        list_wrap.pack(fill="both", expand=True)
        self.target_tree = ttk.Treeview(
            list_wrap,
            columns=("id", "name"),
            show="headings",
            height=8,
            selectmode="browse",
        )
        self.target_tree.heading("id", text="ID")
        self.target_tree.heading("name", text="Name")
        self.target_tree.column("id", width=52, stretch=False, anchor="w")
        self.target_tree.column("name", width=220, stretch=True, anchor="w")
        target_scroll = ttk.Scrollbar(list_wrap, orient="vertical", command=self.target_tree.yview)
        self.target_tree.configure(yscrollcommand=target_scroll.set)
        self.target_tree.pack(side="left", fill="both", expand=True)
        target_scroll.pack(side="right", fill="y")
        self.target_tree.bind("<<TreeviewSelect>>", self._on_target_pick)
        ttk.Label(
            pathf,
            textvariable=self.target_msg,
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

        mapf = ttk.LabelFrame(body, text="Address map (optional)", padding=8)
        mapf.grid(row=1, column=0, columnspan=2, sticky="nsew", pady=(0, 6))
        mapf.columnconfigure(0, weight=1)
        mapf.rowconfigure(3, weight=1)
        ttk.Label(
            mapf,
            text="Reference Vivado layout (Master Base Address; Slave Base 0x0 is ignored). "
                 "Other formats: use AI to adapt. See docs/address-map-import.md.",
            wraplength=1000,
            foreground="#555555",
        ).grid(row=0, column=0, sticky="w", pady=(0, 6))
        map_bar = ttk.Frame(mapf)
        map_bar.grid(row=1, column=0, sticky="ew", pady=(0, 6))
        ttk.Label(map_bar, text="Map").pack(side="left")
        ttk.Entry(map_bar, textvariable=self.setup_address_map_var).pack(
            side="left", fill="x", expand=True, padx=(6, 6)
        )
        ttk.Button(map_bar, text="Browse…", command=self._browse_address_map).pack(side="left", padx=(0, 6))
        ttk.Button(map_bar, text="Load / Import map", command=self._load_address_map).pack(side="left")
        map_actions = ttk.Frame(mapf)
        map_actions.grid(row=2, column=0, sticky="ew", pady=(0, 6))
        ttk.Label(map_actions, text="Show").pack(side="left")
        self.map_filter = ttk.Combobox(
            map_actions,
            textvariable=self.map_filter_var,
            values=[label for _key, label in MAP_FILTERS],
            state="readonly",
            width=18,
        )
        self.map_filter.pack(side="left", padx=(6, 12))
        self.map_filter.bind("<<ComboboxSelected>>", self._on_map_filter)
        ttk.Button(map_actions, text="Suggest profile", command=self._suggest_profile).pack(
            side="left", padx=(0, 6)
        )
        ttk.Button(
            map_actions, text="Write private profile", command=self._write_private_profile
        ).pack(side="left")
        map_list = ttk.Frame(mapf)
        map_list.grid(row=3, column=0, sticky="nsew")
        mcols = ("master", "iface", "name", "base", "range")
        map_style = ttk.Style(self)
        map_style.configure("AddrMap.Treeview", rowheight=22)
        self.map_tree = ttk.Treeview(
            map_list,
            columns=mcols,
            show="headings",
            height=6,
            selectmode="extended",
            style="AddrMap.Treeview",
        )
        self.map_tree.heading("master", text="Master")
        self.map_tree.heading("iface", text="Interface")
        self.map_tree.heading("name", text="Slave")
        self.map_tree.heading("base", text="Master Base Address")
        self.map_tree.heading("range", text="Range")
        self.map_tree.column("master", width=140, stretch=False, anchor="w")
        self.map_tree.column("iface", width=110, stretch=False, anchor="w")
        self.map_tree.column("name", width=280, stretch=True, anchor="w")
        self.map_tree.column("base", width=160, stretch=False, anchor="w")
        self.map_tree.column("range", width=80, stretch=False, anchor="w")
        map_scroll = ttk.Scrollbar(map_list, orient="vertical", command=self.map_tree.yview)
        self.map_tree.configure(yscrollcommand=map_scroll.set)
        self.map_tree.pack(side="left", fill="both", expand=True)
        map_scroll.pack(side="right", fill="y")
        self.map_tree.bind("<<TreeviewSelect>>", self._on_map_pick)
        ttk.Label(
            mapf,
            textvariable=self.map_msg,
            wraplength=1000,
            foreground="#555555",
        ).grid(row=4, column=0, sticky="w", pady=(6, 0))

        last = ttk.LabelFrame(body, text="History (last 100)", padding=4)
        last.grid(row=2, column=0, sticky="nsew", padx=(0, 6))
        rcols = ("op", "addr", "data")
        self.tree = ttk.Treeview(last, columns=rcols, show="headings", height=10)
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
        right.grid(row=2, column=1, sticky="nsew")
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

    def _target_label(self) -> str:
        if not self.selected_id:
            return "no target"
        if self.selected_name:
            return f"{self.selected_name} (id {self.selected_id})"
        return f"id {self.selected_id}"

    def _refresh_status(self) -> None:
        if self.busy:
            self.status_var.set("Busy…")
        elif not self.connected:
            self.status_var.set("Disconnected")
        elif self.selected_id:
            self.status_var.set(f"Connected · {self._target_label()}")
        elif not self.targets:
            self.status_var.set("Connected · no targets")
        else:
            self.status_var.set("Connected · select a target")

    def _sync_target_message(self) -> None:
        if not self.connected:
            self.target_msg.set("Connect to scan targets on the JTAG chain.")
        elif not self.targets:
            self.target_msg.set(
                "No register targets found. Power the board, load a bitstream, then Refresh targets."
            )
        else:
            self.target_msg.set(
                "Select a scanned target, then Read or Write. Refresh targets after changing the board or bitstream."
            )

    def _log(self, text: str) -> None:
        self.log.insert("end", text.rstrip() + "\n")
        self.log.see("end")

    def _set_busy(self, busy: bool) -> None:
        self.busy = busy
        self._refresh_status()

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
        self.busy = False
        failed = bool(err) or bool(out and out.startswith("ERROR"))
        if failed:
            self.connected = bool(self.session and self.session.alive)
            if not self.connected:
                self.selected_id = None
                self.selected_name = None
                self._pending_id = None
                self._pending_name = None
                self._fill_targets([])
            elif kind == "select":
                self._pending_id = None
                self._pending_name = None
                self._highlight_target(self.selected_id)
            msg = err or out
            self._refresh_status()
            self._log(msg)
            messagebox.showerror(title, msg)
            return
        if kind == "select":
            self.selected_id = self._pending_id
            self.selected_name = self._pending_name
            self._refresh_status()
            self._log(
                f"Selected {self._target_label()} (registers not read). "
                "Enter an address for Read / Write."
            )
            if out:
                self._log(out)
            return
        if kind == "enum":
            body = log_body(out)
            if body:
                self._log(body)
            else:
                self._log("(no output)")
            self._fill_targets(parse_target_lines(out))
            return
        self._refresh_status()
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
        # Both mrd parses and Write / Write+Readback hist tuples land here.
        self.tree.insert("", 0, values=(op, fmt_hist_hex(addr), fmt_hist_hex(data)))
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
            self.addr_var.set(fmt_hist_hex(vals[1]))
            self.data_var.set(fmt_hist_hex(vals[2]))
        elif len(vals) >= 2:
            self.addr_var.set(fmt_hist_hex(vals[0]))
            self.data_var.set(fmt_hist_hex(vals[1]))

    def _highlight_target(self, tid: str | None) -> None:
        self._filling_targets = True
        try:
            current = list(self.target_tree.selection())
            iid = target_iid(tid) if tid else ""
            if iid and self.target_tree.exists(iid):
                if tuple(current) != (iid,):
                    self.target_tree.selection_set(iid)
                    self.target_tree.see(iid)
            elif current:
                self.target_tree.selection_remove(*current)
        finally:
            self._filling_targets = False

    def _fill_targets(self, rows: list[tuple[str, str]]) -> None:
        prev = self.selected_id
        cleaned = normalize_targets(rows)
        self._filling_targets = True
        try:
            children = self.target_tree.get_children()
            if children:
                self.target_tree.delete(*children)
            self.targets = cleaned
            for tid, name in cleaned:
                self.target_tree.insert("", "end", iid=target_iid(tid), values=(tid, name))
        finally:
            self._filling_targets = False
        self._sync_target_message()
        if not self.connected:
            self.selected_id = None
            self.selected_name = None
            self._pending_id = None
            self._pending_name = None
            self._refresh_status()
            return
        keep: tuple[str, str] | None = None
        if prev:
            for tid, name in cleaned:
                if tid == prev:
                    keep = (tid, name)
                    break
        if keep is None:
            self.selected_id = None
            self.selected_name = None
            self._pending_id = None
            self._pending_name = None
            self._highlight_target(None)
            self._refresh_status()
            return
        self._pending_id, self._pending_name = keep
        self._highlight_target(keep[0])
        self._run("Select target", f"select_id {keep[0]}", kind="select")

    def _on_target_pick(self, _evt=None) -> None:
        if self._filling_targets:
            return
        sel = self.target_tree.selection()
        picked = str(sel[0]) if sel else ""
        if self.busy or not self.connected:
            keep = self.selected_id or (self._pending_id if self.busy else None)
            keep_iid = target_iid(keep) if keep else ""
            if picked != keep_iid:
                self._highlight_target(keep)
            return
        if not picked:
            return
        vals = self.target_tree.item(picked, "values")
        if len(vals) < 2:
            return
        tid, name = str(vals[0]), str(vals[1])
        if not tid.isdigit():
            return
        if tid == self.selected_id:
            return
        self._pending_id = tid
        self._pending_name = name
        self._run("Select target", f"select_id {tid}", kind="select")

    def _require_target(self) -> str | None:
        if not self.selected_id or not str(self.selected_id).isdigit():
            messagebox.showinfo(
                "Select a target",
                "Select a target from the scan list before Read or Write.",
            )
            return None
        return f"select_id {self.selected_id}"

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
            banner = ""
            try:
                banner = sess.start()
                out = sess.call("gui_connect", timeout=40)
            except Exception as exc:
                err = str(exc)
                sess.close()
            self.after(
                0,
                lambda out=out, err=err, banner=banner: self._connected(out, err, banner),
            )

        self._set_busy(True)
        self._log("Starting XSDB and connect …")
        threading.Thread(target=work, daemon=True).start()

    def _connected(self, out: str, err: str | None, banner: str = "") -> None:
        self.busy = False
        if banner.strip():
            self._log(banner.strip())
        if err or not connect_ok(out):
            self.connected = False
            self.selected_id = None
            self.selected_name = None
            self._pending_id = None
            self._pending_name = None
            if self.session:
                self.session.close()
            self._fill_targets([])
            msg = err or out or "Connect failed"
            self._log(msg)
            messagebox.showerror("Connect failed", msg)
            return
        self.connected = True
        body = log_body(out)
        if body:
            self._log(body)
        self._fill_targets(parse_target_lines(out))

    def _disconnect(self) -> None:
        if self.session:
            self.session.close()
        self.connected = False
        self.selected_id = None
        self.selected_name = None
        self._pending_id = None
        self._pending_name = None
        self._fill_targets([])
        self._log("Disconnected")

    def _clear(self) -> None:
        for item in self.tree.get_children():
            self.tree.delete(item)
        self.log.delete("1.0", "end")
        self._log("Cleared log and last 100 R/W entries")

    def _refresh_targets(self) -> None:
        self._run("Refresh targets", "enum_targets", timeout=40, kind="enum")

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
        if not self._need_session():
            return
        prefix = self._require_target()
        if prefix is None:
            return
        self._run("Read", f"{prefix}; rd {addr} {n}")

    def _wr(self) -> None:
        try:
            addr = norm_hex(self.addr_var.get(), "Address")
            data = norm_hex(self.data_var.get(), "Data")
        except Exception as exc:
            messagebox.showinfo("Address required", "Write needs address and data; fill them in manually.")
            return
        if not self._need_session():
            return
        prefix = self._require_target()
        if prefix is None:
            return
        self._run("Write", f"{prefix}; wr {addr} {data}",
                  hist=[("Write", addr, data)])

    def _wrd(self) -> None:
        try:
            addr = norm_hex(self.addr_var.get(), "Address")
            data = norm_hex(self.data_var.get(), "Data")
        except Exception as exc:
            messagebox.showinfo("Address required", "Write+Readback needs address and data; fill them in manually.")
            return
        if not self._need_session():
            return
        prefix = self._require_target()
        if prefix is None:
            return
        self._run("Write+Readback", f"{prefix}; wrd {addr} {data}",
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

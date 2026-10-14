# Parse Vivado Address Editor export: address_top.xlsx
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Slave:
    master: str
    iface: str
    name: str
    base: str
    rng: str

    @property
    def addr(self) -> str:
        return (
            str(self.base)
            .replace("0x", "")
            .replace("0X", "")
            .replace("_", "")
            .upper()
        )

    @property
    def short(self) -> str:
        n = self.name.strip("/")
        parts = n.split("/")
        return "/".join(parts[-2:]) if len(parts) >= 2 else n


def load_slaves(xlsx: Path) -> list[Slave]:
    import openpyxl

    wb = openpyxl.load_workbook(xlsx, data_only=True)
    ws = wb.active
    master = None
    iface = None
    excluded = False
    out: list[Slave] = []
    for i, row in enumerate(ws.iter_rows(values_only=True), 1):
        if i == 1:
            continue
        cells = list(row) + [None] * 8
        name, _inf, _seg, base, rng = cells[0], cells[1], cells[2], cells[3], cells[4]
        if not name:
            continue
        name = str(name)
        empty_base = base is None or str(base).strip() == ""
        if empty_base:
            if name.startswith("Excluded") or name.startswith("Incomplete"):
                excluded = True
                continue
            if name.startswith("Network "):
                master = None
                iface = None
                excluded = False
                continue
            if name.startswith("/"):
                excluded = False
                continue
            if (
                name.startswith("M_")
                or name.startswith("m_axi")
                or name in ("DLMB", "ILMB")
            ):
                iface = name
                excluded = False
                continue
            master = name
            iface = None
            excluded = False
            continue
        if excluded or not master or not iface:
            continue
        out.append(Slave(master, iface, name, str(base), str(rng or "")))
    return out


def for_path(slaves: list[Slave], path: str) -> list[Slave]:
    if path == "mb":
        return [s for s in slaves if s.master == "microblaze_0" and s.iface == "M_AXI_DP"]
    if path in ("j1", "j2"):
        # JTAG2AXI #1 sits on the same Lite interconnect as xdma_0 / M_AXI_LITE.
        # #2 is another Jtag Master; xlsx has no separate map — GUI still lists Lite
        # so the user can try, but selection success does not depend on these addresses.
        return [s for s in slaves if s.master == "xdma_0" and s.iface == "M_AXI_LITE"]
    return []

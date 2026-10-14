#!/usr/bin/env python3
# Reference parser for one Vivado Address Editor export shape.
#
# Columns: Name, Interface, Slave Segment, Master Base Address, Range,
# Slave Base Address. Rows form a tree (master, then interface, then slaves).
# XSDB mrd/mwr uses Master Base Address. Slave Base Address is often 0x0 and
# is not a poke address.
#
# Other spreadsheets differ. Use AI to adapt this file to your export:
# docs/address-map-import.md

from __future__ import annotations

import argparse
import csv
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence


REFERENCE_HEADERS = (
    "Name",
    "Interface",
    "Slave Segment",
    "Master Base Address",
    "Range",
    "Slave Base Address",
)

_HEADER_KEYS = {
    "name": "name",
    "interface": "interface",
    "slave segment": "segment",
    "master base address": "master_base",
    "range": "range",
    "slave base address": "slave_base",
}

_POSITIONAL = {
    "name": 0,
    "interface": 1,
    "segment": 2,
    "master_base": 3,
    "range": 4,
    "slave_base": 5,
}

_IFACE_EXACT = {"DLMB", "ILMB", "DATA", "INSTRUCTION"}
_EMPTY_MARKERS = {"", "-", "—", "n/a", "N/A", "None"}


class AddressMapError(Exception):
    """The workbook could not be read as the reference address map."""


@dataclass(frozen=True)
class Slave:
    master: str
    iface: str
    name: str
    base: str
    rng: str
    segment: str = ""
    interface_cell: str = ""
    slave_base: str = ""

    @property
    def addr(self) -> str:
        """Hex digits of the Master Base Address, without 0x or underscores."""
        return normalize_hex(self.base)

    @property
    def poke_tcl(self) -> str:
        """Tcl literal for XSDB. Never the slave's own base."""
        return format_tcl_addr(self.base)

    @property
    def short(self) -> str:
        n = self.name.strip("/")
        parts = n.split("/")
        return "/".join(parts[-2:]) if len(parts) >= 2 else n


def master_base_text(value: object) -> str:
    """Cell text for an address. Numeric cells are integers, not hex strings."""
    if value is None or isinstance(value, bool):
        return ""
    if isinstance(value, int):
        return f"0x{value:X}"
    if isinstance(value, float):
        if not value.is_integer():
            return str(value).strip()
        return f"0x{int(value):X}"
    text = str(value).strip()
    if text in _EMPTY_MARKERS:
        return ""
    return text


def normalize_hex(text: str) -> str:
    t = str(text).strip().replace("_", "")
    if t.lower().startswith("0x"):
        t = t[2:]
    return t.upper()


def format_tcl_addr(text: str) -> str:
    h = normalize_hex(text)
    if not h or any(c not in "0123456789ABCDEF" for c in h):
        return "0x00000000"
    return "0x" + h.zfill(max(8, len(h)))


def _cell(row: Sequence[object], index: int | None) -> object:
    if index is None or index < 0 or index >= len(row):
        return None
    return row[index]


def _header_map(row: Sequence[object]) -> dict[str, int] | None:
    found: dict[str, int] = {}
    for i, cell in enumerate(row):
        if cell is None:
            continue
        key = _HEADER_KEYS.get(str(cell).strip().lower())
        if key and key not in found:
            found[key] = i
    if "name" in found and "master_base" in found:
        return found
    return None


def _is_interface_group(name: str) -> bool:
    if name.startswith("M_") or name.startswith("m_axi"):
        return True
    return name.upper() in _IFACE_EXACT


def parse_table(rows: Sequence[Sequence[object]]) -> list[Slave]:
    """Walk the reference tree. Drops Excluded / Incomplete segments."""
    columns = dict(_POSITIONAL)
    start = 1 if rows else 0
    for i, row in enumerate(rows[:8]):
        mapped = _header_map(row)
        if mapped:
            columns = {**_POSITIONAL, **mapped}
            start = i + 1
            break

    master: str | None = None
    iface: str | None = None
    excluded = False
    out: list[Slave] = []
    for row in rows[start:]:
        name_cell = _cell(row, columns.get("name"))
        if name_cell is None or str(name_cell).strip() == "":
            continue
        name = str(name_cell).strip()
        base = master_base_text(_cell(row, columns.get("master_base")))
        if not base:
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
            if _is_interface_group(name):
                iface = name
                excluded = False
                continue
            master = name
            iface = None
            excluded = False
            continue
        if excluded or not master or not iface:
            continue
        segment = _cell(row, columns.get("segment"))
        iface_cell = _cell(row, columns.get("interface"))
        slave_base = master_base_text(_cell(row, columns.get("slave_base")))
        rng = _cell(row, columns.get("range"))
        out.append(
            Slave(
                master=master,
                iface=iface,
                name=name,
                base=base,
                rng="" if rng is None else str(rng).strip(),
                segment="" if segment is None else str(segment).strip(),
                interface_cell="" if iface_cell is None else str(iface_cell).strip(),
                slave_base=slave_base,
            )
        )
    return out


def _read_xlsx(path: Path, sheet: str | None) -> list[tuple]:
    try:
        import openpyxl
    except ImportError as exc:
        raise AddressMapError(
            "reading .xlsx needs openpyxl (pip install openpyxl). "
            "A CSV with the same reference columns is also accepted."
        ) from exc
    try:
        wb = openpyxl.load_workbook(path, data_only=True)
    except Exception as exc:
        raise AddressMapError(f"could not open {path}: {exc}") from exc
    try:
        try:
            ws = wb[sheet] if sheet else wb.active
        except KeyError as exc:
            raise AddressMapError(f"{path} has no sheet {sheet!r}") from exc
        if ws is None:
            raise AddressMapError(f"{path} has no active sheet")
        return [tuple(row) for row in ws.iter_rows(values_only=True)]
    finally:
        wb.close()


def _read_csv(path: Path) -> list[tuple]:
    try:
        with path.open(newline="", encoding="utf-8-sig") as handle:
            return [tuple(row) for row in csv.reader(handle)]
    except OSError as exc:
        raise AddressMapError(f"could not open {path}: {exc}") from exc


def load_rows(path: Path | str, *, sheet: str | None = None) -> list[tuple]:
    src = Path(path)
    if not src.is_file():
        raise AddressMapError(f"address map not found: {src}")
    if src.suffix.lower() == ".csv":
        return _read_csv(src)
    return _read_xlsx(src, sheet)


def load_slaves(xlsx: Path | str, *, sheet: str | None = None) -> list[Slave]:
    return parse_table(load_rows(xlsx, sheet=sheet))


def _is_mb_data(slave: Slave) -> bool:
    return slave.iface.upper() in {"M_AXI_DP", "DATA"}


def _is_lite(slave: Slave) -> bool:
    return "LITE" in slave.iface.upper()


def _name_hits(slave: Slave, needle: str) -> bool:
    return needle in slave.name.lower() or needle in slave.master.lower()


def select_mb(
    slaves: Sequence[Slave], name: str | None = None
) -> tuple[list[Slave], list[str]]:
    """MicroBlaze data slaves.

    With no ``name``, keep M_AXI_DP / Data slaves whose master contains
    ``microblaze``. If none do, keep every such slave and warn.
    ``name`` is an explicit substring of the slave path or master, and it
    searches every M_AXI_DP / Data slave, including renamed masters.
    """
    warnings: list[str] = []
    pool = [s for s in slaves if _is_mb_data(s)]
    if name:
        needle = name.lower()
        matched = [s for s in pool if _name_hits(s, needle)]
        if not matched:
            warnings.append(
                f"--mb-name {name!r} matched no MicroBlaze M_AXI_DP slave."
            )
        return matched, warnings
    named = [s for s in pool if "microblaze" in s.master.lower()]
    if named:
        return named, warnings
    if pool:
        warnings.append(
            "no master name contains 'microblaze'; using every M_AXI_DP / Data slave. "
            "Pass --mb-name, or use AI to adapt the parser."
        )
    return pool, warnings


def select_jtag(
    slaves: Sequence[Slave], name: str | None = None
) -> tuple[list[Slave], list[str]]:
    """Lite-window slaves a JTAG-to-AXI master often shares.

    With no ``name``, prefer a master whose name contains ``xdma``.
    ``name`` searches every M_AXI_LITE slave path or master.
    """
    warnings: list[str] = []
    lite = [s for s in slaves if _is_lite(s)]
    if name:
        needle = name.lower()
        matched = [s for s in lite if _name_hits(s, needle)]
        if not matched:
            warnings.append(f"--jtag-name {name!r} matched no M_AXI_LITE slave.")
        return matched, warnings
    xdma = [s for s in lite if "xdma" in s.master.lower()]
    if xdma:
        return xdma, warnings
    if lite:
        warnings.append(
            "no master name contains 'xdma'; using every M_AXI_LITE slave. "
            "JTAG-to-AXI often shares that window, but the instance may be renamed. "
            "Pass --jtag-name, or use AI to adapt the parser."
        )
    return lite, warnings


def for_path(slaves: list[Slave], path: str) -> list[Slave]:
    """Slaves for a poke path. ``j1`` and ``j2`` share one Lite map."""
    key = path.lower()
    if key == "mb":
        rows, _ = select_mb(slaves)
        return rows
    if key in {"jtag", "j1", "j2"}:
        rows, _ = select_jtag(slaves)
        return rows
    return []


def format_table(slaves: Sequence[Slave]) -> str:
    header = ("master", "iface", "name", "master_base_address", "range")
    body = [
        (s.master, s.iface, s.name, s.base, s.rng)
        for s in slaves
    ]
    rows = [header, *body]
    widths = [
        max(len(str(row[i])) for row in rows) for i in range(len(header))
    ]
    lines = [
        "  ".join(str(row[i]).ljust(widths[i]) for i in range(len(header))).rstrip()
        for row in rows
    ]
    return "\n".join(lines)


def _warn_choice(
    label: str,
    rows: Sequence[Slave],
    flag: str | None,
    empty_note: str,
) -> list[str]:
    if not rows:
        return [empty_note]
    first = rows[0]
    where = f"{first.master} {first.iface} {first.name} ({first.base})"
    if len(rows) == 1:
        if flag:
            return [f"suggest-profile: {label} matched {flag} ({where})."]
        return [
            f"suggest-profile: {label} is the only match ({where}). "
            "Confirm it before copying into profiles/private/."
        ]
    extra = len(rows) - 1
    skipped = "1 other slave skipped" if extra == 1 else f"{extra} other slaves skipped"
    if flag:
        why = f"{flag} matched {len(rows)} slaves; the first is used"
    else:
        why = "the first match of the example rule"
    return [
        f"suggest-profile: {label} uses {why} ({where}). "
        f"{skipped}. "
        "This is an example rule, not a lab convention. "
        "Pass an explicit name filter or edit the snippet."
    ]


def suggest_profile(
    slaves: Sequence[Slave],
    *,
    source: str,
    mb_name: str | None = None,
    jtag_name: str | None = None,
) -> tuple[str, list[str]]:
    """Tcl snippet for profiles/private/. Stdout only; nothing is written."""
    mb_rows, mb_notes = select_mb(slaves, mb_name)
    jtag_rows, jtag_notes = select_jtag(slaves, jtag_name)
    warnings = [*mb_notes, *jtag_notes]
    warnings.extend(
        _warn_choice(
            "MB_SMOKE_ADDR",
            mb_rows,
            f"--mb-name {mb_name!r}" if mb_name else "",
            "suggest-profile: no MicroBlaze M_AXI_DP slave; ::MB_SMOKE_ADDR left at 0x0.",
        )
    )
    warnings.extend(
        _warn_choice(
            "JTAG_SMOKE_ADDR",
            jtag_rows,
            f"--jtag-name {jtag_name!r}" if jtag_name else "",
            "suggest-profile: no xdma M_AXI_LITE slave; ::JTAG_SMOKE_ADDR left at 0x0.",
        )
    )
    mb = mb_rows[0] if mb_rows else None
    jtag = jtag_rows[0] if jtag_rows else None
    mb_addr = mb.poke_tcl if mb else "0x00000000"
    jtag_addr = jtag.poke_tcl if jtag else "0x00000000"
    mb_comment = (
        f"# MB: {mb.master} {mb.iface} {mb.name}"
        if mb
        else "# MB: (none) — smoke will skip this read"
    )
    if jtag:
        jtag_comment = (
            "# JTAG (M_AXI_LITE window; JTAG-to-AXI is not its own row): "
            f"{jtag.master} {jtag.iface} {jtag.name}"
        )
    else:
        jtag_comment = "# JTAG: (none) — smoke will skip this read"
    text = "\n".join(
        [
            "# Suggested board-profile snippet from addr_map.py.",
            f"# Source map: {source}",
            "# Example rule: first MicroBlaze M_AXI_DP slave, first xdma M_AXI_LITE slave.",
            "# Copy into profiles/private/<name>.tcl and edit. This command does not write that file.",
            "# Do not commit real Master Base Addresses.",
            "#",
            mb_comment,
            jtag_comment,
            'set ::PROFILE_NAME "suggested"',
            f"set ::MB_SMOKE_ADDR   {mb_addr}",
            f"set ::JTAG_SMOKE_ADDR {jtag_addr}",
            "",
        ]
    )
    return text, warnings


def _path_choice(value: str) -> str:
    key = value.lower()
    if key not in {"all", "mb", "jtag", "j1", "j2"}:
        raise argparse.ArgumentTypeError("expected all, mb, or jtag")
    return key


def _resolve_xlsx(positional: str | None, option: str | None) -> Path:
    if positional and option and Path(positional) != Path(option):
        raise AddressMapError("pass the workbook once (positional path or --xlsx)")
    chosen = option or positional
    if not chosen:
        raise AddressMapError("pass an address map path, for example examples/address.xlsx")
    return Path(chosen)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="addr_map.py",
        description=(
            "List Master Base Addresses from a Vivado-style Address Editor export. "
            "This is a reference parser for one column layout "
            "(Name, Interface, Slave Segment, Master Base Address, …). "
            "Other exports differ — use AI to adapt this parser. "
            "See docs/address-map-import.md."
        ),
    )
    parser.add_argument(
        "xlsx",
        nargs="?",
        help="path to address.xlsx (or a CSV with the same columns)",
    )
    parser.add_argument(
        "--xlsx",
        dest="xlsx_opt",
        help="path to address.xlsx (same as the positional argument)",
    )
    parser.add_argument(
        "--path",
        type=_path_choice,
        default="all",
        help="mb, jtag, or all (default: all). j1 and j2 are aliases of jtag",
    )
    parser.add_argument(
        "--mb-name",
        help="substring of the MicroBlaze slave path (M_AXI_DP / Data)",
    )
    parser.add_argument(
        "--jtag-name",
        help="substring of the Lite slave path (xdma M_AXI_LITE when present)",
    )
    parser.add_argument(
        "--suggest-profile",
        action="store_true",
        help="print a profiles/private snippet to stdout; do not write a file",
    )
    parser.add_argument(
        "--sheet",
        help="worksheet name (default: the active sheet)",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(list(argv) if argv is not None else None)
    try:
        path = _resolve_xlsx(args.xlsx, args.xlsx_opt)
        slaves = load_slaves(path, sheet=args.sheet)
    except AddressMapError as exc:
        print(f"addr_map.py: {exc}", file=sys.stderr)
        return 2

    if not slaves:
        print(
            "addr_map.py: no slaves imported. The reference parser expects a tree: "
            "master and interface rows with an empty Master Base Address, then slave "
            "rows that have one. Excluded and Incomplete groups are dropped. "
            "A flat table or different headers need an adapter — "
            "use AI with docs/address-map-import.md and your export.",
            file=sys.stderr,
        )

    if args.suggest_profile:
        if args.path != "all":
            print(
                "addr_map.py: --path filters the table only; "
                "--suggest-profile still fills both ::MB_SMOKE_ADDR and ::JTAG_SMOKE_ADDR.",
                file=sys.stderr,
            )
        snippet, warnings = suggest_profile(
            slaves,
            source=str(path),
            mb_name=args.mb_name,
            jtag_name=args.jtag_name,
        )
        for note in warnings:
            print(f"addr_map.py: {note}", file=sys.stderr)
        sys.stdout.write(snippet)
        return 0

    if args.path == "all":
        shown = list(slaves)
        if args.mb_name or args.jtag_name:
            print(
                "addr_map.py: --mb-name / --jtag-name apply to --path mb|jtag "
                "and to --suggest-profile. Listing every imported slave.",
                file=sys.stderr,
            )
    elif args.path == "mb":
        shown, notes = select_mb(slaves, args.mb_name)
        for note in notes:
            print(f"addr_map.py: {note}", file=sys.stderr)
    else:
        shown, notes = select_jtag(slaves, args.jtag_name)
        for note in notes:
            print(f"addr_map.py: {note}", file=sys.stderr)

    print(
        f"# {path}  (Master Base Address is the XSDB poke address; "
        "Slave Base Address is ignored)"
    )
    print(format_table(shown))
    return 0


if __name__ == "__main__":
    sys.exit(main())

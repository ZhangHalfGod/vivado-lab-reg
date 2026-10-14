"""Reference Address Editor import: fictional map, not a lab spreadsheet."""

from __future__ import annotations

import io
import subprocess
import sys
import unittest
import zipfile
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import addr_map

ROOT = Path(__file__).resolve().parents[1]
EXAMPLE = ROOT / "examples" / "address.xlsx"
BANNED = (
    "11080000",
    "116BCC00",
    "116B0000",
    "ext_reg_if",
    "sdi_analysis",
    "address_top",
)


class ExampleWorkbookTests(unittest.TestCase):
    def test_example_is_the_fictional_reference_map(self) -> None:
        slaves = addr_map.load_slaves(EXAMPLE)
        names = [s.name for s in slaves]
        self.assertEqual(
            names,
            [
                "/example_ip_a/S00_AXI",
                "/example_ip_c/S00_AXI",
                "/example_ip_b/S_AXI_LITE",
            ],
        )
        by_name = {s.name: s for s in slaves}
        mb = by_name["/example_ip_a/S00_AXI"]
        self.assertEqual(mb.master, "microblaze_0")
        self.assertEqual(mb.iface, "M_AXI_DP")
        self.assertEqual(mb.base, "0x1000_0000")
        self.assertEqual(mb.addr, "10000000")
        self.assertEqual(mb.poke_tcl, "0x10000000")
        self.assertEqual(mb.slave_base, "0x0000_0000")
        self.assertNotEqual(mb.poke_tcl, addr_map.format_tcl_addr(mb.slave_base))
        self.assertEqual(by_name["/example_ip_c/S00_AXI"].poke_tcl, "0x18000000")
        lite = by_name["/example_ip_b/S_AXI_LITE"]
        self.assertEqual(lite.master, "xdma_0")
        self.assertEqual(lite.iface, "M_AXI_LITE")
        self.assertEqual(lite.poke_tcl, "0x20000000")
        self.assertNotIn("example_ip_excluded", names)

    def test_example_file_has_no_lab_map(self) -> None:
        with zipfile.ZipFile(EXAMPLE) as workbook:
            text = "\n".join(
                workbook.read(name).decode("utf-8", "ignore")
                for name in workbook.namelist()
            )
        for banned in BANNED:
            self.assertNotIn(banned, text)


class ParseTests(unittest.TestCase):
    def test_headers_win_over_column_order(self) -> None:
        rows = [
            (
                "Slave Base Address",
                "Master Base Address",
                "Name",
                "Range",
                "Interface",
                "Slave Segment",
            ),
            (None, None, "microblaze_0", None, None, None),
            (None, None, "M_AXI_DP", None, None, None),
            (
                "0x0000_0000",
                "0x1000_0000",
                "/example_ip_a/S00_AXI",
                "64K",
                "S00_AXI",
                "SEG_example_ip_a_Reg",
            ),
        ]
        slaves = addr_map.parse_table(rows)
        self.assertEqual(len(slaves), 1)
        self.assertEqual(slaves[0].base, "0x1000_0000")
        self.assertEqual(slaves[0].slave_base, "0x0000_0000")
        self.assertEqual(slaves[0].addr, "10000000")

    def test_numeric_master_base_is_hex(self) -> None:
        rows = [
            addr_map.REFERENCE_HEADERS,
            ("cpu_0", None, None, None, None, None),
            ("Data", None, None, None, None, None),
            ("/example_ip_a/S00_AXI", "S00_AXI", "SEG", 0x10000000, "64K", 0),
        ]
        slaves = addr_map.parse_table(rows)
        self.assertEqual(slaves[0].iface, "Data")
        self.assertEqual(slaves[0].base, "0x10000000")
        self.assertEqual(slaves[0].slave_base, "0x0")
        self.assertEqual(slaves[0].poke_tcl, "0x10000000")

    def test_excluded_and_network_do_not_leak(self) -> None:
        rows = [
            addr_map.REFERENCE_HEADERS,
            ("microblaze_0", None, None, None, None, None),
            ("M_AXI_DP", None, None, None, None, None),
            ("/example_ip_a/S00_AXI", "S00_AXI", "SEG", "0x1000_0000", "64K", "0x0"),
            ("Incomplete Address Segments", None, None, None, None, None),
            ("/example_ip_excluded/S00_AXI", "S00_AXI", "SEG", "0x3000_0000", "4K", "0x0"),
            ("Network 0", None, None, None, None, None),
            ("/example_ip_b/S_AXI_LITE", "S_AXI_LITE", "SEG", "0x2000_0000", "4K", "0x0"),
        ]
        names = [s.name for s in addr_map.parse_table(rows)]
        self.assertEqual(names, ["/example_ip_a/S00_AXI"])

    def test_flat_table_is_not_this_reference_shape(self) -> None:
        rows = [
            ("Name", "Master Base Address"),
            ("/example_ip_a/S00_AXI", "0x1000_0000"),
        ]
        self.assertEqual(addr_map.parse_table(rows), [])

    def test_csv_uses_the_same_rules(self) -> None:
        import tempfile

        text = (
            "Name,Interface,Slave Segment,Master Base Address,Range,Slave Base Address\n"
            "microblaze_0,,,,,\n"
            "M_AXI_DP,,,,,\n"
            "/example_ip_a/S00_AXI,S00_AXI,SEG,0x1000_0000,64K,0x0000_0000\n"
        )
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "address.csv"
            path.write_text(text, encoding="utf-8")
            slaves = addr_map.load_slaves(path)
        self.assertEqual(slaves[0].poke_tcl, "0x10000000")
        self.assertEqual(slaves[0].slave_base, "0x0000_0000")


class SelectTests(unittest.TestCase):
    def setUp(self) -> None:
        self.slaves = addr_map.load_slaves(EXAMPLE)

    def test_paths_follow_interface_not_a_lab_slave_name(self) -> None:
        mb = addr_map.for_path(self.slaves, "mb")
        jtag = addr_map.for_path(self.slaves, "jtag")
        self.assertEqual([s.name for s in mb], [
            "/example_ip_a/S00_AXI",
            "/example_ip_c/S00_AXI",
        ])
        self.assertEqual([s.name for s in jtag], ["/example_ip_b/S_AXI_LITE"])
        self.assertEqual(addr_map.for_path(self.slaves, "j1"), jtag)
        self.assertEqual(addr_map.for_path(self.slaves, "j2"), jtag)
        self.assertEqual(addr_map.for_path(self.slaves, "all"), [])

    def test_explicit_name_can_see_a_renamed_master(self) -> None:
        extra = addr_map.Slave(
            "renamed_cpu",
            "M_AXI_DP",
            "/example_ip_d/S00_AXI",
            "0x4000_0000",
            "4K",
        )
        rows, notes = addr_map.select_mb([*self.slaves, extra], "example_ip_d")
        self.assertEqual([s.name for s in rows], ["/example_ip_d/S00_AXI"])
        self.assertEqual(notes, [])
        preferred, notes = addr_map.select_mb([*self.slaves, extra])
        self.assertTrue(all("microblaze" in s.master for s in preferred))
        self.assertEqual(notes, [])

    def test_lite_without_xdma_warns(self) -> None:
        only = [
            addr_map.Slave(
                "axi_interconnect_0",
                "M_AXI_LITE",
                "/example_ip_b/S_AXI_LITE",
                "0x2000_0000",
                "4K",
            )
        ]
        rows, notes = addr_map.select_jtag(only)
        self.assertEqual(len(rows), 1)
        self.assertTrue(any("xdma" in note for note in notes))


class CliTests(unittest.TestCase):
    def _run(self, args: list[str]) -> tuple[int, str, str]:
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = addr_map.main(args)
        return code, out.getvalue(), err.getvalue()

    def test_list_prints_master_base_only(self) -> None:
        code, out, err = self._run([str(EXAMPLE)])
        self.assertEqual(code, 0, err)
        self.assertIn("master", out)
        self.assertIn("master_base_address", out)
        self.assertIn("/example_ip_a/S00_AXI", out)
        self.assertIn("0x1000_0000", out)
        self.assertIn("/example_ip_b/S_AXI_LITE", out)
        self.assertIn("0x2000_0000", out)
        self.assertNotIn("example_ip_excluded", out)
        self.assertNotIn("0x3000_0000", out)
        self.assertNotIn("0x0000_0000", out)
        self.assertEqual(err, "")

    def test_path_filters(self) -> None:
        code, out, _err = self._run(["--xlsx", str(EXAMPLE), "--path", "mb"])
        self.assertEqual(code, 0)
        self.assertIn("/example_ip_a/S00_AXI", out)
        self.assertNotIn("/example_ip_b/S_AXI_LITE", out)
        code, out, _err = self._run([str(EXAMPLE), "--path", "jtag"])
        self.assertEqual(code, 0)
        self.assertIn("/example_ip_b/S_AXI_LITE", out)
        self.assertNotIn("/example_ip_a/S00_AXI", out)

    def test_suggest_profile_is_stdout_and_warns(self) -> None:
        code, out, err = self._run([str(EXAMPLE), "--suggest-profile"])
        self.assertEqual(code, 0)
        self.assertIn("set ::MB_SMOKE_ADDR   0x10000000", out)
        self.assertIn("set ::JTAG_SMOKE_ADDR 0x20000000", out)
        self.assertIn('set ::PROFILE_NAME "suggested"', out)
        self.assertNotIn("0x18000000", out)
        self.assertIn("/example_ip_a/S00_AXI", out)
        self.assertIn("example rule", err)
        self.assertIn("profiles/private", out)
        self.assertNotIn("set ::", err)

    def test_explicit_filters_pick_the_named_slave(self) -> None:
        code, out, err = self._run(
            [
                "--xlsx",
                str(EXAMPLE),
                "--suggest-profile",
                "--mb-name",
                "example_ip_c",
                "--jtag-name",
                "example_ip_b",
            ]
        )
        self.assertEqual(code, 0, err)
        self.assertIn("set ::MB_SMOKE_ADDR   0x18000000", out)
        self.assertIn("set ::JTAG_SMOKE_ADDR 0x20000000", out)
        self.assertNotIn("0x10000000", out)
        self.assertIn("example_ip_c", err)

    def test_missing_file(self) -> None:
        code, out, err = self._run(["--xlsx", "examples/no-such-address.xlsx"])
        self.assertEqual(code, 2)
        self.assertEqual(out, "")
        self.assertIn("not found", err)

    def test_missing_sheet(self) -> None:
        code, out, err = self._run(["--xlsx", str(EXAMPLE), "--sheet", "No Such Sheet"])
        self.assertEqual(code, 2)
        self.assertEqual(out, "")
        self.assertIn("no sheet", err)

    def test_module_entry_on_the_example(self) -> None:
        proc = subprocess.run(
            [sys.executable, "-m", "addr_map", "--path", "jtag", str(EXAMPLE)],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("/example_ip_b/S_AXI_LITE", proc.stdout)
        self.assertNotIn("/example_ip_a/S00_AXI", proc.stdout)


class DocTests(unittest.TestCase):
    def test_import_doc_tells_readers_to_adapt_with_ai(self) -> None:
        text = (ROOT / "docs" / "address-map-import.md").read_text(encoding="utf-8")
        self.assertIn("Use AI to adapt", text)
        self.assertIn("请使用 AI 进行适配", text)
        self.assertIn("examples/address.xlsx", text)
        self.assertNotIn("address_top.xlsx", text)
        for banned in BANNED:
            self.assertNotIn(banned, text)

    def test_readmes_point_at_the_importer(self) -> None:
        for name in ("README.md", "README.zh-CN.md", "profiles/README.md"):
            text = (ROOT / name).read_text(encoding="utf-8")
            self.assertIn("address-map-import.md", text)
            self.assertNotIn("address_top.xlsx", text)


if __name__ == "__main__":
    unittest.main()

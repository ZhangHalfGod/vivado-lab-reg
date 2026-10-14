"""GUI address-map import: fictional example workbook, not a lab spreadsheet."""

from __future__ import annotations

import json
import os
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import addr_map
import gui

ROOT = Path(__file__).resolve().parents[1]
EXAMPLE = ROOT / "examples" / "address.xlsx"


class AddressMapHelperTests(unittest.TestCase):
    def setUp(self) -> None:
        import tempfile

        self.tmp = Path(tempfile.mkdtemp(prefix="vlr-map-"))
        self._env = mock.patch.dict(os.environ, {"APPDATA": str(self.tmp)}, clear=False)
        self._env.start()

    def tearDown(self) -> None:
        self._env.stop()
        import shutil

        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_saved_path_round_trip_keeps_other_keys(self) -> None:
        gui.save_config({"xsdb_bat": r"C:\lab\xsdb.bat", "profile": r"C:\lab\board.tcl"})
        gui.save_config({"address_map": str(EXAMPLE)})
        gui.save_xsdb_path(Path(r"D:\other\xsdb.bat"))
        data = gui.load_config()
        self.assertEqual(data["address_map"], str(EXAMPLE))
        self.assertEqual(data["profile"], r"C:\lab\board.tcl")
        self.assertEqual(gui.initial_address_map_text(), str(EXAMPLE))

    def test_absent_key_is_empty(self) -> None:
        self.assertEqual(gui.initial_address_map_text(), "")
        gui.save_config({"address_map": ""})
        self.assertEqual(gui.initial_address_map_text(), "")

    def test_validate_address_map(self) -> None:
        self.assertEqual(gui.validate_address_map("  "), (None, None))
        missing, err = gui.validate_address_map(str(self.tmp / "address.xlsx"))
        self.assertIsNone(missing)
        self.assertIn("not found", err or "")
        notes = self.tmp / "notes.txt"
        notes.write_text("nope", encoding="utf-8")
        path, err = gui.validate_address_map(str(notes))
        self.assertIsNone(path)
        self.assertIn(".xlsx", err or "")
        path, err = gui.validate_address_map(f'  "{EXAMPLE}"  ')
        self.assertEqual(path, EXAMPLE.resolve())
        self.assertIsNone(err)

    def test_filters_match_for_path_and_first_match_warns(self) -> None:
        slaves = addr_map.load_slaves(EXAMPLE)
        all_rows, notes = gui.filter_imported_slaves(slaves, "all")
        self.assertEqual(all_rows, slaves)
        self.assertEqual(notes, [])
        mb_rows, mb_notes = gui.filter_imported_slaves(slaves, "mb")
        self.assertEqual(mb_rows, addr_map.for_path(slaves, "mb"))
        self.assertEqual(mb_notes, [])
        jtag_rows, jtag_notes = gui.filter_imported_slaves(slaves, "jtag")
        self.assertEqual(jtag_rows, addr_map.for_path(slaves, "jtag"))
        self.assertEqual(jtag_rows, addr_map.for_path(slaves, "j1"))
        self.assertEqual(jtag_notes, [])
        text, warnings = gui.build_profile_suggestion(slaves, [], str(EXAMPLE))
        self.assertIn("set ::MB_SMOKE_ADDR   0x10000000", text)
        self.assertIn("set ::JTAG_SMOKE_ADDR 0x20000000", text)
        self.assertNotIn("0x18000000", text)
        self.assertTrue(any("example rule" in note for note in warnings))

    def test_selected_rows_are_name_filters(self) -> None:
        slaves = addr_map.load_slaves(EXAMPLE)
        chosen = [s for s in slaves if s.name.endswith("example_ip_c/S00_AXI")]
        self.assertEqual(gui.profile_name_filters(chosen), (chosen[0].name, None))
        text, warnings = gui.build_profile_suggestion(slaves, chosen, str(EXAMPLE))
        self.assertIn("set ::MB_SMOKE_ADDR   0x18000000", text)
        self.assertIn("set ::JTAG_SMOKE_ADDR 0x20000000", text)
        self.assertNotIn("0x10000000", text)
        self.assertTrue(any("example_ip_c" in note for note in warnings))

    def test_openpyxl_message_says_how_to_install(self) -> None:
        msg = gui.openpyxl_message(
            addr_map.AddressMapError("reading .xlsx needs openpyxl (pip install openpyxl).")
        )
        self.assertIn("pip install openpyxl", msg)


class AddressMapWindowTests(unittest.TestCase):
    def setUp(self) -> None:
        import tempfile

        self.tmp = Path(tempfile.mkdtemp(prefix="vlr-gui-map-"))
        self._env = mock.patch.dict(os.environ, {"APPDATA": str(self.tmp)}, clear=False)
        self._env.start()
        self.app = None

    def tearDown(self) -> None:
        if self.app is not None:
            try:
                self.app.destroy()
            except Exception:
                pass
        self._env.stop()
        import shutil

        shutil.rmtree(self.tmp, ignore_errors=True)

    def _buttons(self) -> list[str]:
        from tkinter import ttk

        found: list[str] = []

        def walk(widget) -> None:
            for child in widget.winfo_children():
                if isinstance(child, ttk.Button):
                    found.append(str(child.cget("text")))
                walk(child)

        walk(self.app)
        return found

    def _enter(self, address_map: str = "") -> gui.App:
        xsdb = self.tmp / "xsdb.bat"
        xsdb.write_text("@echo off\r\n", encoding="utf-8")
        self.app = gui.App()
        self.app.setup_path_var.set(str(xsdb))
        if address_map:
            self.app.setup_address_map_var.set(address_map)
        self.app._enter_main()
        self.app.update_idletasks()
        return self.app

    def _slave_names(self) -> list[str]:
        return [
            str(self.app.map_tree.item(iid, "values")[2])
            for iid in self.app.map_tree.get_children()
        ]

    def test_setup_and_main_show_the_import_controls(self) -> None:
        self.app = gui.App()
        self.app.update_idletasks()
        self.app.update()
        from tkinter import ttk

        frames = []

        def walk(widget) -> None:
            for child in widget.winfo_children():
                if isinstance(child, ttk.LabelFrame):
                    frames.append(str(child.cget("text")))
                walk(child)

        walk(self.app)
        self.assertIn("Address map (optional)", frames)
        self.assertIn("Board profile (optional)", frames)
        labels = self._buttons()
        self.assertIn("Load / Import map", labels)
        self.assertIn("Suggest profile", labels)
        self.assertIn("Write private profile", labels)
        self.assertIn("Refresh targets", labels)

    def test_continue_persists_address_map_beside_profile(self) -> None:
        profile = self.tmp / "board.tcl"
        profile.write_text("set ::MB_SMOKE_ADDR 0x1\n", encoding="utf-8")
        app = self._enter()
        app.setup_profile_var.set(str(profile))
        app.setup_address_map_var.set(str(EXAMPLE))
        app._enter_main()
        saved = json.loads(gui.config_file().read_text(encoding="utf-8"))
        self.assertEqual(saved["profile"], str(profile.resolve()))
        self.assertEqual(saved["address_map"], str(EXAMPLE.resolve()))
        self.assertIn(str(EXAMPLE.resolve()), app.log.get("1.0", "end"))
        self.assertIsNotNone(app.target_tree)
        app._fill_targets([("3", "MicroBlaze #0"), ("5", "JTAG2AXI")])
        self.assertEqual(len(app.target_tree.get_children()), 2)
        self.assertIsNone(app.selected_id)

    def test_invalid_map_does_not_enter_main(self) -> None:
        xsdb = self.tmp / "xsdb.bat"
        xsdb.write_text("@echo off\r\n", encoding="utf-8")
        warnings: list[tuple] = []
        self.app = gui.App()
        self.app.setup_path_var.set(str(xsdb))
        self.app.setup_address_map_var.set(str(self.tmp / "missing.xlsx"))
        with mock.patch.object(
            gui.messagebox, "showwarning", lambda *args, **kwargs: warnings.append(args)
        ):
            self.app._enter_main()
        self.assertTrue(warnings)
        self.assertIsNone(self.app.session)
        self.assertTrue(self.app.setup_frame.winfo_ismapped())

    def test_load_example_lists_slaves_and_fills_address(self) -> None:
        app = self._enter(str(EXAMPLE))
        app._load_address_map()
        self.assertEqual(
            self._slave_names(),
            [
                "/example_ip_a/S00_AXI",
                "/example_ip_c/S00_AXI",
                "/example_ip_b/S_AXI_LITE",
            ],
        )
        self.assertNotIn("example_ip_excluded", self._slave_names())
        iid = app.map_tree.get_children()[0]
        app.map_tree.selection_set(iid)
        app.map_tree.focus(iid)
        app._on_map_pick()
        self.assertEqual(app.addr_var.get(), "10000000")
        app.map_filter_var.set("MicroBlaze path")
        app._on_map_filter()
        self.assertEqual(
            self._slave_names(),
            ["/example_ip_a/S00_AXI", "/example_ip_c/S00_AXI"],
        )
        app.map_filter_var.set("JTAG-Lite path")
        app._on_map_filter()
        self.assertEqual(self._slave_names(), ["/example_ip_b/S_AXI_LITE"])
        lite = app.map_tree.get_children()[0]
        app.map_tree.selection_set(lite)
        app.map_tree.focus(lite)
        app._on_map_pick()
        self.assertEqual(app.addr_var.get(), "20000000")

    def test_suggest_profile_uses_selection_or_first_match(self) -> None:
        app = self._enter(str(EXAMPLE))
        app._load_address_map()
        app._suggest_profile()
        win = app._suggestion_win
        win.update_idletasks()
        blob = ""

        def walk(widget) -> None:
            nonlocal blob
            if widget.winfo_class() == "Text":
                blob += widget.get("1.0", "end")
            for child in widget.winfo_children():
                walk(child)

        walk(win)
        self.assertIn("set ::MB_SMOKE_ADDR   0x10000000", blob)
        self.assertIn("set ::JTAG_SMOKE_ADDR 0x20000000", blob)
        win.destroy()

        app.map_filter_var.set("All")
        app._on_map_filter()
        for iid in app.map_tree.get_children():
            if "example_ip_c" in str(app.map_tree.item(iid, "values")):
                app.map_tree.selection_set(iid)
                break
        text, _warnings = gui.build_profile_suggestion(
            app.map_slaves, app._selected_map_slaves(), str(EXAMPLE)
        )
        self.assertIn("set ::MB_SMOKE_ADDR   0x18000000", text)

    def test_missing_openpyxl_is_an_english_error(self) -> None:
        app = self._enter(str(EXAMPLE))
        errors: list[tuple] = []
        with mock.patch.object(
            addr_map,
            "load_slaves",
            side_effect=addr_map.AddressMapError(
                "reading .xlsx needs openpyxl (pip install openpyxl)."
            ),
        ):
            with mock.patch.object(
                gui.messagebox, "showerror", lambda *args, **kwargs: errors.append(args)
            ):
                app._load_address_map()
        self.assertTrue(errors)
        self.assertIn("openpyxl", errors[0][0].lower())
        self.assertIn("pip install openpyxl", errors[0][1])
        self.assertEqual(app.map_tree.get_children(), ())

    def test_write_private_profile_confirms_overwrite(self) -> None:
        app = self._enter(str(EXAMPLE))
        app._load_address_map()
        dest = self.tmp / "lab.tcl"
        dest.write_text("old\n", encoding="utf-8")
        titles: list[str] = []

        def askyesno(title, message, **kwargs):
            titles.append(title)
            return False

        with mock.patch.object(gui.filedialog, "asksaveasfilename", return_value=str(dest)):
            with mock.patch.object(gui.messagebox, "askyesno", askyesno):
                app._write_private_profile()
        self.assertEqual(dest.read_text(encoding="utf-8"), "old\n")
        self.assertEqual(titles, ["Overwrite profile"])

        titles.clear()
        answers = iter([True, False])

        def askyesno_replace(title, message, **kwargs):
            titles.append(title)
            return next(answers)

        with mock.patch.object(gui.filedialog, "asksaveasfilename", return_value=str(dest)):
            with mock.patch.object(gui.messagebox, "askyesno", askyesno_replace):
                app._write_private_profile()
        body = dest.read_text(encoding="utf-8")
        self.assertIn("set ::MB_SMOKE_ADDR   0x10000000", body)
        self.assertIn("set ::JTAG_SMOKE_ADDR 0x20000000", body)
        self.assertEqual(titles, ["Overwrite profile", "Write private profile"])
        self.assertEqual(app.profile_var.get(), "(none)")

    def test_save_as_cancel_writes_nothing(self) -> None:
        app = self._enter(str(EXAMPLE))
        app._load_address_map()
        with mock.patch.object(gui.filedialog, "asksaveasfilename", return_value=""):
            with mock.patch.object(gui.messagebox, "askyesno") as ask:
                app._write_private_profile()
        ask.assert_not_called()

    def test_docs_point_at_the_reference_gui(self) -> None:
        note = (ROOT / "docs" / "address-map-import.md").read_text(encoding="utf-8")
        self.assertIn("Load / Import map", note)
        self.assertIn("Use AI to adapt", note)
        self.assertIn("请使用 AI 进行适配", note)
        usage = (ROOT / "docs" / "usage-zh.md").read_text(encoding="utf-8")
        self.assertIn("Address map (optional)", usage)
        self.assertIn("address-map-import.md", usage)
        self.assertIn("请使用 AI 进行适配", usage)
        for name in ("README.md", "README.zh-CN.md"):
            text = (ROOT / name).read_text(encoding="utf-8")
            self.assertIn("Address map (optional)", text)
            self.assertIn("address-map-import.md", text)


if __name__ == "__main__":
    unittest.main()

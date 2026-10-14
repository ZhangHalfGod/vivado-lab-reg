"""Config merge, profile validation, and setup-window wiring for board profiles."""

from __future__ import annotations

import json
import os
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import gui


class ProfileConfigTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(self._tmp_dir())
        self._env = mock.patch.dict(os.environ, {"APPDATA": str(self.tmp)}, clear=False)
        self._env.start()
        self.addCleanup(self._env.stop)
        self.addCleanup(self._rmtree)

    def _tmp_dir(self) -> str:
        import tempfile

        path = tempfile.mkdtemp(prefix="vlr-profile-")
        self._created = Path(path)
        return path

    def _rmtree(self) -> None:
        import shutil

        shutil.rmtree(self._created, ignore_errors=True)

    def test_save_merges_profile_and_xsdb(self) -> None:
        gui.save_config({"xsdb_bat": r"C:\lab\xsdb.bat", "profile": r"C:\lab\board.tcl"})
        gui.save_xsdb_path(Path(r"D:\other\xsdb.bat"))
        data = gui.load_config()
        self.assertEqual(data["xsdb_bat"], r"D:\other\xsdb.bat")
        self.assertEqual(data["profile"], r"C:\lab\board.tcl")
        text = gui.config_file().read_text(encoding="utf-8")
        self.assertEqual(json.loads(text)["profile"], r"C:\lab\board.tcl")

    def test_empty_saved_profile_beats_env(self) -> None:
        gui.save_config({"profile": ""})
        with mock.patch.dict(os.environ, {"VIVADO_LAB_REG_PROFILE": "/tmp/from-env.tcl"}):
            self.assertEqual(gui.initial_profile_text(), "")

    def test_env_prefills_when_key_absent(self) -> None:
        with mock.patch.dict(
            os.environ,
            {"XSDB_PROFILE": "/tmp/from-xsdb.tcl"},
            clear=False,
        ):
            os.environ.pop("VIVADO_LAB_REG_PROFILE", None)
            self.assertEqual(gui.initial_profile_text(), "/tmp/from-xsdb.tcl")

    def test_vivado_env_beats_xsdb_env(self) -> None:
        with mock.patch.dict(
            os.environ,
            {
                "VIVADO_LAB_REG_PROFILE": "/tmp/vivado.tcl",
                "XSDB_PROFILE": "/tmp/xsdb.tcl",
            },
        ):
            self.assertEqual(gui.initial_profile_text(), "/tmp/vivado.tcl")

    def test_validate_profile(self) -> None:
        self.assertEqual(gui.validate_profile("  "), (None, None))
        missing, err = gui.validate_profile("/no/such/board.tcl")
        self.assertIsNone(missing)
        self.assertIn("not found", err or "")
        other = self.tmp / "notes.txt"
        other.write_text("nope", encoding="utf-8")
        path, err = gui.validate_profile(str(other))
        self.assertIsNone(path)
        self.assertIn(".tcl", err or "")
        good = self.tmp / "board.tcl"
        good.write_text("set ::MB_SMOKE_ADDR 0x1\n", encoding="utf-8")
        path, err = gui.validate_profile(f'  "{good}"  ')
        self.assertEqual(path, good.resolve())
        self.assertIsNone(err)

    def test_session_environ_replaces_inherited_profile(self) -> None:
        with mock.patch.dict(
            os.environ,
            {"VIVADO_LAB_REG_PROFILE": "/old.tcl", "XSDB_PROFILE": "/also-old.tcl"},
        ):
            cleared = gui.session_environ(None)
            self.assertNotIn("VIVADO_LAB_REG_PROFILE", cleared)
            self.assertNotIn("XSDB_PROFILE", cleared)
            chosen = self.tmp / "board.tcl"
            chosen.write_text("", encoding="utf-8")
            env = gui.session_environ(chosen)
            self.assertEqual(env["VIVADO_LAB_REG_PROFILE"], str(chosen))


class SetupWindowTests(unittest.TestCase):
    def setUp(self) -> None:
        import tempfile

        self.tmp = Path(tempfile.mkdtemp(prefix="vlr-gui-"))
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

    def _labelframe_texts(self, widget) -> list[str]:
        from tkinter import ttk

        found: list[str] = []
        for child in widget.winfo_children():
            if isinstance(child, ttk.LabelFrame):
                found.append(str(child.cget("text")))
            found.extend(self._labelframe_texts(child))
        return found

    def test_setup_shows_profile_and_continue_is_visible(self) -> None:
        self.app = gui.App()
        self.app.update_idletasks()
        self.app.update()
        self.assertIn("Board profile (optional)", self._labelframe_texts(self.app))
        buttons = []

        def walk(widget) -> None:
            from tkinter import ttk

            for child in widget.winfo_children():
                if isinstance(child, ttk.Button) and str(child.cget("text")).startswith("Continue"):
                    buttons.append(child)
                walk(child)

        walk(self.app)
        self.assertEqual(len(buttons), 1)
        button = buttons[0]
        self.assertTrue(button.winfo_ismapped())
        bottom = self.app.winfo_rooty() + self.app.winfo_height()
        self.assertLessEqual(button.winfo_rooty() + button.winfo_height(), bottom + 2)

    def test_continue_persists_profile_and_session_env(self) -> None:
        xsdb = self.tmp / "xsdb.bat"
        xsdb.write_text("@echo off\r\n", encoding="utf-8")
        profile = self.tmp / "board.tcl"
        profile.write_text("set ::MB_SMOKE_ADDR 0x1000\n", encoding="utf-8")
        self.app = gui.App()
        self.app.setup_path_var.set(str(xsdb))
        self.app.setup_profile_var.set(str(profile))
        self.app._enter_main()
        self.assertEqual(self.app.profile_path, profile.resolve())
        self.assertEqual(self.app.session.profile, profile.resolve())
        saved = json.loads(gui.config_file().read_text(encoding="utf-8"))
        self.assertEqual(saved["xsdb_bat"], str(xsdb.resolve()))
        self.assertEqual(saved["profile"], str(profile.resolve()))
        env = gui.session_environ(self.app.session.profile)
        self.assertEqual(env["VIVADO_LAB_REG_PROFILE"], str(profile.resolve()))
        self.assertIn(str(profile.resolve()), self.app.log.get("1.0", "end"))

    def test_continue_clears_profile(self) -> None:
        xsdb = self.tmp / "xsdb.bat"
        xsdb.write_text("@echo off\r\n", encoding="utf-8")
        gui.save_config({"xsdb_bat": str(xsdb), "profile": str(self.tmp / "old.tcl")})
        self.app = gui.App()
        self.app.setup_path_var.set(str(xsdb))
        self.app._clear_profile()
        self.app._enter_main()
        saved = json.loads(gui.config_file().read_text(encoding="utf-8"))
        self.assertEqual(saved["profile"], "")
        self.assertIsNone(self.app.session.profile)
        self.assertEqual(self.app.profile_var.get(), "(none)")
        env = gui.session_environ(self.app.session.profile)
        self.assertNotIn("VIVADO_LAB_REG_PROFILE", env)

    def test_invalid_profile_does_not_enter_main(self) -> None:
        xsdb = self.tmp / "xsdb.bat"
        xsdb.write_text("@echo off\r\n", encoding="utf-8")
        warnings: list[tuple] = []
        self.app = gui.App()
        self.app.update_idletasks()
        self.app.setup_path_var.set(str(xsdb))
        self.app.setup_profile_var.set(str(self.tmp / "missing.tcl"))
        with mock.patch.object(gui.messagebox, "showwarning", lambda *args, **kwargs: warnings.append(args)):
            self.app._enter_main()
        self.app.update_idletasks()
        self.assertTrue(warnings)
        self.assertIsNone(self.app.session)
        self.assertTrue(self.app.setup_frame.winfo_ismapped())
        self.assertFalse(self.app.main_frame.winfo_ismapped())


if __name__ == "__main__":
    unittest.main()

# -*- mode: python ; coding: utf-8 -*-
# Windows GUI exe for a lab PC. Build with build_exe.bat.
# Output is dist/VivadoLabReg.exe (gitignored). Do not commit that binary.
#
# Bundled: gui.py, addr_map.py, gui.tcl, tool.tcl, and the Python runtime.
# Not bundled: Vivado Lab / xsdb.bat, cable drivers, profiles/private,
# and %APPDATA%\VivadoLabReg\config.json.
# Install openpyxl before this build if the exe should read .xlsx.
# UPX is off so a lab PC without UPX still produces a working windowed exe.

import importlib.util

from PyInstaller.utils.hooks import collect_submodules

hiddenimports = []
if importlib.util.find_spec("openpyxl") is not None:
    hiddenimports += collect_submodules("openpyxl")

a = Analysis(
    ['gui.py'],
    pathex=[],
    binaries=[],
    datas=[('gui.tcl', '.'), ('tool.tcl', '.')],
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name='VivadoLabReg',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

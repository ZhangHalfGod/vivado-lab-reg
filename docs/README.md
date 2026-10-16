# Docs

**Language / 语言:** Day-to-day English is the [README](../README.md). 中文 GUI 步骤在 [usage-zh.md](usage-zh.md)。

| Topic | Where |
| --- | --- |
| Scan targets, profiles, address map, `--json` | [README.md](../README.md) · [README.zh-CN.md](../README.zh-CN.md) |
| Windows GUI steps | [usage-zh.md](usage-zh.md) |
| Screenshots | [images/gui-walkthrough/](images/gui-walkthrough/) |
| Address map import | [address-map-import.md](address-map-import.md) |
| Board profiles | [profiles/README.md](../profiles/README.md) |
| Agent Skill (`--json`; writes only when asked) | [skills/vivado-lab-reg/SKILL.md](../skills/vivado-lab-reg/SKILL.md) |
| Windows exe | `build_exe.bat` and `VivadoLabReg.spec` write `dist/VivadoLabReg.exe` (not committed). See Packaging in the README. |

Targets come from the JTAG scan (id and name). They are not fixed slots. Smoke addresses come from a board profile. `0x0` or no profile skips that read. The address map fills the Address field. It does not select a target.

## L3

Agents and CI enumerate targets and peek with `xsdb.sh --json` / `xsdb.cmd --json`. `bash tests/test_json_cli.sh` does not need a board. The [Skill](../skills/vivado-lab-reg/SKILL.md) keeps writes (`wr`, `jwr`, `wrd`, `jwrd`, and the `#2` forms) behind an explicit request. Humans use the same commands without `--json`, or the GUI.

## L3（中文）

Agent 和 CI 用 `--json` 枚举 target、读寄存器。`bash tests/test_json_cli.sh` 不需要板子。写寄存器受 [Skill](../skills/vivado-lab-reg/SKILL.md) 约束：只有明确要求写时才使用 `wr` / `jwr` / `wrd` / `jwrd` 以及 `#2` 写。人和 GUI 走同一套扫描 target、profile 和地址表；`--json` 只改变输出格式。

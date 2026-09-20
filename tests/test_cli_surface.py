"""walictl's parser surface equals its rows in tools/cli.toml, and the binary behaves as
the CLI vocabulary requires (ops docs/specs/2026-09-20-cli-conventions-design.md).
Fixture: the `env` fixture from test_walictl.py (a config, three wallpapers, XDG dirs)."""
from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
import tomllib
from pathlib import Path

import pytest
from test_walictl import env, load_walictl  # noqa: F401 (env is a fixture)

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "bin" / "walictl"
TABLE = ROOT / "tools" / "cli.toml"

spec = importlib.util.spec_from_file_location("cli_surface", ROOT / "tools" / "cli_surface.py")
cli_surface = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cli_surface)

COMMANDS = sorted(row[1] for row in cli_surface.table_rows(TABLE, "walictl") if row[0] == "command")

# table_rows() strips output/verb/protocol metadata (by design: it's never compared to
# the live parser), so the raw table is read again here to find each command's `output`
# override, if any.
RAW_COMMANDS = tomllib.loads(TABLE.read_text())["cli"]["walictl"]["commands"]

# "variant" and "phone" are group headers: required subparsers make them un-runnable on
# their own (always a usage error), so the output-mode rule never applies to them directly.
NON_LEAF_COMMANDS = {("variant",), ("phone",)}

# Commands that unconditionally reach the Noctalia daemon (current, edit, hide, neighbors,
# and everything routed through navigate(): next/previous/random/earlier/later/observe) or
# unconditionally need real, decodable image bytes (variant preview/apply/reset all call
# image_size()/magick; the `env` fixture's wallpaper files are empty placeholders). The
# `env` fixture has no Noctalia or magick stub, and this file runs walictl as a real
# subprocess (not the in-process FakeNoctalia test_walictl.py uses), so touching the real
# daemon here would be both unsafe (it can drive whatever compositor happens to be
# running) and fixture-dependent. Listed explicitly and cross-checked against the table
# below rather than skipped silently.
JSON_UNSAFE_COMMANDS = {
    ("current",), ("edit",), ("hide",), ("neighbors",),
    ("next",), ("previous",), ("random",), ("earlier",), ("later",), ("observe",),
    ("variant", "preview"), ("variant", "apply"), ("variant", "reset"),
}


def run(*args: str, extra: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run([sys.executable, str(SCRIPT), *args], capture_output=True, text=True, check=False,
                          env={**os.environ, **(extra or {})})


def test_surface_equals_table():
    live = cli_surface.argparse_rows(load_walictl().build_parser())
    assert cli_surface.diff(live, cli_surface.table_rows(TABLE, "walictl")) == []


@pytest.mark.parametrize("path", [()] + COMMANDS, ids=lambda p: " ".join(p) or "root")
def test_help_on_every_command(path, env):  # noqa: F811 (env is the imported fixture)
    for flag in ("--help", "-h"):
        out = run(*path, flag)
        assert out.returncode == 0 and out.stdout and out.stderr == "", (path, flag)
    if path:
        assert run("help", *path).stdout == run(*path, "--help").stdout


def test_version(env):  # noqa: F811 (env is the imported fixture)
    for flag in ("--version", "-V"):
        out = run(flag)
        assert out.returncode == 0 and out.stdout.startswith("walictl ")


@pytest.mark.parametrize("args", [["bogus"], ["favorites", "--bogus"], ["unhide"], ["help", "bogus"]])
def test_usage_errors_exit_two(args, env):  # noqa: F811 (env is the imported fixture)
    out = run(*args)
    assert out.returncode == 2 and out.stdout == "" and out.stderr.strip()
    assert len(out.stderr.strip().splitlines()) <= 2


def test_global_routing(env):  # noqa: F811 (env is the imported fixture)
    for args in (["--json", "favorites"], ["favorites", "--json"]):
        assert isinstance(json.loads(run(*args).stdout), dict), args
    for args in (["--pretty", "favorites"], ["favorites", "--pretty"]):
        out = run(*args)
        assert out.returncode == 0
        with pytest.raises(json.JSONDecodeError):
            json.loads(out.stdout or "x")
    assert run("--json", "favorites", "--pretty").returncode == 2


def test_output_default_and_precedence(env):  # noqa: F811 (env is the imported fixture)
    unflagged = run("favorites")
    with pytest.raises(json.JSONDecodeError):
        json.loads(unflagged.stdout or "x")
    assert isinstance(json.loads(run("favorites", extra={"WALICTL_FORMAT": "json"}).stdout), dict)
    pretty = run("--pretty", "favorites", extra={"WALICTL_FORMAT": "json"})
    with pytest.raises(json.JSONDecodeError):
        json.loads(pretty.stdout or "x")


def test_failures_exit_one_and_json_error_object(env):  # noqa: F811 (env is the imported fixture)
    out = run("favorite", "no-such-photo")
    assert out.returncode == 1 and "unknown photo id" in out.stderr
    out = run("--json", "favorite", "no-such-photo")
    assert out.returncode == 1 and out.stdout == ""
    error = json.loads(out.stderr)["error"]
    assert isinstance(error["kind"], str) and isinstance(error["detail"], str)


def test_walictl_has_no_enum_rows():
    # the enum-baseline map is empty here on purpose; a new enum binding must add both
    assert not any(r[0] in ("option", "arg") and "enum" in r for r in cli_surface.table_rows(TABLE, "walictl"))


def test_color(env):  # noqa: F811 (env is the imported fixture)
    assert run("--color", "never", "favorites").returncode == 0
    assert run("favorites", "--color", "never").returncode == 0
    assert run("--color", "sometimes", "favorites").returncode == 2
    assert run("favorites", extra={"WALICTL_COLOR": "always"}).returncode == 0


def test_completion_callback_and_scripts(env, tmp_path):  # noqa: F811 (env is the imported fixture)
    def candidates(words, index):
        out = run("--", *words, extra={"WALICTL_COMPLETE": "zsh", "WALICTL_COMPLETE_INDEX": str(index)})
        assert out.returncode == 0
        return [line.split("\t")[0] for line in out.stdout.splitlines()]
    root = candidates(["walictl", ""], 1)
    for name in ("current", "favorites", "next", "random", "variant", "phone", "help"):
        assert name in root
    assert "show" in candidates(["walictl", "variant", ""], 2)
    assert "--limit" in candidates(["walictl", "neighbors", "--"], 2)
    zsh = tmp_path / "_walictl"
    zsh.write_text(run(extra={"WALICTL_COMPLETE": "zsh"}).stdout)
    out = subprocess.run(["zsh", "-f", "-c", f"autoload -Uz compinit; compinit -D -u; source {zsh}; print -r -- ${{_comps[walictl]}}"], capture_output=True, text=True, check=False)
    assert out.stdout.strip() == "_walictl", out.stderr
    bash = tmp_path / "walictl.bash"
    bash.write_text(run(extra={"WALICTL_COMPLETE": "bash"}).stdout)
    assert subprocess.run(["bash", "-c", f"source {bash}; complete -p walictl"], capture_output=True, check=False).returncode == 0


def test_json_unsafe_commands_match_the_table():
    """JSON_UNSAFE_COMMANDS is exactly every leaf command this file doesn't exercise
    below, so a new command row can't silently go uncovered: it must be added to one
    list or the other."""
    all_leaves = {tuple(row["path"]) for row in RAW_COMMANDS} - NON_LEAF_COMMANDS
    exercised = {path for path, *_ in OUTPUT_MODE_CASES}
    assert all_leaves - exercised == JSON_UNSAFE_COMMANDS
    assert exercised & JSON_UNSAFE_COMMANDS == set()


def test_no_command_overrides_the_cli_default_output():
    # the acceptance matrix's output-mode rule ("--json emits exactly one JSON value on
    # stdout") applies to a command as given, unless its row overrides the CLI default
    # with `output`; walictl's table has none, so the rule applies to every command here.
    assert not any("output" in row for row in RAW_COMMANDS)


# (path, argv-after-the-command, setup) for every command row without an `output`
# override that can run against the `env` fixture without a Noctalia daemon or real
# image bytes. `setup` prepares config/data these particular commands need; commands
# that need nothing beyond `env` use a no-op.
def _no_setup(env, tmp_path):  # noqa: F811 (env is the imported fixture)
    pass


def _setup_variant_and_phone(env, tmp_path):  # noqa: F811 (env is the imported fixture)
    config = env["config_home"] / "wali" / "config.toml"
    phone_dir = tmp_path / "phone"
    config.write_text(
        config.read_text() + f'edits_file = "{tmp_path / "edits.json"}"\n[phone]\ndir = "{phone_dir}"\noutput = "90x200"\n'
    )
    # phone sync requires the favorites file to exist; variant show doesn't care.
    env["favorites"].write_text(json.dumps({"version": 2, "favorites": {}, "hidden": {}}))


def _setup_hidden_photo(env, tmp_path):  # noqa: F811 (env is the imported fixture)
    env["favorites"].write_text(json.dumps({"version": 2, "favorites": {}, "hidden": {"PXL_20210609_120000000": {"added": "T"}}}))


def _setup_import_source(env, tmp_path):  # noqa: F811 (env is the imported fixture)
    (tmp_path / "legacy-favorites.txt").write_text(str(env["wallpapers"] / "PXL_20220402_162957459.jpg") + "\n")


OUTPUT_MODE_CASES = [
    (("favorites",), ["favorites"], _no_setup),
    (("hidden",), ["hidden"], _no_setup),
    (("favorite",), ["favorite", "PXL_20210608_111152739"], _no_setup),
    (("unhide",), ["unhide", "PXL_20210609_120000000"], _setup_hidden_photo),
    (("import-favorites",), ["import-favorites", "PLACEHOLDER", "--force"], _setup_import_source),
    (("phone", "sync"), ["phone", "sync", "--dry-run"], _setup_variant_and_phone),
    (("variant", "show"), ["variant", "show", "PXL_20220402_162957459"], _setup_variant_and_phone),
]


@pytest.mark.parametrize("path,argv,setup", OUTPUT_MODE_CASES, ids=[" ".join(argv) for _, argv, _ in OUTPUT_MODE_CASES])
def test_output_json_for_every_command_without_an_output_override(path, argv, setup, env, tmp_path):  # noqa: F811 (env is the imported fixture)
    setup(env, tmp_path)
    argv = [
        str(tmp_path / "legacy-favorites.txt") if word == "PLACEHOLDER" else word
        for word in argv
    ]
    out = run(*argv, "--json")
    assert out.returncode == 0, (path, out.stderr)
    json.loads(out.stdout)  # exactly one JSON value: raises on anything else (or nothing)

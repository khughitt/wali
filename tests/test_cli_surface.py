"""walictl's parser surface equals its rows in tools/cli.toml, and the binary behaves as
the CLI vocabulary requires (ops docs/specs/2026-09-20-cli-conventions-design.md).
Fixture: the `env` fixture from test_walictl.py (a config, three wallpapers, XDG dirs)."""
from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
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

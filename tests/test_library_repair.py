from __future__ import annotations

import importlib.machinery
import importlib.util
import shutil
import subprocess
import sys
from pathlib import Path
from types import ModuleType

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "library-repair"
ORIGINAL_ID = "PXL_20210622_004806837"

needs_magick = pytest.mark.skipif(shutil.which("magick") is None, reason="ImageMagick 7 is not installed")


def load_repair() -> ModuleType:
    loader = importlib.machinery.SourceFileLoader("library_repair", str(SCRIPT))
    spec = importlib.util.spec_from_loader("library_repair", loader)
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules["library_repair"] = module
    loader.exec_module(module)
    return module


@pytest.fixture
def repair(monkeypatch: pytest.MonkeyPatch) -> ModuleType:
    module = load_repair()
    monkeypatch.setattr(module, "LIBRARY_WIDTH", 120)
    return module


@pytest.fixture
def env(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> dict[str, Path]:
    tmp_path = tmp_path.resolve()
    library, archive = tmp_path / "3440", tmp_path / "archive"
    library.mkdir()
    (archive / "2021" / "06").mkdir(parents=True)
    config_home = tmp_path / "config"
    (config_home / "wali").mkdir(parents=True)
    (config_home / "wali" / "config.toml").write_text(
        f'wallpaper_dir = "{library}"\n'
        f'favorites_file = "{tmp_path / "favorites.json"}"\n'
        f'archive_root = "{archive}"\n'
    )
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    jpegoptim = bin_dir / "jpegoptim"
    jpegoptim.write_text(f'#!/bin/sh\nprintf "%s\\n" "$*" >> "{tmp_path / "jpegoptim.log"}"\n')
    jpegoptim.chmod(0o755)
    monkeypatch.setenv("PATH", f"{bin_dir}:{Path(shutil.which('magick') or '/usr/bin/magick').parent}:/usr/bin:/bin")
    monkeypatch.setenv("XDG_CONFIG_HOME", str(config_home))
    return {"library": library, "archive": archive, "original": archive / "2021" / "06" / f"{ORIGINAL_ID}.jpg",
            "current": library / f"{ORIGINAL_ID}.jpg", "backup": tmp_path / "backup", "plan": tmp_path / "plan.tsv",
            "jpegoptim_log": tmp_path / "jpegoptim.log"}


def with_orientation(jpeg: bytes, value: int) -> bytes:
    """Splice a big-endian EXIF APP1 carrying only Orientation after the SOI."""
    tiff = (b"MM\x00\x2a\x00\x00\x00\x08" + b"\x00\x01"
            + b"\x01\x12\x00\x03\x00\x00\x00\x01" + value.to_bytes(2, "big") + b"\x00\x00"
            + b"\x00\x00\x00\x00")
    payload = b"Exif\x00\x00" + tiff
    return jpeg[:2] + b"\xff\xe1" + (len(payload) + 2).to_bytes(2, "big") + payload + jpeg[2:]


def make_photo(path: Path, orientation: int | None = None) -> None:
    """A 160x90 landscape (stored pixels) with a distinct quadrant, so every rotation differs."""
    subprocess.run(["magick", "-size", "160x90", "gradient:gray20-gray80", "-fill", "white",
                    "-draw", "rectangle 0,0 50,30", "-fill", "black", "-draw", "rectangle 120,60 159,89",
                    "-quality", "95", str(path)], check=True)
    if orientation is not None:
        path.write_bytes(with_orientation(path.read_bytes(), orientation))


def identify(path: Path) -> tuple[str, str]:
    out = subprocess.run(["magick", "identify", "-format", "%wx%h %[orientation]", str(path)],
                         check=True, capture_output=True, text=True).stdout
    size, orientation = out.split()
    return size, orientation


# --- plan -------------------------------------------------------------------


def test_parse_plan_reads_actions_comments_and_blank_lines(repair: ModuleType) -> None:
    plan = repair.parse_plan(
        "# header\n\nPXL_20210622_004806837\tupright\nPXL_20210716_135115099 keep  # a note\n"
        "PXL_20230421_154832081 rotate=270\n"
    )
    assert plan == [
        repair.Entry("PXL_20210622_004806837", "upright"),
        repair.Entry("PXL_20210716_135115099", "keep"),
        repair.Entry("PXL_20230421_154832081", "rotate", 270),
    ]


@pytest.mark.parametrize(
    ("text", "message"),
    [
        ("PXL_20210622_004806837 sideways\n", "unknown action 'sideways'"),
        ("PXL_20210622_004806837 rotate=45\n", "unknown action 'rotate=45'"),
        ("PXL_20210622_004806837 rotate=x\n", "unknown action 'rotate=x'"),
        ("PXL_20210622_004806837\n", "plan line 1: expected"),
        ("PXL_20210622_004806837 keep\nPXL_20210622_004806837 upright\n", "plan line 2: PXL_20210622_004806837 is listed twice"),
        ("../evil keep\n", "photo id"),
    ],
)
def test_parse_plan_rejects_bad_lines(repair: ModuleType, text: str, message: str) -> None:
    with pytest.raises((repair.RepairError, repair.walictl.WalictlError), match=message):
        repair.parse_plan(text)


def test_render_ops(repair: ModuleType) -> None:
    assert repair.render_ops(repair.Entry("a", "upright"), None) == ["-auto-orient"]
    assert repair.render_ops(repair.Entry("a", "keep"), 90) == ["-rotate", "90", "-orient", "top-left"]
    assert repair.render_ops(repair.Entry("a", "rotate", 0), 0) == ["-orient", "top-left"]


# --- apply ------------------------------------------------------------------


@needs_magick
def test_upright_applies_the_orientation_and_backs_up_once(
    repair: ModuleType, env: dict[str, Path], capsys: pytest.CaptureFixture[str]
) -> None:
    make_photo(env["original"], orientation=6)
    shutil.copy(env["original"], env["current"])
    before = env["current"].read_bytes()
    env["plan"].write_text(f"{ORIGINAL_ID} upright\n")
    argv = ["apply", str(env["plan"]), "--backup", str(env["backup"])]

    assert repair.main(argv) == 0
    assert identify(env["current"]) == ("120x213", "TopLeft")
    assert (env["backup"] / env["current"].name).read_bytes() == before
    assert env["jpegoptim_log"].read_text().startswith("--strip-none ")
    assert "repaired 1" in capsys.readouterr().out
    assert sorted(p.name for p in env["library"].iterdir()) == [env["current"].name]

    assert repair.main(argv) == 0
    assert (env["backup"] / env["current"].name).read_bytes() == before, "a rerun must keep the first backup"


@needs_magick
@pytest.mark.parametrize("rotation", [90, 180, 270])
def test_keep_finds_the_rotation_and_drops_a_baked_crop(
    repair: ModuleType, env: dict[str, Path], capsys: pytest.CaptureFixture[str], rotation: int
) -> None:
    # What wali_rotate did: rotate the stored pixels, center-crop to 21:9, keep the flag.
    make_photo(env["original"], orientation=6)
    subprocess.run(["magick", str(env["original"]), "-rotate", str(rotation), "-gravity", "center",
                    "-crop", "21:9", "+repage", "-resize", "344x", str(env["current"])], check=True)
    env["plan"].write_text(f"{ORIGINAL_ID} keep\n")

    assert repair.main(["apply", str(env["plan"]), "--backup", str(env["backup"])]) == 0
    assert f"keep: rotate {rotation}" in capsys.readouterr().out
    expected = "120x68" if rotation == 180 else "120x213"
    assert identify(env["current"]) == (expected, "TopLeft")


@needs_magick
def test_keep_of_a_sideways_file_keeps_the_stored_pixels(repair: ModuleType, env: dict[str, Path]) -> None:
    make_photo(env["original"], orientation=6)
    subprocess.run(["magick", str(env["original"]), "-resize", "344x", str(env["current"])], check=True)
    assert identify(env["current"])[1] == "RightTop"
    env["plan"].write_text(f"{ORIGINAL_ID} keep\n")

    assert repair.main(["apply", str(env["plan"]), "--backup", str(env["backup"])]) == 0
    assert identify(env["current"]) == ("120x68", "TopLeft")


@needs_magick
def test_an_ambiguous_match_fails_before_any_write(
    repair: ModuleType, env: dict[str, Path], capsys: pytest.CaptureFixture[str]
) -> None:
    subprocess.run(["magick", "-size", "160x90", "xc:gray50", str(env["original"])], check=True)
    shutil.copy(env["original"], env["current"])
    env["plan"].write_text(f"{ORIGINAL_ID} keep\n")

    assert repair.main(["apply", str(env["plan"]), "--backup", str(env["backup"])]) == 1
    assert "ambiguous match" in capsys.readouterr().err
    assert not env["backup"].exists()


@needs_magick
def test_the_whole_plan_resolves_before_anything_is_written(
    repair: ModuleType, env: dict[str, Path], capsys: pytest.CaptureFixture[str]
) -> None:
    make_photo(env["original"], orientation=3)
    shutil.copy(env["original"], env["current"])
    before = env["current"].read_bytes()
    (env["library"] / "PXL_20210623_000000000.jpg").touch()  # no original
    env["plan"].write_text(f"{ORIGINAL_ID} upright\nPXL_20210623_000000000 upright\nPXL_20210624_000000000 upright\n")

    assert repair.main(["apply", str(env["plan"]), "--backup", str(env["backup"])]) == 1
    err = capsys.readouterr().err
    assert "PXL_20210623_000000000: no archive original" in err
    assert "PXL_20210624_000000000: not in the library" in err
    assert env["current"].read_bytes() == before
    assert not env["backup"].exists()


@needs_magick
def test_dry_run_reports_and_writes_nothing(
    repair: ModuleType, env: dict[str, Path], capsys: pytest.CaptureFixture[str]
) -> None:
    make_photo(env["original"], orientation=3)
    shutil.copy(env["original"], env["current"])
    before = env["current"].read_bytes()
    env["plan"].write_text(f"{ORIGINAL_ID} upright\n")

    assert repair.main(["apply", str(env["plan"]), "--backup", str(env["backup"]), "--dry-run"]) == 0
    assert capsys.readouterr().out.splitlines() == [f"[1/1] {ORIGINAL_ID} upright", "would repair 1"]
    assert env["current"].read_bytes() == before
    assert not env["backup"].exists()


def test_a_backup_inside_the_library_is_refused(
    repair: ModuleType, env: dict[str, Path], capsys: pytest.CaptureFixture[str]
) -> None:
    env["plan"].write_text("")
    assert repair.main(["apply", str(env["plan"]), "--backup", str(env["library"] / "old")]) == 1
    assert "backup directory is inside the library" in capsys.readouterr().err


def test_a_host_without_the_archive_is_refused(
    repair: ModuleType, env: dict[str, Path], tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    config = tmp_path / "config" / "wali" / "config.toml"
    config.write_text("\n".join(line for line in config.read_text().splitlines() if "archive_root" not in line))
    env["plan"].write_text("")
    assert repair.main(["apply", str(env["plan"]), "--backup", str(env["backup"])]) == 1
    assert "archive_root is required" in capsys.readouterr().err


# --- audit ------------------------------------------------------------------


@needs_magick
def test_audit_lists_rotated_files_until_they_are_repaired(
    repair: ModuleType, env: dict[str, Path], capsys: pytest.CaptureFixture[str]
) -> None:
    make_photo(env["current"], orientation=8)
    make_photo(env["library"] / "PXL_20210623_000000000.jpg")
    make_photo(env["library"] / "PXL_20210624_000000000.jpg", orientation=1)

    assert repair.main(["audit"]) == 1
    out = capsys.readouterr().out.splitlines()
    assert out == [f"{ORIGINAL_ID}.jpg\tLeftBottom", "1 of 3 library files carry an EXIF rotation"]

    make_photo(env["original"], orientation=8)
    env["plan"].write_text(f"{ORIGINAL_ID} upright\n")
    assert repair.main(["apply", str(env["plan"]), "--backup", str(env["backup"])]) == 0
    capsys.readouterr()
    assert repair.main(["audit"]) == 0
    assert capsys.readouterr().out.splitlines() == ["0 of 3 library files carry an EXIF rotation"]

# Phone Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `walictl phone sync` mirrors the favorites set into a Dropbox folder as centre-cropped phone-sized renders, with a manifest that re-renders when the source or output changes, run nightly by a systemd timer on titan.

**Architecture:** `bin/walictl` gains a `[phone]` config table, a `phone.json` manifest in the state dir keyed by photo id and holding the source identity (path, size, mtime_ns) and output size, one `magick` call per render into a `<id>.jpg.tmp` temporary (`jpg:`-prefixed so it is still JPEG) then `os.replace`, and a plan/execute split so `--dry-run` reports without touching anything. Everything runs under `phone.lock`. Two units in `systemd/` and a `dots` task wire it into titan.

**Tech Stack:** Python 3.11+ standard library, `subprocess` to `magick` (ImageMagick 7); pytest with a `magick` stub on `PATH` plus one real-`magick` test; `just verify`.

**Spec:** `docs/specs/2026-09-19-phone-sync-design.md`. Task `wali-8ad74b` is the parent of every step below; goal `wali-51adcc` owns it and the `dots` piece.

## Global Constraints

- `bin/walictl` stays standard-library only; `pyproject.toml` declares no runtime dependencies.
- Config: `[phone] dir = "<path>"` and `output = "WIDTHxHEIGHT"`, both required inside the table. Errors: `config table [phone] must be a table`, `config key phone.<key> is required`, `config key phone.dir must be a non-empty string`, `config key phone.output must be WIDTHxHEIGHT with positive integers`. Any `phone` command with no table: `config table [phone] is required`.
- `walictl` owns every non-dotfile `*.jpg` in `[phone] dir` and its own temporaries `*.jpg.tmp` (written as `jpg:<path>` so the encoder still produces JPEG; the `.tmp` suffix can never be a published render, whose suffix is always `.jpg`); it never touches any other entry there — dotfiles (including a `.private.jpg`), other extensions, subdirectories — and creates an empty `.nomedia` once.
- The destination type is validated in both modes without creating it: an existing non-directory at `[phone] dir` is `phone.dir is not a directory: <path>`, on `--dry-run` too.
- The ratings file must be *read* for `phone sync`: `Ratings.load(path, required=True)` raises `favorites file not found: <path>` when `read_json` returns `None`. No `exists()` pre-check.
- Manifest `$XDG_STATE_HOME/wali/phone.json`: `{"version": 1, "renders": {"<id>": {"source": str, "size": int, "mtime_ns": int, "output": "WxH"}}}`. A render is current iff `dir/<id>.jpg` exists and the manifest entry equals the current identity. Missing/malformed manifest (invalid JSON, not an object, wrong version, invalid UTF-8) → a warning on stderr and an empty manifest, never an error. Interruption between an image write and its manifest write leaves a mismatch that the next run treats as stale.
- Render argv, exactly: `magick <source> -auto-orient -strip -resize WxH^ -gravity center -extent WxH -quality 88 jpg:<dir>/<id>.jpg.tmp`, then `os.replace` to `<dir>/<id>.jpg`. `magick command not found` (checked with `shutil.which` before any mutation on a non-dry run) and `magick failed: <stderr>` (stops the run, the temporary removed, prior renders and removals kept, no summary printed).
- Order inside the lock: prepare dir (mkdir, `.nomedia`, drop non-dotfile `*.jpg.tmp`) → load manifest → plan → removals (each followed by a manifest save) → renders in sorted id order (each followed by a manifest save) → summary. `--dry-run` skips prepare, removals, renders, and manifest writes.
- Summary: `rendered N, removed M, kept K, skipped S` on stdout, or with `--json` `{"ok": true, "rendered": [ids], "removed": [ids], "kept": K, "skipped": [{"id": ..., "reason": "missing from library"}]}`. Each skip is also `skipped <id>: missing from library` on stderr. Skips do not change the exit code.
- Every failure is one line on stderr, exit 1, through the existing `main` handler.
- Photo ids from the ratings file pass `check_photo_id` before they build a path.
- Run all commands from the worktree root `.worktrees/phone-sync/`. `just verify` passes before each commit. `tasks start <step-id>` before a task, `tasks done <step-id> "<what landed>"` in the same commit as its code.

---

### Task 1: Config `[phone]` and a keyed `parse_output`

**Files:**
- Modify: `bin/walictl` (`Config`, new `PhoneConfig`, `load_config`, `parse_output`, new `load_phone_config`)
- Test: `tests/test_walictl.py` (config tests; the positional `Config(...)` call in `test_resolve_variant_and_source`)

**Interfaces:**
- Produces: `PhoneConfig(dir: Path, output: tuple[int, int])` (frozen dataclass); `Config.phone: PhoneConfig | None` as the field after `edits`; `parse_output(value: object, key: str = "edits.output") -> tuple[int, int]`; `load_phone_config(raw: dict[str, object]) -> PhoneConfig | None`.
- Consumes: `_expand`, `WalictlError`.

- [x] **Step 1: Write the failing tests**

Add `import os` to the test module's imports (used by later tasks too). Add a helper beside `run_cli`:

```python
def phone_env(env: dict[str, Path], output: str = "90x200") -> Path:
    """Switch [phone] on for a test; returns the mirrored folder (not created)."""
    folder = env["wallpapers"].parent / "phone"
    config = env["config_home"] / "wali" / "config.toml"
    config.write_text(config.read_text() + f'[phone]\ndir = "{folder}"\noutput = "{output}"\n')
    return folder
```

In `test_load_config_reads_required_and_optional_keys` add `assert config.phone is None`. In `test_resolve_variant_and_source` change the positional construction to `walictl.Config(config.wallpaper_dir, config.favorites_file, None, None, None, config.sampling)`. Add:

```python
def test_load_config_reads_phone(walictl: ModuleType, env: dict[str, Path]) -> None:
    folder = phone_env(env, "1344x2992")
    config = walictl.load_config(walictl.config_path())
    assert config.phone == walictl.PhoneConfig(dir=folder, output=(1344, 2992))


@pytest.mark.parametrize(
    ("extra", "message"),
    [
        ("phone = 5\n", "config table [phone] must be a table"),
        ('[phone]\noutput = "1x2"\n', "config key phone.dir is required"),
        ('[phone]\ndir = "~/p"\n', "config key phone.output is required"),
        ('[phone]\ndir = ""\noutput = "1x2"\n', "config key phone.dir must be a non-empty string"),
        ('[phone]\ndir = "~/p"\noutput = "wide"\n', "config key phone.output must be WIDTHxHEIGHT"),
        ('[phone]\ndir = "~/p"\noutput = "0x2"\n', "config key phone.output must be WIDTHxHEIGHT"),
    ],
)
def test_invalid_phone_config(walictl: ModuleType, env: dict[str, Path], extra: str, message: str) -> None:
    path = env["config_home"] / "wali" / "config.toml"
    path.write_text(path.read_text() + extra)
    with pytest.raises(walictl.WalictlError, match=re.escape(message)):
        walictl.load_config(path)


def test_parse_output_names_its_key(walictl: ModuleType) -> None:
    assert walictl.parse_output("10x20") == (10, 20)
    with pytest.raises(walictl.WalictlError, match=re.escape("config key edits.output must be WIDTHxHEIGHT")):
        walictl.parse_output("x")
    with pytest.raises(walictl.WalictlError, match=re.escape("config key phone.output must be WIDTHxHEIGHT")):
        walictl.parse_output("x", "phone.output")
```

- [x] **Step 2: Run the tests to verify they fail**

Run: `uv run --frozen pytest -q tests/test_walictl.py -k "phone or parse_output or resolve_variant_and_source"`
Expected: FAIL — `PhoneConfig` has no attribute, `Config.__init__` takes 5 positional arguments, `parse_output()` takes 1 positional argument.

- [x] **Step 3: Implement**

After `EditsConfig`:

```python
@dataclass(frozen=True)
class PhoneConfig:
    dir: Path
    output: tuple[int, int]
```

In `Config`, add `phone: PhoneConfig | None` after `edits`. In `load_config`, add `phone=load_phone_config(raw),` after `edits=load_edits_config(raw),`. Replace `parse_output` and add `load_phone_config` after `load_edits_config`:

```python
def parse_output(value: object, key: str = "edits.output") -> tuple[int, int]:
    match = re.fullmatch(r"(\d+)x(\d+)", value) if isinstance(value, str) else None
    if match is None or int(match[1]) <= 0 or int(match[2]) <= 0:
        raise WalictlError(f"config key {key} must be WIDTHxHEIGHT with positive integers")
    return int(match[1]), int(match[2])


def load_phone_config(raw: dict[str, object]) -> PhoneConfig | None:
    table = raw.get("phone")
    if table is None:
        return None
    if not isinstance(table, dict):
        raise WalictlError("config table [phone] must be a table")
    for key in ("dir", "output"):
        if key not in table:
            raise WalictlError(f"config key phone.{key} is required")
    return PhoneConfig(dir=_expand(table["dir"], "phone.dir"), output=parse_output(table["output"], "phone.output"))
```

- [x] **Step 4: Run the tests**

Run: `uv run --frozen pytest -q tests/test_walictl.py`
Expected: all PASS.

- [x] **Step 5: Verify and commit**

```bash
just verify
tasks done wali-59e9ad "[phone] config table and keyed parse_output"
git add bin/walictl tests/test_walictl.py tasks
git commit -m "feat(walictl): [phone] config table"
```

---

### Task 2: Required ratings, the manifest, and source identity

**Files:**
- Modify: `bin/walictl` (`Ratings.load`; new `# --- phone ---` section after the ratings section with `phone_lock`, `phone_manifest_path`, `source_identity`, `PhoneManifest`)
- Test: `tests/test_walictl.py`

**Interfaces:**
- Consumes: `read_json`, `write_json_atomic`, `state_dir`, `WalictlError`.
- Produces: `Ratings.load(path, *, required: bool = False)`; `PHONE_MANIFEST_VERSION = 1`; `phone_lock() -> Path` (`state_dir()/"phone.lock"`); `phone_manifest_path() -> Path` (`state_dir()/"phone.json"`); `source_identity(source: Path, output: tuple[int, int]) -> dict[str, object]` with keys `source`, `size`, `mtime_ns`, `output`; `PhoneManifest(renders: dict[str, dict[str, object]])` with `load(path, warn: Callable[[str], None]) -> PhoneManifest` and `save(path) -> None`.

- [x] **Step 1: Write the failing tests**

```python
def test_ratings_load_required_fails_on_the_read(walictl: ModuleType, env: dict[str, Path]) -> None:
    assert walictl.Ratings.load(env["favorites"]).favorites == {}
    with pytest.raises(walictl.WalictlError, match=re.escape(f"favorites file not found: {env['favorites']}")):
        walictl.Ratings.load(env["favorites"], required=True)
    env["favorites"].write_text('{"version": 2, "favorites": {}, "hidden": {}}')
    assert walictl.Ratings.load(env["favorites"], required=True).favorites == {}


def test_phone_paths_live_in_state_dir(walictl: ModuleType, env: dict[str, Path]) -> None:
    assert walictl.phone_lock() == env["state_home"] / "wali" / "phone.lock"
    assert walictl.phone_manifest_path() == env["state_home"] / "wali" / "phone.json"


def test_source_identity_records_path_size_mtime_and_output(walictl: ModuleType, tmp_path: Path) -> None:
    source = tmp_path / "s.jpg"
    source.write_bytes(b"abc")
    os.utime(source, ns=(1_700_000_000_000_000_000, 1_700_000_000_000_000_001))
    assert walictl.source_identity(source, (1344, 2992)) == {
        "source": str(source), "size": 3, "mtime_ns": 1_700_000_000_000_000_001, "output": "1344x2992",
    }


def test_phone_manifest_round_trip_and_recovery(walictl: ModuleType, tmp_path: Path) -> None:
    path = tmp_path / "phone.json"
    warnings: list[str] = []
    assert walictl.PhoneManifest.load(path, warnings.append).renders == {} and warnings == []
    entry = {"source": "/a.jpg", "size": 1, "mtime_ns": 2, "output": "1x2"}
    manifest = walictl.PhoneManifest(renders={"a": entry})
    manifest.save(path)
    assert json.loads(path.read_text()) == {"version": 1, "renders": {"a": entry}}
    assert walictl.PhoneManifest.load(path, warnings.append).renders == {"a": entry} and warnings == []
    path.write_text("{")
    assert walictl.PhoneManifest.load(path, warnings.append).renders == {}
    assert warnings == [f"phone manifest is not valid JSON: {path}; rebuilding"]
    path.write_text('{"version": 2, "renders": {}}')
    assert walictl.PhoneManifest.load(path, warnings.append).renders == {}
    assert warnings[-1] == f"phone manifest is unreadable: {path}; rebuilding"
    path.write_text(json.dumps({"version": 1, "renders": {"a": entry, "b": {"source": "/b.jpg"}, "c": 5}}))
    assert walictl.PhoneManifest.load(path, warnings.append).renders == {"a": entry}
    path.write_bytes(b"\xff\xfe not utf-8")
    assert walictl.PhoneManifest.load(path, warnings.append).renders == {}
    assert warnings[-1] == f"phone manifest is unreadable: {path}; rebuilding"
```

- [x] **Step 2: Run the tests to verify they fail**

Run: `uv run --frozen pytest -q tests/test_walictl.py -k "ratings_load_required or phone_paths or source_identity or phone_manifest"`
Expected: FAIL — unexpected keyword `required`, no attribute `phone_lock`.

- [x] **Step 3: Implement**

In `Ratings.load`:

```python
    @classmethod
    def load(cls, path: Path, *, required: bool = False) -> Ratings:
        payload = read_json(path, "favorites file")
        if payload is None:
            if required:
                raise WalictlError(f"favorites file not found: {path}")
            return cls(favorites={}, hidden={})
```

New section after the favorites section (before `# --- history ---`):

```python
# --- phone ------------------------------------------------------------------

PHONE_MANIFEST_VERSION = 1
PHONE_TMP_SUFFIX = ".jpg.tmp"  # never a published render, whose suffix is always .jpg


def phone_lock() -> Path:
    return state_dir() / "phone.lock"


def phone_manifest_path() -> Path:
    return state_dir() / "phone.json"


def source_identity(source: Path, output: tuple[int, int]) -> dict[str, object]:
    stat = source.stat()
    return {"source": str(source), "size": stat.st_size, "mtime_ns": stat.st_mtime_ns, "output": f"{output[0]}x{output[1]}"}


def _identity_entry(value: object) -> dict[str, object] | None:
    if not isinstance(value, dict):
        return None
    if not (isinstance(value.get("source"), str) and isinstance(value.get("output"), str)):
        return None
    if any(isinstance(value.get(key), bool) or not isinstance(value.get(key), int) for key in ("size", "mtime_ns")):
        return None
    return {key: value[key] for key in ("source", "size", "mtime_ns", "output")}


@dataclass
class PhoneManifest:
    """Which source each phone render was made from. The folder is the truth; this is its record."""

    renders: dict[str, dict[str, object]]

    @classmethod
    def load(cls, path: Path, warn: Callable[[str], None]) -> PhoneManifest:
        try:
            payload = read_json(path, "phone manifest")
        except WalictlError as exc:
            warn(f"{exc}; rebuilding")
            return cls(renders={})
        except UnicodeError:
            warn(f"phone manifest is unreadable: {path}; rebuilding")
            return cls(renders={})
        if payload is None:
            return cls(renders={})
        renders = payload.get("renders")
        if payload.get("version") != PHONE_MANIFEST_VERSION or not isinstance(renders, dict):
            warn(f"phone manifest is unreadable: {path}; rebuilding")
            return cls(renders={})
        checked = {str(photo): entry for photo, value in renders.items() if (entry := _identity_entry(value)) is not None}
        return cls(renders=checked)

    def save(self, path: Path) -> None:
        write_json_atomic(path, {"version": PHONE_MANIFEST_VERSION, "renders": self.renders})
```

- [x] **Step 4: Run the tests**

Run: `uv run --frozen pytest -q tests/test_walictl.py`
Expected: all PASS.

- [x] **Step 5: Verify and commit**

```bash
just verify
tasks done wali-756c72 "Ratings.load required=True, phone manifest and source identity"
git add bin/walictl tests/test_walictl.py tasks
git commit -m "feat(walictl): phone manifest and required ratings read"
```

---

### Task 3: The render

**Files:**
- Modify: `bin/walictl` (phone section: `phone_render`; `import shutil`)
- Test: `tests/test_walictl.py` (a `magick` stub fixture, render tests, one real-magick test)

**Interfaces:**
- Consumes: `PHONE_TMP_SUFFIX`, `WalictlError`.
- Produces: `phone_render(source: Path, target: Path, output: tuple[int, int]) -> None` — renders into `target.with_name(f"{target.stem}{PHONE_TMP_SUFFIX}")` (`PXL_1.jpg` → `PXL_1.jpg.tmp`; `holiday.tmp.jpg` → `holiday.tmp.jpg.tmp`; passed to magick as `jpg:<path>`) then `os.replace`s to `target`. The `magick` fixture (returns the argv log path) and its env knobs `MAGICK_FAIL`, `MAGICK_EXPECT_LOCK` for Task 4.

- [x] **Step 1: Write the failing tests**

The fixture, beside `noctalia`:

```python
@pytest.fixture
def magick(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    """A magick stand-in on PATH: logs argv, writes its last argument, fails when MAGICK_FAIL is set.

    With MAGICK_EXPECT_LOCK set to a lock path it exits 3 unless that lock is held by someone else.
    Returns the argv log; one line per call.
    """
    bin_dir, log = tmp_path / "stub-bin", tmp_path / "magick.log"
    bin_dir.mkdir()
    stub = bin_dir / "magick"
    stub.write_text(
        "#!/usr/bin/env python3\n"
        "import fcntl, os, sys\n"
        f"with open({str(log)!r}, 'a') as handle:\n"
        "    handle.write(' '.join(sys.argv[1:]) + '\\n')\n"
        "lock = os.environ.get('MAGICK_EXPECT_LOCK')\n"
        "if lock:\n"
        "    with open(lock, 'a') as handle:\n"
        "        try:\n"
        "            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)\n"
        "        except BlockingIOError:\n"
        "            pass\n"
        "        else:\n"
        "            sys.stderr.write('lock not held\\n')\n"
        "            sys.exit(3)\n"
        "if os.environ.get('MAGICK_FAIL'):\n"
        "    sys.stderr.write('magick: boom\\n')\n"
        "    sys.exit(1)\n"
        "with open(sys.argv[-1].removeprefix('jpg:'), 'wb') as out:\n"
        "    out.write(b'render:' + sys.argv[1].encode())\n"
    )
    stub.chmod(0o755)
    monkeypatch.setenv("PATH", f"{bin_dir}:{os.environ['PATH']}")
    monkeypatch.delenv("MAGICK_FAIL", raising=False)
    monkeypatch.delenv("MAGICK_EXPECT_LOCK", raising=False)
    return log
```

The tests:

```python
def test_phone_render_argv_and_atomic_publish(walictl: ModuleType, tmp_path: Path, magick: Path) -> None:
    source, target = tmp_path / "src.jpg", tmp_path / "out" / "PXL_1.jpg"
    source.write_bytes(b"x")
    target.parent.mkdir()
    walictl.phone_render(source, target, (90, 200))
    assert target.read_bytes() == b"render:" + str(source).encode()
    assert sorted(p.name for p in target.parent.iterdir()) == ["PXL_1.jpg"]
    assert magick.read_text().splitlines() == [
        f"{source} -auto-orient -strip -resize 90x200^ -gravity center -extent 90x200 -quality 88 jpg:{target.parent / 'PXL_1.jpg.tmp'}"
    ]


def test_phone_render_failure_removes_the_temporary(
    walictl: ModuleType, tmp_path: Path, magick: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    source, target = tmp_path / "src.jpg", tmp_path / "PXL_1.jpg"
    source.write_bytes(b"x")
    target.write_bytes(b"previous")
    monkeypatch.setenv("MAGICK_FAIL", "1")
    with pytest.raises(walictl.WalictlError, match=re.escape("magick failed: magick: boom")):
        walictl.phone_render(source, target, (90, 200))
    assert target.read_bytes() == b"previous"
    assert not (tmp_path / "PXL_1.jpg.tmp").exists()


def test_phone_render_without_magick(walictl: ModuleType, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("PATH", str(tmp_path / "empty"))
    source = tmp_path / "src.jpg"
    source.write_bytes(b"x")
    with pytest.raises(walictl.WalictlError, match="magick command not found"):
        walictl.phone_render(source, tmp_path / "PXL_1.jpg", (90, 200))


@pytest.mark.skipif(shutil.which("magick") is None, reason="ImageMagick 7 is not installed")
def test_phone_render_with_real_magick_crops_to_the_output(walictl: ModuleType, tmp_path: Path) -> None:
    for name, size in (("landscape", "400x300"), ("portrait", "300x400")):
        source = tmp_path / f"{name}.jpg"
        subprocess.run(["magick", "-size", size, "xc:steelblue", str(source)], check=True)
        target = tmp_path / f"{name}-phone.jpg"
        walictl.phone_render(source, target, (90, 200))
        identify = subprocess.run(["magick", "identify", "-format", "%wx%h", str(target)], capture_output=True, text=True, check=True)
        assert identify.stdout == "90x200"
```

Add `import shutil` to the test module.

- [x] **Step 2: Run the tests to verify they fail**

Run: `uv run --frozen pytest -q tests/test_walictl.py -k phone_render`
Expected: FAIL — no attribute `phone_render`.

- [x] **Step 3: Implement**

Add `import shutil` to `bin/walictl`'s imports (alphabetical, after `re`). In the phone section, after `source_identity`:

```python
def phone_render(source: Path, target: Path, output: tuple[int, int]) -> None:
    """One magick call: cover-scale and centre-crop source to output, published atomically as target."""
    size = f"{output[0]}x{output[1]}"
    tmp = target.with_name(f"{target.stem}{PHONE_TMP_SUFFIX}")
    argv = [
        "magick", str(source), "-auto-orient", "-strip",
        "-resize", f"{size}^", "-gravity", "center", "-extent", size,
        "-quality", "88", f"jpg:{tmp}",
    ]
    try:
        result = subprocess.run(argv, capture_output=True, text=True, check=False)
    except FileNotFoundError as exc:
        raise WalictlError("magick command not found") from exc
    if result.returncode != 0:
        tmp.unlink(missing_ok=True)
        raise WalictlError(f"magick failed: {result.stderr.strip()}")
    os.replace(tmp, target)
```

- [x] **Step 4: Run the tests**

Run: `uv run --frozen pytest -q tests/test_walictl.py`
Expected: all PASS (the real-magick test runs on titan, where `magick` is installed).

- [x] **Step 5: Verify and commit**

```bash
just verify
tasks done wali-3f1e03 "phone_render: one magick call, atomic publish, stub and real-magick tests"
git add bin/walictl tests/test_walictl.py tasks
git commit -m "feat(walictl): phone render via magick"
```

---

### Task 4: `walictl phone sync`

**Files:**
- Modify: `bin/walictl` (phone section: `PhonePlan`, `phone_renders`, `phone_plan`, `prepare_phone_dir`, `cmd_phone_sync`, `cmd_phone`; `COMMANDS`; `build_parser`)
- Test: `tests/test_walictl.py`

**Interfaces:**
- Consumes: `PhoneConfig`, `Config.phone`, `Ratings.load(required=True)`, `PhoneManifest`, `source_identity`, `phone_render`, `phone_lock`, `phone_manifest_path`, `resolve_source`, `scan_library`, `check_photo_id`, `locked`, the `magick` fixture and `phone_env` helper.
- Produces: `PhonePlan(render: list[tuple[str, Path]], remove: list[str], kept: list[str], skipped: list[str])`; `phone_renders(directory: Path) -> dict[str, Path]`; `phone_plan(config: Config, phone: PhoneConfig, ratings: Ratings, manifest: PhoneManifest, library: dict[str, Path], *, force: bool) -> PhonePlan`; `prepare_phone_dir(directory: Path) -> None`; `cmd_phone_sync`, `cmd_phone`; parser `phone sync [--dry-run] [--force] [--json]` with `args.phone_command`.

- [x] **Step 1: Write the failing tests**

A ratings helper beside `phone_env`:

```python
def write_ratings(env: dict[str, Path], favorites: list[str], hidden: list[str] = []) -> None:
    payload = {
        "version": 2,
        "favorites": {photo: {"added": "T"} for photo in favorites},
        "hidden": {photo: {"added": "T"} for photo in hidden},
    }
    env["favorites"].write_text(json.dumps(payload))
```

The tests. `PXL_20210608_111152739` has an archive original in `env`; `PXL_20210609_120000000` and `PXL_20220402_162957459` are library-only.

```python
ORIGINAL, LIBRARY_ONLY, OTHER = "PXL_20210608_111152739", "PXL_20210609_120000000", "PXL_20220402_162957459"


def test_phone_sync_requires_the_config_table(walictl: ModuleType, env: dict[str, Path]) -> None:
    code, _, stderr = run_cli(walictl, ["phone", "sync"])
    assert code == 1 and stderr == "config table [phone] is required\n"


def test_phone_sync_requires_the_ratings_file(walictl: ModuleType, env: dict[str, Path], magick: Path) -> None:
    folder = phone_env(env)
    folder.mkdir()
    (folder / f"{OTHER}.jpg").write_bytes(b"keep")
    code, stdout, stderr = run_cli(walictl, ["phone", "sync"])
    assert code == 1 and stderr == f"favorites file not found: {env['favorites']}\n" and stdout == ""
    assert (folder / f"{OTHER}.jpg").read_bytes() == b"keep"
    assert not magick.exists()


def test_phone_sync_mirrors_favorites(walictl: ModuleType, env: dict[str, Path], magick: Path) -> None:
    folder = phone_env(env)
    folder.mkdir()
    (folder / "stale.jpg").write_bytes(b"old")
    (folder / "PXL_x.jpg.tmp").write_bytes(b"half")
    (folder / "holiday.tmp.jpg").write_bytes(b"a render whose id ends in .tmp")
    (folder / ".private.jpg").write_bytes(b"dotfile")
    (folder / ".private.jpg.tmp").write_bytes(b"dotfile")
    (folder / "notes.txt").write_text("mine")
    (folder / "photo.png").write_bytes(b"png")
    (folder / "sub").mkdir()
    write_ratings(env, [LIBRARY_ONLY, ORIGINAL, "holiday.tmp"], hidden=[OTHER])
    code, stdout, stderr = run_cli(walictl, ["phone", "sync"])
    assert (code, stdout, stderr) == (0, "rendered 2, removed 1, kept 0, skipped 1\n", "skipped holiday.tmp: missing from library\n")
    original = env["archive"] / "2021" / "06" / f"{ORIGINAL}.jpg"
    assert (folder / f"{ORIGINAL}.jpg").read_bytes() == b"render:" + str(original).encode()
    assert (folder / f"{LIBRARY_ONLY}.jpg").read_bytes() == b"render:" + str(env["wallpapers"] / f"{LIBRARY_ONLY}.jpg").encode()
    assert sorted(p.name for p in folder.iterdir()) == [
        ".nomedia", ".private.jpg", ".private.jpg.tmp", f"{ORIGINAL}.jpg", f"{LIBRARY_ONLY}.jpg", "holiday.tmp.jpg", "notes.txt", "photo.png", "sub",
    ]
    lines = magick.read_text().splitlines()
    assert [line.split()[0] for line in lines] == [str(original), str(env["wallpapers"] / f"{LIBRARY_ONLY}.jpg")]
    assert all("-resize 90x200^ -gravity center -extent 90x200 -quality 88" in line for line in lines)
    manifest = json.loads((env["state_home"] / "wali" / "phone.json").read_text())
    assert manifest["version"] == 1 and sorted(manifest["renders"]) == [ORIGINAL, LIBRARY_ONLY]
    assert manifest["renders"][ORIGINAL] == walictl.source_identity(original, (90, 200))
    code, stdout, _ = run_cli(walictl, ["phone", "sync"])
    assert (code, stdout) == (0, "rendered 0, removed 0, kept 2, skipped 1\n")
    assert len(magick.read_text().splitlines()) == 2


def test_phone_sync_skips_favorites_missing_from_library(walictl: ModuleType, env: dict[str, Path], magick: Path) -> None:
    phone_env(env)
    write_ratings(env, ["PXL_20300101_000000000", ORIGINAL])
    code, stdout, stderr = run_cli(walictl, ["phone", "sync", "--json"])
    assert code == 0 and stderr == "skipped PXL_20300101_000000000: missing from library\n"
    assert json.loads(stdout) == {
        "ok": True, "rendered": [ORIGINAL], "removed": [], "kept": 0,
        "skipped": [{"id": "PXL_20300101_000000000", "reason": "missing from library"}],
    }


def test_phone_sync_rejects_a_path_like_favorite(walictl: ModuleType, env: dict[str, Path], magick: Path) -> None:
    phone_env(env)
    write_ratings(env, ["../victim"])
    code, _, stderr = run_cli(walictl, ["phone", "sync"])
    assert code == 1 and stderr.startswith("favorite id must be a single file name stem")


def test_phone_sync_rerenders_when_the_original_appears(walictl: ModuleType, env: dict[str, Path], magick: Path) -> None:
    folder = phone_env(env)
    write_ratings(env, [LIBRARY_ONLY])
    assert run_cli(walictl, ["phone", "sync"])[1] == "rendered 1, removed 0, kept 0, skipped 0\n"
    original = env["archive"] / "2021" / "06" / f"{LIBRARY_ONLY}.jpg"
    original.write_bytes(b"full-size")
    assert run_cli(walictl, ["phone", "sync"])[1] == "rendered 1, removed 0, kept 0, skipped 0\n"
    assert (folder / f"{LIBRARY_ONLY}.jpg").read_bytes() == b"render:" + str(original).encode()
    assert run_cli(walictl, ["phone", "sync"])[1] == "rendered 0, removed 0, kept 1, skipped 0\n"


def test_phone_sync_rerenders_on_source_output_or_force(walictl: ModuleType, env: dict[str, Path], magick: Path) -> None:
    phone_env(env)
    write_ratings(env, [ORIGINAL])
    sync = lambda *extra: run_cli(walictl, ["phone", "sync", *extra])[1]  # noqa: E731
    assert sync() == "rendered 1, removed 0, kept 0, skipped 0\n"
    (env["archive"] / "2021" / "06" / f"{ORIGINAL}.jpg").write_bytes(b"re-edited")
    assert sync() == "rendered 1, removed 0, kept 0, skipped 0\n"
    assert sync() == "rendered 0, removed 0, kept 1, skipped 0\n"
    config = env["config_home"] / "wali" / "config.toml"
    config.write_text(config.read_text().replace('output = "90x200"', 'output = "100x220"'))
    assert sync() == "rendered 1, removed 0, kept 0, skipped 0\n"
    assert "-extent 100x220" in magick.read_text().splitlines()[-1]
    assert sync() == "rendered 0, removed 0, kept 1, skipped 0\n"
    assert sync("--force") == "rendered 1, removed 0, kept 0, skipped 0\n"


def test_phone_sync_recovers_from_manifest_mismatch(walictl: ModuleType, env: dict[str, Path], magick: Path) -> None:
    folder = phone_env(env)
    write_ratings(env, [ORIGINAL, LIBRARY_ONLY])
    manifest = env["state_home"] / "wali" / "phone.json"
    assert run_cli(walictl, ["phone", "sync"])[1] == "rendered 2, removed 0, kept 0, skipped 0\n"
    # Image written, manifest entry not yet: the render is stale.
    payload = json.loads(manifest.read_text())
    del payload["renders"][ORIGINAL]
    manifest.write_text(json.dumps(payload))
    assert run_cli(walictl, ["phone", "sync"])[1] == "rendered 1, removed 0, kept 1, skipped 0\n"
    # Manifest entry present, image gone: the render is stale.
    (folder / f"{LIBRARY_ONLY}.jpg").unlink()
    assert run_cli(walictl, ["phone", "sync"])[1] == "rendered 1, removed 0, kept 1, skipped 0\n"
    # Image gone without a removal, manifest entry left behind: a stale entry with no file is ignored.
    write_ratings(env, [ORIGINAL])
    (folder / f"{LIBRARY_ONLY}.jpg").unlink()
    assert run_cli(walictl, ["phone", "sync"])[1] == "rendered 0, removed 0, kept 1, skipped 0\n"
    # Manifest missing or malformed: everything is stale, with a warning for the malformed case.
    manifest.unlink()
    assert run_cli(walictl, ["phone", "sync"])[1] == "rendered 1, removed 0, kept 0, skipped 0\n"
    manifest.write_text("{")
    code, stdout, stderr = run_cli(walictl, ["phone", "sync"])
    assert (code, stdout) == (0, "rendered 1, removed 0, kept 0, skipped 0\n")
    assert stderr == f"phone manifest is not valid JSON: {manifest}; rebuilding\n"


def test_phone_sync_dry_run_mutates_nothing(walictl: ModuleType, env: dict[str, Path], magick: Path) -> None:
    folder = phone_env(env)
    write_ratings(env, [ORIGINAL])
    code, stdout, stderr = run_cli(walictl, ["phone", "sync", "--dry-run", "--json"])
    assert code == 0 and stderr == ""
    assert json.loads(stdout) == {"ok": True, "rendered": [ORIGINAL], "removed": [], "kept": 0, "skipped": []}
    assert not folder.exists() and not magick.exists()
    assert not (env["state_home"] / "wali" / "phone.json").exists()
    folder.mkdir()
    (folder / "stale.jpg").write_bytes(b"old")
    (folder / "PXL_x.jpg.tmp").write_bytes(b"half")
    code, stdout, _ = run_cli(walictl, ["phone", "sync", "--dry-run"])
    assert (code, stdout) == (0, "rendered 1, removed 1, kept 0, skipped 0\n")
    assert sorted(p.name for p in folder.iterdir()) == ["PXL_x.jpg.tmp", "stale.jpg"]


def test_phone_sync_stops_at_a_magick_failure(
    walictl: ModuleType, env: dict[str, Path], magick: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    folder = phone_env(env)
    folder.mkdir()
    (folder / "stale.jpg").write_bytes(b"old")
    write_ratings(env, [ORIGINAL, LIBRARY_ONLY])
    monkeypatch.setenv("MAGICK_FAIL", "1")
    code, stdout, stderr = run_cli(walictl, ["phone", "sync"])
    assert (code, stdout, stderr) == (1, "", "magick failed: magick: boom\n")
    assert sorted(p.name for p in folder.iterdir()) == [".nomedia"]
    assert json.loads((env["state_home"] / "wali" / "phone.json").read_text()) == {"version": 1, "renders": {}}
    assert len(magick.read_text().splitlines()) == 1


def test_phone_sync_needs_magick_before_any_work(walictl: ModuleType, env: dict[str, Path], monkeypatch: pytest.MonkeyPatch) -> None:
    folder = phone_env(env)
    folder.mkdir()
    (folder / "stale.jpg").write_bytes(b"old")
    write_ratings(env, [])
    monkeypatch.setenv("PATH", str(env["config_home"] / "empty"))
    code, _, stderr = run_cli(walictl, ["phone", "sync"])
    assert code == 1 and stderr == "magick command not found\n"
    assert sorted(p.name for p in folder.iterdir()) == ["stale.jpg"]
    assert run_cli(walictl, ["phone", "sync", "--dry-run"])[0] == 0


def test_phone_sync_empty_favorites_empties_the_folder(walictl: ModuleType, env: dict[str, Path], magick: Path) -> None:
    folder = phone_env(env)
    folder.mkdir()
    (folder / "stale.jpg").write_bytes(b"old")
    write_ratings(env, [])
    code, stdout, _ = run_cli(walictl, ["phone", "sync"])
    assert (code, stdout) == (0, "rendered 0, removed 1, kept 0, skipped 0\n")
    assert sorted(p.name for p in folder.iterdir()) == [".nomedia"]


def test_phone_sync_holds_the_lock_while_rendering(
    walictl: ModuleType, env: dict[str, Path], magick: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    phone_env(env)
    write_ratings(env, [ORIGINAL])
    monkeypatch.setenv("MAGICK_EXPECT_LOCK", str(env["state_home"] / "wali" / "phone.lock"))
    code, stdout, stderr = run_cli(walictl, ["phone", "sync"])
    assert (code, stdout, stderr) == (0, "rendered 1, removed 0, kept 0, skipped 0\n", "")


def test_phone_sync_rejects_a_file_at_dir(walictl: ModuleType, env: dict[str, Path], magick: Path) -> None:
    folder = phone_env(env)
    folder.write_text("not a directory")
    write_ratings(env, [ORIGINAL])
    for extra in ([], ["--dry-run"]):
        code, stdout, stderr = run_cli(walictl, ["phone", "sync", *extra])
        assert (code, stdout, stderr) == (1, "", f"phone.dir is not a directory: {folder}\n")
    assert folder.read_text() == "not a directory"
```

- [x] **Step 2: Run the tests to verify they fail**

Run: `uv run --frozen pytest -q tests/test_walictl.py -k phone_sync`
Expected: FAIL — argparse rejects `phone` (exit 2), `write_ratings` defined but the command missing.

- [x] **Step 3: Implement**

In the phone section, after `phone_render`:

```python
@dataclass
class PhonePlan:
    render: list[tuple[str, Path]]
    remove: list[str]
    kept: list[str]
    skipped: list[str]


def _owned(path: Path, suffix: str) -> bool:
    """An entry walictl manages: a regular, non-dotfile file with the given suffix."""
    return path.is_file() and not path.name.startswith(".") and path.name.endswith(suffix)


def phone_renders(directory: Path) -> dict[str, Path]:
    """The renders in the mirrored folder: every non-dotfile *.jpg."""
    if not directory.exists():
        return {}
    if not directory.is_dir():
        raise WalictlError(f"phone.dir is not a directory: {directory}")
    return {path.stem: path for path in directory.iterdir() if _owned(path, ".jpg")}


def phone_plan(
    config: Config, phone: PhoneConfig, ratings: Ratings, manifest: PhoneManifest, library: dict[str, Path], *, force: bool
) -> PhonePlan:
    existing = phone_renders(phone.dir)
    wanted = [check_photo_id(photo, "favorite id") for photo in ratings.favorite_ids()]
    plan = PhonePlan(render=[], remove=sorted(set(existing) - set(wanted)), kept=[], skipped=[])
    for photo in wanted:
        source = resolve_source(config, photo) or library.get(photo)
        if source is None:
            plan.skipped.append(photo)
        elif photo in existing and not force and manifest.renders.get(photo) == source_identity(source, phone.output):
            plan.kept.append(photo)
        else:
            plan.render.append((photo, source))
    return plan


def prepare_phone_dir(directory: Path) -> None:
    try:
        directory.mkdir(parents=True, exist_ok=True)
    except (FileExistsError, NotADirectoryError) as exc:
        raise WalictlError(f"phone.dir is not a directory: {directory}") from exc
    (directory / ".nomedia").touch(exist_ok=True)
    for path in directory.iterdir():
        if _owned(path, PHONE_TMP_SUFFIX):
            path.unlink()


def cmd_phone_sync(ctx: Context, args: argparse.Namespace) -> int:
    if ctx.config.phone is None:
        raise WalictlError("config table [phone] is required")
    phone = ctx.config.phone
    ratings = Ratings.load(ctx.config.favorites_file, required=True)
    library = scan_library(ctx.config.wallpaper_dir)
    if phone.dir.exists() and not phone.dir.is_dir():
        raise WalictlError(f"phone.dir is not a directory: {phone.dir}")
    if not args.dry_run and shutil.which("magick") is None:
        raise WalictlError("magick command not found")

    def warn(message: str) -> None:
        ctx.err.write(f"{message}\n")

    manifest_path = phone_manifest_path()
    with locked(phone_lock()):
        if not args.dry_run:
            prepare_phone_dir(phone.dir)
        manifest = PhoneManifest.load(manifest_path, warn)
        plan = phone_plan(ctx.config, phone, ratings, manifest, library, force=args.force)
        for photo in plan.skipped:
            warn(f"skipped {photo}: missing from library")
        if not args.dry_run:
            for photo in plan.remove:
                (phone.dir / f"{photo}.jpg").unlink()
                manifest.renders.pop(photo, None)
                manifest.save(manifest_path)
            for photo, source in plan.render:
                identity = source_identity(source, phone.output)
                phone_render(source, phone.dir / f"{photo}.jpg", phone.output)
                manifest.renders[photo] = identity
                manifest.save(manifest_path)
    rendered = [photo for photo, _ in plan.render]
    if args.json:
        skipped = [{"id": photo, "reason": "missing from library"} for photo in plan.skipped]
        json.dump({"ok": True, "rendered": rendered, "removed": plan.remove, "kept": len(plan.kept), "skipped": skipped}, ctx.out)
        ctx.out.write("\n")
    else:
        ctx.out.write(f"rendered {len(rendered)}, removed {len(plan.remove)}, kept {len(plan.kept)}, skipped {len(plan.skipped)}\n")
    return 0


PHONE_COMMANDS: dict[str, Callable[[Context, argparse.Namespace], int]] = {"sync": cmd_phone_sync}


def cmd_phone(ctx: Context, args: argparse.Namespace) -> int:
    return PHONE_COMMANDS[args.phone_command](ctx, args)
```

`PHONE_COMMANDS` and `cmd_phone` must come after `cmd_phone_sync` and before `COMMANDS`; since `Context` is defined later in the file than the phone section, place `cmd_phone_sync`, `PHONE_COMMANDS`, and `cmd_phone` after `cmd_edit` (just before `COMMANDS`), leaving the data helpers in the phone section. Add `"phone": cmd_phone,` to `COMMANDS` after `"observe"`. In `build_parser`, before `return parser`:

```python
    phone = subparsers.add_parser("phone", help="the phone's mirrored favorites")
    phone_sub = phone.add_subparsers(dest="phone_command", required=True)
    sync = phone_sub.add_parser("sync", help="mirror favorites into [phone] dir as phone-sized renders")
    sync.add_argument("--dry-run", action="store_true", help="report the plan; render and remove nothing")
    sync.add_argument("--force", action="store_true", help="re-render every favorite")
    sync.add_argument("--json", action="store_true")
```

- [x] **Step 4: Run the tests**

Run: `uv run --frozen pytest -q tests/test_walictl.py`
Expected: all PASS.

- [x] **Step 5: Verify and commit**

```bash
just verify
tasks done wali-7f84a5 "walictl phone sync: plan/execute mirror under phone.lock, dry-run, force, json"
git add bin/walictl tests/test_walictl.py tasks
git commit -m "feat(walictl): phone sync mirrors favorites as phone renders"
```

---

### Task 5: Timer units and documentation

**Files:**
- Create: `systemd/wali-phone-sync.service`, `systemd/wali-phone-sync.timer`
- Modify: `docs/noctalia-wallpaper-switcher.md` (ownership table, files table, commands, a new "Phone" section), `README.md` (`systemd/` row)

**Interfaces:** none new; documents Task 4.

- [x] **Step 1: Write the units**

`systemd/wali-phone-sync.service`:

```ini
[Unit]
Description=Mirror favorites into the phone folder with walictl

[Service]
Type=oneshot
ExecStart=%h/bin/walictl phone sync
```

`systemd/wali-phone-sync.timer`:

```ini
[Unit]
Description=Mirror favorites to the phone daily

[Timer]
OnCalendar=daily
Persistent=true
AccuracySec=1h
Unit=wali-phone-sync.service

[Install]
WantedBy=timers.target
```

Check: `systemd-analyze verify --user systemd/wali-phone-sync.timer` (warnings about the unit not being installed are expected; syntax errors are not).

- [x] **Step 2: Update the docs**

`README.md`, the `systemd/` row:

```markdown
| `systemd/` | `wali-rotate.timer`, `wali-phone-sync.timer`, and their services |
```

`docs/noctalia-wallpaper-switcher.md` — ownership table, after the "Timed rotation" row:

```markdown
| Phone renders of favorites | `systemd/wali-phone-sync.timer` running `walictl phone sync` on titan |
```

Files table, after `history.json`:

```markdown
| `$XDG_STATE_HOME/wali/phone.json` | Which source each phone render was made from; rebuilt when missing |
| `<phone.dir>` | The mirrored phone folder under Dropbox; `walictl` owns every `*.jpg` in it |
```

Commands block, after `walictl import-favorites`:

```
walictl phone sync          # mirror favorites into [phone] dir; --dry-run, --force, --json
```

A new section before "Design:":

````markdown
## Phone

Favorites reach the phone as centre-cropped renders at the phone's size.
`walictl phone sync` needs a `[phone]` table on the rendering host (titan,
which has the archive originals):

```toml
[phone]
dir = "~/d/linux/backgrounds/amalthea"   # under Dropbox; walictl owns its *.jpg
output = "1344x2992"                     # the phone's screen
```

Each run renders favorites that are missing or stale (a new source, a
changed output size, or `--force`), removes renders of photos that are no
longer favorites, and leaves everything else in the folder alone. It creates
an empty `.nomedia` there so the phone's gallery ignores the renders. A
favorite this host has not received is skipped with a warning. The ratings
file must exist: a missing file is an error, not an empty set, so a sync can
never empty the phone by accident. `phone.json` in the state dir records the
source of each render; a missing or malformed manifest is rebuilt on the next
run. `--dry-run` reports the plan and changes nothing.

`wali-phone-sync.timer` runs the sync daily. Dotfiles links the units on
every host; enable the timer on titan only:
`systemctl --user enable --now wali-phone-sync.timer`.

On the phone: Dropsync mirrors the Dropbox folder to local storage (method
*download mirror*, so deletions propagate; exclude `*.jpg.tmp`), and Muzei's
*My Photos* source rotates through the local folder with its dim and blur
effects set to 0 — the renders are already the wallpaper.
````

- [x] **Step 3: Verify and commit**

```bash
just verify
tasks done wali-2f951f "wali-phone-sync units and phone docs"
git add systemd README.md docs/noctalia-wallpaper-switcher.md tasks
git commit -m "feat(systemd): wali-phone-sync timer and phone docs"
```

---

### Task 6: Titan configuration and manual verification

**Files:**
- Modify (dotfiles repo, outside this tree; `dots-edcbef`, the `dots` task the goal depends on): `setup.sh` (`setup_systemd_user_units`: two `ln_s` lines for `wali-phone-sync.service` and `.timer`, beside the rotation units at `setup.sh:763`, not in the `ENABLE_USER_TIMERS` block), `tests/setup_and_health.zsh` (the wali unit fixture at `:154` and the link assertions at `:599` gain the two units), `wali/titan/config.toml` (`[phone]` table as documented).

**Interfaces:** none.

- [x] **Step 1: Land the dotfiles piece**

In `~/d/dotfiles`, on a worktree of its own, make the three changes above, run its test suite, commit with the `dots` task closed in the same commit, and merge as that repo's workflow requires.

- [x] **Step 2: First sync on titan, through the worktree's own executable**

Do not touch `~/bin/walictl`: it is currently the quick-edit review shim, and so is `~/d/dotfiles/bin/walictl` (both exec `.worktrees/quick-edit/bin/walictl`, which has no `phone` command). Run the checks directly:

```bash
W=~/d/wali/.worktrees/phone-sync/bin/walictl
$W phone sync --dry-run          # expect rendered ≈686, removed 0, skipped ≈1
$W phone sync                    # several minutes; first run
ls ~/d/linux/backgrounds/amalthea | wc -l   # ≈687 including .nomedia
$W phone sync                    # expect rendered 0, kept ≈686
```

- [x] **Step 3: Phone side, then park for review**

On the phone: Dropsync folder pair (Dropbox `linux/backgrounds/amalthea` → a local folder, download mirror, exclude `*.jpg.tmp`), then Muzei → My Photos → that folder, effects off. Unfavorite one photo on titan, run `$W phone sync`, confirm the render leaves the phone after the next Dropsync pass.

```bash
tasks park wali-4e5921 "first sync done through the worktree executable; judge the phone set in Muzei and the unfavorite round-trip" --waiting-on user --reason review
```

- [x] **Step 4: Enable the timer only once the serving checkout has `phone`**

The unit runs `%h/bin/walictl phone sync`, so enabling it before that exact executable has the command produces a failing service every night. After review:

1. Merge `phone-sync` into `main` (finishing-a-development-branch) and confirm `dots-edcbef` has landed.
2. Install the unit links — the `ln_s` lines in `setup.sh` do nothing until setup runs, and `daemon-reload` cannot create them: `~/d/dotfiles/setup.sh --only systemd`, then `ls -l ~/.config/systemd/user/wali-phone-sync.*` shows both links.
3. The executable the service runs must pass, no substitute: `~/bin/walictl phone sync --dry-run` exits 0 with a `rendered …` line. If `~/bin/walictl` is still the quick-edit review shim, stop here and wait for that review's restore step (see the hazard note on `wali-608311`); do not enable the timer against another path.
4. Then:

```bash
systemctl --user daemon-reload
systemctl --user enable --now wali-phone-sync.timer
systemctl --user list-timers wali-phone-sync.timer
```

- [x] **Step 5: Close**

`tasks done wali-4e5921 "phone set verified on amalthea; timer enabled on titan"`.

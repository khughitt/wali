# Quick Edit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Per-photo adjustments (rotate, tone, blur, noise, bloom, edge-anchored crop) tried live in the panel, stored as a synced recipe, and rendered per host into a variant `walictl` displays instead of the library file.

**Architecture:** `walictl` gains a recipe model (`edits.json`, config `edits_file`), an ImageMagick pipeline that builds one `magick` argv per render, a per-host variant cache keyed by recipe + output size + source identity, and a `variant` command family (`show`, `preview`, `apply`, `reset`). Selection paths call `ensure_variant` so a recipe renders lazily on any host. The panel gets an edit mode: sliders and toggles that request a downscaled preview on every change, coalesced through the existing `busy` gate, with Apply/Reset/Cancel.

**Tech Stack:** Python 3 standard library + `subprocess` to `magick` (ImageMagick 7); pytest with a stub `magick` on `PATH` and one real-`magick` parity test; Luau plugin (Noctalia 5.1.0, plugin API 28), `lua` for `plugin_test.lua`; `just verify`.

**Spec:** `docs/specs/2026-09-13-quick-edit-design.md`. Task `wali-608311` is the parent of every step below.

## Global Constraints

- `bin/walictl` stays standard-library only; `pyproject.toml` declares no runtime dependencies.
- Config: `edits_file` (optional top-level key) and `[edits] output = "WxH"` (optional). With `edits_file` unset, recipes are off: no render step, navigation as today, and every `variant` command fails with `config key edits_file is required`. `[edits]` without `edits_file` is `config key edits_file is required for [edits]`.
- The `variants_dir` config key is removed; the cache is `$XDG_CACHE_HOME/wali/variants/<id>/<key16>/<id>.jpg` (no sidecar: a render is current iff its keyed file exists); previews are `$XDG_CACHE_HOME/wali/preview/<id>/<key8>.jpg`. Temporary render files end in `.tmp.jpg`.
- Noctalia skips a `wallpaper-set` for the path it already shows, so every distinct render has a distinct path. Nothing deletes a render except a prune that runs after a successful `wallpaper-set` (or for a photo that is not displayed).
- Photo ids from recipe files, ratings files, and command arguments pass `check_photo_id`: a single stem, non-empty, not `.`/`..`, no `/`, no NUL. Cache maintenance lists directories; it never expands an id inside a glob.
- Recipe keys, defaults, ranges, and magick mapping are the spec's table; operation order is rotate → (resize, preview only) → tone → blur → noise → bloom → crop. `chroma` and `zoom` do not exist.
- Lock order is history → edits → variants; a command needing several acquires them in that order and never the reverse. `apply` and `reset` hold the history lock from reading the displayed wallpaper through updating history.
- `apply` order: render to temp in the new keyed dir (variants lock, released) → save recipe (edits lock) → publish (variants lock) → set wallpaper if displayed → update the history entry's path → prune the photo's other renders (variants lock; skipped when the set was rejected). `reset` order: remove recipe → set library file if displayed → update history path → prune every render of the photo, only if not displayed or the set succeeded.
- A missing `magick` is `magick command not found`; a failed render is `magick failed: <stderr>` and leaves the previous render.
- Every failure is one line on stderr, exit 1.
- `plugin.toml` adds `"a"` to `capture_keys` (a manifest change: `noctalia msg plugins disable khughitt/wali-panel` then `enable`).
- Plans `2026-09-13-wali-panel-pass-2.md` and `2026-09-13-hidden-photos.md` land first; this plan's panel tasks assume their `panel.luau` (ghost nav, `state.view`, `utilityButton` with `onRightClick`, `labels` test helper).
- Run all commands from the worktree root `.worktrees/panel-scope/`. `just verify` passes before each commit. `tasks start <step-id>` before a task, `tasks done <step-id> "<what landed>"` in the same commit as its code.

---

### Task 1: Config `edits_file` / `[edits] output`, and the cache replaces `variants_dir`

**Files:**
- Modify: `bin/walictl` (`Config`, new `EditsConfig`, `load_config`, `check_photo_id`, `photo_id_arg`, `resolve_variant`, cache path helpers, `build_parser`)
- Test: `tests/test_walictl.py` (the `env` fixture, config tests, variant tests)

**Interfaces:**
- Produces: `EditsConfig(file: Path, output: tuple[int, int] | None)`; `Config.edits: EditsConfig | None` (replacing `variants_dir`); `check_photo_id(value: object, label: str) -> str`; `photo_id_arg` (argparse type); `cache_dir() -> Path` (`$XDG_CACHE_HOME/wali`), `variants_dir() -> Path`, `previews_dir() -> Path`, `variant_dir(photo_id) -> Path` (`variants/<id>`), `variant_file(photo_id, key) -> Path` (`variants/<id>/<key[:16]>/<id>.jpg`), `preview_dir(photo_id) -> Path`; `parse_output("3440x1440") -> (3440, 1440)`. `resolve_variant(config, photo_id)` is reduced to returning `None` (with `config.edits` unset it always did); Task 4 replaces it with the key-aware `current_variant`.
- Consumes: `_xdg`, `_expand`, `WalictlError`.

- [ ] **Step 1: Write the failing tests**

In the `env` fixture, add a cache home beside the others:

```python
    config_home, state_home, cache_home = tmp_path / "config", tmp_path / "state", tmp_path / "cache"
    ...
    monkeypatch.setenv("XDG_CACHE_HOME", str(cache_home))
    return {"config_home": config_home, "state_home": state_home, "cache_home": cache_home, "wallpapers": wallpapers, "archive": archive, "favorites": favorites}
```

Add a helper next to `run_cli` that switches recipes on for a test:

```python
def enable_edits(env: dict[str, Path], output: str | None = "3440x1440") -> Path:
    edits = env["wallpapers"].parent / "edits.json"
    config = env["config_home"] / "wali" / "config.toml"
    text = config.read_text() + f'edits_file = "{edits}"\n'
    if output is not None:
        text += f'[edits]\noutput = "{output}"\n'
    config.write_text(text)
    return edits
```

Replace the two `variants_dir` assertions in `test_load_config_reads_required_and_optional_keys` and `test_load_config_expands_tilde_and_reads_sampling` with `assert config.edits is None`, and drop `variants_dir = "~/v"\n` from the latter's config text. Add:

```python
def test_load_config_reads_edits(walictl: ModuleType, env: dict[str, Path]) -> None:
    edits = enable_edits(env)
    config = walictl.load_config(walictl.config_path())
    assert config.edits == walictl.EditsConfig(file=edits, output=(3440, 1440))
    path = env["config_home"] / "wali" / "config.toml"
    path.write_text(f'wallpaper_dir = "{env["wallpapers"]}"\nfavorites_file = "{env["favorites"]}"\nedits_file = "{edits}"\n')
    assert walictl.load_config(path).edits == walictl.EditsConfig(file=edits, output=None)


@pytest.mark.parametrize(
    ("extra", "message"),
    [
        ('[edits]\noutput = "3440x1440"\n', "config key edits_file is required for [edits]"),
        ('edits_file = "~/e.json"\n[edits]\noutput = "wide"\n', "config key edits.output must be WIDTHxHEIGHT"),
        ('edits_file = "~/e.json"\n[edits]\noutput = "0x10"\n', "config key edits.output must be WIDTHxHEIGHT"),
        ('edits_file = "~/e.json"\n[edits]\noutput = 5\n', "config key edits.output must be WIDTHxHEIGHT"),
        ('edits_file = ""\n', "config key edits_file must be a non-empty string"),
    ],
)
def test_invalid_edits_config(walictl: ModuleType, env: dict[str, Path], extra: str, message: str) -> None:
    path = env["config_home"] / "wali" / "config.toml"
    path.write_text(path.read_text() + extra)
    with pytest.raises(walictl.WalictlError, match=re.escape(message)):
        walictl.load_config(path)
```

(add `import re` to the test module's imports.)

Rewrite `test_resolve_variant_and_source` and `test_display_path_prefers_variant_and_rejects_unknown_id` around the cache paths and id validation:

```python
def test_cache_paths_and_photo_id_validation(walictl: ModuleType, env: dict[str, Path]) -> None:
    photo = "PXL_20210608_111152739"
    assert walictl.variant_dir(photo) == env["cache_home"] / "wali" / "variants" / photo
    assert walictl.variant_file(photo, "abcdef0123456789ffff") == walictl.variant_dir(photo) / "abcdef0123456789" / f"{photo}.jpg"
    assert walictl.preview_dir(photo) == env["cache_home"] / "wali" / "preview" / photo
    assert walictl.check_photo_id("a.b", "id") == "a.b"
    for bad in ("", ".", "..", "a/b", "../victim", "a\x00b", 5, None):
        with pytest.raises(walictl.WalictlError, match="id must be a single file name stem"):
            walictl.check_photo_id(bad, "id")


def test_cli_rejects_path_like_ids(walictl: ModuleType, env: dict[str, Path]) -> None:
    code, _, stderr = run_cli(walictl, ["favorite", "--add", "../victim"])
    assert code == 2 and "single file name stem" in stderr


def test_resolve_variant_and_source(walictl: ModuleType, env: dict[str, Path]) -> None:
    config = walictl.load_config(walictl.config_path())
    assert walictl.resolve_variant(config, "PXL_20210608_111152739") is None
    assert walictl.resolve_source(config, "PXL_20210608_111152739") == env["archive"] / "2021" / "06" / "PXL_20210608_111152739.jpg"
    assert walictl.resolve_source(config, "PXL_20210609_120000000") is None
    assert walictl.resolve_source(config, "IMG_1") is None
    no_archive = walictl.Config(config.wallpaper_dir, config.favorites_file, None, None, config.sampling)
    assert walictl.resolve_source(no_archive, "PXL_20210608_111152739") is None


def test_display_path_rejects_unknown_id(walictl: ModuleType, env: dict[str, Path]) -> None:
    config = walictl.load_config(walictl.config_path())
    library = walictl.scan_library(config.wallpaper_dir)
    assert walictl.display_path(config, library, "PXL_20210609_120000000") == env["wallpapers"] / "PXL_20210609_120000000.jpg"
    with pytest.raises(walictl.WalictlError, match="unknown photo id: nope"):
        walictl.display_path(config, library, "nope")
```

Delete `test_replay_prefers_a_variant_created_later`, `test_sampling_prefers_variant_file`, and `test_capture_navigation_preserves_variants_and_browser_history` (Task 4 replaces them with recipe-driven versions), and in `test_favorites_json_lists_paths_and_existence` remove the `variants` setup and the `variants_dir` config line, expecting the second item's `path` to be `str(env["wallpapers"] / "PXL_20210609_120000000.jpg")`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --frozen pytest -q tests/test_walictl.py -k "config or variant or display_path"`
Expected: FAIL with `AttributeError: ... has no attribute 'EditsConfig'` and `variant_dir`.

- [ ] **Step 3: Implement**

In `bin/walictl`, replace the `Config` dataclass and the tail of `load_config`:

```python
@dataclass(frozen=True)
class EditsConfig:
    file: Path
    output: tuple[int, int] | None


@dataclass(frozen=True)
class Config:
    wallpaper_dir: Path
    favorites_file: Path
    archive_root: Path | None
    edits: EditsConfig | None
    sampling: Sampling


def parse_output(value: object) -> tuple[int, int]:
    match = re.fullmatch(r"(\d+)x(\d+)", value) if isinstance(value, str) else None
    if match is None or int(match[1]) <= 0 or int(match[2]) <= 0:
        raise WalictlError("config key edits.output must be WIDTHxHEIGHT with positive integers")
    return int(match[1]), int(match[2])


def load_edits_config(raw: dict[str, object]) -> EditsConfig | None:
    table = raw.get("edits")
    if "edits_file" not in raw:
        if table is not None:
            raise WalictlError("config key edits_file is required for [edits]")
        return None
    if table is None:
        return EditsConfig(file=_expand(raw["edits_file"], "edits_file"), output=None)
    if not isinstance(table, dict):
        raise WalictlError("config table [edits] must be a table")
    output = parse_output(table["output"]) if "output" in table else None
    return EditsConfig(file=_expand(raw["edits_file"], "edits_file"), output=output)
```

and in `load_config`'s return: `edits=load_edits_config(raw),` in place of the `variants_dir=` line. Add the id check next to `photo_id` and the cache helpers next to `state_dir`:

```python
def check_photo_id(value: object, label: str) -> str:
    """An id that is safe to place in a path: one file-name stem, nothing more."""
    if (
        not isinstance(value, str)
        or value in ("", ".", "..")
        or "/" in value
        or "\x00" in value
        or Path(value).name != value
    ):
        raise WalictlError(f"{label} must be a single file name stem: {value!r}")
    return value


def photo_id_arg(value: str) -> str:
    try:
        return check_photo_id(value, "photo id")
    except WalictlError as exc:
        raise argparse.ArgumentTypeError(str(exc)) from exc
```

```python
def cache_dir() -> Path:
    return _xdg("XDG_CACHE_HOME", ".cache") / "wali"


def variants_dir() -> Path:
    return cache_dir() / "variants"


def previews_dir() -> Path:
    return cache_dir() / "preview"


def variant_dir(photo_id: str) -> Path:
    return variants_dir() / photo_id


def variant_file(photo_id: str, key: str) -> Path:
    return variant_dir(photo_id) / key[:16] / f"{photo_id}.jpg"


def preview_dir(photo_id: str) -> Path:
    return previews_dir() / photo_id
```

Reduce `resolve_variant` to a stub Task 4 replaces:

```python
def resolve_variant(config: Config, photo_id: str) -> Path | None:
    return None  # replaced by current_variant once recipes exist
```

In `build_parser`, give every positional `photo_id` argument `type=photo_id_arg` (`favorite`, and the `hide`/`unhide` parsers from the hidden-photos plan).

`display_path` and `replay_path` keep calling `resolve_variant` for now (Task 4 swaps in `ensure_variant`). `find_by_stem` loses its only non-test caller (`scan_library` still uses `_extension_rank`): delete it and its test `test_find_by_stem_matches_literal_bracketed_stem`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --frozen pytest -q`
Expected: all pass.

- [ ] **Step 5: Verify and commit**

Run: `just verify`

```bash
tasks done <step-1-id> "edits_file / [edits] output config; variant cache paths replace variants_dir"
git add bin/walictl tests/test_walictl.py tasks
git commit -m "feat(walictl): edits config and a per-host variant cache"
```

---

### Task 2: Recipe model and `EditsStore`

**Files:**
- Modify: `bin/walictl` (new section `# --- recipes ---` after the ratings section)
- Test: `tests/test_walictl.py`

**Interfaces:**
- Produces: `_rating_entries` (hidden-photos plan) also calls `check_photo_id(photo, "favorites file id")` per entry, with a line in `test_ratings_reject_corrupt_file` for `{"version": 2, "favorites": {"../x": {"added": "T"}}, "hidden": {}}` → `favorites file id must be a single file name stem`; `RECIPE_DEFAULTS: dict[str, int | str]`, `RECIPE_RANGES: dict[str, tuple[int, int]]`, `ROTATIONS = (0, 90, 180, 270)`, `ANCHORS = ("center", "top", "bottom", "left", "right")`; `parse_settings(settings: list[str]) -> dict[str, int | str]` (`k=v` strings → recipe with defaults dropped); `validate_recipe(raw: object, label: str) -> dict[str, int | str]`; `effective(recipe) -> dict` (defaults filled in); `canonical(recipe) -> str`; `EDITS_VERSION = 1`; `class EditsStore(edits: dict[str, dict[str, object]])` with `load(path)`, `save(path)`, `get(photo_id) -> dict | None` (the recipe without `updated`), `set(photo_id, recipe, now)`, `remove(photo_id) -> bool`; `edits_lock() -> Path`, `variants_lock() -> Path`.
- Consumes: `read_json`, `write_json_atomic`, `state_dir`.

- [ ] **Step 1: Write the failing tests**

```python
def test_parse_settings_drops_defaults_and_validates(walictl: ModuleType) -> None:
    assert walictl.parse_settings([]) == {}
    assert walictl.parse_settings(["brightness=0", "saturation=100", "anchor=center", "rotate=0"]) == {}
    assert walictl.parse_settings(["rotate=90", "brightness=-10", "saturation=80", "anchor=top"]) == {
        "rotate": 90, "brightness": -10, "saturation": 80, "anchor": "top",
    }
    for bad, message in (
        (["rotate=45"], "rotate must be one of 0, 90, 180, 270"),
        (["anchor=middle"], "anchor must be one of center, top, bottom, left, right"),
        (["brightness=101"], "brightness must be between -100 and 100"),
        (["blur=-1"], "blur must be between 0 and 20"),
        (["blur=1.5"], "blur must be an integer"),
        (["chroma=5"], "unknown recipe key: chroma"),
        (["brightness"], "settings take the form key=value: brightness"),
        (["brightness=1", "brightness=2"], "duplicate setting: brightness"),
    ):
        with pytest.raises(walictl.WalictlError, match=re.escape(message)):
            walictl.parse_settings(bad)


def test_effective_and_canonical_recipe(walictl: ModuleType) -> None:
    assert walictl.effective({"rotate": 90}) == {**walictl.RECIPE_DEFAULTS, "rotate": 90}
    assert walictl.canonical({"saturation": 80, "rotate": 90}) == '{"rotate":90,"saturation":80}'
    assert walictl.canonical({}) == "{}"


def test_edits_store_round_trip_and_validation(walictl: ModuleType, tmp_path: Path) -> None:
    path = tmp_path / "edits.json"
    store = walictl.EditsStore.load(path)
    assert store.get("a") is None
    store.set("a", {"rotate": 90, "anchor": "top"}, "T1")
    store.save(path)
    loaded = walictl.EditsStore.load(path)
    assert loaded.get("a") == {"rotate": 90, "anchor": "top"}
    assert json.loads(path.read_text()) == {"version": 1, "edits": {"a": {"rotate": 90, "anchor": "top", "updated": "T1"}}}
    assert loaded.remove("a") is True and loaded.remove("a") is False
    loaded.set("b", {}, "T2")
    assert loaded.get("b") is None, "an all-default recipe is not stored"
    for text, message in (
        ("{not json", "edits file is not valid JSON"),
        ('{"version": 2, "edits": {}}', "unsupported edits version"),
        ('{"version": 1}', "edits file has no edits object"),
        ('{"version": 1, "edits": {"a": 5}}', "malformed edits entry: a"),
        ('{"version": 1, "edits": {"a": {"rotate": 45, "updated": "T"}}}', "malformed edits entry: a: rotate must be one of"),
        ('{"version": 1, "edits": {"a": {"rotate": 90}}}', "malformed edits entry: a: missing updated"),
        ('{"version": 1, "edits": {"../victim": {"rotate": 90, "updated": "T"}}}', "edits file id must be a single file name stem"),
    ):
        path.write_text(text)
        with pytest.raises(walictl.WalictlError, match=re.escape(message)):
            walictl.EditsStore.load(path)


def test_edit_locks_live_in_state_dir(walictl: ModuleType, env: dict[str, Path]) -> None:
    assert walictl.edits_lock() == env["state_home"] / "wali" / "edits.lock"
    assert walictl.variants_lock() == env["state_home"] / "wali" / "variants.lock"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --frozen pytest -q tests/test_walictl.py -k "recipe or edits"`
Expected: FAIL with `AttributeError: ... 'parse_settings'`.

- [ ] **Step 3: Implement**

Add after the ratings section:

```python
# --- recipes ----------------------------------------------------------------

EDITS_VERSION = 1
ROTATIONS: tuple[int, ...] = (0, 90, 180, 270)
ANCHORS: tuple[str, ...] = ("center", "top", "bottom", "left", "right")
RECIPE_DEFAULTS: dict[str, int | str] = {
    "rotate": 0, "brightness": 0, "contrast": 0, "saturation": 100, "hue": 0,
    "blur": 0, "noise": 0, "bloom": 0, "anchor": "center",
}
RECIPE_RANGES: dict[str, tuple[int, int]] = {
    "brightness": (-100, 100), "contrast": (-100, 100), "saturation": (0, 200), "hue": (-180, 180),
    "blur": (0, 20), "noise": (0, 100), "bloom": (0, 100),
}


def edits_lock() -> Path:
    return state_dir() / "edits.lock"


def variants_lock() -> Path:
    return state_dir() / "variants.lock"


def _check_recipe_value(key: str, value: object) -> int | str:
    if key == "anchor":
        if not isinstance(value, str) or value not in ANCHORS:
            raise WalictlError(f"anchor must be one of {', '.join(ANCHORS)}")
        return value
    if isinstance(value, bool) or not isinstance(value, int):
        raise WalictlError(f"{key} must be an integer")
    if key == "rotate":
        if value not in ROTATIONS:
            raise WalictlError("rotate must be one of " + ", ".join(str(r) for r in ROTATIONS))
        return value
    low, high = RECIPE_RANGES[key]
    if not low <= value <= high:
        raise WalictlError(f"{key} must be between {low} and {high}")
    return value


def validate_recipe(raw: object, label: str) -> dict[str, int | str]:
    """A recipe with only non-default keys, or an error prefixed with `label`."""
    if not isinstance(raw, dict):
        raise WalictlError(f"{label}: recipe must be an object")
    recipe: dict[str, int | str] = {}
    for key, value in raw.items():
        if key not in RECIPE_DEFAULTS:
            raise WalictlError(f"{label}: unknown recipe key: {key}")
        try:
            checked = _check_recipe_value(key, value)
        except WalictlError as exc:
            raise WalictlError(f"{label}: {exc}") from exc
        if checked != RECIPE_DEFAULTS[key]:
            recipe[key] = checked
    return recipe


def parse_settings(settings: list[str]) -> dict[str, int | str]:
    raw: dict[str, object] = {}
    for setting in settings:
        key, sep, text = setting.partition("=")
        if not sep:
            raise WalictlError(f"settings take the form key=value: {setting}")
        if key in raw:
            raise WalictlError(f"duplicate setting: {key}")
        if key not in RECIPE_DEFAULTS:
            raise WalictlError(f"unknown recipe key: {key}")
        if key == "anchor":
            raw[key] = text
        else:
            try:
                raw[key] = int(text)
            except ValueError as exc:
                raise WalictlError(f"{key} must be an integer") from exc
    try:
        return validate_recipe(raw, "settings")
    except WalictlError as exc:
        raise WalictlError(str(exc).removeprefix("settings: ")) from exc


def effective(recipe: dict[str, int | str]) -> dict[str, int | str]:
    return {**RECIPE_DEFAULTS, **recipe}


def canonical(recipe: dict[str, int | str]) -> str:
    return json.dumps(recipe, sort_keys=True, separators=(",", ":"))


@dataclass
class EditsStore:
    edits: dict[str, dict[str, object]]

    @classmethod
    def load(cls, path: Path) -> EditsStore:
        payload = read_json(path, "edits file")
        if payload is None:
            return cls(edits={})
        version = payload.get("version")
        if type(version) is not int or version != EDITS_VERSION:
            raise WalictlError(f"unsupported edits version in {path}: {version!r}")
        entries = payload.get("edits")
        if not isinstance(entries, dict):
            raise WalictlError(f"edits file has no edits object: {path}")
        checked: dict[str, dict[str, object]] = {}
        for photo, value in entries.items():
            check_photo_id(photo, "edits file id")
            if not isinstance(value, dict):
                raise WalictlError(f"malformed edits entry: {photo}")
            if not isinstance(value.get("updated"), str):
                raise WalictlError(f"malformed edits entry: {photo}: missing updated")
            recipe = validate_recipe({k: v for k, v in value.items() if k != "updated"}, f"malformed edits entry: {photo}")
            checked[str(photo)] = {**recipe, "updated": value["updated"]}
        return cls(edits=checked)

    def save(self, path: Path) -> None:
        write_json_atomic(path, {"version": EDITS_VERSION, "edits": self.edits})

    def get(self, photo_id: str) -> dict[str, int | str] | None:
        entry = self.edits.get(photo_id)
        if entry is None:
            return None
        return {k: v for k, v in entry.items() if k != "updated"}  # type: ignore[misc]

    def set(self, photo_id: str, recipe: dict[str, int | str], now: str) -> None:
        if not recipe:
            self.edits.pop(photo_id, None)
            return
        self.edits[photo_id] = {**recipe, "updated": now}

    def remove(self, photo_id: str) -> bool:
        return self.edits.pop(photo_id, None) is not None
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --frozen pytest -q`
Expected: all pass.

- [ ] **Step 5: Verify and commit**

Run: `just verify`

```bash
tasks done <step-2-id> "recipe validation, --set parsing, canonical form, EditsStore"
git add bin/walictl tests/test_walictl.py tasks
git commit -m "feat(walictl): recipe model and edits store"
```

---

### Task 3: The magick pipeline

**Files:**
- Modify: `bin/walictl` (new section `# --- rendering ---`)
- Test: `tests/test_walictl.py` (a `fake_magick` fixture)

**Interfaces:**
- Produces: `PREVIEW_WIDTH = 560`; `image_size(path) -> tuple[int, int]` via `magick identify -format "%w %h"`; `crop_box(width, height, output, anchor) -> tuple[int, int, int, int]` (`cw, ch, x, y`); `magick_argv(source, recipe, output, dest, preview_width) -> list[str]`; `render(source, recipe, output, dest, preview_width=None) -> None` (runs the argv, raises `magick command not found` / `magick failed: <stderr>`); `output_required(recipe, output)` raising `config key edits.output is required for anchor`.
- Consumes: `effective`, `subprocess`.
- Test fixture `fake_magick(env, monkeypatch) -> Path` (the log file): installs a `magick` script first on `PATH` that answers `identify` with `$FAKE_MAGICK_SIZE` (default `3440 1935`), and for any other invocation appends the argv as one JSON line to the log and copies argv[1] to argv[-1]; `FAKE_MAGICK_FAIL=1` makes it exit 1 with `boom` on stderr; `FAKE_MAGICK_PARTIAL=1` writes one byte to argv[-1] and then exits 1 (a render that dies mid-write).
- `FakeNoctalia.run` today asserts every `subprocess.run` is `noctalia msg`; it must forward anything else to the real `subprocess.run`, or no test using both fixtures can reach the stub.

- [ ] **Step 1: Write the fixture and the failing tests**

First make `FakeNoctalia` forward non-Noctalia commands. In its `__init__` add `self.real_run = subprocess.run` (captured before the fixture monkeypatches it), and at the top of `run`:

```python
    def run(self, args: list[str], **kwargs: Any) -> subprocess.CompletedProcess[str]:
        if list(args[:2]) != ["noctalia", "msg"]:
            return self.real_run(args, **kwargs)
        self.calls.append(list(args))
```

(dropping the `assert args[:2] == ...` line). Fixture, next to `noctalia`:

```python
@pytest.fixture
def fake_magick(env: dict[str, Path], monkeypatch: pytest.MonkeyPatch) -> Path:
    bin_dir = env["cache_home"].parent / "bin"
    bin_dir.mkdir()
    log = bin_dir / "magick.log"
    script = bin_dir / "magick"
    script.write_text(
        "#!/usr/bin/env python3\n"
        "import json, os, shutil, sys\n"
        "args = sys.argv[1:]\n"
        "if args and args[0] == 'identify':\n"
        "    sys.stdout.write(os.environ.get('FAKE_MAGICK_SIZE', '3440 1935'))\n"
        "    sys.exit(0)\n"
        f"with open({str(log)!r}, 'a') as handle:\n"
        "    handle.write(json.dumps(args) + '\\n')\n"
        "if os.environ.get('FAKE_MAGICK_FAIL'):\n"
        "    sys.stderr.write('boom\\n')\n"
        "    sys.exit(1)\n"
        "if os.environ.get('FAKE_MAGICK_PARTIAL'):\n"
        "    open(args[-1], 'wb').write(b'x')\n"
        "    sys.stderr.write('died\\n')\n"
        "    sys.exit(1)\n"
        "shutil.copyfile(args[0], args[-1])\n"
    )
    script.chmod(0o755)
    monkeypatch.setenv("PATH", f"{bin_dir}:{os.environ['PATH']}")
    monkeypatch.delenv("FAKE_MAGICK_FAIL", raising=False)
    monkeypatch.delenv("FAKE_MAGICK_PARTIAL", raising=False)
    monkeypatch.delenv("FAKE_MAGICK_SIZE", raising=False)
    return log


def magick_calls(log: Path) -> list[list[str]]:
    return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
```

(add `import os` to the test imports.) Tests:

```python
@pytest.mark.parametrize(
    ("size", "anchor", "expected"),
    [
        ((3440, 1935), "center", (3440, 1440, 0, 247)),
        ((3440, 1935), "top", (3440, 1440, 0, 0)),
        ((3440, 1935), "bottom", (3440, 1440, 0, 495)),
        ((1935, 3440), "center", (1935, 810, 0, 1315)),
        ((1935, 3440), "left", (1935, 810, 0, 1315)),
        ((4000, 1000), "left", (2388, 1000, 0, 0)),
        ((4000, 1000), "right", (2388, 1000, 1612, 0)),
        ((4000, 1000), "center", (2388, 1000, 806, 0)),
    ],
)
def test_crop_box_fits_output_aspect_from_anchor(
    walictl: ModuleType, size: tuple[int, int], anchor: str, expected: tuple[int, int, int, int]
) -> None:
    assert walictl.crop_box(size[0], size[1], (3440, 1440), anchor) == expected


def test_magick_argv_per_key(walictl: ModuleType, env: dict[str, Path], fake_magick: Path) -> None:
    src, dst = Path("/s.jpg"), Path("/d.jpg")
    base = ["magick", "/s.jpg"]
    tail = ["-quality", "92", "/d.jpg"]
    argv = walictl.magick_argv
    assert argv(src, {}, None, dst, None) == base + tail
    assert argv(src, {"rotate": 90}, None, dst, None) == base + ["-rotate", "90"] + tail
    assert argv(src, {"brightness": 10, "contrast": -5}, None, dst, None) == base + ["-brightness-contrast", "10x-5"] + tail
    assert argv(src, {"saturation": 80}, None, dst, None) == base + ["-modulate", "100,80,100"] + tail
    assert argv(src, {"hue": 90}, None, dst, None) == base + ["-modulate", "100,100,150"] + tail
    assert argv(src, {"blur": 3}, None, dst, None) == base + ["-blur", "0x3"] + tail
    assert argv(src, {"noise": 40}, None, dst, None) == base + ["-attenuate", "0.4", "+noise", "Gaussian"] + tail
    assert argv(src, {"bloom": 50}, None, dst, None) == base + [
        "(", "+clone", "-blur", "0x25", "-evaluate", "multiply", "0.5", ")", "-compose", "screen", "-composite",
    ] + tail
    # full render: center anchor leaves the crop to Noctalia even with an output configured
    assert argv(src, {"brightness": 1}, (3440, 1440), dst, None) == base + ["-brightness-contrast", "1x0"] + tail
    assert argv(src, {"anchor": "top"}, (3440, 1440), dst, None) == base + ["-crop", "3440x1440+0+0", "+repage"] + tail
    # rotation swaps the size before the crop box is computed
    assert argv(src, {"rotate": 90, "anchor": "top"}, (3440, 1440), dst, None) == base + [
        "-rotate", "90", "-crop", "1935x810+0+0", "+repage",
    ] + tail
    # operation order
    assert argv(src, {"rotate": 180, "blur": 2, "bloom": 10, "noise": 10, "saturation": 50, "anchor": "bottom"}, (3440, 1440), dst, None) == base + [
        "-rotate", "180", "-modulate", "100,50,100", "-blur", "0x2", "-attenuate", "0.1", "+noise", "Gaussian",
        "(", "+clone", "-blur", "0x25", "-evaluate", "multiply", "0.1", ")", "-compose", "screen", "-composite",
        "-crop", "3440x1440+0+495", "+repage",
    ] + tail


def test_magick_argv_preview_scales_pixel_units_and_crops(walictl: ModuleType, env: dict[str, Path], fake_magick: Path) -> None:
    src, dst = Path("/s.jpg"), Path("/p.jpg")
    argv = walictl.magick_argv
    # 3440 wide → 560: factor 0.16279..., blur 10 → 1.628, bloom radius 25 → 4.07, noise 0.5 → 0.0814
    got = argv(src, {"blur": 10, "noise": 50, "bloom": 20}, None, dst, 560)
    assert got[:4] == ["magick", "/s.jpg", "-resize", "560x"]
    assert got[4:6] == ["-blur", "0x1.628"]
    assert got[6:10] == ["-attenuate", "0.0814", "+noise", "Gaussian"]
    assert got[10:21] == ["(", "+clone", "-blur", "0x4.07", "-evaluate", "multiply", "0.2", ")", "-compose", "screen", "-composite"]
    assert got[21:] == ["-quality", "92", "/p.jpg"]
    # with an output configured every preview is cropped, center included; the box is in preview pixels
    assert argv(src, {}, (3440, 1440), dst, 560) == ["magick", "/s.jpg", "-resize", "560x", "-crop", "560x234+0+40", "+repage", "-quality", "92", "/p.jpg"]
    # rotate first, then resize: a 90° turn makes the source 1935 wide, so the factor is 560/1935
    got = argv(src, {"rotate": 90, "blur": 10, "anchor": "top"}, (3440, 1440), dst, 560)
    assert got == ["magick", "/s.jpg", "-rotate", "90", "-resize", "560x", "-blur", "0x2.894", "-crop", "560x234+0+0", "+repage", "-quality", "92", "/p.jpg"]


def test_render_runs_magick_and_reports_failures(walictl: ModuleType, env: dict[str, Path], fake_magick: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    source = env["wallpapers"] / "PXL_20210608_111152739.jpg"
    source.write_bytes(b"jpeg")
    dest = env["cache_home"] / "out.jpg"
    dest.parent.mkdir(parents=True)
    walictl.render(source, {"rotate": 90}, None, dest)
    assert dest.read_bytes() == b"jpeg"
    assert magick_calls(fake_magick) == [[str(source), "-rotate", "90", "-quality", "92", str(dest)]]
    monkeypatch.setenv("FAKE_MAGICK_FAIL", "1")
    with pytest.raises(walictl.WalictlError, match="magick failed: boom"):
        walictl.render(source, {"rotate": 90}, None, dest)
    monkeypatch.setenv("PATH", str(env["cache_home"]))
    with pytest.raises(walictl.WalictlError, match="magick command not found"):
        walictl.render(source, {"rotate": 90}, None, dest)


def test_output_required_for_anchor(walictl: ModuleType) -> None:
    walictl.output_required({"anchor": "top"}, (1, 1))
    walictl.output_required({"brightness": 1}, None)
    with pytest.raises(walictl.WalictlError, match="config key edits.output is required for anchor"):
        walictl.output_required({"anchor": "top"}, None)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --frozen pytest -q tests/test_walictl.py -k "crop_box or magick or render or output_required"`
Expected: FAIL with `AttributeError: ... 'crop_box'`.

- [ ] **Step 3: Implement**

Add after the recipes section:

```python
# --- rendering --------------------------------------------------------------

PREVIEW_WIDTH = 560
BLOOM_RADIUS = 25.0


def _num(value: float) -> str:
    """Compact decimal for magick: 3 → '3', 1.628 → '1.628'."""
    text = f"{value:.4g}"
    return text.rstrip("0").rstrip(".") if "." in text else text


def output_required(recipe: dict[str, int | str], output: tuple[int, int] | None) -> None:
    if recipe.get("anchor", "center") != "center" and output is None:
        raise WalictlError("config key edits.output is required for anchor")


def image_size(path: Path) -> tuple[int, int]:
    result = _magick(["identify", "-format", "%w %h", str(path)])
    try:
        width, height = (int(part) for part in result.stdout.split())
    except ValueError as exc:
        raise WalictlError(f"magick identify returned no size for {path}: {result.stdout.strip()!r}") from exc
    return width, height


def crop_box(width: int, height: int, output: tuple[int, int], anchor: str) -> tuple[int, int, int, int]:
    """The largest output-aspect box inside width×height, placed at the anchor."""
    out_w, out_h = output
    if width * out_h >= height * out_w:
        crop_w, crop_h = height * out_w // out_h, height
    else:
        crop_w, crop_h = width, width * out_h // out_w
    x = {"left": 0, "right": width - crop_w}.get(anchor, (width - crop_w) // 2)
    y = {"top": 0, "bottom": height - crop_h}.get(anchor, (height - crop_h) // 2)
    return crop_w, crop_h, x, y


def magick_argv(
    source: Path, recipe: dict[str, int | str], output: tuple[int, int] | None, dest: Path, preview_width: int | None
) -> list[str]:
    """One magick invocation: rotate → (resize) → tone → blur → noise → bloom → crop."""
    values = effective(recipe)
    rotate, anchor = int(values["rotate"]), str(values["anchor"])
    argv = ["magick", str(source)]
    width, height = (0, 0)
    if preview_width is not None or anchor != "center":
        width, height = image_size(source)
        if rotate in (90, 270):
            width, height = height, width
    if rotate:
        argv += ["-rotate", str(rotate)]
    scale = 1.0
    if preview_width is not None:
        scale = preview_width / width
        argv += ["-resize", f"{preview_width}x"]
        width, height = preview_width, round(height * scale)
    brightness, contrast = int(values["brightness"]), int(values["contrast"])
    if brightness or contrast:
        argv += ["-brightness-contrast", f"{brightness}x{contrast}"]
    saturation, hue = int(values["saturation"]), int(values["hue"])
    if saturation != 100 or hue:
        argv += ["-modulate", f"100,{saturation},{_num(100 + hue / 1.8)}"]
    if values["blur"]:
        argv += ["-blur", f"0x{_num(int(values['blur']) * scale)}"]
    if values["noise"]:
        argv += ["-attenuate", _num(int(values["noise"]) / 100 * scale), "+noise", "Gaussian"]
    if values["bloom"]:
        argv += [
            "(", "+clone", "-blur", f"0x{_num(BLOOM_RADIUS * scale)}",
            "-evaluate", "multiply", _num(int(values["bloom"]) / 100), ")",
            "-compose", "screen", "-composite",
        ]
    crop = output is not None and (anchor != "center" or preview_width is not None)
    if crop:
        assert output is not None
        crop_w, crop_h, x, y = crop_box(width, height, output, anchor)
        argv += ["-crop", f"{crop_w}x{crop_h}+{x}+{y}", "+repage"]
    return argv + ["-quality", "92", str(dest)]


def _magick(args: list[str]) -> subprocess.CompletedProcess[str]:
    try:
        result = subprocess.run(["magick", *args], check=False, capture_output=True, text=True)
    except FileNotFoundError as exc:
        raise WalictlError("magick command not found") from exc
    if result.returncode != 0:
        raise WalictlError(f"magick failed: {' '.join(result.stderr.split()) or result.returncode}")
    return result


def render(
    source: Path, recipe: dict[str, int | str], output: tuple[int, int] | None, dest: Path, preview_width: int | None = None
) -> None:
    _magick(magick_argv(source, recipe, output, dest, preview_width)[1:])
```

Note `image_size` is only invoked when a crop or a preview needs the size, so a full render of a tone-only recipe is one process. `test_magick_argv_per_key` relies on the fake `identify` answering `3440 1935`; `magick_argv(src, {}, None, dst, None)` must not call it (the `PATH` in that test has the fake, so a call would still succeed, but the argument order proves the flow).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --frozen pytest -q`
Expected: all pass. If a `_num` expectation differs by rounding (e.g. `1.628` vs `1.6279`), adjust `_num` to `f"{value:.4g}"` semantics as written, not the test: `560/3440*10 = 1.6279…` → `.4g` gives `1.628`; `25*0.16279 = 4.0698` → `4.07`; `0.5*0.16279 = 0.08140` → `0.0814`; `560/1935*10 = 2.8940` → `2.894`.

- [ ] **Step 5: Verify and commit**

Run: `just verify`

```bash
tasks done <step-3-id> "magick pipeline: argv builder, crop box, preview scaling, render"
git add bin/walictl tests/test_walictl.py tasks
git commit -m "feat(walictl): ImageMagick render pipeline"
```

---

### Task 4: The variant cache and lazy rendering on selection

**Files:**
- Modify: `bin/walictl` (`source_identity`, `render_key`, `render_to_temp`, `publish_variant`, `prune_variants`, `current_variant`, `ensure_variant`; `display_path`, `replay_path`, `navigate`, `describe`, `cmd_current`, `_rating_items`)
- Test: `tests/test_walictl.py`

**Interfaces:**
- Produces: `source_identity(path) -> dict[str, object]` (`{"path", "size", "mtime_ns"}`); `render_key(recipe, output, identity) -> str` (SHA-256 hex of the canonical JSON of `{"recipe", "output", "source"}`); `render_to_temp(source, recipe, output, target_dir) -> Path` (a `.tmp.jpg` inside `target_dir`, created as needed; deleted on failure); `publish_variant(tmp, photo_id, key) -> Path` (`os.replace` onto `variant_file`); `prune_variants(photo_id, keep: Path | None)` (removes every `variant_dir(photo_id)/<key>/` except the one holding `keep`; lists directories, no glob); `recipe_key(config, library, photo_id) -> tuple[recipe | None, key | None]` (loads the recipe under `edits.lock`); `current_variant(config, library, photo_id) -> Path | None` (the keyed file if it exists — never renders, never deletes); `ensure_variant(config, library, photo_id) -> Path | None` (renders when missing; never deletes). `resolve_variant(config, photo_id)` is removed; `describe`, `cmd_current`, and `_rating_items` call `current_variant(config, library, photo_id)`. `display_path(config, library, photo_id)` returns `ensure_variant(...) or library[photo_id]`; `replay_path(config, library, entry)` returns `ensure_variant(config, library, entry.id) or library.get(entry.id) or Path(entry.path)`. `navigate` calls `prune_variants(selected.id, keep=displayed)` after `set_default` succeeds.
- Consumes: Tasks 1–3, `locked`, `edits_lock`, `variants_lock`, `EditsStore`.

- [ ] **Step 1: Write the failing tests**

```python
def recipe_for(walictl: ModuleType, env: dict[str, Path], photo: str, recipe: dict[str, object]) -> None:
    edits = env["wallpapers"].parent / "edits.json"
    store = walictl.EditsStore.load(edits)
    store.set(photo, recipe, "T")
    store.save(edits)


def renders_of(walictl: ModuleType, photo: str) -> list[Path]:
    root = walictl.variant_dir(photo)
    return sorted(p for p in root.glob("*/*.jpg")) if root.is_dir() else []


def test_ensure_variant_renders_per_key_and_never_deletes(
    walictl: ModuleType, env: dict[str, Path], fake_magick: Path
) -> None:
    enable_edits(env)
    config = walictl.load_config(walictl.config_path())
    library = walictl.scan_library(config.wallpaper_dir)
    photo = "PXL_20210608_111152739"
    (env["wallpapers"] / f"{photo}.jpg").write_bytes(b"v1")
    assert walictl.ensure_variant(config, library, photo) is None
    assert magick_calls(fake_magick) == []
    recipe_for(walictl, env, photo, {"rotate": 90})
    first = walictl.ensure_variant(config, library, photo)
    key = walictl.render_key({"rotate": 90}, (3440, 1440), walictl.source_identity(library[photo]))
    assert first == walictl.variant_file(photo, key) and first.read_bytes() == b"v1"
    assert first.stem == photo, "the render keeps the photo id as its stem"
    assert len(magick_calls(fake_magick)) == 1
    assert walictl.ensure_variant(config, library, photo) == first
    assert len(magick_calls(fake_magick)) == 1, "an existing keyed render is not repeated"
    assert walictl.current_variant(config, library, photo) == first
    recipe_for(walictl, env, photo, {"rotate": 180})
    assert walictl.current_variant(config, library, photo) is None, "current_variant never renders"
    second = walictl.ensure_variant(config, library, photo)
    assert second != first and second.parent != first.parent, "a changed recipe renders to a new path"
    assert first.exists(), "ensure_variant never deletes"
    (env["wallpapers"] / f"{photo}.jpg").write_bytes(b"v2-longer")
    third = walictl.ensure_variant(config, library, photo)
    assert third not in (first, second) and third.read_bytes() == b"v2-longer", "a changed source renders to a new path"
    assert not list(walictl.variant_dir(photo).rglob("*.tmp.jpg")), "no temp files left behind"
    recipe_for(walictl, env, photo, {})
    assert walictl.ensure_variant(config, library, photo) is None
    assert renders_of(walictl, photo) == sorted([first, second, third]), "a removed recipe leaves renders for the prune"
    walictl.prune_variants(photo, keep=None)
    assert renders_of(walictl, photo) == []
    assert not walictl.variant_dir(photo).exists()


def test_prune_variants_keeps_only_the_displayed_render(walictl: ModuleType, env: dict[str, Path], fake_magick: Path) -> None:
    enable_edits(env)
    config = walictl.load_config(walictl.config_path())
    library = walictl.scan_library(config.wallpaper_dir)
    photo = "PXL_20210608_111152739"
    recipe_for(walictl, env, photo, {"rotate": 90})
    first = walictl.ensure_variant(config, library, photo)
    recipe_for(walictl, env, photo, {"rotate": 180})
    second = walictl.ensure_variant(config, library, photo)
    walictl.prune_variants(photo, keep=second)
    assert renders_of(walictl, photo) == [second] and not first.parent.exists()
    walictl.prune_variants("PXL_20210609_120000000", keep=None)  # no renders: no error


def test_ensure_variant_failure_keeps_the_previous_render(
    walictl: ModuleType, env: dict[str, Path], fake_magick: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    enable_edits(env)
    config = walictl.load_config(walictl.config_path())
    library = walictl.scan_library(config.wallpaper_dir)
    photo = "PXL_20210608_111152739"
    (env["wallpapers"] / f"{photo}.jpg").write_bytes(b"v1")
    recipe_for(walictl, env, photo, {"rotate": 90})
    first = walictl.ensure_variant(config, library, photo)
    recipe_for(walictl, env, photo, {"rotate": 270})
    monkeypatch.setenv("FAKE_MAGICK_PARTIAL", "1")
    with pytest.raises(walictl.WalictlError, match="magick failed: died"):
        walictl.ensure_variant(config, library, photo)
    assert first.read_bytes() == b"v1" and renders_of(walictl, photo) == [first]
    assert not list(walictl.variant_dir(photo).rglob("*.tmp.jpg")), "a partial render is removed"
    monkeypatch.delenv("FAKE_MAGICK_PARTIAL")
    assert walictl.current_variant(config, library, photo) is None, "a failed render is never current"


def test_navigation_never_renders_with_edits_unset(
    walictl: ModuleType, env: dict[str, Path], noctalia: FakeNoctalia, fake_magick: Path
) -> None:
    assert run_cli(walictl, ["random", "--seed", "3"])[0] == 0
    assert run_cli(walictl, ["previous"])[0] == 0
    assert run_cli(walictl, ["later"])[0] == 0
    assert magick_calls(fake_magick) == []


def test_sampling_and_replay_use_the_rendered_variant(
    walictl: ModuleType, env: dict[str, Path], noctalia: FakeNoctalia, fake_magick: Path
) -> None:
    enable_edits(env)
    for stem in ("PXL_20210609_120000000", "PXL_20220402_162957459"):
        recipe_for(walictl, env, stem, {"brightness": 5})
    run_cli(walictl, ["random", "--seed", "3"])
    picked = load_history(walictl).entries[1]
    assert Path(picked.path).stem == picked.id and Path(picked.path).is_relative_to(walictl.variant_dir(picked.id))
    assert noctalia.default == Path(picked.path)
    # a recipe added after the entry was recorded is picked up on replay
    recipe_for(walictl, env, "PXL_20210608_111152739", {"rotate": 90})
    code, stdout, _ = run_cli(walictl, ["previous"])
    assert (code, stdout) == (0, "previous: PXL_20210608_111152739\n")
    assert noctalia.default.is_relative_to(walictl.variant_dir("PXL_20210608_111152739"))
    assert load_history(walictl).entries[0].path == str(noctalia.default)
    # a recipe removed after the entry was recorded replays the library file, and the successful
    # selection prunes the stale render
    recipe_for(walictl, env, picked.id, {})
    code, stdout, _ = run_cli(walictl, ["next"])
    assert (code, stdout) == (0, f"next: {picked.id}\n")
    assert noctalia.default == env["wallpapers"] / f"{picked.id}.jpg"
    assert renders_of(walictl, picked.id) == []


def test_selection_prunes_only_after_a_successful_set(
    walictl: ModuleType, env: dict[str, Path], noctalia: FakeNoctalia, fake_magick: Path
) -> None:
    enable_edits(env)
    photo = "PXL_20210609_120000000"
    recipe_for(walictl, env, photo, {"rotate": 90})
    assert run_cli(walictl, ["later"])[0] == 0
    first = noctalia.default
    assert run_cli(walictl, ["earlier"])[0] == 0
    recipe_for(walictl, env, photo, {"rotate": 180})
    noctalia.reject_set = "busy"
    code, _, stderr = run_cli(walictl, ["later"])
    assert code == 1 and "busy" in stderr
    assert len(renders_of(walictl, photo)) == 2 and first.exists(), "a rejected selection prunes nothing"
    noctalia.reject_set = None
    assert run_cli(walictl, ["later"])[0] == 0
    assert renders_of(walictl, photo) == [noctalia.default] and not first.exists()


def test_capture_navigation_renders_variants(
    walictl: ModuleType, env: dict[str, Path], noctalia: FakeNoctalia, fake_magick: Path
) -> None:
    enable_edits(env)
    recipe_for(walictl, env, "PXL_20210609_120000000", {"anchor": "top"})
    assert run_cli(walictl, ["later"]) == (0, "later: PXL_20210609_120000000\n", "")
    assert noctalia.default.stem == "PXL_20210609_120000000"
    assert noctalia.default.is_relative_to(walictl.variant_dir("PXL_20210609_120000000"))
    assert magick_calls(fake_magick)[-1][1:5] == ["-crop", "3440x1440+0+0", "+repage", "-quality"]
    assert magick_calls(fake_magick)[-1][-1].endswith(".tmp.jpg"), "renders go to a temp file first"


def test_render_failure_fails_selection_and_leaves_wallpaper(
    walictl: ModuleType, env: dict[str, Path], noctalia: FakeNoctalia, fake_magick: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    enable_edits(env)
    recipe_for(walictl, env, "PXL_20210609_120000000", {"rotate": 90})
    monkeypatch.setenv("FAKE_MAGICK_FAIL", "1")
    code, stdout, stderr = run_cli(walictl, ["later"])
    assert (code, stdout, stderr) == (1, "", "magick failed: boom\n")
    assert noctalia.default == env["wallpapers"] / "PXL_20210608_111152739.jpg"
    assert [e.origin for e in load_history(walictl).entries] == ["observed"]


def test_current_reports_the_keyed_variant_without_rendering(
    walictl: ModuleType, env: dict[str, Path], noctalia: FakeNoctalia, fake_magick: Path
) -> None:
    enable_edits(env)
    photo = "PXL_20210608_111152739"
    recipe_for(walictl, env, photo, {"rotate": 90})
    assert json.loads(run_cli(walictl, ["current", "--json"])[1])["variant_path"] is None
    assert magick_calls(fake_magick) == []
    config = walictl.load_config(walictl.config_path())
    rendered = walictl.ensure_variant(config, walictl.scan_library(config.wallpaper_dir), photo)
    assert json.loads(run_cli(walictl, ["current", "--json"])[1])["variant_path"] == str(rendered)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --frozen pytest -q tests/test_walictl.py -k "ensure_variant or prune or renders or rendered_variant or never_renders or render_failure or keyed_variant"`
Expected: FAIL with `AttributeError: ... 'ensure_variant'`.

- [ ] **Step 3: Implement**

Add after the rendering section:

```python
# --- variant cache ----------------------------------------------------------


def source_identity(path: Path) -> dict[str, object]:
    stat = path.stat()
    return {"path": str(path), "size": stat.st_size, "mtime_ns": stat.st_mtime_ns}


def render_key(recipe: dict[str, int | str], output: tuple[int, int] | None, identity: dict[str, object]) -> str:
    payload = {"recipe": recipe, "output": list(output) if output else None, "source": identity}
    return hashlib.sha256(json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def render_to_temp(
    source: Path, recipe: dict[str, int | str], output: tuple[int, int] | None, target_dir: Path,
    preview_width: int | None = None,
) -> Path:
    """Render into a .tmp.jpg beside its future home; the caller publishes or deletes it."""
    target_dir.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=".render.", suffix=".tmp.jpg", dir=target_dir)
    os.close(fd)
    tmp = Path(name)
    try:
        render(source, recipe, output, tmp, preview_width)
    except BaseException:
        tmp.unlink(missing_ok=True)
        raise
    return tmp


def publish_variant(tmp: Path, photo_id: str, key: str) -> Path:
    target = variant_file(photo_id, key)
    os.replace(tmp, target)
    return target


def prune_variants(photo_id: str, keep: Path | None) -> None:
    """Remove every render of the photo except `keep`. Caller holds variants.lock."""
    root = variant_dir(photo_id)
    if not root.is_dir():
        return
    for keyed in root.iterdir():
        if keep is not None and keyed == keep.parent:
            continue
        for stale in keyed.iterdir():
            stale.unlink()
        keyed.rmdir()
    if not any(root.iterdir()):
        root.rmdir()


def recipe_key(config: Config, library: dict[str, Path], photo_id: str) -> tuple[dict[str, int | str] | None, str | None]:
    """The photo's recipe and the key of its render on this host, or (None, None)."""
    if config.edits is None:
        return None, None
    with locked(edits_lock()):
        recipe = EditsStore.load(config.edits.file).get(photo_id)
    if recipe is None:
        return None, None
    source = library.get(photo_id)
    if source is None:
        raise WalictlError(f"unknown photo id: {photo_id}")
    return recipe, render_key(recipe, config.edits.output, source_identity(source))


def current_variant(config: Config, library: dict[str, Path], photo_id: str) -> Path | None:
    """The photo's up-to-date render if one exists on disk. Never renders, never deletes."""
    _recipe, key = recipe_key(config, library, photo_id)
    if key is None:
        return None
    target = variant_file(photo_id, key)
    return target if target.is_file() else None


def ensure_variant(config: Config, library: dict[str, Path], photo_id: str) -> Path | None:
    """The photo's render, rendering it if missing. Never deletes: pruning waits for a successful set."""
    recipe, key = recipe_key(config, library, photo_id)
    if recipe is None or key is None:
        return None
    with locked(variants_lock()):
        target = variant_file(photo_id, key)
        if target.is_file():
            return target
        output_required(recipe, config.edits.output if config.edits else None)
        tmp = render_to_temp(library[photo_id], recipe, config.edits.output if config.edits else None, target.parent)
        return publish_variant(tmp, photo_id, key)
```

Add `import hashlib` to the imports. Replace `display_path` and `replay_path`, and delete `resolve_variant`:

```python
def display_path(config: Config, library: dict[str, Path], photo_id: str) -> Path:
    if photo_id not in library:
        raise WalictlError(f"unknown photo id: {photo_id}")
    return ensure_variant(config, library, photo_id) or library[photo_id]


def replay_path(config: Config, library: dict[str, Path], entry: HistoryEntry) -> Path:
    """Resolve a history entry by id: its variant when a recipe exists, else the library file."""
    if entry.id in library:
        return ensure_variant(config, library, entry.id) or library[entry.id]
    return Path(entry.path)
```

In `navigate`: move `library = scan_library(ctx.config.wallpaper_dir)` up to just after the `observe` early return and drop the duplicate in the `else` branch; change `displayed = replay_path(ctx.config, target)` to `displayed = replay_path(ctx.config, library, target)`; and after each `ctx.noctalia.set_default(displayed)` (both the replay branch and the selection branch) add:

```python
            with locked(variants_lock()):
                prune_variants(<photo id of the branch>, keep=displayed)
```

using `target.id` in the replay branch and `picked` in the selection branch. Both run only after `set_default` returned, so a rejected set (which raises) prunes nothing.

Update the callers of `resolve_variant`: `describe` takes `library` (it already does) and computes `variant = current_variant(ctx.config, library, photo)`; `_rating_items` (hidden-photos plan) uses `current_variant(ctx.config, library, photo) or library.get(photo)`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --frozen pytest -q`
Expected: all pass. `test_file_symlink_observe_and_previous_preserve_history` still passes (its ids are in the library, edits are unset, so `replay_path` returns the library entry).

- [ ] **Step 5: Verify and commit**

Run: `just verify`

```bash
tasks done <step-4-id> "keyed variant cache, ensure_variant on selection and replay, prune after a successful set"
git add bin/walictl tests/test_walictl.py tasks
git commit -m "feat(walictl): render variants lazily into keyed cache paths"
```

---

### Task 5: `walictl variant show | preview | apply | reset`

**Files:**
- Modify: `bin/walictl` (`cmd_variant` and helpers, `COMMANDS`, `build_parser`)
- Modify: `docs/noctalia-wallpaper-switcher.md` (config, commands, a quick-edit paragraph)
- Test: `tests/test_walictl.py`

**Interfaces:**
- Produces: `walictl variant show [<id>] --json` → `{"ok": true, "id", "edited": bool, "recipe": {full effective values}, "variant_path": str|null}`; `walictl variant preview [<id>] --set k=v ...` prints the preview path; `walictl variant apply [<id>] --set k=v ...` prints `applied <id>` (or `reset <id>` when the settings are all defaults); `walictl variant reset [<id>]` prints `reset <id>`. `update_history_path(displayed_before, photo_id, new_path, now)` reconciles then rewrites the current entry's path under the already-held history lock. `prune_previews(photo_id, keep)` removes the other files in `preview_dir(photo_id)` by listing it.
- Consumes: Tasks 1–4, `locked`, `history_lock`, `History`, `reconcile`, `Noctalia`.

- [ ] **Step 1: Write the failing tests**

```python
def test_variant_commands_require_edits_file(walictl: ModuleType, env: dict[str, Path], noctalia: FakeNoctalia) -> None:
    for argv in (["variant", "show", "--json"], ["variant", "preview"], ["variant", "apply", "--set", "rotate=90"], ["variant", "reset"]):
        code, _, stderr = run_cli(walictl, argv)
        assert (code, stderr) == (1, "config key edits_file is required\n"), argv


def test_variant_show_reports_effective_recipe(walictl: ModuleType, env: dict[str, Path], noctalia: FakeNoctalia, fake_magick: Path) -> None:
    enable_edits(env)
    payload = json.loads(run_cli(walictl, ["variant", "show", "--json"])[1])
    assert payload == {"ok": True, "id": "PXL_20210608_111152739", "edited": False, "recipe": walictl.RECIPE_DEFAULTS, "variant_path": None}
    recipe_for(walictl, env, "PXL_20220402_162957459", {"rotate": 90, "anchor": "top"})
    payload = json.loads(run_cli(walictl, ["variant", "show", "PXL_20220402_162957459", "--json"])[1])
    assert payload["edited"] is True and payload["recipe"] == {**walictl.RECIPE_DEFAULTS, "rotate": 90, "anchor": "top"}
    assert payload["variant_path"] is None and magick_calls(fake_magick) == [], "show never renders"


def test_variant_preview_writes_keyed_file_and_prunes(walictl: ModuleType, env: dict[str, Path], noctalia: FakeNoctalia, fake_magick: Path) -> None:
    enable_edits(env)
    photo = "PXL_20210608_111152739"
    code, first, stderr = run_cli(walictl, ["variant", "preview", "--set", "brightness=10"])
    assert (code, stderr) == (0, "")
    first_path = Path(first.strip())
    assert first_path.parent == walictl.preview_dir(photo) and first_path.suffix == ".jpg"
    assert magick_calls(fake_magick)[-1][:4] == [str(env["wallpapers"] / f"{photo}.jpg"), "-resize", "560x", "-brightness-contrast"]
    assert magick_calls(fake_magick)[-1][-1].endswith(".tmp.jpg"), "previews render to a temp file first"
    second_path = Path(run_cli(walictl, ["variant", "preview", "--set", "brightness=20"])[1].strip())
    assert second_path != first_path
    assert [p.name for p in first_path.parent.iterdir()] == [second_path.name], "older previews for the id are pruned"
    assert Path(run_cli(walictl, ["variant", "preview", "--set", "brightness=20"])[1].strip()) == second_path
    assert len(magick_calls(fake_magick)) == 2, "an existing preview is reused"
    code, _, stderr = run_cli(walictl, ["variant", "preview", "--set", "rotate=45"])
    assert (code, stderr) == (1, "rotate must be one of 0, 90, 180, 270\n")


def test_variant_preview_failure_is_never_reused(
    walictl: ModuleType, env: dict[str, Path], noctalia: FakeNoctalia, fake_magick: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    enable_edits(env)
    monkeypatch.setenv("FAKE_MAGICK_PARTIAL", "1")
    code, _, stderr = run_cli(walictl, ["variant", "preview", "--set", "blur=2"])
    assert (code, stderr) == (1, "magick failed: died\n")
    assert not list(walictl.preview_dir("PXL_20210608_111152739").iterdir()), "a partial preview is removed"
    monkeypatch.delenv("FAKE_MAGICK_PARTIAL")
    assert run_cli(walictl, ["variant", "preview", "--set", "blur=2"])[0] == 0
    assert len(magick_calls(fake_magick)) == 2, "the retry renders again"


def test_variant_preview_anchor_needs_output(walictl: ModuleType, env: dict[str, Path], noctalia: FakeNoctalia, fake_magick: Path) -> None:
    enable_edits(env, output=None)
    code, _, stderr = run_cli(walictl, ["variant", "preview", "--set", "anchor=top"])
    assert (code, stderr) == (1, "config key edits.output is required for anchor\n")
    assert run_cli(walictl, ["variant", "preview", "--set", "blur=2"])[0] == 0
    assert "-crop" not in magick_calls(fake_magick)[-1], "no output: uncropped preview"


def test_variant_apply_renders_saves_and_resets_displayed_photo(
    walictl: ModuleType, env: dict[str, Path], noctalia: FakeNoctalia, fake_magick: Path
) -> None:
    enable_edits(env)
    run_cli(walictl, ["random", "--seed", "3"])
    picked = load_history(walictl).entries[1].id
    code, stdout, stderr = run_cli(walictl, ["variant", "apply", "--set", "rotate=90", "--set", "brightness=5"])
    assert (code, stdout, stderr) == (0, f"applied {picked}\n", "")
    edits = walictl.EditsStore.load(env["wallpapers"].parent / "edits.json")
    assert edits.get(picked) == {"rotate": 90, "brightness": 5}
    first = noctalia.default
    assert first.stem == picked and first.is_relative_to(walictl.variant_dir(picked))
    history = load_history(walictl)
    assert [e.id for e in history.entries] == ["PXL_20210608_111152739", picked] and history.cursor == 1
    assert history.entries[1].path == str(first), "the entry's path follows the variant"
    assert run_cli(walictl, ["observe"])[1] == f"unchanged {picked}\n", "no duplicate observed entry"
    # a second apply with a different recipe renders to a different path, sets it, and prunes the first
    code, stdout, _ = run_cli(walictl, ["variant", "apply", "--set", "rotate=180"])
    assert (code, stdout) == (0, f"applied {picked}\n")
    second = noctalia.default
    assert second != first and second.stem == picked
    assert noctalia.calls[-1] == ["noctalia", "msg", "wallpaper-set", str(second)]
    assert renders_of(walictl, picked) == [second] and not first.exists()
    assert load_history(walictl).entries[1].path == str(second)
    # applying the same recipe again re-sets without rendering
    calls = len(magick_calls(fake_magick))
    assert run_cli(walictl, ["variant", "apply", "--set", "rotate=180"])[0] == 0
    assert len(magick_calls(fake_magick)) == calls and noctalia.calls[-1] == ["noctalia", "msg", "wallpaper-set", str(second)]
    # apply with all defaults behaves as reset
    code, stdout, _ = run_cli(walictl, ["variant", "apply", "--set", "rotate=0"])
    assert (code, stdout) == (0, f"reset {picked}\n")
    assert walictl.EditsStore.load(env["wallpapers"].parent / "edits.json").get(picked) is None
    assert noctalia.default == env["wallpapers"] / f"{picked}.jpg"
    assert renders_of(walictl, picked) == []
    assert load_history(walictl).entries[1].path == str(env["wallpapers"] / f"{picked}.jpg")


def test_variant_apply_on_another_photo_does_not_touch_the_wallpaper(
    walictl: ModuleType, env: dict[str, Path], noctalia: FakeNoctalia, fake_magick: Path
) -> None:
    enable_edits(env)
    code, stdout, _ = run_cli(walictl, ["variant", "apply", "PXL_20220402_162957459", "--set", "anchor=bottom"])
    assert (code, stdout) == (0, "applied PXL_20220402_162957459\n")
    assert noctalia.default == env["wallpapers"] / "PXL_20210608_111152739.jpg"
    assert len(renders_of(walictl, "PXL_20220402_162957459")) == 1
    assert not any(call[2] == "wallpaper-set" for call in noctalia.calls)
    assert run_cli(walictl, ["variant", "apply", "PXL_20220402_162957459", "--set", "anchor=top"])[0] == 0
    assert len(renders_of(walictl, "PXL_20220402_162957459")) == 1, "a photo that is not displayed is pruned at once"
    code, _, stderr = run_cli(walictl, ["variant", "apply", "nope", "--set", "rotate=90"])
    assert (code, stderr) == (1, "unknown photo id: nope\n")


def test_variant_apply_failures_leave_state_consistent(
    walictl: ModuleType, env: dict[str, Path], noctalia: FakeNoctalia, fake_magick: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    enable_edits(env)
    edits = env["wallpapers"].parent / "edits.json"
    photo = "PXL_20210608_111152739"
    assert run_cli(walictl, ["variant", "apply", "--set", "rotate=90"])[0] == 0
    first = noctalia.default
    # render failure: nothing saved, nothing published
    monkeypatch.setenv("FAKE_MAGICK_FAIL", "1")
    code, _, stderr = run_cli(walictl, ["variant", "apply", "--set", "rotate=180"])
    assert (code, stderr) == (1, "magick failed: boom\n")
    assert walictl.EditsStore.load(edits).get(photo) == {"rotate": 90}
    assert renders_of(walictl, photo) == [first]
    monkeypatch.delenv("FAKE_MAGICK_FAIL")
    # recipe-save failure: temp discarded, old render and recipe intact
    edits.chmod(0o444)
    edits.parent.chmod(0o555)
    try:
        code, _, stderr = run_cli(walictl, ["variant", "apply", "--set", "rotate=270"])
    finally:
        edits.parent.chmod(0o755)
        edits.chmod(0o644)
    assert code == 1 and "edits.json" in stderr
    assert walictl.EditsStore.load(edits).get(photo) == {"rotate": 90}
    assert renders_of(walictl, photo) == [first]
    assert not list(walictl.variant_dir(photo).rglob("*.tmp.jpg"))
    # rejected wallpaper change: recipe and new render stay, the old render is not pruned
    noctalia.reject_set = "busy"
    code, _, stderr = run_cli(walictl, ["variant", "apply", "--set", "rotate=270"])
    assert code == 1 and "busy" in stderr
    assert walictl.EditsStore.load(edits).get(photo) == {"rotate": 270}
    assert len(renders_of(walictl, photo)) == 2 and first.exists()
    assert noctalia.default == first


def test_variant_reset_keeps_renders_when_wallpaper_change_is_rejected(
    walictl: ModuleType, env: dict[str, Path], noctalia: FakeNoctalia, fake_magick: Path
) -> None:
    enable_edits(env)
    photo = "PXL_20210608_111152739"
    assert run_cli(walictl, ["variant", "apply", "--set", "rotate=90"])[0] == 0
    rendered = noctalia.default
    noctalia.reject_set = "busy"
    code, _, stderr = run_cli(walictl, ["variant", "reset"])
    assert code == 1 and "busy" in stderr
    assert walictl.EditsStore.load(env["wallpapers"].parent / "edits.json").get(photo) is None
    assert rendered.exists(), "the displayed file is never deleted before a replacement succeeds"
    # a second rejected change, this time a selection, still deletes nothing
    assert run_cli(walictl, ["later"])[0] == 1
    assert rendered.exists()
    noctalia.reject_set = None
    # the next successful selection of the photo resolves to the library file and prunes
    assert run_cli(walictl, ["later"])[0] == 0
    assert run_cli(walictl, ["earlier"])[0] == 0
    assert noctalia.default == env["wallpapers"] / f"{photo}.jpg"
    assert renders_of(walictl, photo) == []
    code, _, stderr = run_cli(walictl, ["variant", "reset"])
    assert (code, stderr) == (1, f"no recipe: {photo}\n")


def test_variant_apply_holds_the_history_lock(
    walictl: ModuleType, env: dict[str, Path], noctalia: FakeNoctalia, fake_magick: Path
) -> None:
    import threading

    enable_edits(env)
    release = threading.Event()
    taken = threading.Event()

    def holder() -> None:
        with walictl.locked(walictl.history_lock()):
            taken.set()
            release.wait(2)

    thread = threading.Thread(target=holder)
    thread.start()
    assert taken.wait(2)
    try:
        walictl_fast = load_walictl()
        normal_lock = walictl_fast.locked

        def short_lock(path: Path, timeout: float = 10.0) -> Any:
            return normal_lock(path, timeout=0.2)

        walictl_fast.locked = short_lock  # type: ignore[assignment]
        for argv in (["variant", "apply", "--set", "rotate=90"], ["variant", "reset"]):
            code, _, stderr = run_cli(walictl_fast, argv)
            assert code == 1 and stderr.startswith("timed out waiting for"), argv
        assert magick_calls(fake_magick) == [], "no render before the history lock is held"
    finally:
        release.set()
        thread.join(2)
    assert not thread.is_alive()
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --frozen pytest -q tests/test_walictl.py -k variant`
Expected: FAIL: argparse exits 2 on the unknown `variant` subcommand.

- [ ] **Step 3: Implement**

Add to the commands section:

```python
def _edits(ctx: Context) -> EditsConfig:
    if ctx.config.edits is None:
        raise WalictlError("config key edits_file is required")
    return ctx.config.edits


def _library_source(library: dict[str, Path], photo: str) -> Path:
    try:
        return library[photo]
    except KeyError as exc:
        raise WalictlError(f"unknown photo id: {photo}") from exc


def update_history_path(displayed_before: Path, photo: str, new_path: Path, now: str) -> None:
    """Point the current history entry at the photo's new file. Caller holds the history lock."""
    path = history_path()
    history = History.load(path)
    reconcile(history, displayed_before, now)
    current = history.current()
    if current is not None and current.id == photo:
        current.path = str(new_path)
    history.save(path)


def prune_previews(photo: str, keep: Path) -> None:
    """Remove the other previews of the photo. Caller holds variants.lock."""
    for stale in preview_dir(photo).iterdir():
        if stale != keep:
            stale.unlink()


def cmd_variant_show(ctx: Context, args: argparse.Namespace) -> int:
    edits = _edits(ctx)
    photo = args.photo_id or _current_id(ctx)
    library = scan_library(ctx.config.wallpaper_dir)
    with locked(edits_lock()):
        recipe = EditsStore.load(edits.file).get(photo)
    variant = current_variant(ctx.config, library, photo)
    payload = {
        "ok": True,
        "id": photo,
        "edited": recipe is not None,
        "recipe": effective(recipe or {}),
        "variant_path": str(variant) if variant else None,
    }
    json.dump(payload, ctx.out)
    ctx.out.write("\n")
    return 0


def cmd_variant_preview(ctx: Context, args: argparse.Namespace) -> int:
    edits = _edits(ctx)
    photo = args.photo_id or _current_id(ctx)
    recipe = parse_settings(args.set)
    output_required(recipe, edits.output)
    source = _library_source(scan_library(ctx.config.wallpaper_dir), photo)
    key = render_key(recipe, edits.output, source_identity(source))
    dest = preview_dir(photo) / f"{key[:8]}.jpg"
    with locked(variants_lock()):
        if not dest.is_file():
            tmp = render_to_temp(source, recipe, edits.output, dest.parent, PREVIEW_WIDTH)
            os.replace(tmp, dest)
        prune_previews(photo, keep=dest)
    ctx.out.write(f"{dest}\n")
    return 0


def _reset_variant(ctx: Context, edits: EditsConfig, photo: str, displayed: Path, library: dict[str, Path]) -> None:
    """Caller holds the history lock. Order: recipe → wallpaper → history → prune (only after success)."""
    with locked(edits_lock()):
        store = EditsStore.load(edits.file)
        if not store.remove(photo):
            raise WalictlError(f"no recipe: {photo}")
        store.save(edits.file)
    if photo == photo_id(displayed):
        original = _library_source(library, photo)
        ctx.noctalia.set_default(original)  # raises on rejection: the prune below never runs
        update_history_path(displayed, photo, original, utc_now())
    with locked(variants_lock()):
        prune_variants(photo, keep=None)
    ctx.out.write(f"reset {photo}\n")


def cmd_variant_apply(ctx: Context, args: argparse.Namespace) -> int:
    edits = _edits(ctx)
    recipe = parse_settings(args.set)
    output_required(recipe, edits.output)
    with locked(history_lock()):
        displayed = ctx.noctalia.get_default()
        photo = args.photo_id or photo_id(displayed)
        library = scan_library(ctx.config.wallpaper_dir)
        source = _library_source(library, photo)
        if not recipe:
            _reset_variant(ctx, edits, photo, displayed, library)
            return 0
        key = render_key(recipe, edits.output, source_identity(source))
        target = variant_file(photo, key)
        tmp: Path | None = None
        with locked(variants_lock()):
            if not target.is_file():
                tmp = render_to_temp(source, recipe, edits.output, target.parent)
        try:
            with locked(edits_lock()):
                store = EditsStore.load(edits.file)
                store.set(photo, recipe, utc_now())
                store.save(edits.file)
        except BaseException:
            if tmp is not None:
                tmp.unlink(missing_ok=True)
            raise
        if tmp is not None:
            with locked(variants_lock()):
                publish_variant(tmp, photo, key)
        if photo == photo_id(displayed):
            ctx.noctalia.set_default(target)  # raises on rejection: the prune below never runs
            update_history_path(displayed, photo, target, utc_now())
        with locked(variants_lock()):
            prune_variants(photo, keep=target)
    ctx.out.write(f"applied {photo}\n")
    return 0


def cmd_variant_reset(ctx: Context, args: argparse.Namespace) -> int:
    edits = _edits(ctx)
    with locked(history_lock()):
        displayed = ctx.noctalia.get_default()
        photo = args.photo_id or photo_id(displayed)
        library = scan_library(ctx.config.wallpaper_dir)
        _reset_variant(ctx, edits, photo, displayed, library)
    return 0


VARIANT_COMMANDS: dict[str, Callable[[Context, argparse.Namespace], int]] = {
    "show": cmd_variant_show,
    "preview": cmd_variant_preview,
    "apply": cmd_variant_apply,
    "reset": cmd_variant_reset,
}


def cmd_variant(ctx: Context, args: argparse.Namespace) -> int:
    return VARIANT_COMMANDS[args.action](ctx, args)
```

Register `"variant": cmd_variant` in `COMMANDS`. In `build_parser`, after the `neighbors` parser:

```python
    variant = subparsers.add_parser("variant", help="per-photo adjustments rendered into a cached variant")
    actions = variant.add_subparsers(dest="action", required=True)
    show = actions.add_parser("show", help="the photo's effective recipe")
    show.add_argument("photo_id", nargs="?", default=None, type=photo_id_arg)
    show.add_argument("--json", action="store_true", required=True)
    for name, help_text in (
        ("preview", "render a 560px-wide preview of the given settings; print its path"),
        ("apply", "replace the recipe with the given settings, render, and show it when displayed"),
    ):
        sub = actions.add_parser(name, help=help_text)
        sub.add_argument("photo_id", nargs="?", default=None, type=photo_id_arg)
        sub.add_argument("--set", action="append", default=[], metavar="KEY=VALUE")
    reset = actions.add_parser("reset", help="remove the recipe and its cached render")
    reset.add_argument("photo_id", nargs="?", default=None, type=photo_id_arg)
```

`write_json_atomic` raising `PermissionError` (an `OSError`) is caught by `main` and printed with the edits path in the message, which the save-failure test checks with `"edits.json" in stderr`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --frozen pytest -q`
Expected: all pass. The lock test expects no `magick` call: `apply` acquires the history lock before scanning or rendering.

- [ ] **Step 5: Document**

In `docs/noctalia-wallpaper-switcher.md`, add to the Files table:

```markdown
| `<edits_file>` | Per-photo edit recipes (`edits.json`), synced beside favorites; optional |
| `$XDG_CACHE_HOME/wali/variants/<id>/<key>/` | One rendered variant per recipe/output/source key, per host |
| `$XDG_CACHE_HOME/wali/preview/<id>/` | Downscaled previews for the panel's edit mode |
```

to the commands block:

```
walictl variant show [<id>] --json          # effective recipe and cached variant path
walictl variant preview [<id>] --set k=v..  # 560px preview of the settings; prints its path
walictl variant apply [<id>] --set k=v..    # replace the recipe, render, show it when displayed
walictl variant reset [<id>]                # drop the recipe and its renders
```

and a paragraph after the hidden-photos one:

```markdown
Quick edits are recipes: `rotate` (0/90/180/270), `brightness`, `contrast`
(-100..100), `saturation` (0..200), `hue` (-180..180), `blur` (0..20), `noise`,
`bloom` (0..100), and `anchor` (center/top/bottom/left/right, a crop to the
output aspect from that edge; needs `[edits] output = "WxH"` in the host
config). Set `edits_file` to turn them on. `walictl` renders a recipe with
`magick` into a per-host cache the first time the photo is selected there;
each distinct recipe, output size, or library file gets its own keyed path,
because Noctalia ignores a wallpaper change to the path it already shows.
Stale renders are removed only after a wallpaper change succeeds. `apply` and
`reset` re-set the wallpaper when the photo is on screen and rewrite its
history entry's path, so history keeps one entry per photo.
```

Also document the config keys in the same file's config text: after the `[sampling]` description, add `edits_file = "~/d/linux/backgrounds/edits.json"` and `[edits] output = "3440x1440"` as an example.

- [ ] **Step 6: Verify and commit**

Run: `just verify`

```bash
tasks done <step-5-id> "walictl variant show/preview/apply/reset with keyed paths, lock order, and deferred pruning; docs"
git add bin/walictl tests/test_walictl.py docs/noctalia-wallpaper-switcher.md tasks
git commit -m "feat(walictl): variant show, preview, apply, and reset"
```

---

### Task 6: Real-ImageMagick parity test

**Files:**
- Test: `tests/test_walictl.py`

**Interfaces:**
- Consumes: `render`, `magick_argv`, `PREVIEW_WIDTH`. Skipped when `shutil.which("magick")` is `None`.

- [ ] **Step 1: Write the test**

```python
@pytest.mark.skipif(shutil.which("magick") is None, reason="ImageMagick is not installed")
def test_preview_matches_downscaled_full_render(walictl: ModuleType, tmp_path: Path) -> None:
    source = tmp_path / "PXL_20210608_111152739.jpg"
    subprocess.run(
        ["magick", "-size", "1200x800", "plasma:fractal", "-seed", "7", "-quality", "95", str(source)],
        check=True, capture_output=True,
    )
    recipe = {"rotate": 90, "anchor": "top", "blur": 6, "bloom": 40, "saturation": 70}
    output = (1600, 1000)
    full, preview = tmp_path / "full.jpg", tmp_path / "preview.jpg"
    walictl.render(source, recipe, output, full)
    walictl.render(source, recipe, output, preview, walictl.PREVIEW_WIDTH)
    shrunk = tmp_path / "shrunk.jpg"
    subprocess.run(["magick", str(full), "-resize", f"{walictl.PREVIEW_WIDTH}x", str(shrunk)], check=True, capture_output=True)
    sizes = [
        subprocess.run(["magick", "identify", "-format", "%w %h", str(p)], check=True, capture_output=True, text=True).stdout
        for p in (shrunk, preview)
    ]
    assert sizes[0] == sizes[1], f"preview {sizes[1]!r} must have the shrunk full render's size {sizes[0]!r}"
    compare = subprocess.run(
        ["magick", "compare", "-metric", "RMSE", str(shrunk), str(preview), "null:"], capture_output=True, text=True
    )
    # compare exits 1 when images differ at all; the metric is what matters: "123.4 (0.0188)"
    normalized = float(compare.stderr.strip().split("(")[1].rstrip(")"))
    assert normalized < 0.03, f"preview diverges from the full render: RMSE {normalized}"
```

(add `import shutil` to the test imports.)

- [ ] **Step 2: Run it**

Run: `uv run --frozen pytest -q tests/test_walictl.py -k preview_matches_downscaled_full_render -rs`
Expected: PASS on this machine (`magick` installed). If the RMSE lands above 0.03, first confirm the sizes match (a one-pixel height difference from rounding shows up as a size assertion, not a metric); a real divergence means the preview's scaled `blur`/bloom radius or the crop box is off in `magick_argv`, and the fix goes there.

- [ ] **Step 3: Verify and commit**

Run: `just verify`

```bash
tasks done <step-6-id> "real-magick preview parity test"
git add tests/test_walictl.py tasks
git commit -m "test(walictl): preview parity against a real ImageMagick render"
```

---

### Task 7: Panel logic for edit mode

**Files:**
- Modify: `integrations/noctalia-plugin/logic.luau`
- Modify: `integrations/noctalia-plugin/plugin.toml` (`capture_keys` adds `"a"`), `tests/wali.zsh` (its `capture_keys` assertion), `integrations/noctalia-plugin/README.md` (key table)
- Test: `integrations/noctalia-plugin/plugin_test.lua`

**Interfaces:**
- Produces: `Logic.sliders` — ordered list of `{ key, label, min, max, default }` for brightness, contrast, saturation, hue, blur, noise, bloom; `Logic.rotations = { 0, 90, 180, 270 }`; `Logic.anchors = { "center", "top", "bottom", "left", "right" }`; `Logic.recipeDefaults` (the same defaults as `walictl`'s `RECIPE_DEFAULTS`); `Logic.setArguments(recipe) -> { "--set", "k=v", ... }` for keys differing from the defaults, keys in `Logic.recipeKeys` order; `Logic.variantCommand(action, photoId, recipe) -> argv` (`show` appends `--json`, `preview`/`apply` append the settings, `reset` neither); `Logic.decodeVariant(text, decoder) -> { id, edited, recipe, variant_path } | nil, error`; `Logic.previewPath(stdout) -> string | nil, error` (the trimmed single line); `Logic.isDefaultRecipe(recipe) -> boolean`.

- [ ] **Step 1: Write the failing tests**

In `plugin_test.lua`, after the hidden-photo logic assertions:

```lua
equal(#Logic.sliders, 7)
equal(Logic.sliders[1], { key = "brightness", label = "Brightness", min = -100, max = 100, default = 0 })
equal(Logic.sliders[3], { key = "saturation", label = "Saturation", min = 0, max = 200, default = 100 })
equal(Logic.sliders[5], { key = "blur", label = "Blur", min = 0, max = 20, default = 0 })
equal(Logic.recipeDefaults, { rotate = 0, brightness = 0, contrast = 0, saturation = 100, hue = 0, blur = 0, noise = 0, bloom = 0, anchor = "center" })
assert(Logic.isDefaultRecipe(Logic.recipeDefaults))
assert(not Logic.isDefaultRecipe({ rotate = 90 }))
equal(Logic.setArguments({ rotate = 90, saturation = 100, brightness = -10, anchor = "top" }), {
  "--set", "rotate=90", "--set", "brightness=-10", "--set", "anchor=top",
})
equal(Logic.setArguments({}), {})
equal(Logic.variantCommand("show", "PXL_1"), { "walictl", "variant", "show", "PXL_1", "--json" })
equal(Logic.variantCommand("preview", "PXL_1", { blur = 2 }), { "walictl", "variant", "preview", "PXL_1", "--set", "blur=2" })
equal(Logic.variantCommand("apply", "PXL_1", { rotate = 180, hue = 0 }), { "walictl", "variant", "apply", "PXL_1", "--set", "rotate=180" })
equal(Logic.variantCommand("reset", "PXL_1"), { "walictl", "variant", "reset", "PXL_1" })

local shown = { ok = true, id = "PXL_1", edited = true, variant_path = "/c/PXL_1.jpg",
  recipe = { rotate = 90, brightness = 0, contrast = 0, saturation = 100, hue = 0, blur = 0, noise = 0, bloom = 0, anchor = "top" } }
equal(Logic.decodeVariant("shown", function() return shown end), shown)
local badVariant, badVariantError = Logic.decodeVariant("x", function() return { ok = true, id = "PXL_1", edited = false, recipe = { rotate = "90" } } end)
assert(badVariant == nil and badVariantError:find("rotate", 1, true))
badVariant, badVariantError = Logic.decodeVariant("x", function() return { ok = true, id = "PXL_1", edited = false, recipe = { rotate = 0 } } end)
assert(badVariant == nil and badVariantError:find("brightness", 1, true), "every recipe key is required")
badVariant, badVariantError = Logic.decodeVariant("x", function() return { ok = false } end)
assert(badVariant == nil and badVariantError:find("failure", 1, true))
equal(Logic.previewPath("/cache/wali/preview/PXL_1.abcd1234.jpg\n"), "/cache/wali/preview/PXL_1.abcd1234.jpg")
local noPath, noPathError = Logic.previewPath("  \n")
assert(noPath == nil and noPathError:find("path", 1, true))
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `lua integrations/noctalia-plugin/plugin_test.lua`
Expected: FAIL at `#Logic.sliders` (`attempt to get length of a nil value`).

- [ ] **Step 3: Implement**

In `logic.luau`, before `return M`:

```lua
M.sliders = {
  { key = "brightness", label = "Brightness", min = -100, max = 100, default = 0 },
  { key = "contrast", label = "Contrast", min = -100, max = 100, default = 0 },
  { key = "saturation", label = "Saturation", min = 0, max = 200, default = 100 },
  { key = "hue", label = "Hue", min = -180, max = 180, default = 0 },
  { key = "blur", label = "Blur", min = 0, max = 20, default = 0 },
  { key = "noise", label = "Noise", min = 0, max = 100, default = 0 },
  { key = "bloom", label = "Bloom", min = 0, max = 100, default = 0 },
}
M.rotations = { 0, 90, 180, 270 }
M.anchors = { "center", "top", "bottom", "left", "right" }
M.recipeKeys = { "rotate", "brightness", "contrast", "saturation", "hue", "blur", "noise", "bloom", "anchor" }
M.recipeDefaults = {
  rotate = 0, brightness = 0, contrast = 0, saturation = 100, hue = 0, blur = 0, noise = 0, bloom = 0, anchor = "center",
}

function M.isDefaultRecipe(recipe)
  for _, key in ipairs(M.recipeKeys) do
    if recipe[key] ~= nil and recipe[key] ~= M.recipeDefaults[key] then return false end
  end
  return true
end

function M.setArguments(recipe)
  local args = {}
  for _, key in ipairs(M.recipeKeys) do
    local value = recipe[key]
    if value ~= nil and value ~= M.recipeDefaults[key] then
      args[#args + 1] = "--set"
      args[#args + 1] = key .. "=" .. tostring(value)
    end
  end
  return args
end

function M.variantCommand(action, photoId, recipe)
  local argv = { "walictl", "variant", action, photoId }
  if action == "show" then
    argv[#argv + 1] = "--json"
  elseif action == "preview" or action == "apply" then
    for _, arg in ipairs(M.setArguments(recipe or {})) do argv[#argv + 1] = arg end
  end
  return argv
end

function M.validateVariant(payload)
  if type(payload) ~= "table" then return nil, "walictl variant show did not return an object" end
  if payload.ok ~= true then return nil, "walictl variant show reported failure" end
  if type(payload.id) ~= "string" then return nil, "walictl variant show returned an invalid id field" end
  if type(payload.edited) ~= "boolean" then return nil, "walictl variant show returned an invalid edited field" end
  if payload.variant_path ~= nil and type(payload.variant_path) ~= "string" then
    return nil, "walictl variant show returned an invalid variant_path field"
  end
  if type(payload.recipe) ~= "table" then return nil, "walictl variant show returned an invalid recipe field" end
  for _, key in ipairs(M.recipeKeys) do
    local expected = key == "anchor" and "string" or "number"
    if type(payload.recipe[key]) ~= expected then
      return nil, "walictl variant show returned an invalid recipe." .. key .. " field"
    end
  end
  return payload
end

function M.decodeVariant(text, decoder)
  local decoded, payload, decodeError = pcall(decoder, text)
  if not decoded then return nil, tostring(payload) end
  if payload == nil then return nil, tostring(decodeError or "walictl variant show returned invalid JSON") end
  return M.validateVariant(payload)
end

function M.previewPath(stdout)
  local line = tostring(stdout or ""):match("^%s*(.-)%s*$")
  if line == "" then return nil, "walictl variant preview returned no path" end
  return line
end
```

In `plugin.toml`, add `"a"` to `capture_keys` after `"y"`; mirror the list in `tests/wali.zsh`. In the README key table add `| \`a\` | Toggle edit mode (adjustments) |`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `lua integrations/noctalia-plugin/plugin_test.lua && zsh tests/wali.zsh`
Expected: both pass.

- [ ] **Step 5: Verify and commit**

Run: `just verify`

```bash
tasks done <step-7-id> "Logic: slider table, recipe helpers, variant commands and decoding; key a"
git add integrations/noctalia-plugin tests/wali.zsh tasks
git commit -m "feat(panel): edit-mode logic and manifest key"
```

---

### Task 8: Panel edit mode UI

**Files:**
- Modify: `integrations/noctalia-plugin/panel.luau`
- Modify: `integrations/noctalia-plugin/README.md`, `docs/noctalia-wallpaper-switcher.md`
- Test: `integrations/noctalia-plugin/plugin_test.lua`

**Interfaces:**
- Consumes: Task 7's `Logic` API; `state`, `render`, `refresh`, `run`, `resultError`, `trimmed`, `utilityButton`, `frame`, `frameHeight` from `panel.luau`; `ui.slider`.
- Produces: `state.edit = nil | { id, recipe, generation, previewPath, pending, seeded, previewing, edited }`; an `adjust` utility button (key `a`); in edit mode the frame is 200 px and shows `state.edit.previewPath or state.current.path`; a `ui.scroll` of slider rows (`key = "slider:<key>"`), rotate buttons (`rotate:<deg>`), anchor buttons (`anchor:<name>`), and `reset` / `cancel` / `apply` buttons. Enabled rules: draft controls (sliders, rotate, anchor) are enabled once the draft is seeded and stay enabled while a preview renders (`seeded and (not busy or previewing)`), so a change during a preview is the coalesced follow-up; Apply and Reset need the panel idle (`seeded and not busy`); everything but Cancel is disabled while `variant show` loads or an apply/reset runs.

- [ ] **Step 1: Write the failing tests**

Extend the `ui` stub node list with `"slider"`. Teach the fake decoder:

```lua
      if text == "variant shown" then
        return { ok = true, id = "PXL_20260820_000000000", edited = true, variant_path = "/c/v.jpg",
          recipe = { rotate = 90, brightness = 0, contrast = 0, saturation = 100, hue = 0, blur = 0, noise = 0, bloom = 0, anchor = "top" } }
      end
      if text == "variant fresh" then
        return { ok = true, id = "PXL_20260820_000000000", edited = false, variant_path = nil,
          recipe = { rotate = 0, brightness = 0, contrast = 0, saturation = 100, hue = 0, blur = 0, noise = 0, bloom = 0, anchor = "center" } }
      end
```

Add before `print("Wali plugin tests passed")`:

```lua
-- edit mode: enter, seed, preview on change, coalesce, apply
onOpen({})
runs[#runs].callback(success("with source"))
local adjust = assert(button(rendered, "adjust"), "adjust button missing")
adjust.props.onClick()
equal(runs[#runs].command, Shell.command(Logic.variantCommand("show", "PXL_20260820_000000000")))
runs[#runs].callback(success("variant shown"))
local function slider(node, key)
  if node.type == "slider" and node.props.key == key then return node end
  for _, child in ipairs(node.children) do
    local found = slider(child, key)
    if found then return found end
  end
  return nil
end
assert(find(rendered, "scroll"), "edit mode needs a scrolling control column")
equal(find(rendered, "image").props.height, 200)
equal(assert(slider(rendered, "slider:saturation")).props.value, 100)
equal(assert(button(rendered, "rotate:90")).props.selected, true)
equal(assert(button(rendered, "anchor:top")).props.selected, true)
assert(assert(button(rendered, "reset")).props.enabled, "reset is enabled for an edited photo")
assert(button(rendered, "previous") == nil, "navigation is hidden in edit mode")

slider(rendered, "slider:brightness").props.onDragEnd(20)
equal(runs[#runs].command, Shell.command(Logic.variantCommand("preview", "PXL_20260820_000000000",
  { rotate = 90, brightness = 20, anchor = "top" })))
-- draft controls stay usable while the preview renders; apply/reset wait for idle
assert(slider(rendered, "slider:blur").props.enabled, "sliders must stay enabled during a preview")
assert(button(rendered, "rotate:180").props.enabled, "toggles must stay enabled during a preview")
assert(not button(rendered, "apply").props.enabled, "apply waits for the preview")
assert(not button(rendered, "reset").props.enabled, "reset waits for the preview")
-- a second change while the preview runs is coalesced into one follow-up request
slider(rendered, "slider:blur").props.onDragEnd(3)
assert(button(rendered, "rotate:180")).props.onClick()
local previewRuns = #runs
runs[#runs].callback(success("/cache/preview/a.jpg\n"))
equal(find(rendered, "image").props.path, "/cache/preview/a.jpg")
equal(#runs, previewRuns + 1, "pending changes send exactly one follow-up preview")
equal(runs[#runs].command, Shell.command(Logic.variantCommand("preview", "PXL_20260820_000000000",
  { rotate = 180, brightness = 20, blur = 3, anchor = "top" })))
runs[#runs].callback(success("/cache/preview/b.jpg\n"))
equal(find(rendered, "image").props.path, "/cache/preview/b.jpg")

-- a failed preview keeps the last good one and shows the error
slider(rendered, "slider:noise").props.onDragEnd(10)
runs[#runs].callback({ exitCode = 1, stdout = "", stderr = "magick failed: boom", timedOut = false })
equal(find(rendered, "image").props.path, "/cache/preview/b.jpg")
local sawError = false
for _, text in ipairs(labels(rendered)) do if text == "magick failed: boom" then sawError = true end end
assert(sawError)

-- apply sends the pinned id and the full state, then refreshes and leaves edit mode
assert(button(rendered, "apply").props.enabled, "apply is enabled when idle")
assert(button(rendered, "apply")).props.onClick()
equal(runs[#runs].command, Shell.command(Logic.variantCommand("apply", "PXL_20260820_000000000",
  { rotate = 180, brightness = 20, blur = 3, noise = 10, anchor = "top" })))
assert(not slider(rendered, "slider:blur").props.enabled, "controls are disabled while apply runs")
assert(button(rendered, "cancel").props.enabled, "cancel is always available")
runs[#runs].callback(success("applied PXL_20260820_000000000"))
equal(runs[#runs].command, Shell.command(commands.current))
runs[#runs].callback(success("with source"))
assert(find(rendered, "scroll") == nil, "apply leaves edit mode")
assert(button(rendered, "previous"), "navigation returns")

-- cancel invalidates a late preview
onKey("a", true)
assert(not slider(rendered, "slider:contrast").props.enabled, "controls are disabled until the draft is seeded")
runs[#runs].callback(success("variant fresh"))
assert(slider(rendered, "slider:contrast").props.enabled)
assert(not assert(button(rendered, "reset")).props.enabled, "reset is disabled without a recipe")
slider(rendered, "slider:contrast").props.onDragEnd(5)
local late = runs[#runs]
assert(button(rendered, "cancel")).props.onClick()
assert(find(rendered, "scroll") == nil, "cancel leaves edit mode")
late.callback(success("/cache/preview/late.jpg\n"))
equal(find(rendered, "image").props.path, "/wall/current.jpg", "a late preview must not paint the frame")

-- the pinned id survives a wallpaper change made elsewhere
onKey("a", true)
runs[#runs].callback(success("variant shown"))
__wali_state.current = { ok = true, id = "OTHER", path = "/wall/other.jpg", favorite = false, hidden = false,
  history = { cursor = 0, length = 1 } }
slider(rendered, "slider:contrast").props.onDragEnd(5)
equal(runs[#runs].command, Shell.command(Logic.variantCommand("preview", "PXL_20260820_000000000",
  { rotate = 90, contrast = 5, anchor = "top" })))
runs[#runs].callback(success("/cache/preview/c.jpg\n"))
assert(button(rendered, "reset").props.enabled, "reset is enabled for an edited photo when idle")
assert(button(rendered, "reset")).props.onClick()
equal(runs[#runs].command, Shell.command(Logic.variantCommand("reset", "PXL_20260820_000000000")))
runs[#runs].callback(success("reset PXL_20260820_000000000"))
equal(runs[#runs].command, Shell.command(commands.current))
runs[#runs].callback(success("with source"))
assert(find(rendered, "scroll") == nil)

-- navigation keys are ignored in edit mode
onKey("a", true)
runs[#runs].callback(success("variant fresh"))
local navRuns = #runs
for _, chord in ipairs({ "h", "l", "j", "k", "r", "f", "x", "shift+x" }) do onKey(chord, true) end
equal(#runs, navRuns, "edit mode must ignore navigation keys")
assert(find(rendered, "scroll"), "edit mode must survive navigation keys")
onKey("a", true)
assert(find(rendered, "scroll") == nil, "a toggles edit mode off")
```

`state` must be reachable from the test for the pinned-id case: `panel.luau` declares it `local`. Expose it for tests only by adding, at the end of `panel.luau`, `_G.__wali_state = state` guarded by `if _G.WALI_TEST then ... end`, and set `WALI_TEST = true` in `plugin_test.lua` before `dofile(here .. "panel.luau")`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `lua integrations/noctalia-plugin/plugin_test.lua`
Expected: FAIL at `adjust button missing`.

- [ ] **Step 3: Implement**

In `panel.luau`, add `edit = nil` to the initial `state` and `local editFrameHeight = 200`. After the hidden-list functions, add the edit-mode machinery:

```lua
local function editRecipe()
  local recipe = {}
  for key, value in pairs(state.edit.recipe) do recipe[key] = value end
  return recipe
end

local requestPreview

local function finishPreview(generation, result)
  state.busy = false
  if state.edit then state.edit.previewing = false end
  if state.edit == nil or state.edit.generation ~= generation then
    -- Cancelled or reopened on another photo while this preview ran.
    render()
    return
  end
  local message = resultError(result, "walictl variant preview")
  local path
  if not message then path, message = Logic.previewPath(result.stdout) end
  if message then
    state.errorText = message
  else
    state.edit.previewPath = path
    state.errorText = nil
  end
  render()
  if state.edit.pending then
    state.edit.pending = false
    requestPreview()
  end
end

requestPreview = function()
  if state.edit == nil then return end
  if not Logic.canStart(state.busy) then
    state.edit.pending = true
    return
  end
  state.busy = true
  state.edit.previewing = true
  local generation = state.edit.generation
  render()
  if not run(Logic.variantCommand("preview", state.edit.id, editRecipe()), function(result)
    finishPreview(generation, result)
  end) then
    state.busy = false
    state.edit.previewing = false
    state.errorText = "Failed to launch walictl variant preview"
    render()
  end
end

local function setRecipeValue(key, value)
  if state.edit == nil or not state.edit.seeded then return end
  state.edit.recipe[key] = value
  requestPreview()
end

local generationCounter = 0

local function enterEdit()
  if not state.current or not Logic.canStart(state.busy) then return end
  generationCounter = generationCounter + 1
  local id = state.current.id
  state.edit = {
    id = id, recipe = {}, generation = generationCounter, previewPath = nil, pending = false,
    seeded = false, previewing = false, edited = false,
  }
  state.busy = true
  state.errorText = nil
  render()
  local launched = run(Logic.variantCommand("show", id), function(result)
    state.busy = false
    if state.edit == nil or state.edit.id ~= id then
      render()
      return
    end
    local message = resultError(result, "walictl variant show")
    local payload
    if not message then payload, message = Logic.decodeVariant(result.stdout, noctalia.json.decode) end
    if message then
      state.edit = nil
      state.errorText = message
    else
      state.edit.recipe = payload.recipe
      state.edit.edited = payload.edited
      state.edit.seeded = true
    end
    render()
  end)
  if not launched then
    state.busy = false
    state.edit = nil
    state.errorText = "Failed to launch walictl variant show"
    render()
  end
end

local function leaveEdit()
  generationCounter = generationCounter + 1
  state.edit = nil
  render()
end

local function toggleEdit()
  if state.edit then leaveEdit() else enterEdit() end
end

local function finishVariantChange(action, result)
  state.busy = false
  local message = resultError(result, "walictl variant " .. action)
  if message then
    state.errorText = message
    render()
    return
  end
  generationCounter = generationCounter + 1
  state.edit = nil
  state.errorText = nil
  refresh()
end

local function applyEdit()
  if state.edit == nil or not state.edit.seeded or not Logic.canStart(state.busy) then return end
  state.busy = true
  render()
  local recipe = editRecipe()
  local launched = run(Logic.variantCommand("apply", state.edit.id, recipe), function(result)
    finishVariantChange("apply", result)
  end)
  if not launched then
    state.busy = false
    state.errorText = "Failed to launch walictl variant apply"
    render()
  end
end

local function resetEdit()
  if state.edit == nil or not state.edit.seeded or not Logic.canStart(state.busy) then return end
  state.busy = true
  render()
  local launched = run(Logic.variantCommand("reset", state.edit.id), function(result)
    finishVariantChange("reset", result)
  end)
  if not launched then
    state.busy = false
    state.errorText = "Failed to launch walictl variant reset"
    render()
  end
end
```

Rendering. In `frame(enabled)`, add a first branch:

```lua
  if state.edit and state.current then
    return ui.image({
      path = state.edit.previewPath or state.current.path, height = editFrameHeight, radius = 14, fit = "contain",
      border = "outline/0.5", borderWidth = 1,
    })
  end
```

Add the controls builder after `frame`:

```lua
local function sliderRow(spec, enabled)
  local value = state.edit.recipe[spec.key] or spec.default
  return ui.row({ align = "center", gap = 8 }, {
    ui.label({ text = spec.label, fontSize = 12, width = 78 }),
    ui.slider({ key = "slider:" .. spec.key, min = spec.min, max = spec.max, step = 1, value = value,
      controlSize = "sm", flexGrow = 1, enabled = enabled,
      onDragEnd = function(newValue) setRecipeValue(spec.key, math.floor(newValue + 0.5)) end }),
    ui.label({ text = tostring(value), fontSize = 11, fontFamily = "monospace", width = 36, textAlign = "end" }),
  })
end

local function choiceRow(label, key, choices, enabled)
  local buttons = { ui.label({ text = label, fontSize = 12, width = 78 }) }
  local current = state.edit.recipe[key] or Logic.recipeDefaults[key]
  for _, choice in ipairs(choices) do
    buttons[#buttons + 1] = ui.button({ key = key .. ":" .. tostring(choice), text = tostring(choice), fontSize = 11,
      variant = "ghost", controlSize = "sm", selected = current == choice, enabled = enabled,
      onClick = function() setRecipeValue(key, choice) end })
  end
  return ui.row({ align = "center", gap = 4 }, buttons)
end

local function editControls()
  local edit = state.edit
  -- Draft controls stay live during a preview so changes coalesce; only apply/reset wait for idle.
  local draftEnabled = edit.seeded and (not state.busy or edit.previewing)
  local actionEnabled = edit.seeded and not state.busy
  local rows = {}
  for _, spec in ipairs(Logic.sliders) do rows[#rows + 1] = sliderRow(spec, draftEnabled) end
  rows[#rows + 1] = choiceRow("Rotate", "rotate", Logic.rotations, draftEnabled)
  rows[#rows + 1] = choiceRow("Anchor", "anchor", Logic.anchors, draftEnabled)
  return ui.column({ gap = 10, flexGrow = 1 }, {
    ui.scroll({ flexGrow = 1, gap = 6 }, rows),
    ui.row({ align = "center", gap = 8 }, {
      ui.button({ key = "reset", text = "Reset", variant = "destructive", controlSize = "sm",
        enabled = actionEnabled and edit.edited, tooltip = "Remove the recipe and its renders", onClick = resetEdit }),
      ui.spacer({ flexGrow = 1 }),
      ui.button({ key = "cancel", text = "Cancel", variant = "ghost", controlSize = "sm", enabled = true, onClick = leaveEdit }),
      ui.button({ key = "apply", text = "Apply", variant = "primary", controlSize = "sm",
        enabled = actionEnabled and (not Logic.isDefaultRecipe(edit.recipe) or edit.edited),
        tooltip = "Save the recipe and render it", onClick = applyEdit }),
    }),
  })
end
```

In `render`, branch on edit mode:

```lua
render = function()
  local enabled = not state.busy
  local current = state.current
  if state.edit and current then
    panel.render(ui.column({ flexGrow = 1, gap = 12, padding = 24 }, {
      frame(enabled),
      ui.label({ text = Logic.captionDetail(current, state.errorText).text, fontSize = 12, fontFamily = "monospace",
        color = Logic.captionDetail(current, state.errorText).color, maxLines = 2 }),
      editControls(),
    }))
    return
  end
  panel.render(ui.column({ flexGrow = 1, gap = 16, padding = 24 }, {
    frame(enabled),
    caption(current, enabled),
    actions(current, enabled),
  }))
end
```

In `actions`, add the adjust button before `hide`:

```lua
    utilityButton("adjust", "adjustments", "Adjust (a)", loaded, toggleEdit),
```

In `onOpen`, add `state.edit = nil` and bump `generationCounter` (so a preview from a previous open cannot land). In `onKey`, handle edit mode first:

```lua
function onKey(chord, pressed)
  if not pressed then return end
  if chord == "a" then
    toggleEdit()
    return
  end
  if state.edit then return end
  ...existing chord handling unchanged...
end
```

Finally, for the tests, at the end of the file:

```lua
if _G.WALI_TEST then _G.__wali_state = state end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `lua integrations/noctalia-plugin/plugin_test.lua`
Expected: `Wali plugin tests passed`.

- [ ] **Step 5: Document**

In `integrations/noctalia-plugin/README.md`, add after the hide paragraph:

```markdown
Adjust (`adjustments`, `a`) opens edit mode for the photo on screen: the frame
shrinks to a preview, and a scrolling column of sliders (brightness, contrast,
saturation, hue, blur, noise, bloom), rotate and anchor toggles, and
Reset / Cancel / Apply take the rest of the panel. Every change asks
`walictl variant preview` for a 560 px render and paints it into the frame;
changes made while a preview runs are sent once, after it returns. Apply runs
`walictl variant apply` for the photo the session started on, even if the
wallpaper changed meanwhile, then re-reads the metadata. Cancel discards the
draft. Navigation keys are ignored while editing; `a` or Cancel leaves.
```

In `docs/noctalia-wallpaper-switcher.md`, extend the panel keys sentence with `` `a` toggles edit mode ``.

- [ ] **Step 6: Verify and commit**

Run: `just verify`

```bash
tasks done <step-8-id> "panel edit mode: sliders, live coalesced preview, apply/reset/cancel with pinned id"
git add integrations/noctalia-plugin docs/noctalia-wallpaper-switcher.md tasks
git commit -m "feat(panel): edit mode with live preview"
```

---

### Task 9: Host config and manual verification

**Files:**
- Modify (dotfiles repo, outside this tree): `wali/titan/config.toml` and `wali/europa/config.toml` in `~/d/dotfiles` — add `edits_file = "~/d/linux/backgrounds/edits.json"` and `[edits] output = "<that host's WxH>"` (titan: `3440x1440`; europa: read it from `niri msg outputs` there).

- [ ] **Step 1: Configure titan and load the branch**

Add the two keys to `~/d/dotfiles/wali/titan/config.toml` (the linked `~/.config/wali/config.toml`), then load the worktree plugin and CLI exactly as the hidden-photos plan's Task 7 does (relink the plugin, write the review shim over `~/bin/walictl`, disable/enable the plugin).

- [ ] **Step 2: Walk the spec's manual check**

Open the panel on a portrait or 16:9 photo, press `a`, rotate 90, anchor `top`, drag blur; confirm the preview updates and the caption shows nothing red. Apply; confirm the wallpaper changes, `walictl current --json` reports `variant_path`, and the caption shows `variant`. Cycle away (`r`) and back (`h`) and confirm the variant persists. `walictl variant reset` from a terminal and confirm the library file returns. Then on europa, after its config gains `edits_file` and `output`, select the same photo and confirm it renders there with europa's output size.

- [ ] **Step 3: Park for review, then close**

```bash
tasks park <step-9-id> "Titan configured and the branch loaded; judge the edit-mode layout, slider heights, and preview latency on the rendered panel" --waiting-on user --reason review
```

After review: restore `~/bin/walictl` from `~/d/dotfiles/bin/walictl`, relink the plugin to `~/d/wali/integrations/noctalia-plugin`, re-enable, commit the dotfiles config change in that repo, and `tasks done <step-9-id> "quick edit verified on titan; europa config added"`.

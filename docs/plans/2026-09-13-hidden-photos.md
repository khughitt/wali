# Hidden Photos Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the panel (and the CLI) hide a photo so it is never sampled again, keep the hidden set inspectable and reversible, and make every selection path honour it.

**Architecture:** `favorites.json` becomes a version-2 ratings file with `favorites` and `hidden` maps behind one `Ratings` class that enforces their exclusivity. `walictl` gains `hide`, `unhide`, and `hidden --json`; the sampler drops hidden candidates before weighting and capture-time navigation steps over them. The panel adds a hide button whose right-click opens the hidden list view, built on the same `Logic`/`panel` split as today.

**Tech Stack:** Python 3 standard library (`bin/walictl`), pytest; Luau plugin on Noctalia 5.1.0 (plugin API 28 for `panel.openContextMenu`), `lua` for `plugin_test.lua`; `just verify`.

**Spec:** `docs/specs/2026-09-13-hidden-photos-design.md`. Task `wali-0fe239` is the parent of every step below.

## Global Constraints

- `bin/walictl` stays standard-library only; `pyproject.toml` declares no runtime dependencies.
- The config key `favorites_file` and the file name `favorites.json` keep their names.
- Ratings file version becomes `2`; version `1` loads (no `hidden`) and is rewritten as `2` on the next save; any other version is `unsupported favorites version`.
- A photo is in at most one set; every writer refuses overlap with `unfavorite first: <id>` / `unhide first: <id>`; `load` refuses an overlapping file with `photo in both favorites and hidden: <id>`.
- Hidden photos are removed from sampling candidates before weighting (never weight 0), month density is computed over the full library, and no visible candidates is `every photo is hidden`.
- `hide` saves the hide before attempting a replacement; a failed replacement still exits 1 with `hidden <id>` already on stdout.
- Every failure is one line on stderr, exit 1.
- `plugin.toml` bumps `plugin_api` to `28` (context menu) and adds `"x"` and `"shift+x"` to `capture_keys`; a `plugin.toml` change needs `noctalia msg plugins disable khughitt/wali-panel` then `enable`.
- Plan `docs/plans/2026-09-13-wali-panel-pass-2.md` lands first: this plan's panel tasks assume Refresh is gone and the nav buttons are ghost.
- Run all commands from the worktree root `.worktrees/panel-scope/`. `just verify` passes before each commit. `tasks start <step-id>` before a task, `tasks done <step-id> "<what landed>"` in the same commit as its code.

---

### Task 1: `Ratings` store with exclusive `favorites` and `hidden` maps

**Files:**
- Modify: `bin/walictl` (`FAVORITES_VERSION`, the `Favorites` class, `cmd_favorite`, `cmd_favorites`, `weights`, `navigate`, `describe`, `cmd_current`)
- Test: `tests/test_walictl.py`

**Interfaces:**
- Produces: `RATINGS_VERSION = 2`; `class Ratings(favorites: dict[str, dict[str, str]], hidden: dict[str, dict[str, str]])` with `load(path) -> Ratings`, `save(path)`, `favorite_ids() -> list[str]`, `hidden_ids() -> list[str]`, `add_favorite(photo, now) -> bool`, `remove_favorite(photo) -> bool`, `add_hidden(photo, now) -> bool`, `remove_hidden(photo) -> bool`. The `add_*` methods return `False` when the photo is already in that set and raise `WalictlError` when it is in the other set. `weights(ids, ratings: Ratings, recent, sampling)` takes a `Ratings` (its hidden handling changes in Task 3). The test helper `ratings_of(walictl, favorites=(), hidden=())` replaces `favorites_of`.
- Consumes: `read_json`, `write_json_atomic`, `WalictlError`.

- [ ] **Step 1: Write the failing tests**

In `tests/test_walictl.py`, replace `test_favorites_round_trip_and_idempotent_ops`, `test_favorites_rejects_corrupt_file`, and `test_favorites_rejects_non_integer_version` with:

```python
def test_ratings_round_trip_and_idempotent_ops(walictl: ModuleType, tmp_path: Path) -> None:
    path = tmp_path / "favorites.json"
    store = walictl.Ratings.load(path)
    assert store.favorite_ids() == [] and store.hidden_ids() == []
    assert store.add_favorite("b", "2026-09-07T00:00:00Z") is True
    assert store.add_favorite("b", "2026-09-07T00:00:01Z") is False
    assert store.add_favorite("a", "2026-09-07T00:00:02Z") is True
    assert store.add_hidden("h", "2026-09-07T00:00:03Z") is True
    assert store.add_hidden("h", "2026-09-07T00:00:04Z") is False
    store.save(path)
    loaded = walictl.Ratings.load(path)
    assert loaded.favorite_ids() == ["a", "b"] and loaded.hidden_ids() == ["h"]
    assert loaded.favorites["b"] == {"added": "2026-09-07T00:00:00Z"}
    assert loaded.hidden["h"] == {"added": "2026-09-07T00:00:03Z"}
    assert loaded.remove_favorite("b") is True
    assert loaded.remove_favorite("b") is False
    assert loaded.remove_hidden("h") is True
    assert loaded.remove_hidden("h") is False
    assert json.loads(path.read_text())["version"] == 2
    assert not list(tmp_path.glob("*.tmp"))


def test_ratings_refuse_overlap_in_both_directions(walictl: ModuleType) -> None:
    store = walictl.Ratings(favorites={}, hidden={})
    store.add_favorite("f", "T")
    store.add_hidden("h", "T")
    with pytest.raises(walictl.WalictlError, match="unfavorite first: f"):
        store.add_hidden("f", "T")
    with pytest.raises(walictl.WalictlError, match="unhide first: h"):
        store.add_favorite("h", "T")
    assert store.favorite_ids() == ["f"] and store.hidden_ids() == ["h"]


def test_ratings_upgrade_version_1_on_save(walictl: ModuleType, tmp_path: Path) -> None:
    path = tmp_path / "favorites.json"
    path.write_text('{"version": 1, "favorites": {"a": {"added": "T"}}}')
    store = walictl.Ratings.load(path)
    assert store.favorite_ids() == ["a"] and store.hidden_ids() == []
    store.save(path)
    assert json.loads(path.read_text()) == {"version": 2, "favorites": {"a": {"added": "T"}}, "hidden": {}}


def test_ratings_reject_corrupt_file(walictl: ModuleType, tmp_path: Path) -> None:
    path = tmp_path / "favorites.json"
    path.write_text("{not json")
    with pytest.raises(walictl.WalictlError, match="favorites file is not valid JSON"):
        walictl.Ratings.load(path)
    path.write_text('{"version": 9, "favorites": {}, "hidden": {}}')
    with pytest.raises(walictl.WalictlError, match="unsupported favorites version"):
        walictl.Ratings.load(path)
    path.write_text('{"version": 2, "favorites": {"a": null}, "hidden": {}}')
    with pytest.raises(walictl.WalictlError, match="malformed favorites entry: a"):
        walictl.Ratings.load(path)
    path.write_text('{"version": 2, "favorites": {}, "hidden": {"a": {"added": 5}}}')
    with pytest.raises(walictl.WalictlError, match="malformed hidden entry: a"):
        walictl.Ratings.load(path)
    path.write_text('{"version": 2, "favorites": {}}')
    with pytest.raises(walictl.WalictlError, match="favorites file has no hidden object"):
        walictl.Ratings.load(path)
    path.write_text('{"version": 2, "favorites": {"a": {"added": "T"}}, "hidden": {"a": {"added": "T"}}}')
    with pytest.raises(walictl.WalictlError, match="photo in both favorites and hidden: a"):
        walictl.Ratings.load(path)


@pytest.mark.parametrize("version", [True, 1.0])
def test_ratings_reject_non_integer_version(walictl: ModuleType, tmp_path: Path, version: object) -> None:
    path = tmp_path / "favorites.json"
    path.write_text(json.dumps({"version": version, "favorites": {}, "hidden": {}}))
    with pytest.raises(walictl.WalictlError, match="unsupported favorites version"):
        walictl.Ratings.load(path)
```

Replace the `favorites_of` helper with:

```python
def ratings_of(walictl: ModuleType, favorites: tuple[str, ...] = (), hidden: tuple[str, ...] = ()) -> Any:
    store = walictl.Ratings(favorites={}, hidden={})
    for photo in favorites:
        store.add_favorite(photo, "T")
    for photo in hidden:
        store.add_hidden(photo, "T")
    return store
```

and update every caller: `favorites_of(walictl, "PXL_20210608_1")` becomes `ratings_of(walictl, favorites=("PXL_20210608_1",))` in `test_weights_zero_boosts_are_uniform_except_recent`, `test_weights_apply_favorite_and_month_density`, and `test_sample_rejects_non_finite_total`.

Update every remaining `Favorites` use in the test file:

- `walictl.Favorites(entries={})` → `walictl.Ratings(favorites={}, hidden={})`; `store.add(...)` → `store.add_favorite(...)` (in `test_current_json_contract`, `test_favorite_can_remove_an_id_whose_file_is_missing`, `test_favorites_json_lists_paths_and_existence`).
- `walictl.Favorites.load(...).ids()` → `walictl.Ratings.load(...).favorite_ids()` (in `test_favorite_toggles_current_and_explicit_ids`, `test_favorite_can_remove_an_id_whose_file_is_missing`, `test_favorite_concurrent_additions_both_land`, the three `import-favorites` tests).
- In `test_import_favorites_dedupes_and_reports`: `store.ids()` → `store.favorite_ids()` and `store.entries.values()` → `store.favorites.values()`.

Add to `test_favorite_toggles_current_and_explicit_ids`, before its final `assert`:

```python
    hidden = walictl.Ratings.load(env["favorites"])
    hidden.add_hidden("PXL_20210609_120000000", "T")
    hidden.save(env["favorites"])
    code, _, stderr = run_cli(walictl, ["favorite", "--add", "PXL_20210609_120000000"])
    assert (code, stderr) == (1, "unhide first: PXL_20210609_120000000\n")
    code, _, stderr = run_cli(walictl, ["favorite", "PXL_20210609_120000000"])
    assert (code, stderr) == (1, "unhide first: PXL_20210609_120000000\n")
    assert walictl.Ratings.load(env["favorites"]).favorite_ids() == []
```

In `test_current_json_contract` the expected payload gains `"hidden": False` after `"favorite": True`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --frozen pytest -q tests/test_walictl.py -k "ratings or favorite or current_json or weights"`
Expected: FAIL with `AttributeError: module 'walictl' has no attribute 'Ratings'`.

- [ ] **Step 3: Implement `Ratings` and switch the callers**

In `bin/walictl`, replace the block from `FAVORITES_VERSION = 1` through the end of the `Favorites` class with:

```python
RATINGS_VERSION = 2


def favorites_lock() -> Path:
    return state_dir() / "favorites.lock"


def _rating_entries(payload: dict[str, object], key: str, path: Path) -> dict[str, dict[str, str]]:
    entries = payload.get(key)
    if not isinstance(entries, dict):
        raise WalictlError(f"favorites file has no {key} object: {path}")
    checked: dict[str, dict[str, str]] = {}
    for photo, value in entries.items():
        if not isinstance(value, dict) or not isinstance(value.get("added"), str):
            raise WalictlError(f"malformed {key} entry: {photo} in {path}")
        checked[str(photo)] = {"added": value["added"]}
    return checked


@dataclass
class Ratings:
    """Favorites and hidden photos: one file, two disjoint sets."""

    favorites: dict[str, dict[str, str]]
    hidden: dict[str, dict[str, str]]

    @classmethod
    def load(cls, path: Path) -> Ratings:
        payload = read_json(path, "favorites file")
        if payload is None:
            return cls(favorites={}, hidden={})
        version = payload.get("version")
        if type(version) is not int or version not in (1, RATINGS_VERSION):
            raise WalictlError(f"unsupported favorites version in {path}: {version!r}")
        favorites = _rating_entries(payload, "favorites", path)
        # Version 1 predates hidden photos; it is rewritten as version 2 on the next save.
        hidden = _rating_entries(payload, "hidden", path) if version == RATINGS_VERSION else {}
        overlap = sorted(set(favorites) & set(hidden))
        if overlap:
            raise WalictlError(f"photo in both favorites and hidden: {overlap[0]} in {path}")
        return cls(favorites=favorites, hidden=hidden)

    def save(self, path: Path) -> None:
        write_json_atomic(path, {"version": RATINGS_VERSION, "favorites": self.favorites, "hidden": self.hidden})

    def favorite_ids(self) -> list[str]:
        return sorted(self.favorites)

    def hidden_ids(self) -> list[str]:
        return sorted(self.hidden)

    def add_favorite(self, photo_id: str, now: str) -> bool:
        if photo_id in self.hidden:
            raise WalictlError(f"unhide first: {photo_id}")
        if photo_id in self.favorites:
            return False
        self.favorites[photo_id] = {"added": now}
        return True

    def remove_favorite(self, photo_id: str) -> bool:
        return self.favorites.pop(photo_id, None) is not None

    def add_hidden(self, photo_id: str, now: str) -> bool:
        if photo_id in self.favorites:
            raise WalictlError(f"unfavorite first: {photo_id}")
        if photo_id in self.hidden:
            return False
        self.hidden[photo_id] = {"added": now}
        return True

    def remove_hidden(self, photo_id: str) -> bool:
        return self.hidden.pop(photo_id, None) is not None
```

Update `weights` to take a `Ratings` (hidden handling comes in Task 3; here only the membership test changes):

```python
def weights(ids: list[str], ratings: Ratings, recent: set[str], sampling: Sampling) -> dict[str, float]:
    months = {photo: capture_date(photo) for photo in ids}
    month_of = {photo: (d.year, d.month) for photo, d in months.items() if d is not None}
    photos_per_month = Counter(month_of.values())
    favorites_per_month = Counter(month for photo, month in month_of.items() if photo in ratings.favorites)
    result: dict[str, float] = {}
    for photo in ids:
        if photo in recent:
            result[photo] = 0.0
            continue
        weight = 1.0
        if photo in ratings.favorites:
            weight *= 1.0 + sampling.favorite_boost
        month = month_of.get(photo)
        if month is not None:
            density = favorites_per_month[month] / photos_per_month[month]
            weight *= 1.0 + sampling.period_boost * density
        result[photo] = weight
    return result
```

Update `describe` (signature and payload):

```python
def describe(
    ctx: Context, displayed: Path, library: dict[str, Path], ratings: Ratings, history: History
) -> dict[str, object]:
    photo = photo_id(displayed)
    taken = capture_date(photo)
    source = resolve_source(ctx.config, photo)
    variant = resolve_variant(ctx.config, photo)
    return {
        "ok": True,
        "id": photo,
        "date": taken.isoformat() if taken else None,
        "display_date": display_date(taken),
        "path": str(displayed),
        "source_path": str(source) if source else None,
        "variant_path": str(variant) if variant else None,
        "favorite": photo in ratings.favorites,
        "hidden": photo in ratings.hidden,
        "history": {"cursor": history.cursor if history.cursor >= 0 else None, "length": len(history.entries)},
    }
```

In `cmd_current`, `favorites = Favorites.load(...)` becomes `ratings = Ratings.load(ctx.config.favorites_file)` and is passed to `describe`. In `navigate`, the sampling branch becomes:

```python
                ratings = Ratings.load(ctx.config.favorites_file)
                weighted = weights(
                    list(library),
                    ratings,
                    history.recent_ids(ctx.config.sampling.exclude_recent),
                    ctx.config.sampling,
                )
```

Replace `cmd_favorite`:

```python
def cmd_favorite(ctx: Context, args: argparse.Namespace) -> int:
    photo = args.photo_id or _current_id(ctx)
    with locked(favorites_lock()):
        store = Ratings.load(ctx.config.favorites_file)
        removing = args.remove or (not args.add and photo in store.favorites)
        if removing:
            store.remove_favorite(photo)
            state = "unfavorited"
        else:
            if photo not in scan_library(ctx.config.wallpaper_dir):
                raise WalictlError(f"unknown photo id: {photo}")
            store.add_favorite(photo, utc_now())
            state = "favorited"
        store.save(ctx.config.favorites_file)
    ctx.out.write(f"{state} {photo}\n")
    return 0
```

In `cmd_favorites`, `store = Favorites.load(...)` → `store = Ratings.load(...)`, `store.ids()` → `store.favorite_ids()`, `store.entries[photo]` → `store.favorites[photo]`. In `cmd_import_favorites`, `store = Favorites(entries={})` → `store = Ratings(favorites={}, hidden={})` and `store.add(photo, now)` → `store.add_favorite(photo, now)` (Task 2 changes this function further). Confirm nothing else references `Favorites`: `grep -n "Favorites\b" bin/walictl` prints nothing.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --frozen pytest -q`
Expected: all pass.

- [ ] **Step 5: Verify and commit**

Run: `just verify`

```bash
tasks done <step-1-id> "Ratings store: version 2 with disjoint favorites and hidden, overlap refused by every add"
git add bin/walictl tests/test_walictl.py tasks
git commit -m "feat(walictl): ratings store with favorites and hidden maps"
```

---

### Task 2: `import-favorites --force` preserves hidden and refuses conflicts

**Files:**
- Modify: `bin/walictl` (`cmd_import_favorites`)
- Test: `tests/test_walictl.py`

**Interfaces:**
- Consumes: `Ratings` from Task 1.
- Produces: `import-favorites --force` keeps the existing `hidden` map; an imported id that is hidden fails with `hidden photos in import (unhide first): <id>[, <id>...]` and writes nothing.

- [ ] **Step 1: Write the failing test**

Add after `test_import_favorites_refuses_to_overwrite_without_force`:

```python
def test_import_favorites_force_preserves_hidden_and_refuses_conflicts(
    walictl: ModuleType, env: dict[str, Path], tmp_path: Path
) -> None:
    store = walictl.Ratings(favorites={}, hidden={})
    store.add_favorite("old", "T")
    store.add_hidden("PXL_20210609_120000000", "T")
    store.add_hidden("zzz", "T")
    store.save(env["favorites"])
    source = tmp_path / "favorites.txt"
    source.write_text("x.jpg\nPXL_20210609_120000000.jpg\nzzz.jpg\n")
    code, _, stderr = run_cli(walictl, ["import-favorites", "--force", str(source)])
    assert (code, stderr) == (1, "hidden photos in import (unhide first): PXL_20210609_120000000, zzz\n")
    unchanged = walictl.Ratings.load(env["favorites"])
    assert unchanged.favorite_ids() == ["old"] and unchanged.hidden_ids() == ["PXL_20210609_120000000", "zzz"]
    source.write_text("x.jpg\n")
    assert run_cli(walictl, ["import-favorites", "--force", str(source)])[0] == 0
    rebuilt = walictl.Ratings.load(env["favorites"])
    assert rebuilt.favorite_ids() == ["x"] and rebuilt.hidden_ids() == ["PXL_20210609_120000000", "zzz"]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `uv run --frozen pytest -q tests/test_walictl.py -k force_preserves_hidden`
Expected: FAIL: exit code 0 where 1 was expected, or `hidden_ids() == []`.

- [ ] **Step 3: Implement**

Replace the locked block in `cmd_import_favorites`:

```python
    with locked(favorites_lock()):
        if ctx.config.favorites_file.exists() and not args.force:
            raise WalictlError(f"favorites file already exists (use --force): {ctx.config.favorites_file}")
        existing = Ratings.load(ctx.config.favorites_file)
        conflicts = [photo for photo in unique_ids if photo in existing.hidden]
        if conflicts:
            raise WalictlError(f"hidden photos in import (unhide first): {', '.join(conflicts)}")
        store = Ratings(favorites={}, hidden=existing.hidden)
        for photo in unique_ids:
            store.add_favorite(photo, now)
        store.save(ctx.config.favorites_file)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --frozen pytest -q`
Expected: all pass.

- [ ] **Step 5: Verify and commit**

Run: `just verify`

```bash
tasks done <step-2-id> "import-favorites --force keeps hidden and refuses hidden ids"
git add bin/walictl tests/test_walictl.py tasks
git commit -m "feat(walictl): import-favorites preserves hidden photos"
```

---

### Task 3: Sampling and capture-time navigation exclude hidden photos

**Files:**
- Modify: `bin/walictl` (`weights`, `navigate`, `dated_position`, `cmd_neighbors`)
- Test: `tests/test_walictl.py`

**Interfaces:**
- Consumes: `Ratings`.
- Produces: `weights(ids, ratings, recent, sampling)` returns entries only for photos not in `ratings.hidden`; `navigate` raises `every photo is hidden` when the library is non-empty but no candidate is visible; `dated_position(library, photo, hidden: Collection[str]) -> tuple[list[str], int]` where the ordered list contains `photo` and every dated, non-hidden id; `cmd_neighbors` uses it.

- [ ] **Step 1: Write the failing tests**

Add after `test_weights_apply_favorite_and_month_density`:

```python
def test_weights_drop_hidden_but_keep_month_density(walictl: ModuleType) -> None:
    ids = ["PXL_20210608_1", "PXL_20210609_1", "PXL_20210610_1"]
    sampling = walictl.Sampling(exclude_recent=0, favorite_boost=0.0, period_boost=3.0)
    result = walictl.weights(ids, ratings_of(walictl, favorites=("PXL_20210608_1",), hidden=("PXL_20210610_1",)), set(), sampling)
    assert set(result) == {"PXL_20210608_1", "PXL_20210609_1"}
    # Density is 1 favorite over 3 photos in June 2021, the hidden one included.
    assert result["PXL_20210609_1"] == pytest.approx(2.0)


def test_uniform_fallback_never_picks_hidden(walictl: ModuleType) -> None:
    import random

    sampling = walictl.Sampling(exclude_recent=2, favorite_boost=0.0, period_boost=0.0)
    ratings = ratings_of(walictl, hidden=("PXL_20210610_1",))
    weighted = walictl.weights(["PXL_20210608_1", "PXL_20210609_1", "PXL_20210610_1"], ratings, {"PXL_20210608_1", "PXL_20210609_1"}, sampling)
    assert weighted == {"PXL_20210608_1": 0.0, "PXL_20210609_1": 0.0}
    picks = {walictl.sample(weighted, random.Random(seed), lambda _: None) for seed in range(20)}
    assert picks == {"PXL_20210608_1", "PXL_20210609_1"}
```

Add after `test_next_at_end_samples`:

```python
def test_random_fails_when_every_photo_is_hidden(walictl: ModuleType, env: dict[str, Path], noctalia: FakeNoctalia) -> None:
    store = ratings_of(walictl, hidden=("PXL_20210608_111152739", "PXL_20210609_120000000", "PXL_20220402_162957459"))
    store.save(env["favorites"])
    code, stdout, stderr = run_cli(walictl, ["random", "--seed", "1"])
    assert (code, stdout, stderr) == (1, "", "every photo is hidden\n")
    assert noctalia.default == env["wallpapers"] / "PXL_20210608_111152739.jpg"
```

Add after `test_neighbors_fails_for_undated_current`:

```python
def test_capture_navigation_steps_over_hidden(walictl: ModuleType, env: dict[str, Path], noctalia: FakeNoctalia) -> None:
    ratings_of(walictl, hidden=("PXL_20210609_120000000",)).save(env["favorites"])
    code, stdout, _ = run_cli(walictl, ["later"])
    assert (code, stdout) == (0, "later: PXL_20220402_162957459\n")
    code, stdout, _ = run_cli(walictl, ["earlier"])
    assert (code, stdout) == (0, "earlier: PXL_20210608_111152739\n")
    payload = json.loads(run_cli(walictl, ["neighbors", "--json"])[1])
    assert [n["id"] for n in payload["after"]] == ["PXL_20220402_162957459"]


def test_capture_navigation_from_a_hidden_current_still_has_neighbours(
    walictl: ModuleType, env: dict[str, Path], noctalia: FakeNoctalia
) -> None:
    ratings_of(walictl, hidden=("PXL_20210609_120000000",)).save(env["favorites"])
    noctalia.default = env["wallpapers"] / "PXL_20210609_120000000.jpg"
    code, stdout, _ = run_cli(walictl, ["earlier"])
    assert (code, stdout) == (0, "earlier: PXL_20210608_111152739\n")
    noctalia.default = env["wallpapers"] / "PXL_20210609_120000000.jpg"
    payload = json.loads(run_cli(walictl, ["neighbors", "--json"])[1])
    assert payload["id"] == "PXL_20210609_120000000"
    assert [n["id"] for n in payload["before"]] == ["PXL_20210608_111152739"]
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --frozen pytest -q tests/test_walictl.py -k "hidden"`
Expected: FAIL: `weights` still returns the hidden id; `random` succeeds; `later` lands on the hidden photo.

- [ ] **Step 3: Implement**

In `weights`, skip hidden photos in the loop (the month counters above the loop stay computed over all `ids`):

```python
    for photo in ids:
        if photo in ratings.hidden:
            continue
        if photo in recent:
            result[photo] = 0.0
            continue
```

In `navigate`, load ratings once for both capture-time and sampling branches, and check for an all-hidden library:

```python
        else:
            library = scan_library(ctx.config.wallpaper_dir)
            ratings = Ratings.load(ctx.config.favorites_file)
            if action in ("earlier", "later"):
                ordered, index = dated_position(library, current.id, ratings.hidden)
                index += -1 if action == "earlier" else 1
                if not 0 <= index < len(ordered):
                    raise WalictlError(f"no {action} photo in the library")
                picked = ordered[index]
            else:
                weighted = weights(
                    list(library),
                    ratings,
                    history.recent_ids(ctx.config.sampling.exclude_recent),
                    ctx.config.sampling,
                )
                if library and not weighted:
                    raise WalictlError("every photo is hidden")
                picked = sample(weighted, rng, lambda message: print(message, file=ctx.err))
```

Replace `dated_position`:

```python
def dated_position(library: dict[str, Path], photo: str, hidden: Collection[str]) -> tuple[list[str], int]:
    """Dated library ids in capture order, minus hidden ones, always including `photo`."""
    if capture_date(photo) is None:
        raise WalictlError(f"current wallpaper has no capture date: {photo}")
    dated = sorted(
        (taken, candidate)
        for candidate in library
        if (taken := capture_date(candidate)) is not None and (candidate == photo or candidate not in hidden)
    )
    ordered = [candidate for _, candidate in dated]
    if photo not in ordered:
        raise WalictlError(f"current wallpaper is not in the library: {photo}")
    return ordered, ordered.index(photo)
```

Add `Collection` to the `collections.abc` import at the top of `bin/walictl`: `from collections.abc import Callable, Collection, Iterator`. In `cmd_neighbors`:

```python
    library = scan_library(ctx.config.wallpaper_dir)
    ratings = Ratings.load(ctx.config.favorites_file)
    ordered, index = dated_position(library, photo, ratings.hidden)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --frozen pytest -q`
Expected: all pass, including the existing sampler and navigation tests.

- [ ] **Step 5: Verify and commit**

Run: `just verify`

```bash
tasks done <step-3-id> "hidden photos leave sampling candidates and capture-time navigation"
git add bin/walictl tests/test_walictl.py tasks
git commit -m "feat(walictl): exclude hidden photos from sampling and neighbours"
```

---

### Task 4: `hide`, `unhide`, and `hidden --json`

**Files:**
- Modify: `bin/walictl` (new `cmd_hide`, `cmd_unhide`, `cmd_hidden`, shared `_rating_items`; `cmd_favorites`; `COMMANDS`; `build_parser`)
- Modify: `docs/noctalia-wallpaper-switcher.md` (commands block and a hidden-photos paragraph)
- Test: `tests/test_walictl.py`

**Interfaces:**
- Consumes: `Ratings`, `navigate`, `_rng`, `_current_id`, `scan_library`, `resolve_variant`, `resolve_source`, `capture_date`, `display_date`.
- Produces: `walictl hide [<id>] [--seed N]`, `walictl unhide <id>`, `walictl hidden --json` → `{"ok": true, "hidden": [{id, added, date, display_date, path, source_path, exists}]}`. `favorites --json` items gain `date` and `display_date` too, so both lists share one shape.

- [ ] **Step 1: Write the failing tests**

In `test_favorites_json_lists_paths_and_existence`, add `"date"` and `"display_date"` to each expected item: `"date": "2021-06-08", "display_date": "June 8, 2021"` for the first, `"date": "2021-06-09", "display_date": "June 9, 2021"` for the second, `"date": "2021-09-19", "display_date": "September 19, 2021"` for the third (insert them after `"added"`).

Add after `test_favorite_concurrent_additions_both_land`:

```python
def test_hide_current_records_then_samples(walictl: ModuleType, env: dict[str, Path], noctalia: FakeNoctalia) -> None:
    code, stdout, stderr = run_cli(walictl, ["hide", "--seed", "3"])
    assert (code, stderr) == (0, "")
    history = load_history(walictl)
    assert stdout == f"hidden PXL_20210608_111152739\nrandom: {history.entries[1].id}\n"
    assert [e.origin for e in history.entries] == ["observed", "random"]
    assert history.entries[1].id != "PXL_20210608_111152739"
    assert walictl.Ratings.load(env["favorites"]).hidden_ids() == ["PXL_20210608_111152739"]
    assert json.loads(run_cli(walictl, ["current", "--json"])[1])["hidden"] is False


def test_hide_other_id_records_only(walictl: ModuleType, env: dict[str, Path], noctalia: FakeNoctalia) -> None:
    code, stdout, _ = run_cli(walictl, ["hide", "PXL_20220402_162957459"])
    assert (code, stdout) == (0, "hidden PXL_20220402_162957459\n")
    assert noctalia.default == env["wallpapers"] / "PXL_20210608_111152739.jpg"
    assert load_history(walictl).entries == []
    assert run_cli(walictl, ["hide", "PXL_20220402_162957459"])[1] == "hidden PXL_20220402_162957459\n"
    code, _, stderr = run_cli(walictl, ["hide", "nope"])
    assert (code, stderr) == (1, "unknown photo id: nope\n")


def test_hide_refuses_a_favorite(walictl: ModuleType, env: dict[str, Path], noctalia: FakeNoctalia) -> None:
    run_cli(walictl, ["favorite", "--add", "PXL_20210608_111152739"])
    code, stdout, stderr = run_cli(walictl, ["hide"])
    assert (code, stdout, stderr) == (1, "", "unfavorite first: PXL_20210608_111152739\n")
    assert walictl.Ratings.load(env["favorites"]).hidden_ids() == []


def test_hide_last_visible_photo_keeps_the_hide_and_reports_replacement_failure(
    walictl: ModuleType, env: dict[str, Path], noctalia: FakeNoctalia
) -> None:
    ratings_of(walictl, hidden=("PXL_20210609_120000000", "PXL_20220402_162957459")).save(env["favorites"])
    code, stdout, stderr = run_cli(walictl, ["hide"])
    assert (code, stdout, stderr) == (1, "hidden PXL_20210608_111152739\n", "every photo is hidden\n")
    assert walictl.Ratings.load(env["favorites"]).hidden_ids() == [
        "PXL_20210608_111152739", "PXL_20210609_120000000", "PXL_20220402_162957459",
    ]
    assert json.loads(run_cli(walictl, ["current", "--json"])[1])["hidden"] is True


def test_hide_keeps_the_hide_when_noctalia_rejects_the_replacement(
    walictl: ModuleType, env: dict[str, Path], noctalia: FakeNoctalia
) -> None:
    noctalia.reject_set = "busy"
    code, stdout, stderr = run_cli(walictl, ["hide", "--seed", "3"])
    assert code == 1 and stdout == "hidden PXL_20210608_111152739\n" and "busy" in stderr
    assert walictl.Ratings.load(env["favorites"]).hidden_ids() == ["PXL_20210608_111152739"]


def test_unhide_restores_and_rejects_unknown(walictl: ModuleType, env: dict[str, Path], noctalia: FakeNoctalia) -> None:
    run_cli(walictl, ["hide", "PXL_20220402_162957459"])
    assert run_cli(walictl, ["unhide", "PXL_20220402_162957459"])[1] == "unhidden PXL_20220402_162957459\n"
    assert walictl.Ratings.load(env["favorites"]).hidden_ids() == []
    code, _, stderr = run_cli(walictl, ["unhide", "PXL_20220402_162957459"])
    assert (code, stderr) == (1, "not hidden: PXL_20220402_162957459\n")


def test_hidden_json_mirrors_favorites_json(walictl: ModuleType, env: dict[str, Path], noctalia: FakeNoctalia) -> None:
    ratings_of(walictl, hidden=("PXL_20210608_111152739", "PXL_20210919_170859013")).save(env["favorites"])
    code, stdout, _ = run_cli(walictl, ["hidden", "--json"])
    assert code == 0
    assert json.loads(stdout) == {
        "ok": True,
        "hidden": [
            {"id": "PXL_20210608_111152739", "added": "T", "date": "2021-06-08", "display_date": "June 8, 2021", "path": str(env["wallpapers"] / "PXL_20210608_111152739.jpg"), "source_path": str(env["archive"] / "2021" / "06" / "PXL_20210608_111152739.jpg"), "exists": True},
            {"id": "PXL_20210919_170859013", "added": "T", "date": "2021-09-19", "display_date": "September 19, 2021", "path": None, "source_path": None, "exists": False},
        ],
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --frozen pytest -q tests/test_walictl.py -k "hide or hidden or favorites_json"`
Expected: FAIL: argparse exits 2 for the unknown `hide` subcommand; the favorites contract lacks `date`.

- [ ] **Step 3: Implement**

Replace `cmd_favorites` with a shared item builder and three commands:

```python
def _rating_items(ctx: Context, entries: dict[str, dict[str, str]]) -> list[dict[str, object]]:
    library = scan_library(ctx.config.wallpaper_dir)
    items = []
    for photo in sorted(entries):
        path = resolve_variant(ctx.config, photo) or library.get(photo)
        source = resolve_source(ctx.config, photo)
        taken = capture_date(photo)
        items.append(
            {
                "id": photo,
                "added": entries[photo].get("added"),
                "date": taken.isoformat() if taken else None,
                "display_date": display_date(taken),
                "path": str(path) if path else None,
                "source_path": str(source) if source else None,
                "exists": path is not None,
            }
        )
    return items


def cmd_favorites(ctx: Context, args: argparse.Namespace) -> int:
    store = Ratings.load(ctx.config.favorites_file)
    json.dump({"ok": True, "favorites": _rating_items(ctx, store.favorites)}, ctx.out)
    ctx.out.write("\n")
    return 0


def cmd_hidden(ctx: Context, args: argparse.Namespace) -> int:
    store = Ratings.load(ctx.config.favorites_file)
    json.dump({"ok": True, "hidden": _rating_items(ctx, store.hidden)}, ctx.out)
    ctx.out.write("\n")
    return 0


def cmd_hide(ctx: Context, args: argparse.Namespace) -> int:
    displayed = _current_id(ctx)
    photo = args.photo_id or displayed
    with locked(favorites_lock()):
        store = Ratings.load(ctx.config.favorites_file)
        if photo not in store.hidden:
            if photo not in scan_library(ctx.config.wallpaper_dir):
                raise WalictlError(f"unknown photo id: {photo}")
            store.add_hidden(photo, utc_now())
            store.save(ctx.config.favorites_file)
    ctx.out.write(f"hidden {photo}\n")
    # The hide is saved; a failed replacement below exits 1 without undoing it.
    if photo == displayed:
        navigate(ctx, "random", _rng(args))
    return 0


def cmd_unhide(ctx: Context, args: argparse.Namespace) -> int:
    with locked(favorites_lock()):
        store = Ratings.load(ctx.config.favorites_file)
        if not store.remove_hidden(args.photo_id):
            raise WalictlError(f"not hidden: {args.photo_id}")
        store.save(ctx.config.favorites_file)
    ctx.out.write(f"unhidden {args.photo_id}\n")
    return 0
```

Register them in `COMMANDS` (keep the dict alphabetical): `"hidden": cmd_hidden`, `"hide": cmd_hide`, `"unhide": cmd_unhide`. In `build_parser`, after the `favorites` parser:

```python
    hide = subparsers.add_parser("hide", help="hide a photo from sampling; replaces it when it is displayed")
    hide.add_argument("photo_id", nargs="?", default=None)
    hide.add_argument("--seed", type=int, default=None, help="seed the replacement sampler (tests)")
    unhide = subparsers.add_parser("unhide", help="restore a hidden photo")
    unhide.add_argument("photo_id")
    hidden = subparsers.add_parser("hidden", help="list hidden photos")
    hidden.add_argument("--json", action="store_true", required=True)
```

`_current_id` calls `ctx.noctalia.get_default()`, so an IPC failure fails `hide` before anything is recorded.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --frozen pytest -q`
Expected: all pass.

- [ ] **Step 5: Document the commands**

In `docs/noctalia-wallpaper-switcher.md`, add to the commands block after the `walictl favorites --json` line:

```
walictl hide [<id>]         # hide from sampling; when it is displayed, sample a replacement
walictl unhide <id>         # restore a hidden photo
walictl hidden --json       # hidden photos, same item shape as favorites
```

Update the `walictl current --json` comment to `# id, date, path, source_path, variant_path, favorite, hidden, history`, and add a paragraph after the "Sampling weights" paragraph:

```markdown
Hidden photos live beside favorites in the same synced file (version 2, with
`favorites` and `hidden` maps); a photo is in at most one set, and `hide`,
`favorite`, and `import-favorites` refuse to move one across without an
explicit `unhide` or `--remove`. Hidden photos are never sampled, `earlier`,
`later`, and `neighbors` step over them, and history replay does not filter
them: `current --json` reports `hidden` so a replayed hidden photo is visible
as such. `hide` records first and then replaces the displayed photo; if no
visible photo remains or Noctalia rejects the change, the hide stands and the
command exits 1.
```

- [ ] **Step 6: Verify and commit**

Run: `just verify`

```bash
tasks done <step-4-id> "walictl hide/unhide/hidden with replacement-failure semantics; docs"
git add bin/walictl tests/test_walictl.py docs/noctalia-wallpaper-switcher.md tasks
git commit -m "feat(walictl): hide, unhide, and hidden commands"
```

---

### Task 5: Panel logic for hiding

**Files:**
- Modify: `integrations/noctalia-plugin/logic.luau` (`commands`, `validateCurrent`, `refreshAfter`, new `unhideCommand`, `decodeHidden`, `hideGlyph`, `hideTooltip`)
- Modify: `integrations/noctalia-plugin/plugin.toml` (`plugin_api = 28`, `capture_keys`)
- Test: `integrations/noctalia-plugin/plugin_test.lua`, `tests/wali.zsh` (manifest assertions)

**Interfaces:**
- Consumes: the `current --json` payload with `hidden`; the `hidden --json` payload.
- Produces: `Logic.commandFor("hide")` → `{ "walictl", "hide" }`, `Logic.commandFor("hidden")` → `{ "walictl", "hidden", "--json" }`, `Logic.unhideCommand(id)` → `{ "walictl", "unhide", id }`, `Logic.decodeHidden(text, decoder) -> items | nil, error` where each item is `{ id = string, added = string?, date = string?, display_date = string?, path = string?, source_path = string?, exists = boolean }`, `Logic.hideGlyph(hidden) -> "eye" | "eye-off"`, `Logic.hideTooltip(hidden) -> string`, `Logic.refreshAfter("hide") == true`, `Logic.validateCurrent` requiring a boolean `hidden`.

- [ ] **Step 1: Read the manifest test**

`tests/wali.zsh` pins the manifest: `assert wali["plugin_api"] == 22`, `assert wali["plugin_api"] <= 23` (the ceiling is what the installed Noctalia supported when it was written), and the exact `capture_keys` list. Step 4 updates all three together with `plugin.toml`.

- [ ] **Step 2: Write the failing tests**

In `plugin_test.lua`, add `hide = { "walictl", "hide" }` and `hidden = { "walictl", "hidden", "--json" }` to the `commands` table at the top. Add `hidden = false` to the top-level `payload` fixture (after `favorite = true`) and `hidden = false` to the `"without source"` payload in the fake decoder. Add `history = { cursor = 0, length = 1 }, hidden = false` to every `validateCurrent` candidate that must pass or fail on another field (the `date`/`display_date`/`source_path`/`variant_path` loop, the `id`/`path` loop, the `favorite = "yes"` case, and the history cases from the pass-2 plan).

After the `nextTooltip` assertions, add:

```lua
equal(Logic.unhideCommand("PXL_1"), { "walictl", "unhide", "PXL_1" })
assert(Logic.refreshAfter("hide"), "hide must refresh current metadata")
local noHidden, noHiddenError = Logic.validateCurrent({ ok = true, id = "x", path = "/p", favorite = false, history = { cursor = 0, length = 1 } })
assert(noHidden == nil and noHiddenError:find("hidden", 1, true), "hidden must be required")
local badHidden, badHiddenError = Logic.validateCurrent({ ok = true, id = "x", path = "/p", favorite = false, hidden = "no", history = { cursor = 0, length = 1 } })
assert(badHidden == nil and badHiddenError:find("hidden", 1, true))
equal(Logic.hideGlyph(false), "eye-off")
equal(Logic.hideGlyph(true), "eye")
equal(Logic.hideTooltip(false), "Hide (x) · right-click: hidden list")
equal(Logic.hideTooltip(true), "Restore (x)")

local hiddenItems = {
  { id = "PXL_20260101_000000000", added = "T", date = "2026-01-01", display_date = "January 1, 2026",
    path = "/wall/a.jpg", source_path = nil, exists = true },
  { id = "gone", added = "T", date = nil, display_date = nil, path = nil, source_path = nil, exists = false },
}
equal(Logic.decodeHidden("list", function(text)
  assert(text == "list")
  return { ok = true, hidden = hiddenItems }
end), hiddenItems)
local badList, badListError = Logic.decodeHidden("x", function() return { ok = true, hidden = "nope" } end)
assert(badList == nil and badListError:find("hidden", 1, true))
badList, badListError = Logic.decodeHidden("x", function() return { ok = true, hidden = { { id = 5 } } } end)
assert(badList == nil and badListError:find("id", 1, true))
badList, badListError = Logic.decodeHidden("x", function() return { ok = false } end)
assert(badList == nil and badListError:find("failure", 1, true))
badList, badListError = Logic.decodeHidden("x", function() error("invalid JSON") end)
assert(badList == nil and badListError:find("invalid JSON", 1, true))
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `lua integrations/noctalia-plugin/plugin_test.lua`
Expected: the `commands` loop fails first: `Logic.commandFor("hide")` raises `unknown walictl action: hide`.

- [ ] **Step 4: Implement**

In `logic.luau`, extend `commands`:

```lua
  hide = { "walictl", "hide" },
  hidden = { "walictl", "hidden", "--json" },
```

Add after `M.commandFor`:

```lua
function M.unhideCommand(photoId)
  return { "walictl", "unhide", photoId }
end
```

In `M.validateCurrent`, after the `favorite` check:

```lua
  if type(payload.hidden) ~= "boolean" then return nil, "walictl current returned an invalid hidden field" end
```

Add `or action == "hide"` to `M.refreshAfter`. Add before `return M`:

```lua
function M.validateHidden(payload)
  if type(payload) ~= "table" then return nil, "walictl hidden did not return an object" end
  if payload.ok ~= true then return nil, "walictl hidden reported failure" end
  if type(payload.hidden) ~= "table" then return nil, "walictl hidden returned an invalid hidden field" end
  for index, item in ipairs(payload.hidden) do
    if type(item) ~= "table" or type(item.id) ~= "string" then
      return nil, "walictl hidden returned an invalid id in item " .. tostring(index)
    end
    if type(item.exists) ~= "boolean" then
      return nil, "walictl hidden returned an invalid exists field in item " .. tostring(index)
    end
    for _, field in ipairs({ "added", "date", "display_date", "path", "source_path" }) do
      if item[field] ~= nil and type(item[field]) ~= "string" then
        return nil, "walictl hidden returned an invalid " .. field .. " field in item " .. tostring(index)
      end
    end
  end
  return payload.hidden
end

function M.decodeHidden(text, decoder)
  local decoded, payload, decodeError = pcall(decoder, text)
  if not decoded then return nil, tostring(payload) end
  if payload == nil then return nil, tostring(decodeError or "walictl hidden returned invalid JSON") end
  return M.validateHidden(payload)
end

function M.hideGlyph(hidden)
  return hidden and "eye" or "eye-off"
end

function M.hideTooltip(hidden)
  return hidden and "Restore (x)" or "Hide (x) · right-click: hidden list"
end
```

In `plugin.toml`: `plugin_api = 28` and

```toml
capture_keys = ["h", "Left", "l", "Right", "k", "Up", "j", "Down", "r", "f", "e", "y", "x", "shift+x", "shift+question", "F1"]
```

In `tests/wali.zsh`, change the two `plugin_api` assertions to `assert wali["plugin_api"] == 28` and `assert wali["plugin_api"] <= 28` (installed Noctalia 5.1.0 carries `openContextMenu`; 28 is the verified ceiling), and the `capture_keys` list to the one above. Change the `Plugin API` line in `integrations/noctalia-plugin/README.md` to `28`.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `lua integrations/noctalia-plugin/plugin_test.lua && zsh tests/wali.zsh`
Expected: both pass.

- [ ] **Step 6: Verify and commit**

Run: `just verify`

```bash
tasks done <step-5-id> "Logic: hide/hidden/unhide commands, hidden validation, decodeHidden; plugin_api 28, x keys"
git add integrations/noctalia-plugin/logic.luau integrations/noctalia-plugin/plugin.toml integrations/noctalia-plugin/plugin_test.lua integrations/noctalia-plugin/README.md tests/wali.zsh tasks
git commit -m "feat(panel): logic and manifest for hidden photos"
```

---

### Task 6: Panel UI — hide button, context menu, hidden list view

**Files:**
- Modify: `integrations/noctalia-plugin/panel.luau`
- Modify: `integrations/noctalia-plugin/README.md` (key table, entries, behaviour paragraph)
- Modify: `docs/noctalia-wallpaper-switcher.md` (panel keys sentence)
- Test: `integrations/noctalia-plugin/plugin_test.lua`

**Interfaces:**
- Consumes: everything Task 5 produces; `startAction`, `finishAction`, `refresh`, `utilityButton`, `frame`, `frameHeight`, `state`, `run` in `panel.luau`.
- Produces: global `onHiddenMenu(actionId, context)` (the context-menu callback Noctalia calls by name); `state.view` ∈ `"photo" | "help" | "hidden"` replacing `state.showHelp`; `state.hiddenList` (`nil` while loading, else the decoded items); a `hide` button with `onRightClick`; `restore:<id>` buttons in the list view.

- [ ] **Step 1: Write the failing panel tests**

In `plugin_test.lua`, extend the `ui` stub node list with `"scroll"`, and give the `panel` stub a context-menu recorder:

```lua
local menuRequests = {}
panel = {
  render = function(tree) rendered = tree end,
  openContextMenu = function(request)
    menuRequests[#menuRequests + 1] = request
    return true
  end,
}
```

Teach the fake decoder a hidden list: inside `decode`, before the fallback `return nil, "invalid JSON"`, add:

```lua
      if text == "hidden list" then
        return { ok = true, hidden = {
          { id = "PXL_20260101_000000000", added = "T", date = "2026-01-01", display_date = "January 1, 2026",
            path = "/wall/a.jpg", exists = true },
          { id = "gone", added = "T", exists = false },
        } }
      end
      if text == "empty list" then return { ok = true, hidden = {} } end
```

Add `"hide"` to the glyph-only tooltip loop's key list. Then, at the end of the file before `print("Wali plugin tests passed")`, with `"with source"` metadata loaded (call `onOpen({})` and answer `runs[#runs].callback(success("with source"))` first):

```lua
-- hide: left-click hides and refreshes even when the command fails
onOpen({})
runs[#runs].callback(success("with source"))
local hide = assert(button(rendered, "hide"), "hide button missing")
equal(hide.props.glyph, "eye-off")
equal(hide.props.tooltip, "Hide (x) · right-click: hidden list")
hide.props.onClick()
equal(runs[#runs].command, Shell.command(commands.hide))
runs[#runs].callback({ exitCode = 1, stdout = "hidden PXL_20260820_000000000\n", stderr = "every photo is hidden", timedOut = false })
equal(runs[#runs].command, Shell.command(commands.current), "hide must refresh metadata even on failure")
runs[#runs].callback(success("with source"))
local detail = nil
for _, text in ipairs(labels(rendered)) do if text == "every photo is hidden" then detail = text end end
assert(detail, "replacement failure must stay visible after the refresh")

-- a hidden current photo shows a restore action
noctalia.json.decode = (function(original)
  return function(text)
    if text == "hidden current" then
      local copy = {}
      for k, v in pairs(payload) do copy[k] = v end
      copy.hidden = true
      return copy
    end
    return original(text)
  end
end)(noctalia.json.decode)
onOpen({})
runs[#runs].callback(success("hidden current"))
local restore = assert(button(rendered, "hide"))
equal(restore.props.glyph, "eye")
equal(restore.props.tooltip, "Restore (x)")
restore.props.onClick()
equal(runs[#runs].command, Shell.command(Logic.unhideCommand("PXL_20260820_000000000")))
runs[#runs].callback(success("unhidden PXL_20260820_000000000"))
equal(runs[#runs].command, Shell.command(commands.current), "restore must refresh metadata")
runs[#runs].callback(success("with source"))

-- right-click opens the menu; its action opens the list view
assert(button(rendered, "hide")).props.onRightClick()
equal(#menuRequests, 1)
equal(menuRequests[1].onActivate, "onHiddenMenu")
equal(menuRequests[1].items[1].id, "show-hidden")
onHiddenMenu("show-hidden", nil)
assert(find(rendered, "image") == nil, "hidden view must replace the photo")
equal(runs[#runs].command, Shell.command(commands.hidden))
runs[#runs].callback(success("hidden list"))
local scroll = assert(find(rendered, "scroll"), "hidden list must scroll")
equal(#scroll.children, 2)
local restoreRow = assert(button(rendered, "restore:gone"))
restoreRow.props.onClick()
equal(runs[#runs].command, Shell.command(Logic.unhideCommand("gone")))
runs[#runs].callback(success("unhidden gone"))
equal(runs[#runs].command, Shell.command(commands.current), "restore from the list must re-read current first")
runs[#runs].callback(success("with source"))
equal(runs[#runs].command, Shell.command(commands.hidden), "restore from the list must then reload the list")
runs[#runs].callback(success("empty list"))
assert(find(rendered, "scroll") == nil)
local empty = false
for _, text in ipairs(labels(rendered)) do if text == "Nothing hidden" then empty = true end end
assert(empty, "empty list must say so")

-- restoring the displayed photo from the list updates the caption
onOpen({})
runs[#runs].callback(success("hidden current"))
onKey("shift+x", true)
runs[#runs].callback(success("hidden list"))
onHiddenMenu("show-hidden", nil) -- a second open while idle just reloads
runs[#runs].callback(success("hidden list"))
assert(button(rendered, "restore:PXL_20260101_000000000")).props.onClick()
runs[#runs].callback(success("unhidden PXL_20260101_000000000"))
equal(runs[#runs].command, Shell.command(commands.current))
runs[#runs].callback(success("with source"))
runs[#runs].callback(success("empty list"))
onKey("x", true)
assert(find(rendered, "image") ~= nil, "x must close the list view")
equal(assert(button(rendered, "hide")).props.glyph, "eye-off", "caption state must follow the re-read current")

-- opening the list while a command is busy is ignored, so no loader is left behind
assert(button(rendered, "next")).props.onClick()
local busyRuns = #runs
onKey("shift+x", true)
equal(#runs, busyRuns, "list must not load while busy")
assert(find(rendered, "image") ~= nil, "view must not change while busy")
onHiddenMenu("show-hidden", nil)
assert(find(rendered, "image") ~= nil, "menu action must not change the view while busy")
runs[#runs].callback(success())
runs[#runs].callback(success("with source"))

-- keyboard: shift+x toggles the list, x hides from the photo view and closes the list
onKey("shift+x", true)
assert(find(rendered, "image") == nil, "shift+x must open the list view")
runs[#runs].callback(success("empty list"))
onKey("shift+x", true)
assert(find(rendered, "image") ~= nil, "shift+x must leave the list view")
onKey("shift+x", true)
runs[#runs].callback(success("empty list"))
local hideCount = #runs
onKey("x", true)
equal(#runs, hideCount, "x in the list view closes it without hiding")
assert(find(rendered, "image") ~= nil)
onKey("x", true)
equal(runs[#runs].command, Shell.command(commands.hide))
runs[#runs].callback(success("hidden PXL_20260820_000000000"))
runs[#runs].callback(success("with source"))
```

`labels` is the helper defined in the pass-2 plan's tests; it is already in the file when this plan runs.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `lua integrations/noctalia-plugin/plugin_test.lua`
Expected: FAIL at `hide button missing`.

- [ ] **Step 3: Implement the panel changes**

In `panel.luau`, replace the state line and the help toggle, and add the hidden-list machinery. State:

```lua
local state = {
  busy = false, loading = false, keepError = false, errorText = nil, current = nil,
  view = "photo", hiddenList = nil,
}
```

Replace `refresh` so a caller can keep an error message across the reload:

```lua
refresh = function(keepError)
  if not Logic.canStart(state.busy) then return end
  state.busy = true
  state.loading = true
  if not keepError then state.errorText = nil end
  state.keepError = keepError == true
  render()
  if not run(Logic.commandFor("current"), finishCurrent) then
    state.busy = false
    state.loading = false
    state.keepError = false
    state.errorText = "Failed to launch walictl current"
    render()
  end
end
```

and in `finishCurrent`, replace the success branch so a kept error survives, and reload the hidden list when that view is open (the restore-from-list path relies on this):

```lua
  else
    state.current = payload
    if not state.keepError then state.errorText = nil end
  end
  state.keepError = false
  render()
  if state.view == "hidden" then loadHidden() end
```

`loadHidden` is defined further down; declare it at the top next to `render` and `refresh` (`local loadHidden`) and assign it with `loadHidden = function() ... end` instead of `local function loadHidden()`.

In `finishAction`, make `hide` refresh on failure too, keeping the error:

```lua
local function finishAction(action, result)
  state.busy = false
  local message = resultError(result, "walictl " .. action)
  if message then
    state.errorText = message
    if action == "hide" then
      refresh(true)
      return
    end
    render()
    return
  end
  ...
```

Extend `startAction`'s guard list with `"hide"` so it needs loaded metadata:

```lua
  if not state.current and (action == "favorite" or action == "edit" or action == "earlier" or action == "later" or action == "hide") then
    return
  end
```

Add the hidden-list functions after `copyPath`:

```lua
local function finishHidden(result)
  state.busy = false
  local message = resultError(result, "walictl hidden")
  local items
  if not message then items, message = Logic.decodeHidden(result.stdout, noctalia.json.decode) end
  if message then
    state.hiddenList = {}
    state.errorText = message
  else
    state.hiddenList = items
    state.errorText = nil
  end
  render()
end

local function loadHidden()
  if not Logic.canStart(state.busy) then return end
  state.busy = true
  state.hiddenList = nil
  state.errorText = nil
  render()
  if not run(Logic.commandFor("hidden"), finishHidden) then
    state.busy = false
    state.hiddenList = {}
    state.errorText = "Failed to launch walictl hidden"
    render()
  end
end

local function openHiddenList()
  -- The view flips only when the load can start; otherwise a busy command
  -- would leave the list view showing a loader that nothing completes.
  if not Logic.canStart(state.busy) then return end
  state.view = "hidden"
  loadHidden()
end

local function closeHiddenList()
  state.view = "photo"
  state.hiddenList = nil
  render()
end

local function toggleHiddenList()
  if state.view == "hidden" then closeHiddenList() else openHiddenList() end
end

local function startUnhide(photoId)
  if not Logic.canStart(state.busy) then return end
  state.busy = true
  state.errorText = nil
  render()
  local launched = run(Logic.unhideCommand(photoId), function(result)
    state.busy = false
    local message = resultError(result, "walictl unhide")
    if message then
      state.errorText = message
      render()
      return
    end
    -- Always re-read current first: the restored photo may be the displayed
    -- one. finishCurrent reloads the list afterwards when the list is open.
    refresh()
  end)
  if not launched then
    state.busy = false
    state.errorText = "Failed to launch walictl unhide"
    render()
  end
end

local function hideOrRestore()
  if not state.current then return end
  if state.current.hidden then
    startUnhide(state.current.id)
  else
    startAction("hide")
  end
end

function onHiddenMenu(actionId, _context)
  if actionId == "show-hidden" then openHiddenList() end
end

local function openHideMenu()
  panel.openContextMenu({
    items = { { id = "show-hidden", label = "Show hidden…" } },
    onActivate = "onHiddenMenu",
  })
end
```

Replace `toggleHelp` and the top of `frame()` so views are exclusive:

```lua
local function toggleHelp()
  state.view = state.view == "help" and "photo" or "help"
  render()
end

local function hiddenRow(item, enabled)
  return ui.row({ align = "center", gap = 12 }, {
    ui.image({ path = item.path or "", width = 64, height = 40, radius = 6, fit = "cover", visible = item.path ~= nil }),
    ui.column({ gap = 2, flexGrow = 1 }, {
      ui.label({ text = item.display_date or item.date or item.id, fontSize = 14, fontWeight = "medium", maxLines = 1 }),
      ui.label({ text = item.id, fontSize = 11, fontFamily = "monospace", color = "on_surface_variant", maxLines = 1 }),
    }),
    ui.button({ key = "restore:" .. item.id, glyph = "eye", glyphSize = 16, variant = "ghost", controlSize = "sm",
      tooltip = "Restore", enabled = enabled, onClick = function() startUnhide(item.id) end }),
  })
end

local function hiddenView(enabled)
  local rows = {
    ui.row({ align = "center", gap = 8 }, {
      ui.label({ text = "Hidden photos", fontSize = 20, fontWeight = "semibold" }),
      ui.spacer({ flexGrow = 1 }),
      utilityButton("close-hidden", "x", "Back (shift+x)", true, closeHiddenList),
    }),
  }
  if state.hiddenList == nil then
    rows[#rows + 1] = ui.glyph({ name = "loader", size = 32, color = "on_surface_variant/0.6" })
  elseif #state.hiddenList == 0 then
    rows[#rows + 1] = ui.label({ text = "Nothing hidden", fontSize = 13, color = "on_surface_variant" })
  else
    local items = {}
    for _, item in ipairs(state.hiddenList) do items[#items + 1] = hiddenRow(item, enabled) end
    rows[#rows + 1] = ui.scroll({ flexGrow = 1, gap = 6 }, items)
  end
  return ui.column({ height = frameHeight, padding = 20, gap = 8, radius = 14, fill = "surface_variant" }, rows)
end

local function frame(enabled)
  if state.view == "hidden" then return hiddenView(enabled) end
  if state.view == "help" then
    -- the existing help column; add these two entries to its row list after the "f" line:
    --   "x           Hide photo", "shift+x     Hidden list",
    -- and keep the rest unchanged
  end
  -- the existing photo and placeholder branches are unchanged
end
```

`utilityButton` is defined below `frame` today; move `navButton` and `utilityButton` above `frame` so `hiddenView` can call it. In the caption, when `current.hidden` is true the detail line reads `hidden` in `tertiary`; extend `Logic.captionDetail` in `logic.luau`:

```lua
function M.captionDetail(payload, errorText)
  if errorText ~= nil then return { text = errorText, color = "error" } end
  if payload ~= nil and payload.hidden then return { text = payload.id .. " · hidden", color = "tertiary" } end
  return { text = payload and payload.id or "", color = "on_surface_variant" }
end
```

and add `equal(Logic.captionDetail({ ok = true, id = "x", path = "/p", favorite = false, hidden = true, history = { cursor = 0, length = 1 } }, nil), { text = "x · hidden", color = "tertiary" })` next to the other `captionDetail` assertions.

In `actions`, add the hide button before Edit:

```lua
    utilityButton("hide", Logic.hideGlyph(current ~= nil and current.hidden), Logic.hideTooltip(current ~= nil and current.hidden), loaded, hideOrRestore),
```

and give it the right-click handler by extending `utilityButton` with an optional sixth argument:

```lua
local function utilityButton(key, glyph, tooltip, enabled, onClick, onRightClick)
  return ui.button({ key = key, glyph = glyph, glyphSize = 16, variant = "ghost", controlSize = "sm",
    tooltip = tooltip, enabled = enabled, onClick = onClick, onRightClick = onRightClick })
end
```

passing `openHideMenu` as that argument for the hide button. `render` passes `enabled` into `frame(enabled)`. In `onOpen`, `state.view = "photo"` and `state.hiddenList = nil` replace `state.showHelp = false`. In `onKey`:

```lua
function onKey(chord, pressed)
  if not pressed then return end
  if chord == "shift+question" or chord == "F1" then
    toggleHelp()
  elseif chord == "shift+x" then
    toggleHiddenList()
  elseif chord == "x" then
    if state.view == "hidden" then closeHiddenList() elseif state.view == "photo" then hideOrRestore() end
  elseif chord == "y" then
    copyPath()
  elseif keyActions[chord] then
    startAction(keyActions[chord])
  end
end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `lua integrations/noctalia-plugin/plugin_test.lua`
Expected: `Wali plugin tests passed`. If the earlier help-toggle assertions fail because `state.view` replaced `state.showHelp`, the toggle above is the only place that reads it; fix the toggle, not the tests.

- [ ] **Step 5: Update the docs**

In `integrations/noctalia-plugin/README.md`, add to the key table after the `f` row:

```markdown
| `x` | Hide the photo (never sampled again); restore it when it is already hidden |
| `shift+x` | Toggle the hidden list in the preview area |
```

and add after the "photo-first" paragraph:

```markdown
Hide (`eye-off`) sits with the other quiet buttons. A click runs `walictl hide`,
which records the hide and samples a replacement; the panel re-reads the
metadata whether or not the replacement succeeded, so a failure ("every photo
is hidden") stays in the caption. Right-click the button, or press `shift+x`,
for the hidden list: a scrolling set of thumbnails with a Restore button each.
A photo reached through history that is hidden shows `hidden` in the caption
and turns the button into Restore.
```

In `docs/noctalia-wallpaper-switcher.md`, extend the panel keys sentence: after `` `f` toggles favorite, `` add `` `x` hides (or restores) the photo, `shift+x` opens the hidden list, ``.

- [ ] **Step 6: Verify and commit**

Run: `just verify`

```bash
tasks done <step-6-id> "panel hide button, context menu, hidden list view, x / shift+x keys, docs"
git add integrations/noctalia-plugin tasks docs/noctalia-wallpaper-switcher.md
git commit -m "feat(panel): hide photos and browse the hidden list"
```

---

### Task 7: Manual verification on the running Noctalia

**Files:** none unless review asks for changes.

- [ ] **Step 1: Load the branch — plugin and CLI**

The panel runs `walictl` by name. `~/bin/walictl` is a copy of the dotfiles shim (`~/d/dotfiles/bin/walictl`, identical bytes) that execs `~/d/wali/bin/walictl`, the main checkout, which has no `hide` and no `current.hidden` until this branch merges. Point both the plugin and the CLI at the worktree for the review, from the worktree root:

```bash
ln -sfn "$(pwd)/integrations/noctalia-plugin" ~/.config/noctalia/plugins/wali-panel
printf '#!/usr/bin/env bash\n# review shim: restored from ~/d/dotfiles/bin/walictl afterwards\nexec "%s/bin/walictl" "$@"\n' "$(pwd)" > ~/bin/walictl
walictl hidden --json   # proves the shell reaches the worktree CLI
noctalia msg plugins disable khughitt/wali-panel && noctalia msg plugins enable khughitt/wali-panel
```

`~/bin` is first on `PATH`, and Noctalia inherited that `PATH`, so the running process picks up the new shim on its next `walictl` call without a restart. The manifest changed, so the disable/enable is required; hot reload is not enough.

- [ ] **Step 2: Walk the spec's manual check**

Hide from the panel and confirm the wallpaper changes; open the hidden list by right-click and by `shift+x`; restore the photo; run `walictl random --seed 1` a few times and `walictl hidden --json` to confirm the restored photo can be sampled and the list is empty; `walictl previous` back onto a hidden photo and confirm the caption reads `hidden` and the button reads Restore.

- [ ] **Step 3: Park for review, then close**

```bash
tasks park <step-7-id> "Panel loaded from the worktree; judge the hide button placement, the context menu, and the hidden list rows" --waiting-on user --reason review
```

After review, restore both and re-enable:

```bash
cp ~/d/dotfiles/bin/walictl ~/bin/walictl
ln -sfn "$HOME/d/wali/integrations/noctalia-plugin" ~/.config/noctalia/plugins/wali-panel
noctalia msg plugins disable khughitt/wali-panel && noctalia msg plugins enable khughitt/wali-panel
tasks done <step-7-id> "hidden photos verified on the running panel"
```

Do this before the branch merges only if the review is finished; otherwise the main checkout's CLI lacks `hide` and the merged panel would fail its first hide.

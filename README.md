# wali

Wallpaper selection, history, and favorites on top of Noctalia v5.

Noctalia displays wallpapers and derives colors. `walictl` decides which photo
is shown, remembers what was shown, and keeps favorites. The Wali Panel plugin
(`khughitt/wali-panel`) is a view over `walictl current --json`, and the shell
helpers in `shell/wali.zsh` ingest and edit photos. Ownership, commands, keys,
and the config format are in `docs/noctalia-wallpaper-switcher.md`.

## Layout

| Path | Purpose |
|---|---|
| `bin/walictl` | The CLI (Python 3.11+, standard library only) |
| `shell/wali.zsh` | zsh helpers: `wali_ingest`, `wali_set`, `wali_search`, `wali_rotate`, … |
| `integrations/noctalia-plugin/` | The `khughitt/wali-panel` Noctalia v5 plugin |
| `systemd/` | `wali-rotate.timer` and its service |
| `tests/` | pytest suite for walictl, zsh suite for the helpers and the plugin manifest |
| `docs/` | Usage and ownership |

## Install

This checkout is reached as `~/d/wali` by the dotfiles repo, which owns the
wiring: `bin/walictl` there is a shim that execs `~/d/wali/bin/walictl`,
`setup.sh` links the plugin and the units, `zshrc` sources
`shell/wali.zsh`, and `wali/<host>/config.toml` there is linked to
`$XDG_CONFIG_HOME/wali/config.toml`. Run dotfiles' `setup.sh` after cloning.

Development:

```bash
just setup    # uv sync; marks .venv com.dropbox.ignored
just verify   # check + test
```

## History

The design behind walictl is `docs/specs/2026-09-07-wallpaper-management-redesign-design.md`
in the dotfiles repo, where it was written and carried out. The previous
click + sqlite CLI is on the `legacy-click-cli` branch and the `v0.1-legacy` tag.

## Pending

Ruff findings pending: run `uv run ruff check`.

- `DTZ007` at `bin/walictl:114`
- `UP017` at `bin/walictl:177`
- `I001` at `tests/test_walictl.py:1`
- `SIM117` at `tests/test_walictl.py:292`
- `DTZ007` at `tests/test_walictl.py:306`
- `SIM117` at `tests/test_walictl.py:724`
- `RUF015` at `tests/test_walictl.py:744`

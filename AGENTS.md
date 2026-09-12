Wallpaper selection, history, and favorites on top of Noctalia v5. `README.md`
has the layout; `docs/noctalia-wallpaper-switcher.md` has the ownership split
with Noctalia, the commands, the panel keys, and the config format.

## Gates

- `just setup` once per machine (`uv sync`, and the venv marked
  `com.dropbox.ignored`: the checkout lives under Dropbox). `just verify` before
  a commit: `check` (justfile format, `zsh -n`, `tasks check`) and `test`
  (pytest for `bin/walictl`, `tests/wali.zsh` for the helpers and the plugin
  manifest, `plugin_test.lua` for the panel; `lua` must be installed).
- `bin/walictl` is standard-library Python only; `pyproject.toml` declares no
  runtime dependencies on purpose. Keep it that way.

## Boundaries

- The dotfiles repo owns the wiring: its `bin/walictl` shim execs this
  checkout's, its `setup.sh` links `integrations/noctalia-plugin` and
  `systemd/` into place, its `zshrc` sources `shell/wali.zsh`, and per-host
  `config.toml` files live there under `wali/<host>/`. Nothing here should
  assume a path other than being reached as `~/d/wali`.
- `integrations/noctalia-plugin/plugin.toml` is a contract: the id
  `khughitt/wali-panel` and the panel's entries are what Noctalia's enabled
  state and the dotfiles setup tests know. `tests/wali.zsh` asserts it.
- The design behind walictl is in the dotfiles repo,
  `docs/specs/2026-09-07-wallpaper-management-redesign-design.md`; the old
  click + sqlite CLI is on the `legacy-click-cli` branch.

## Tasks workflow

- Run `tasks prime` at the start of a work session and `tasks ready` before choosing work.
- Run `tasks start ID` before implementation, add concise notes as evidence changes, and close the task with a one-line result in the same commit as the work.
- Never edit `tasks/*.md` directly; use the `tasks` CLI for every task mutation.
- Before completion, run `tasks check`. Require zero errors and report every warning.

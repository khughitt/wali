set dotenv-load := false

default:
    @just --list

# Install the dev venv and keep it out of Dropbox: the checkout is under ~/d.
setup:
    uv sync
    attr -s com.dropbox.ignored -V 1 .venv

check:
    just --fmt --check --justfile justfile
    zsh -n shell/wali.zsh tests/wali.zsh tests/tmp_cleanup.zsh
    uv run --frozen ruff check
    tasks check

test:
    uv run --frozen pytest -q
    zsh tests/wali.zsh
    @command -v lua >/dev/null || { echo 'lua is required for the Noctalia plugin tests' >&2; exit 127; }
    lua integrations/noctalia-plugin/plugin_test.lua

verify: check test

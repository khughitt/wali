set dotenv-load := false

default:
    @just --list

# Install the dev venv and keep it out of Dropbox: the checkout is under ~/d.
setup:
    uv sync
    attr -s com.dropbox.ignored -V 1 .venv

check:
    just --fmt --check --justfile justfile
    tasks check

test:
    uv run --frozen pytest -q
    @command -v lua >/dev/null || { echo 'lua is required for the Noctalia plugin tests' >&2; exit 127; }
    lua integrations/noctalia-plugin/plugin_test.lua

verify: check test

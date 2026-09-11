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

verify: check test

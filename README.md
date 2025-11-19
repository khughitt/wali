# Overview

Simple wallpaper switcher + stats.

**Basic idea**:

1. create a directory with a bunch of images you like
2. run `wali` to randomly select an image and set it as your background
    - [pywal](https://github.com/dylanaraps/pywal) is used to update color schemes

When switching, you can optionally include a character indicating how much you liked the current
background:

```
y   "yesh"
n   "newp"
Y   "YESH"
N   "never again.."
o   "ok" (default)
```

So, for example, `wali y` means "choose a new background and score the current one as positive.."

Wallpaper stats are stored in a sqlite database.

At present, this database is not used for anything.

In the future, the sampling algorithm will be modified to perform a weighted sampling, with higher
priority given to wallpapers / time ranges with favorable ratings.

# Install

```bash
git clone https://github.com/khughitt/wali
cd wali
uv sync
```

Add an environmental variable in `~/.zshenv` or some other place sourced by your shell indicating
the base directory with the images you want to use:

```bash
export WALI_DIR='/path/to/images'
```

# Usage

Basic usage (X11 with feh):
```bash
alias wali="cd ~/software/wali/ && uv run wali --image-dir=\"$WALI_DIR\" change"
wali
```

For Wayland with swww:
```bash
alias wali="cd ~/software/wali/ && uv run wali --wallpaper-backend swww --image-dir=\"$WALI_DIR\" change"
wali
```

Modify the "~/software/wali" path to indicate the directory you cloned wali to.

## Options

- `--wallpaper-backend`: Choose between `feh` (default, X11) or `swww` (Wayland)
- `--backend`: Color extraction backend (haishoku, wal, colorz, colorthief, schemer2)
- `--seasons`: Sample wallpapers with dates close to the current date
- `--file`: Specify a particular wallpaper file instead of random selection

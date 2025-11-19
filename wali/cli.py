"""
wali cli
"""

import os
import click
import sys
import subprocess
from wali import Wali, WaliVote


@click.group()
@click.option(
    "--image-dir",
    help="Top-level directory to scan for images (default: $WALI_IMAGE_DIR)",
    default="$WALI_IMAGE_DIR",
)
@click.option(
    "--db-path",
    help="Path to sqlite database (default: $XDG_CONFIG_HOME/wali/wali.db)",
    default="$XDG_CONFIG_HOME/wali/wali.db",
)
@click.option(
    "--wallpaper-backend",
    type=click.Choice(["feh", "swww"]),
    default="feh",
    help="Backend to use for setting wallpapers (default: feh)",
)
@click.pass_context
def cli(ctx, image_dir: str, db_path: str, wallpaper_backend: str):
    """Initialize CLI"""
    image_dir = os.path.expandvars(os.path.expanduser(image_dir))
    db_path = os.path.expandvars(os.path.expanduser(db_path))

    # check to make sure valid image directory provided
    if not os.path.isdir(image_dir):
        raise click.UsageError(
            f"Image directory {image_dir} does not exist. Please provide a valid image directory."
        )

    ctx.obj = {
        "wali": Wali(image_dir, db_path=db_path, wallpaper_backend=wallpaper_backend),
        "wallpaper_backend": wallpaper_backend,
    }


@cli.command
@click.argument("rating", type=str, default="o")
@click.option(
    "--backend",
    type=click.Choice(["haishoku", "wal", "colorz", "colorthief", "schemer2"]),
    default="haishoku",
    help="Backend to use for color extraction",
)
@click.option("--seasons", help="Sample dates close to current date", default=False)
@click.option(
    "--file",
    help="Specific wallpaper file path to use instead of random selection",
    type=click.Path(exists=True),
)
@click.pass_obj
def change(ctx_obj, rating: str, backend: str, seasons: bool, file: str):
    """
    Change wallpaper.

    An optional rating can be included at the end of the command to indicate a preference
    for/against the current wallpaper.

    Examples:

      wali --image-dir="~/wallpapers" change y
      wali --image-dir="~/wallpapers" change n
      wali --image-dir="~/wallpapers" change --file="/path/to/wallpaper.jpg"

    Ratings:

    y   "yesh"
    n   "newp"
    Y   "YESH"
    N   "never again.."
    o   "ok" (default)

    If no rating is specified, a neutral default ('ok') is used.
    """
    wali = ctx_obj["wali"]
    wallpaper_backend = ctx_obj["wallpaper_backend"]

    # get current bg
    current_wp = wali.get_current_wallpaper()

    print(current_wp)

    # check to make sure rating option specified is valid
    vote_opts = {
        "o": WaliVote.ok,
        "n": WaliVote.newp,
        "y": WaliVote.yesh,
        "Y": WaliVote.fav,
        "N": WaliVote.never,
    }

    if rating not in vote_opts.keys():
        print("Invalid rating specified! Must be one of ['o', 'y', 'Y', 'n', 'N']")
        sys.exit()

    wali.add_rating(current_wp, vote_opts[rating])

    # choose new wallpaper - either specified file or random selection
    new_wallpaper = file if file else wali.choose_wallpaper(seasons)

    # set wallpaper using selected backend
    wali.set_wallpaper(new_wallpaper, wallpaper_backend)

    # run pywal for color extraction
    print(["wal", "-i", new_wallpaper, "--backend", backend])
    subprocess.run(["wal", "-i", new_wallpaper, "--backend", backend])


def run():
    """Initialize and run CLI"""
    cli()

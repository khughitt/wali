"""
wali cli
"""
import os
import click
import sys
import subprocess
from wali import Wali, WaliVote


@click.group()
@click.option("--image-dir", 
              help="Top-level directory to scan for images",
              required=True)
@click.option("--db-path", 
              help="Path to sqlite database (default: $XDG_CONFIG_HOME/wali/wali.db)",
              default="$XDG_CONFIG_HOME/wali/wali.db",
              required=True)
@click.pass_context
def cli(ctx, image_dir:str, db_path:str):
    """Initialize CLI"""
    if image_dir is None:
        raise click.UsageError("Image directory is required")

    if db_path is None:
        raise click.UsageError("Database path is required")
    
    image_dir = os.path.expandvars(os.path.expanduser(image_dir))
    db_path = os.path.expandvars(os.path.expanduser(db_path))

    ctx.obj = Wali(image_dir, db_path=db_path)

@cli.command
@click.argument('rating', type=str, default='o')
@click.option('--backend', type=click.Choice(['haishoku', 'wal', 'colorz', 'colorthief', 'schemer2']), 
              default='haishoku', help="Backend to use for color extraction")
@click.pass_obj
def change(wali, rating:str, backend:str):
    """
    Change wallpaper.

    An optional rating can be included at the end of the command to indicate a preference
    for/against the current wallpaper.

    Examples:

      wali --image-dir="~/wallpapers" change y
      wali --image-dir="~/wallpapers" change n

    Ratings:

    y   "yesh"
    n   "newp"
    Y   "YESH"
    N   "never again.."
    o   "ok" (default)

    If no rating is specified, a neutral default ('ok') is used.
    """ 
    # get current bg
    current_wp = wali.get_current_wallpaper()

    print(current_wp)

    # check to make sure rating option specified is valid
    vote_opts = {
        'o': WaliVote.ok,
        'n': WaliVote.newp,
        'y': WaliVote.yesh,
        'Y': WaliVote.fav,
        'N': WaliVote.never
    }

    if rating not in vote_opts.keys():
        print("Invalid rating specified! Must be one of ['o', 'y', 'Y', 'n', 'N']")
        sys.exit()

    wali.add_rating(current_wp, vote_opts[rating])

    # choose new wallpaper
    new_wallpaper = wali.choose_wallpaper()

    # run pywal
    # alt approach: https://github.com/dylanaraps/pywal/wiki/Using-%60pywal%60-as-a-module
    print(["wal", "-i", new_wallpaper, "--backend", backend])
    subprocess.run(["wal", "-i", new_wallpaper, "--backend", backend])

def run():
    """Initialize and run CLI"""
    cli()

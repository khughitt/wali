"""
wali cli
"""
import os
import click
import subprocess
from wali import Wali


@click.group()
@click.option("--image-dir", help="Top-level directory to scan for images", required=True)
@click.option("--db-path", help="Path to sqlite database", default="~/.config/wali/wali.db", required=True)
@click.pass_context
def cli(ctx, image_dir:str, db_path:str):
    """Initialize CLI"""
    # initialize lit
    if image_dir is None:
        raise click.UsageError("Image directory is required")

    if db_path is None:
        raise click.UsageError("Database path is required")
    
    image_dir = os.path.expanduser(image_dir)
    db_path = os.path.expanduser(db_path)

    ctx.obj = Wali(image_dir, db_path=db_path)

@cli.command
@click.option('--rating', type=click.IntRange(min=0, max=2), 
              default=1,
              help="Rating of wallpaper (1 = 'hmm..', 2 = 'yesh!', 0 = 'never again..')")
@click.option('--backend', type=click.Choice(['haishoku', 'wal', 'colorz', 'colorthief', 'schemer2']), 
              default='haishoku', help="Backend to use for color extraction")
@click.pass_obj
def change(wali, rating:int, backend:str):
    """
    changes wallpaper
    """ 
    # get current bg
    current_wp = wali.get_current_wallpaper()

    print(current_wp)

    print("adding rating...")
    wali.add_rating(current_wp, rating)

    # choose new wallpaper
    new_wallpaper = wali.choose_wallpaper()

    # run pywal
    # alt approach: https://github.com/dylanaraps/pywal/wiki/Using-%60pywal%60-as-a-module
    print(["wal", "-i", new_wallpaper, "--backend", backend])
    subprocess.run(["wal", "-i", new_wallpaper, "--backend", backend])

def run():
    """Initialize and run CLI"""
    cli()

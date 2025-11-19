"""
wali class def
"""

import os
import sqlite3
import subprocess
from enum import StrEnum
from datetime import datetime
from PIL import Image
from PIL.ExifTags import TAGS


class WaliVote(StrEnum):
    ok = "ok"
    newp = "newp"
    yesh = "yesh"
    fav = "fav"
    never = "never"


class Wali:
    def __init__(self, image_dir: str, db_path: str, wallpaper_backend: str = "feh"):
        self.image_dir = image_dir
        self.wallpaper_backend = wallpaper_backend
        self.images: list[str] = []
        self._init_db(db_path)

        self._scan_images()

    def _init_db(self, db_path: str):
        """
        Initializes existing database or creates a new sqlite db if none found
        """
        db_dir = os.path.dirname(db_path)

        if not os.path.exists(db_dir):
            os.makedirs(db_dir, mode=0o755, exist_ok=True)

        db_exists = os.path.exists(db_path)

        self.db = sqlite3.connect(db_path)

        if not db_exists:
            print("Creating new database...")
            self._create_db(db_path)

    def choose_wallpaper(self, seasons: bool) -> str:
        if not seasons:
            sql = """SELECT path FROM images ORDER BY RANDOM() LIMIT 1"""
            cur = self.db.cursor()
            cur.execute(sql)
            return cur.fetchone()[0]

        # Calculate weights based on day of year difference
        # We use a Gaussian-like weighting function where images closer to current date
        # have higher weights. The standard deviation is set to 30 days.
        sql = """
        WITH weighted_images AS (
            SELECT 
                path,
                ABS(julianday(date) - julianday('now')) as day_diff,
                EXP(-(ABS(julianday(date) - julianday('now')) * ABS(julianday(date) - julianday('now'))) / (2 * 30 * 30)) as weight
            FROM images
            WHERE date IS NOT NULL
        )
        SELECT path
        FROM weighted_images
        ORDER BY weight * RANDOM() DESC
        LIMIT 1
        """

        cur = self.db.cursor()
        cur.execute(sql)
        result = cur.fetchone()

        if result is None:
            # Fallback to random selection if no dated images found
            cur.execute("SELECT path FROM images ORDER BY RANDOM() LIMIT 1")
            result = cur.fetchone()
        return result[0]

    def get_current_wallpaper(self) -> str:
        """
        Determines the current wallpaper based on the selected backend
        """
        if self.wallpaper_backend == "feh":
            fehbg_path = os.path.expanduser("~/.fehbg")

            if not os.path.exists(fehbg_path):
                raise Exception("~/.fehbg not found")

            with open(fehbg_path, "r") as fp:
                path = fp.read().strip().split()[-1]

                # strip quotes surrounding path
                path = path[1:-1]

                return path

        elif self.wallpaper_backend == "swww":
            result = subprocess.run(["swww", "query"], capture_output=True, text=True)

            if result.returncode != 0:
                raise Exception("Failed to query swww for current wallpaper")

            # swww query output format: "output: image: /path/to/image.jpg"
            # We'll take the first output's image path
            for line in result.stdout.strip().split("\n"):
                if "image:" in line:
                    path = line.split("image:")[1].strip()
                    return path

            raise Exception("Could not parse current wallpaper from swww query")

        else:
            raise ValueError(f"Unsupported wallpaper backend: {self.wallpaper_backend}")

    def set_wallpaper(self, path: str, backend: str | None = None) -> None:
        """
        Sets the wallpaper using the selected backend
        """
        if backend is None:
            backend = self.wallpaper_backend

        if backend == "feh":
            subprocess.run(["feh", "--bg-fill", path])
        elif backend == "swww":
            subprocess.run(["swww", "img", path])
        else:
            raise ValueError(f"Unsupported wallpaper backend: {backend}")

    def add_rating(self, path: str, vote: WaliVote):
        cur = self.db.cursor()
        cur.execute(
            """
            INSERT INTO ratings (image_id, vote)
                SELECT id, ? FROM images WHERE path = ?
        """,
            (vote, path),
        )

        self.db.commit()

    def _get_known_images(self) -> list[str]:
        cur = self.db.cursor()
        cur.execute("SELECT path FROM images")
        return [path for (path,) in cur.fetchall()]

    def _create_db(self, db_path: str) -> None:
        """
        Creates new db
        """
        cur = self.db.cursor()

        # create images table
        cur.execute("""
            CREATE TABLE IF NOT EXISTS images (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                path TEXT NOT NULL,
                exclude BOOLEAN NOT NULL DEFAULT 0,
                timestamp DATETIME
            )
        """)

        # create ratings table
        cur.execute("""
            CREATE TABLE IF NOT EXISTS ratings (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                image_id INTEGER NOT NULL,
                time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                vote TEXT NOT NULL DEFAULT 'ok' CHECK (vote IN ('ok', 'yesh', 'newp', 'fav', 'never')),
                FOREIGN KEY (image_id) REFERENCES images (id)
            )
        """)
        self.db.commit()

    def _scan_images(self) -> None:
        known_images = self._get_known_images()

        cur = self.db.cursor()

        def extract_timestamp_from_exif(image_path):
            try:
                with Image.open(image_path) as img:
                    exif = img._getexif()
                    if exif is None:
                        return None

                    for tag_id in exif:
                        tag = TAGS.get(tag_id, tag_id)
                        if tag == "DateTimeOriginal":
                            date_str = exif[tag_id]
                            return datetime.strptime(date_str, "%Y:%m:%d %H:%M:%S")
            except Exception:
                return None
            return None

        for root, dirs, files in os.walk(self.image_dir):
            for file in files:
                if file.endswith((".jpg", ".png")):
                    full_path = os.path.join(root, file)

                    if full_path not in known_images:
                        print(f"Adding {full_path}...")

                        # Try to extract timestamp from EXIF first
                        timestamp = extract_timestamp_from_exif(full_path)

                        # If no EXIF timestamp, try filename
                        if timestamp is None:
                            print(
                                f"No EXIF timestamp found for {full_path}, using current timestamp"
                            )
                            timestamp = datetime.now()

                        sql = """INSERT INTO images (path, timestamp) VALUES (?, ?)"""
                        cur.execute(sql, (full_path, timestamp))

        self.db.commit()

"""
wali class def
"""
import os
import sqlite3

class Wali:
    def __init__(self, image_dir:str, db_path:str):
        self.image_dir = image_dir
        self.images: list[str] = []
        self._init_db(db_path)
        self._scan_images()

    def _init_db(self, db_path:str):

        os.makedirs(os.path.dirname(db_path), mode=0o755, exist_ok=True)

        db_exists = os.path.exists(db_path)

        self.db = sqlite3.connect(db_path)
        
        if not db_exists:
            print("Creating new database...")
            self._create_db(db_path)

    def choose_wallpaper(self) -> str:
        sql = """SELECT path FROM images ORDER BY RANDOM() LIMIT 1"""

        cur = self.db.cursor()
        cur.execute(sql)
        return cur.fetchone()[0]
    
    def get_current_wallpaper(self) -> str:
        """
        Determines the current wallpaper
        """
        fehbg_path = os.path.expanduser("~/.fehbg")

        if not os.path.exists(fehbg_path):
            raise Exception("~/.fehbg not found")
        
        with open(fehbg_path, "r") as fp:
            path = fp.read().strip().split()[-1]

            # strip quotes surrounding path
            path = path[1:-1]

            return path
    
    def add_rating(self, path:str, vote:int):
        cur = self.db.cursor()
        cur.execute("""
            INSERT INTO ratings (image_id, vote)
                SELECT id, ? FROM images WHERE path = ?
        """, (vote, path))

        self.db.commit()

    def _get_known_images(self) -> list[str]:
        cur = self.db.cursor()
        cur.execute("SELECT path FROM images")
        return [path for path, in cur.fetchall()]

    def _create_db(self, db_path:str) -> None:
        """
        Creates new db
        """
        os.makedirs(os.path.dirname(db_path), exist_ok=True)

        cur = self.db.cursor()

        # create images table
        cur.execute("""
            CREATE TABLE IF NOT EXISTS images (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                path TEXT NOT NULL,
                exclude BOOLEAN NOT NULL DEFAULT 0
            )
        """)

        # create ratings table
        cur.execute("""
            CREATE TABLE IF NOT EXISTS ratings (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                image_id INTEGER NOT NULL,
                time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                vote BOOLEAN NOT NULL DEFAULT 1,
                FOREIGN KEY (image_id) REFERENCES images (id)
            )
        """)

        self.db.commit()


    def _scan_images(self) -> None:
        known_images = self._get_known_images()

        cur = self.db.cursor()

        for root, dirs, files in os.walk(self.image_dir):
            for file in files:
                if file.endswith((".jpg", ".png")):
                    full_path = os.path.join(root, file)

                    if full_path not in known_images:
                        print(f"Adding {full_path}...")
                        sql = """INSERT INTO images (path) VALUES (?)"""
                        cur.execute(sql, (full_path,))

        self.db.commit()
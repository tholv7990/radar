"""Apply the signal_feed v2 view. Run: python -m scripts.apply_signal_feed_v2"""
from pathlib import Path
from collector.config import load_config
from collector import db

cfg = load_config()
conn = db.connect(cfg)
with conn.cursor() as cur:
    cur.execute(Path("db/signal_feed_v2.sql").read_text(encoding="utf-8"))
conn.commit()
conn.close()
print("signal_feed v2 applied")

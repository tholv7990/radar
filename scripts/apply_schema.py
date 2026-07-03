"""Apply db/schema.sql to the Supabase Postgres in .env. Idempotent (create if not exists).

Run from the repo root: python -m scripts.apply_schema
"""
from pathlib import Path

from collector.config import load_config
from collector import db

sql = Path("db/schema.sql").read_text(encoding="utf-8")
cfg = load_config()
conn = db.connect(cfg)
with conn.cursor() as cur:
    cur.execute(sql)
conn.commit()
conn.close()
print("schema applied")

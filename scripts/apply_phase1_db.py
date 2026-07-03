"""Apply the signal_feed view + RLS policies. Run from repo root: python -m scripts.apply_phase1_db

Idempotent: safe to re-run. Each statement commits (or rolls back) on its own so an
"already exists" error on a later RLS statement can never discard the view created
in an earlier statement within the same run.
"""
from pathlib import Path

from collector.config import load_config
from collector import db

def _is_sql(fragment: str) -> bool:
    """True if fragment has at least one non-comment, non-blank line."""
    for line in fragment.splitlines():
        line = line.strip()
        if line and not line.startswith("--"):
            return True
    return False


cfg = load_config()
conn = db.connect(cfg)

with conn.cursor() as cur:
    cur.execute(Path("db/signal_feed.sql").read_text(encoding="utf-8"))
conn.commit()

for stmt in Path("db/rls.sql").read_text(encoding="utf-8").split(";"):
    s = stmt.strip()
    if not s or not _is_sql(s):
        continue
    try:
        with conn.cursor() as cur:
            cur.execute(s)
        conn.commit()
    except Exception as exc:
        if "already exists" in str(exc):
            conn.rollback()
            continue
        raise

conn.close()
print("phase-1 db applied")

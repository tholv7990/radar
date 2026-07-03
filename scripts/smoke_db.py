"""Smoke-test persistence against the real DB: idempotent entity, appended snapshots.

Run from the repo root: python -m scripts.smoke_db
"""
from datetime import datetime, timezone

from collector.config import load_config
from collector.models import CollectedItem
from collector import db

cfg = load_config()
conn = db.connect(cfg)

item = CollectedItem(source="github", external_id="smoke/test", name="test",
                     one_liner="smoke", url="https://x", stars=1, forks=0,
                     provisional_quality=42, raw_json={"hello": "world"},
                     created_at=datetime.now(timezone.utc))
db.save(conn, item)
db.save(conn, item)  # second run must NOT duplicate the entity

with conn.cursor() as cur:
    cur.execute("select count(*) from entities where external_id='smoke/test'")
    assert cur.fetchone()[0] == 1, "entity duplicated — upsert broken"
    cur.execute("select count(*) from snapshots s join entities e on e.id=s.entity_id "
                "where e.external_id='smoke/test'")
    assert cur.fetchone()[0] == 2, "expected 2 snapshots"

# cleanup (psycopg2 — no psql on this box)
with conn.cursor() as cur:
    cur.execute("delete from snapshots using entities where snapshots.entity_id=entities.id "
                "and entities.external_id='smoke/test'")
    cur.execute("delete from entities where external_id='smoke/test'")
conn.commit()
conn.close()
print("smoke OK")

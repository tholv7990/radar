"""Verify signal_feed v2 exposes the deep-dive columns. Run: python -m scripts.test_signal_feed_v2"""
from collector.config import load_config
from collector import db

conn = db.connect(load_config())
cur = conn.cursor()
cur.execute("select column_name from information_schema.columns where table_name='signal_feed'")
cols = {r[0] for r in cur.fetchall()}
for required in ("quality_score", "deep_dive_status"):
    assert required in cols, f"missing column {required}"
cur.execute("select count(*) from signal_feed where quality_score is not null")
assert cur.fetchone()[0] == 0, "expected no quality_score before any deep-dive"
cur.execute("set role authenticated"); cur.execute("select count(*) from signal_feed"); assert cur.fetchone()[0] > 0
cur.execute("reset role")
conn.close()
print("signal_feed v2 OK — quality_score + deep_dive_status present, null pre-dive")

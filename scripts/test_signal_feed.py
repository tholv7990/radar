"""Verify signal_feed returns expected shape + ordering. Run: python -m scripts.test_signal_feed"""
from collector.config import load_config
from collector import db

conn = db.connect(load_config())
cur = conn.cursor()
cur.execute("select column_name from information_schema.columns where table_name='signal_feed'")
cols = {r[0] for r in cur.fetchall()}
for required in ("velocity", "consistency", "momentum_stage", "rank_score", "watch_state",
                 "provisional_quality", "source", "name"):
    assert required in cols, f"missing column {required}"

cur.execute("select count(*) from signal_feed")
n = cur.fetchone()[0]
assert n > 0, "signal_feed empty — did the collector run?"

cur.execute("select momentum_stage, rank_score, provisional_quality from signal_feed limit 5")
rows = cur.fetchall()
assert all(r[0] == 'new' for r in rows), "expected 'new' stage before 2nd snapshot"
assert all(float(r[1]) == float(r[2]) for r in rows), "rank_score should equal provisional_quality at cold-start"

cur.execute("select rank_score from signal_feed order by rank_score desc limit 3")
scores = [float(r[0]) for r in cur.fetchall()]
assert scores == sorted(scores, reverse=True), "not orderable by rank_score"
conn.close()
print(f"signal_feed OK — {n} rows, columns + cold-start + ordering verified")

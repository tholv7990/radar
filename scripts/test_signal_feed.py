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

cur.execute("select momentum_stage, rank_score, provisional_quality, source from signal_feed")
rows = cur.fetchall()
assert all(r[0] == 'new' for r in rows), (
    "expected 'new' stage for ALL rows (both sources) before 2nd snapshot — "
    f"non-'new' rows: {[r for r in rows if r[0] != 'new']}"
)
assert all(float(r[1]) == float(r[2]) for r in rows), (
    "rank_score should equal provisional_quality for ALL rows (both sources) at cold-start — "
    f"mismatches: {[r for r in rows if float(r[1]) != float(r[2])]}"
)
sources_seen = {r[3] for r in rows}
assert len(sources_seen) > 1, (
    f"cold-start uniformity check only saw source(s) {sources_seen} — "
    "need both github and producthunt rows to prove no cross-source asymmetry"
)

cur.execute("select rank_score from signal_feed order by rank_score desc limit 3")
scores = [float(r[0]) for r in cur.fetchall()]
assert scores == sorted(scores, reverse=True), "not orderable by rank_score"

# --- authenticated-role checks -----------------------------------------
# Everything above ran on the table-OWNER connection, which bypasses RLS
# entirely — it proves the view's SQL is correct but proves nothing about
# whether the app's actual runtime role (`authenticated`) can use it. The
# owner can `set role authenticated` to simulate the app's runtime
# permissions (RLS + GRANTs both apply once the role is switched).
try:
    cur.execute("set role authenticated")

    try:
        cur.execute("select count(*) from signal_feed")
    except Exception as exc:
        raise AssertionError(
            f"authenticated role cannot read signal_feed (missing GRANT or RLS policy?): {exc}"
        ) from exc
    auth_n = cur.fetchone()[0]
    assert auth_n > 0, "authenticated role read signal_feed but got 0 rows — RLS policy may be too restrictive"

    cur.execute("select id from entities limit 1")
    row = cur.fetchone()
    assert row is not None, "no entities available to test watchlist write as authenticated"
    entity_id = row[0]

    try:
        cur.execute(
            "insert into watchlist_state (entity_id, state) values (%s, 'watching') "
            "on conflict (entity_id) do update set state = excluded.state",
            (entity_id,),
        )
        cur.execute("delete from watchlist_state where entity_id = %s", (entity_id,))
    except Exception as exc:
        raise AssertionError(
            f"authenticated role cannot write watchlist_state (missing GRANT or RLS policy?): {exc}"
        ) from exc
finally:
    # Discard the insert/delete test data and drop back to the owner role
    # regardless of whether the checks above passed or raised.
    conn.rollback()
    cur.execute("reset role")

# --- anon-denial check ---------------------------------------------------
# The app gates all data access behind login. An unauthenticated request
# using the public `anon` key must NOT be able to read signal_feed (or the
# underlying tables) — this is what db/grants.sql's `revoke ... from anon`
# enforces. If Supabase's default-privilege auto-grant ever reopens this,
# this check must fail (not silently pass).
try:
    cur.execute("set role anon")
    try:
        cur.execute("select 1 from signal_feed limit 1")
    except Exception:
        pass  # expected: permission denied
    else:
        raise AssertionError(
            "anon role was able to read signal_feed — expected a permission error. "
            "The `revoke ... from anon` in db/grants.sql may not be applied "
            "(check for a schema-level or default-privilege grant reopening access)."
        )
finally:
    conn.rollback()
    cur.execute("reset role")

conn.close()
print(f"signal_feed OK — {n} rows, columns + cold-start + ordering verified across sources {sources_seen}")
print(f"authenticated role OK — read {auth_n} rows via signal_feed, insert+delete on watchlist_state succeeded")
print("anon role OK — denied read access to signal_feed as expected")

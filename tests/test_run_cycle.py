from datetime import datetime, timezone, timedelta

from collector.config import Config
from collector.models import CollectedItem
from collector import main, github, producthunt, db

NOW = datetime(2026, 7, 3, tzinfo=timezone.utc)
CFG = Config(github_token="x", ph_token="x", db_dsn="x", github_queries=[])


def _gh_pass():
    return CollectedItem(source="github", external_id="a/b", name="b", raw_json={},
                         stars=100, license="MIT", pushed_at=NOW - timedelta(days=1),
                         forks=10, created_at=NOW - timedelta(days=100))


def _gh_fail():
    return CollectedItem(source="github", external_id="c/d", name="d", raw_json={},
                         stars=1, license=None, pushed_at=NOW)


def test_run_cycle_saves_only_survivors_with_quality(monkeypatch):
    saved = []
    monkeypatch.setattr(github, "collect", lambda cfg: [_gh_pass(), _gh_fail()])
    monkeypatch.setattr(producthunt, "collect", lambda cfg: [])
    monkeypatch.setattr(db, "save", lambda conn, item: saved.append(item))

    stats = main.run_cycle(CFG, conn=None, now=NOW)

    assert stats["github"] == 1
    assert len(saved) == 1
    assert saved[0].external_id == "a/b"
    assert saved[0].provisional_quality is not None  # filled before save
    assert stats["errors"] == []


def test_run_cycle_degrades_safe_when_one_source_fails(monkeypatch):
    def boom(cfg):
        raise RuntimeError("github down")

    monkeypatch.setattr(github, "collect", boom)
    monkeypatch.setattr(producthunt, "collect", lambda cfg: [])
    monkeypatch.setattr(db, "save", lambda conn, item: None)

    stats = main.run_cycle(CFG, conn=None, now=NOW)

    assert stats["github"] == 0
    assert stats["producthunt"] == 0
    assert any("github down" in e for e in stats["errors"])  # logged, not raised

from datetime import datetime, timezone, timedelta

from collector.config import Config
from collector.models import CollectedItem
from collector import prefilter

NOW = datetime(2026, 7, 3, tzinfo=timezone.utc)
CFG = Config(github_token="x", ph_token="x", db_dsn="x",
             github_queries=[], min_stars=50, max_push_age_days=90, min_ph_comments=3)


def gh(**kw):
    base = dict(source="github", external_id="a/b", name="b", raw_json={},
                stars=100, license="MIT", is_fork=False,
                pushed_at=NOW - timedelta(days=1))
    base.update(kw)
    return CollectedItem(**base)


def test_github_healthy_passes():
    assert prefilter.passes(gh(), CFG, NOW) is True


def test_github_fork_rejected():
    assert prefilter.passes(gh(is_fork=True), CFG, NOW) is False


def test_github_low_stars_rejected():
    assert prefilter.passes(gh(stars=10), CFG, NOW) is False


def test_github_no_license_rejected():
    assert prefilter.passes(gh(license=None), CFG, NOW) is False


def test_github_stale_rejected():
    assert prefilter.passes(gh(pushed_at=NOW - timedelta(days=200)), CFG, NOW) is False


def test_github_blocklisted_rejected():
    cfg = Config(github_token="x", ph_token="x", db_dsn="x", github_queries=[],
                 blocklist=frozenset({"a/b"}))
    assert prefilter.passes(gh(), cfg, NOW) is False


def ph(**kw):
    base = dict(source="producthunt", external_id="p1", name="p", raw_json={},
                comments=5, product_url="https://x.com")
    base.update(kw)
    return CollectedItem(**base)


def test_ph_healthy_passes():
    assert prefilter.passes(ph(), CFG, NOW) is True


def test_ph_few_comments_rejected():
    assert prefilter.passes(ph(comments=1), CFG, NOW) is False


def test_ph_no_product_url_rejected():
    assert prefilter.passes(ph(product_url=None), CFG, NOW) is False

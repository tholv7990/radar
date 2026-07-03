from datetime import datetime, timezone, timedelta

from collector.models import CollectedItem
from collector import quality

NOW = datetime(2026, 7, 3, tzinfo=timezone.utc)


def test_github_archived_scores_low():
    item = CollectedItem(source="github", external_id="a/b", name="b", raw_json={},
                         archived=True, license="MIT", stars=1000, forks=200,
                         pushed_at=NOW, created_at=NOW - timedelta(days=100))
    assert quality.provisional_quality(item, NOW) == 10


def test_github_healthy_scores_high():
    item = CollectedItem(source="github", external_id="a/b", name="b", raw_json={},
                         archived=False, license="Apache-2.0", stars=1000, forks=200,
                         pushed_at=NOW, created_at=NOW - timedelta(days=100))
    # license 20 + fresh push 30 + fork:star 0.2*150=30 + age 20 = 100
    assert quality.provisional_quality(item, NOW) == 100


def test_github_weak_scores_low():
    item = CollectedItem(source="github", external_id="a/b", name="b", raw_json={},
                         archived=False, license=None, stars=1000, forks=0,
                         pushed_at=NOW - timedelta(days=200), created_at=NOW - timedelta(days=100))
    # 0 + 0 (stale) + 0 + 20 (age) = 20
    assert quality.provisional_quality(item, NOW) == 20


def test_ph_no_product_url_scores_low():
    item = CollectedItem(source="producthunt", external_id="p", name="p", raw_json={},
                         product_url=None, rating=4.5, votes=1000, comments=100, reviews_count=30)
    assert quality.provisional_quality(item, NOW) == 10


def test_ph_healthy_scores_high():
    item = CollectedItem(source="producthunt", external_id="p", name="p", raw_json={},
                         product_url="https://x.com", rating=4.6, votes=1200,
                         comments=200, reviews_count=38)
    # rating 4.6/5*40=36.8 + ratio 0.166*300=50->cap30 + reviews>20 30 = 96.8 -> 97
    assert quality.provisional_quality(item, NOW) == 97

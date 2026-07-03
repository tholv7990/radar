from datetime import datetime

from .models import CollectedItem


def _clamp(x: float) -> int:
    return max(0, min(100, int(round(x))))


def _days_since(dt: datetime | None, now: datetime) -> int:
    return (now - dt).days if dt else 10 ** 6


def provisional_quality(item: CollectedItem, now: datetime) -> int:
    """Cheap, deterministic health proxy from BACKGROUND-tier fields only.

    Deliberately crude — the Scope blip stays hollow until a real deep-dive
    quality_score replaces it. Weights are calibration knobs, tuned by eye
    after launch. ponytail: crude on purpose; upgrade path is the Phase 2 rubric.
    """
    if item.source == "github":
        if item.archived:
            return 10
        score = 0.0
        if item.license:
            score += 20
        d = _days_since(item.pushed_at, now)
        score += 30 if d < 7 else 20 if d < 30 else 10 if d < 90 else 0
        ratio = (item.forks or 0) / max(item.stars or 0, 1)
        score += min(30, ratio * 150)
        age = _days_since(item.created_at, now)
        score += 20 if 14 <= age <= 3650 else 10
        return _clamp(score)

    if item.source == "producthunt":
        if not item.product_url:
            return 10
        score = 0.0
        score += (item.rating or 0) / 5 * 40
        ratio = (item.comments or 0) / max(item.votes or 0, 1)
        score += min(30, ratio * 300)
        rc = item.reviews_count or 0
        score += 30 if rc > 20 else 15 if rc > 5 else 5
        return _clamp(score)

    return 0

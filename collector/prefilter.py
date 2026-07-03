from datetime import datetime

from .config import Config
from .models import CollectedItem


def _days_since(dt: datetime | None, now: datetime) -> int:
    return (now - dt).days if dt else 10 ** 6


def passes(item: CollectedItem, cfg: Config, now: datetime) -> bool:
    if item.source == "github":
        if item.is_fork:
            return False
        if (item.stars or 0) < cfg.min_stars:
            return False
        if not item.license:
            return False
        if _days_since(item.pushed_at, now) > cfg.max_push_age_days:
            return False
        if item.external_id in cfg.blocklist:
            return False
        # ponytail: README + spam checks deferred — the cheap gate above is
        # enough at launch; add a GET /repos/../readme 404 check if noise creeps in.
        return True

    if item.source == "producthunt":
        if (item.comments or 0) < cfg.min_ph_comments:
            return False
        if not item.product_url:
            return False
        # ponytail: dedupe/spam/language checks deferred (PH volume is ~25-50/day).
        return True

    return False

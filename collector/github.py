from datetime import datetime, timedelta, timezone

import requests

from .config import Config
from .models import CollectedItem

API = "https://api.github.com"


def _dt(s: str | None) -> datetime | None:
    return datetime.fromisoformat(s.replace("Z", "+00:00")) if s else None


def parse_repo(raw: dict) -> CollectedItem:
    spdx = (raw.get("license") or {}).get("spdx_id")
    if spdx in (None, "NOASSERTION"):
        spdx = None
    return CollectedItem(
        source="github",
        external_id=raw["full_name"],
        name=raw.get("name"),
        one_liner=raw.get("description"),
        url=raw.get("html_url"),
        language=raw.get("language"),
        topics=raw.get("topics") or [],
        owner_type=(raw.get("owner") or {}).get("type"),
        created_at=_dt(raw.get("created_at")),
        default_branch=raw.get("default_branch"),
        stars=raw.get("stargazers_count"),
        forks=raw.get("forks_count"),
        # ponytail: search results lack subscribers_count; fall back to watchers_count.
        # Upgrade path: one GET /repos/{full_name} per survivor for true watchers.
        watchers=raw.get("subscribers_count") or raw.get("watchers_count"),
        open_issues=raw.get("open_issues_count"),
        pushed_at=_dt(raw.get("pushed_at")),
        license=spdx,
        archived=raw.get("archived"),
        is_fork=raw.get("fork", False),
        raw_json=raw,
    )


def _headers(cfg: Config) -> dict:
    return {"Authorization": f"Bearer {cfg.github_token}",
            "Accept": "application/vnd.github+json"}


def collect(cfg: Config) -> list[CollectedItem]:
    since = (datetime.now(timezone.utc) - timedelta(days=cfg.max_push_age_days)).date().isoformat()
    items: list[CollectedItem] = []
    for q in cfg.github_queries:
        query = f"{q} stars:>={cfg.min_stars} pushed:>={since}"
        resp = requests.get(
            f"{API}/search/repositories",
            headers=_headers(cfg),
            params={"q": query, "sort": "stars", "order": "desc", "per_page": 50},
            timeout=30,
        )
        resp.raise_for_status()
        items.extend(parse_repo(r) for r in resp.json().get("items", []))
    return items

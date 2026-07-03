from datetime import datetime

import requests

from .config import Config
from .models import CollectedItem

GQL = "https://api.producthunt.com/v2/api/graphql"
QUERY = """
query($first: Int!) {
  posts(first: $first, order: VOTES) {
    edges { node {
      id name tagline description url website
      votesCount commentsCount reviewsRating reviewsCount createdAt
      topics { edges { node { name } } }
    } }
  }
}
"""


def _dt(s: str | None) -> datetime | None:
    return datetime.fromisoformat(s.replace("Z", "+00:00")) if s else None


def parse_post(raw: dict) -> CollectedItem:
    topics = [e["node"]["name"] for e in (raw.get("topics") or {}).get("edges", [])]
    return CollectedItem(
        source="producthunt",
        external_id=raw["id"],
        name=raw.get("name"),
        one_liner=raw.get("tagline"),
        url=raw.get("url"),
        product_url=raw.get("website"),
        topics=topics,
        created_at=_dt(raw.get("createdAt")),
        votes=raw.get("votesCount"),
        comments=raw.get("commentsCount"),
        rating=raw.get("reviewsRating"),
        reviews_count=raw.get("reviewsCount"),
        raw_json=raw,
    )


def collect(cfg: Config, first: int = 50) -> list[CollectedItem]:
    resp = requests.post(
        GQL,
        headers={"Authorization": f"Bearer {cfg.ph_token}"},
        json={"query": QUERY, "variables": {"first": first}},
        timeout=30,
    )
    resp.raise_for_status()
    edges = resp.json()["data"]["posts"]["edges"]
    return [parse_post(e["node"]) for e in edges]

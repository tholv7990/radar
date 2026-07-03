from dataclasses import dataclass, field
from datetime import datetime


@dataclass
class CollectedItem:
    """Normalized record: entity fields + this-run snapshot metrics.

    `is_fork` and `product_url` are transient (used by pre-filter / later
    tiers, not persisted as columns — they live in raw_json). `provisional_quality`
    is filled by the orchestrator before save.
    """
    source: str                      # 'github' | 'producthunt'
    external_id: str                 # repo full_name | PH post id
    name: str
    raw_json: dict
    one_liner: str | None = None
    url: str | None = None
    language: str | None = None
    topics: list[str] = field(default_factory=list)
    owner_type: str | None = None
    created_at: datetime | None = None
    default_branch: str | None = None
    # github metrics
    stars: int | None = None
    forks: int | None = None
    watchers: int | None = None
    open_issues: int | None = None
    pushed_at: datetime | None = None
    license: str | None = None
    archived: bool | None = None
    # producthunt metrics
    votes: int | None = None
    comments: int | None = None
    rating: float | None = None
    reviews_count: int | None = None
    # transient (not persisted as columns)
    is_fork: bool = False
    product_url: str | None = None
    # filled by orchestrator
    provisional_quality: int | None = None

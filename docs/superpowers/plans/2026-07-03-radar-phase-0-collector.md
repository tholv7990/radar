# RADAR Phase 0 — Collector Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A scheduled Python collector that fetches trending GitHub repos and Product Hunt launches, pre-filters them, and writes one durable entity plus a dated snapshot per run into Supabase Postgres — starting the irreplaceable time-series.

**Architecture:** Pure functions for the decision logic (pre-filter, provisional-quality proxy) and thin I/O adapters for GitHub, Product Hunt, and Postgres, wired by a fail-loud/degrade-safe orchestrator. Runs on GitHub Actions cron. No LLM anywhere in this subsystem.

**Tech Stack:** Python 3.11 · `requests` · `psycopg2` · Supabase Postgres · GitHub Actions · pytest.

## Global Constraints

- **No LLM in the collector, ever** — the background path calls no inference API. (Spec invariant.)
- **Python 3.11+.**
- **Idempotent** — upsert entities on `(source, external_id)`; a re-run inserts a new snapshot without duplicating identities. (FR-0.3)
- **Fail loud, degrade safe** — a failure in one source must not abort the other or corrupt prior data; the process exits non-zero if any error occurred. (NFR-3/4)
- **Store `raw_json` on every snapshot** — full payload, jsonb. (C0/C8)
- **Authenticated requests only** — GitHub Bearer token, Product Hunt bearer token. (NFR-5)
- **Single call per source query** — no per-repo detail fetch, no HTTP crawling in the background tier. (C8)

## File structure

```
collector/
  __init__.py          # empty package marker
  models.py            # CollectedItem dataclass (shared contract)
  config.py            # env → Config
  prefilter.py         # passes(item, cfg, now) -> bool   (pure)
  quality.py           # provisional_quality(item, now) -> int   (pure)
  github.py            # search + parse_repo -> CollectedItem
  producthunt.py       # graphql + parse_post -> CollectedItem
  db.py                # psycopg persistence (upsert entity + insert snapshot)
  main.py              # run_cycle orchestrator + CLI entrypoint
db/
  schema.sql           # DDL applied to Supabase
tests/
  test_config.py
  test_prefilter.py
  test_quality.py
  test_github.py
  test_producthunt.py
  test_run_cycle.py
.github/workflows/collect.yml
requirements.txt
```

---

### Task 1: Scaffold, shared model, config, schema

**Files:**
- Create: `requirements.txt`, `collector/__init__.py`, `collector/models.py`, `collector/config.py`, `db/schema.sql`
- Test: `tests/test_config.py`

**Interfaces:**
- Produces: `collector.models.CollectedItem` (dataclass, fields below) — consumed by every later task.
- Produces: `collector.config.Config` and `collector.config.load_config() -> Config`.

- [ ] **Step 1: Create `requirements.txt`**

```
requests==2.32.3
psycopg2-binary==2.9.9
python-dotenv==1.0.1
pytest==8.3.3
```

- [ ] **Step 2: Create `collector/__init__.py`** (empty file)

- [ ] **Step 3: Create `collector/models.py`**

```python
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
```

- [ ] **Step 4: Create `collector/config.py`**

```python
import os
from dataclasses import dataclass, field

from dotenv import load_dotenv

load_dotenv()  # load .env for local runs; no-op in CI


@dataclass
class Config:
    github_token: str
    ph_token: str
    db_dsn: str
    github_queries: list[str]
    min_stars: int = 50
    max_push_age_days: int = 90
    min_ph_comments: int = 3
    blocklist: frozenset = field(default_factory=frozenset)


def load_config() -> Config:
    def req(key: str) -> str:
        val = os.environ.get(key)
        if not val:
            raise RuntimeError(f"missing required env var: {key}")
        return val

    queries = os.environ.get("GITHUB_QUERIES", "language:rust,language:typescript")
    return Config(
        github_token=req("GITHUB_TOKEN"),
        ph_token=req("PH_TOKEN"),
        db_dsn=req("SUPABASE_DB_DSN"),
        github_queries=[q.strip() for q in queries.split(",") if q.strip()],
        min_stars=int(os.environ.get("MIN_STARS", "50")),
        max_push_age_days=int(os.environ.get("MAX_PUSH_AGE_DAYS", "90")),
        min_ph_comments=int(os.environ.get("MIN_PH_COMMENTS", "3")),
    )
```

- [ ] **Step 5: Create `db/schema.sql`**

```sql
create table if not exists entities (
  id            bigint generated always as identity primary key,
  source        text not null check (source in ('github','producthunt')),
  external_id   text not null,
  name          text not null,
  one_liner     text,
  url           text,
  language      text,
  topics        text[],
  owner_type    text,
  created_at    timestamptz,
  default_branch text,
  first_seen_at timestamptz default now(),
  unique (source, external_id)
);

create table if not exists snapshots (
  id            bigint generated always as identity primary key,
  entity_id     bigint not null references entities(id),
  captured_at   timestamptz not null default now(),
  stars int, forks int, watchers int, open_issues int,
  pushed_at timestamptz, license text, archived bool,
  votes int, comments int, rating numeric, reviews_count int,
  provisional_quality int,
  raw_json      jsonb not null
);
create index if not exists snapshots_entity_time on snapshots (entity_id, captured_at desc);

create table if not exists watchlist_state (
  entity_id  bigint primary key references entities(id),
  state      text not null check (state in ('seen','watching','dismissed')),
  note       text,
  updated_at timestamptz default now()
);

create table if not exists deep_dive_cache (
  entity_id     bigint primary key references entities(id),
  status        text not null default 'running' check (status in ('running','done','error')),
  error_note    text,
  computed_at   timestamptz default now(),
  quality_score int,
  momentum_stage text,
  veto_flags    jsonb,
  reasons       jsonb,
  full_result   jsonb
);
```

- [ ] **Step 6: Write the failing test** — `tests/test_config.py`

```python
import pytest

from collector.config import load_config


def test_load_config_missing_env_raises(monkeypatch):
    monkeypatch.delenv("GITHUB_TOKEN", raising=False)
    monkeypatch.setenv("PH_TOKEN", "x")
    monkeypatch.setenv("SUPABASE_DB_DSN", "x")
    with pytest.raises(RuntimeError, match="GITHUB_TOKEN"):
        load_config()


def test_load_config_parses_queries(monkeypatch):
    monkeypatch.setenv("GITHUB_TOKEN", "gh")
    monkeypatch.setenv("PH_TOKEN", "ph")
    monkeypatch.setenv("SUPABASE_DB_DSN", "dsn")
    monkeypatch.setenv("GITHUB_QUERIES", "language:rust, language:go ")
    cfg = load_config()
    assert cfg.github_queries == ["language:rust", "language:go"]
    assert cfg.min_stars == 50
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `pytest tests/test_config.py -v`
Expected: 2 passed. (Implementation already written in Steps 3–4; this task's logic is trivial enough that impl precedes test — the test guards the env-required and parsing behavior.)

- [ ] **Step 8: Commit**

```bash
git add requirements.txt collector/ db/schema.sql tests/test_config.py
git commit -m "feat(collector): scaffold, shared model, config, schema"
```

---

### Task 2: Pre-filter gate

**Files:**
- Create: `collector/prefilter.py`
- Test: `tests/test_prefilter.py`

**Interfaces:**
- Consumes: `CollectedItem`, `Config`.
- Produces: `prefilter.passes(item: CollectedItem, cfg: Config, now: datetime) -> bool`.

- [ ] **Step 1: Write the failing test** — `tests/test_prefilter.py`

```python
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_prefilter.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'collector.prefilter'`

- [ ] **Step 3: Write minimal implementation** — `collector/prefilter.py`

```python
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_prefilter.py -v`
Expected: 9 passed.

- [ ] **Step 5: Commit**

```bash
git add collector/prefilter.py tests/test_prefilter.py
git commit -m "feat(collector): pre-filter gate"
```

---

### Task 3: Provisional quality proxy

**Files:**
- Create: `collector/quality.py`
- Test: `tests/test_quality.py`

**Interfaces:**
- Consumes: `CollectedItem`.
- Produces: `quality.provisional_quality(item: CollectedItem, now: datetime) -> int` (0–100).

- [ ] **Step 1: Write the failing test** — `tests/test_quality.py`

```python
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_quality.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'collector.quality'`

- [ ] **Step 3: Write minimal implementation** — `collector/quality.py`

```python
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_quality.py -v`
Expected: 5 passed.

- [ ] **Step 5: Commit**

```bash
git add collector/quality.py tests/test_quality.py
git commit -m "feat(collector): provisional health proxy"
```

---

### Task 4: GitHub client

**Files:**
- Create: `collector/github.py`
- Test: `tests/test_github.py`

**Interfaces:**
- Consumes: `Config`, `CollectedItem`.
- Produces: `github.parse_repo(raw: dict) -> CollectedItem`; `github.collect(cfg: Config) -> list[CollectedItem]`.

- [ ] **Step 1: Write the failing test** — `tests/test_github.py`

```python
from datetime import timezone

from collector import github

RAW = {
    "full_name": "quill-labs/driftdb",
    "name": "driftdb",
    "description": "Embedded versioned columnar store.",
    "html_url": "https://github.com/quill-labs/driftdb",
    "language": "Rust",
    "topics": ["database", "analytics"],
    "owner": {"type": "Organization"},
    "created_at": "2026-04-01T00:00:00Z",
    "default_branch": "main",
    "stargazers_count": 8400,
    "forks_count": 1764,
    "subscribers_count": 120,
    "open_issues_count": 30,
    "pushed_at": "2026-07-03T07:20:00Z",
    "license": {"spdx_id": "Apache-2.0"},
    "archived": False,
    "fork": False,
}


def test_parse_repo_maps_fields():
    item = github.parse_repo(RAW)
    assert item.source == "github"
    assert item.external_id == "quill-labs/driftdb"
    assert item.one_liner == "Embedded versioned columnar store."
    assert item.language == "Rust"
    assert item.stars == 8400
    assert item.forks == 1764
    assert item.watchers == 120
    assert item.license == "Apache-2.0"
    assert item.archived is False
    assert item.is_fork is False
    assert item.pushed_at.tzinfo == timezone.utc
    assert item.raw_json is RAW


def test_parse_repo_noassertion_license_is_none():
    item = github.parse_repo({**RAW, "license": {"spdx_id": "NOASSERTION"}})
    assert item.license is None


def test_parse_repo_missing_license_is_none():
    item = github.parse_repo({**RAW, "license": None})
    assert item.license is None
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_github.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'collector.github'`

- [ ] **Step 3: Write minimal implementation** — `collector/github.py`

```python
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_github.py -v`
Expected: 3 passed.

- [ ] **Step 5: Commit**

```bash
git add collector/github.py tests/test_github.py
git commit -m "feat(collector): github search + parse"
```

---

### Task 5: Product Hunt client

**Files:**
- Create: `collector/producthunt.py`
- Test: `tests/test_producthunt.py`

**Interfaces:**
- Consumes: `Config`, `CollectedItem`.
- Produces: `producthunt.parse_post(raw: dict) -> CollectedItem`; `producthunt.collect(cfg: Config, first: int = 50) -> list[CollectedItem]`.

- [ ] **Step 1: Write the failing test** — `tests/test_producthunt.py`

```python
from collector import producthunt

NODE = {
    "id": "post-123",
    "name": "Pixelmind",
    "tagline": "Sentence to editable UI mockup.",
    "description": "Longer description.",
    "url": "https://www.producthunt.com/posts/pixelmind",
    "website": "https://pixelmind.app",
    "votesCount": 1240,
    "commentsCount": 210,
    "reviewsRating": 4.6,
    "reviewsCount": 38,
    "createdAt": "2026-06-29T00:00:00Z",
    "topics": {"edges": [{"node": {"name": "design"}}, {"node": {"name": "ai"}}]},
}


def test_parse_post_maps_fields():
    item = producthunt.parse_post(NODE)
    assert item.source == "producthunt"
    assert item.external_id == "post-123"
    assert item.one_liner == "Sentence to editable UI mockup."
    assert item.url == "https://www.producthunt.com/posts/pixelmind"
    assert item.product_url == "https://pixelmind.app"
    assert item.votes == 1240
    assert item.comments == 210
    assert item.rating == 4.6
    assert item.reviews_count == 38
    assert item.topics == ["design", "ai"]
    assert item.raw_json is NODE


def test_parse_post_missing_topics_is_empty():
    item = producthunt.parse_post({**NODE, "topics": None})
    assert item.topics == []
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_producthunt.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'collector.producthunt'`

- [ ] **Step 3: Write minimal implementation** — `collector/producthunt.py`

```python
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_producthunt.py -v`
Expected: 2 passed.

- [ ] **Step 5: Commit**

```bash
git add collector/producthunt.py tests/test_producthunt.py
git commit -m "feat(collector): product hunt graphql + parse"
```

---

### Task 6: Postgres persistence

**Files:**
- Create: `collector/db.py`
- Test: manual integration smoke against a Supabase dev project (documented below — psycopg SQL unit-tested without a real DB tests nothing).

**Interfaces:**
- Consumes: `Config`, `CollectedItem`.
- Produces: `db.connect(cfg) -> connection`; `db.save(conn, item: CollectedItem) -> None` (upserts entity, inserts snapshot, commits).

- [ ] **Step 1: Create a Supabase project and apply the schema**

1. Create a free Supabase project. Copy the connection string (Settings → Database → Connection string, "URI") into your local `.env` as `SUPABASE_DB_DSN=...`.
2. Apply the schema:

```bash
psql "$SUPABASE_DB_DSN" -f db/schema.sql
```

Expected: `CREATE TABLE` / `CREATE INDEX` lines, no errors.

- [ ] **Step 2: Write implementation** — `collector/db.py`

```python
import psycopg2
from psycopg2.extras import Json

from .config import Config
from .models import CollectedItem


def connect(cfg: Config):
    return psycopg2.connect(cfg.db_dsn)


def _upsert_entity(cur, item: CollectedItem) -> int:
    cur.execute(
        """
        insert into entities
            (source, external_id, name, one_liner, url, language, topics,
             owner_type, created_at, default_branch)
        values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
        on conflict (source, external_id) do update set
            name = excluded.name,
            one_liner = excluded.one_liner,
            url = excluded.url,
            language = excluded.language,
            topics = excluded.topics,
            owner_type = excluded.owner_type,
            default_branch = excluded.default_branch
        returning id
        """,
        (item.source, item.external_id, item.name, item.one_liner, item.url,
         item.language, item.topics, item.owner_type, item.created_at, item.default_branch),
    )
    return cur.fetchone()[0]


def _insert_snapshot(cur, entity_id: int, item: CollectedItem) -> None:
    cur.execute(
        """
        insert into snapshots
            (entity_id, stars, forks, watchers, open_issues, pushed_at, license,
             archived, votes, comments, rating, reviews_count, provisional_quality, raw_json)
        values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
        """,
        (entity_id, item.stars, item.forks, item.watchers, item.open_issues,
         item.pushed_at, item.license, item.archived, item.votes, item.comments,
         item.rating, item.reviews_count, item.provisional_quality, Json(item.raw_json)),
    )


def save(conn, item: CollectedItem) -> None:
    with conn.cursor() as cur:
        entity_id = _upsert_entity(cur, item)
        _insert_snapshot(cur, entity_id, item)
    conn.commit()
```

- [ ] **Step 3: Smoke-test persistence against the real DB**

Create a throwaway script `scripts/smoke_db.py`:

```python
from datetime import datetime, timezone

from collector.config import load_config
from collector.models import CollectedItem
from collector import db

cfg = load_config()
conn = db.connect(cfg)
item = CollectedItem(source="github", external_id="smoke/test", name="test",
                     one_liner="smoke", url="https://x", stars=1, forks=0,
                     provisional_quality=42, raw_json={"hello": "world"},
                     created_at=datetime.now(timezone.utc))
db.save(conn, item)
db.save(conn, item)  # second run must NOT duplicate the entity
with conn.cursor() as cur:
    cur.execute("select count(*) from entities where external_id='smoke/test'")
    assert cur.fetchone()[0] == 1, "entity duplicated — upsert broken"
    cur.execute("select count(*) from snapshots s join entities e on e.id=s.entity_id where e.external_id='smoke/test'")
    assert cur.fetchone()[0] == 2, "expected 2 snapshots"
print("smoke OK")
```

Run: `python -m scripts.smoke_db`
Expected: `smoke OK` (idempotent entity, two snapshots). Then clean up:

```bash
psql "$SUPABASE_DB_DSN" -c "delete from snapshots using entities where snapshots.entity_id=entities.id and entities.external_id='smoke/test'; delete from entities where external_id='smoke/test';"
```

- [ ] **Step 4: Commit**

```bash
git add collector/db.py scripts/smoke_db.py
git commit -m "feat(collector): postgres persistence with idempotent upsert"
```

---

### Task 7: Orchestrator

**Files:**
- Create: `collector/main.py`
- Test: `tests/test_run_cycle.py`

**Interfaces:**
- Consumes: `github.collect`, `producthunt.collect`, `prefilter.passes`, `quality.provisional_quality`, `db.save`.
- Produces: `main.run_cycle(cfg, conn, now=None) -> dict` (stats: `{"github": int, "producthunt": int, "errors": list[str]}`); `main.main()` CLI entrypoint.

- [ ] **Step 1: Write the failing test** — `tests/test_run_cycle.py`

```python
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_run_cycle.py -v`
Expected: FAIL with `AttributeError: module 'collector.main' has no attribute 'run_cycle'`

- [ ] **Step 3: Write minimal implementation** — `collector/main.py`

```python
from datetime import datetime, timezone

from . import github, producthunt, prefilter, quality, db
from .config import Config, load_config


def run_cycle(cfg: Config, conn, now: datetime | None = None) -> dict:
    now = now or datetime.now(timezone.utc)
    stats: dict = {"github": 0, "producthunt": 0, "errors": []}
    for name, module in (("github", github), ("producthunt", producthunt)):
        try:
            items = module.collect(cfg)
        except Exception as exc:  # degrade safe: one source failing doesn't stop the other
            stats["errors"].append(f"{name} collect failed: {exc}")
            continue
        for item in items:
            if not prefilter.passes(item, cfg, now):
                continue
            item.provisional_quality = quality.provisional_quality(item, now)
            try:
                db.save(conn, item)
                stats[name] += 1
            except Exception as exc:
                if conn is not None:
                    conn.rollback()
                stats["errors"].append(f"save {item.external_id} failed: {exc}")
    return stats


def main() -> None:
    cfg = load_config()
    conn = db.connect(cfg)
    try:
        stats = run_cycle(cfg, conn)
    finally:
        conn.close()
    print(f"collected github={stats['github']} producthunt={stats['producthunt']} "
          f"errors={len(stats['errors'])}")
    for err in stats["errors"]:
        print(f"  ERROR: {err}")
    if stats["errors"]:
        raise SystemExit(1)  # fail loud so a broken run is noticed


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_run_cycle.py -v`
Expected: 2 passed.

- [ ] **Step 5: Run the full suite and a real end-to-end cycle**

Run: `pytest -v`
Expected: all tests pass.

Run (against real APIs + DB, with `.env` populated): `python -m collector.main`
Expected: `collected github=<n> producthunt=<m> errors=0`. Verify rows landed:

```bash
psql "$SUPABASE_DB_DSN" -c "select source, count(*) from entities group by source;"
```

- [ ] **Step 6: Commit**

```bash
git add collector/main.py tests/test_run_cycle.py
git commit -m "feat(collector): fail-loud degrade-safe orchestrator"
```

---

### Task 8: Scheduled deployment (GitHub Actions)

**Files:**
- Create: `.github/workflows/collect.yml`

**Interfaces:**
- Consumes: `python -m collector.main` and repo secrets/vars.

- [ ] **Step 1: Create the workflow** — `.github/workflows/collect.yml`

```yaml
name: collect
on:
  schedule:
    - cron: "0 8 * * *"   # daily 08:00 UTC
  workflow_dispatch: {}     # allow manual runs

jobs:
  run:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.11"
      - run: pip install -r requirements.txt
      - run: python -m collector.main
        env:
          GITHUB_TOKEN: ${{ secrets.GH_PAT }}
          PH_TOKEN: ${{ secrets.PH_TOKEN }}
          SUPABASE_DB_DSN: ${{ secrets.SUPABASE_DB_DSN }}
          GITHUB_QUERIES: ${{ vars.GITHUB_QUERIES }}
```

- [ ] **Step 2: Configure repo secrets and variables**

In GitHub repo settings → Secrets and variables → Actions, add secrets:
- `GH_PAT` — a personal access token (public_repo scope is enough; used instead of the reserved `GITHUB_TOKEN` name for higher Search API limits).
- `PH_TOKEN` — Product Hunt API developer token.
- `SUPABASE_DB_DSN` — the Supabase Postgres connection string.

And a variable:
- `GITHUB_QUERIES` — e.g. `language:rust,language:typescript` (start small per NFR/B8).

- [ ] **Step 3: Trigger a manual run and verify**

In the Actions tab, run the `collect` workflow via "Run workflow" (workflow_dispatch).
Expected: green run, log line `collected github=<n> producthunt=<m> errors=0`. Confirm a second run adds snapshots without duplicating entities:

```bash
psql "$SUPABASE_DB_DSN" -c "select count(*) as entities from entities; select count(*) as snapshots from snapshots;"
```

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/collect.yml
git commit -m "ci(collector): daily scheduled collection"
```

---

## Definition of done (Phase 0)

- ☐ `pytest -v` green.
- ☐ Cron workflow runs and writes `entities` + dated `snapshots` (incl. `provisional_quality`).
- ☐ Pre-filter applied before storage; junk excluded.
- ☐ Idempotent — re-run adds snapshots, never duplicate entities (smoke-verified in Task 6, cron-verified in Task 8).
- ☐ Fail loud / degrade safe — one source failing doesn't block the other; the process exits non-zero on any error.
- ☐ **Out of scope (later plans):** velocity/momentum SQL view, the Flutter app, any deep-dive / LLM work.

## Notes for the next plan (Phase 1)

- Velocity / acceleration / cross-consistency / light-momentum-score / momentum-stage are a **read-time SQL view** over `snapshots` — build that at the start of the Phase 1 plan (needs ≥2 snapshot dates to produce non-null velocity).
- The Flutter app reads that view + `watchlist_state` via `supabase_flutter` under RLS.
- Deep-dive (Phase 2) and the `deep_dive_cache.status` async/Realtime flow get their own spec once `trend-intelligence-spec.md` (the rubric) is available.

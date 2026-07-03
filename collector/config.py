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

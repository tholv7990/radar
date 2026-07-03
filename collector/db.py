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

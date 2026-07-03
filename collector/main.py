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

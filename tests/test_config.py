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

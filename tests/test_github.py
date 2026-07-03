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

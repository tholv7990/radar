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

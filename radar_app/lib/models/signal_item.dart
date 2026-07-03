class SignalItem {
  final int id;
  final String source;
  final String name;
  final String? oneLiner;
  final String? url;
  final String? language;
  final List<String> topics;
  final int? stars;
  final int? votes;
  final int? comments;
  final int provisionalQuality;
  final int? velocity;
  final int? totalMetric;
  final String consistency;   // corroborated | mixed | suspicious | new
  final String momentumStage; // emerging | rising | steady | fading | new
  final num rankScore;
  final String? watchState;   // seen | watching | dismissed | null
  final DateTime? capturedAt;

  SignalItem({
    required this.id, required this.source, required this.name, this.oneLiner,
    this.url, this.language, required this.topics, this.stars, this.votes,
    this.comments, required this.provisionalQuality, this.velocity,
    this.totalMetric, required this.consistency, required this.momentumStage,
    required this.rankScore, this.watchState, this.capturedAt,
  });

  bool get isGithub => source == 'github';

  static List<String> _topics(dynamic v) =>
      v == null ? <String>[] : (v as List).map((e) => e.toString()).toList();

  factory SignalItem.fromMap(Map<String, dynamic> m) => SignalItem(
        id: m['id'] as int,
        source: m['source'] as String,
        name: m['name'] as String,
        oneLiner: m['one_liner'] as String?,
        url: m['url'] as String?,
        language: m['language'] as String?,
        topics: _topics(m['topics']),
        stars: m['stars'] as int?,
        votes: m['votes'] as int?,
        comments: m['comments'] as int?,
        provisionalQuality: (m['provisional_quality'] ?? 0) as int,
        velocity: (m['velocity'] as num?)?.toInt(),
        totalMetric: (m['total_metric'] as num?)?.toInt(),
        consistency: (m['consistency'] ?? 'new') as String,
        momentumStage: (m['momentum_stage'] ?? 'new') as String,
        rankScore: (m['rank_score'] ?? 0) as num,
        watchState: m['watch_state'] as String?,
        capturedAt: m['captured_at'] == null ? null : DateTime.tryParse(m['captured_at'] as String),
      );
}

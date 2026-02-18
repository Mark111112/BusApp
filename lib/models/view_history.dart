/// 浏览历史模型
class ViewHistory {
  final String movieId;
  final String? title;
  final String? cover;
  final int viewTime;

  ViewHistory({
    required this.movieId,
    this.title,
    this.cover,
    required this.viewTime,
  });

  factory ViewHistory.fromJson(Map<String, dynamic> json) {
    return ViewHistory(
      movieId: json['movie_id'] as String? ?? '',
      title: json['title'] as String?,
      cover: json['cover'] as String?,
      viewTime: json['view_time'] as int? ??
          DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'movie_id': movieId,
      'title': title,
      'cover': cover,
      'view_time': viewTime,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ViewHistory &&
          runtimeType == other.runtimeType &&
          movieId == other.movieId;

  @override
  int get hashCode => movieId.hashCode;
}

/// 收藏模型
class Favorite {
  final String movieId;
  final int createdAt;

  Favorite({
    required this.movieId,
    required this.createdAt,
  });

  factory Favorite.fromJson(Map<String, dynamic> json) {
    return Favorite(
      movieId: json['movie_id'] as String? ?? '',
      createdAt: json['created_at'] as int? ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'movie_id': movieId,
      'created_at': createdAt,
    };
  }
}

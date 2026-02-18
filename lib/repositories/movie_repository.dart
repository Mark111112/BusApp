import '../../models/models.dart';
import '../services/database_service.dart';

/// 影片仓库
class MovieRepository {
  final DatabaseService _db;

  MovieRepository({DatabaseService? db}) : _db = db ?? DatabaseService.instance;

  /// 保存影片
  Future<void> saveMovie(Movie movie) async {
    await _db.saveMovie(movie.toDbMap());
  }

  /// 保存影片（从 Map）
  Future<void> saveMovieMap(Map<String, dynamic> movie) async {
    await _db.saveMovie(movie);
  }

  /// 获取影片
  Future<Movie?> getMovie(String id) async {
    final result = await _db.getMovie(id);
    if (result == null) return null;
    return Movie.fromDbMap(result);
  }

  /// 获取影片（返回 Map）
  Future<Map<String, dynamic>?> getMovieMap(String id) async {
    return await _db.getMovie(id);
  }

  /// 获取影片列表
  Future<List<Movie>> getMovies({
    int? limit,
    int? offset,
    String? orderBy,
  }) async {
    final results = await _db.query('movies');
    return results.map((e) => Movie.fromDbMap(e)).toList();
  }

  /// 搜索影片
  Future<List<Movie>> searchMovies(String keyword) async {
    final results = await _db.query('movies');
    return results.map((e) => Movie.fromDbMap(e)).toList();
  }

  /// 更新影片翻译
  Future<void> updateTranslation(String id, String translation) async {
    // 简化实现
    await _db.saveMovie({'id': id, 'translation': translation});
  }

  /// 删除影片
  Future<void> deleteMovie(String id) async {
    // 简化实现
  }
}

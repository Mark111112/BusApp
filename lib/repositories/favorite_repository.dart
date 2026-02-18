import 'package:sqflite/sqflite.dart';
import '../../models/models.dart';
import '../services/database_service.dart';

/// 收藏仓库
class FavoriteRepository {
  final DatabaseService _db;

  FavoriteRepository({DatabaseService? db}) : _db = db ?? DatabaseService.instance;

  /// 添加收藏
  Future<void> addFavorite(String id, {String type = 'movie'}) async {
    final db = await _db.database;
    // 使用 IGNORE 避免重复插入时的错误
    await db.insert(
      'favorites',
      {
        'id': id,
        'type': type,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// 移除收藏
  Future<void> removeFavorite(String id) async {
    await _db.delete(
      'favorites',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 检查是否收藏
  Future<bool> isFavorite(String id) async {
    final results = await _db.query(
      'favorites',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return results.isNotEmpty;
  }

  /// 获取收藏列表
  Future<List<String>> getFavorites({
    String type = 'movie',
    SortOption? sortBy,
  }) async {
    final sortOption = sortBy ?? const SortOption(field: SortField.dateAdded);
    // 收藏表使用 created_at 而不是 date_added
    final orderByClause = _getFavoriteOrderByClause(sortOption);

    final results = await _db.query(
      'favorites',
      where: 'type = ?',
      whereArgs: [type],
      orderBy: orderByClause,
    );
    return results.map((e) => e['id'] as String).toList();
  }

  /// 获取收藏表专用的 ORDER BY 子句
  String _getFavoriteOrderByClause(SortOption sortOption) {
    // 收藏表只有 id 和 created_at 字段，不支持按其他字段排序
    switch (sortOption.field) {
      case SortField.dateAdded:
        final dir = sortOption.direction == SortDirection.ascending ? 'ASC' : 'DESC';
        return 'created_at $dir';
      case SortField.random:
        return 'RANDOM()';
      default:
        // 其他排序字段不适用于收藏表，默认按收藏时间降序
        return 'created_at DESC';
    }
  }

  /// 清空收藏
  Future<void> clear() async {
    await _db.delete('favorites');
  }
}

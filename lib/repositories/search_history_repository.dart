import '../services/database_service.dart';

/// 搜索历史仓库
class SearchHistoryRepository {
  final DatabaseService _db;

  SearchHistoryRepository({DatabaseService? db}) : _db = db ?? DatabaseService.instance;

  /// 添加搜索历史
  Future<void> add(String keyword) async {
    final db = await _db.database;
    await db.insert('search_history', {
      'keyword': keyword,
      'search_time': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
  }

  /// 获取搜索历史
  Future<List<String>> get({int limit = 20}) async {
    final results = await _db.query(
      'search_history',
      orderBy: 'search_time DESC',
      limit: limit,
    );
    return results.map((e) => e['keyword'] as String).toList();
  }

  /// 清空搜索历史
  Future<void> clear() async {
    await _db.delete('search_history');
  }

  /// 删除单个记录
  Future<void> remove(String keyword) async {
    await _db.delete(
      'search_history',
      where: 'keyword = ?',
      whereArgs: [keyword],
    );
  }
}

import '../services/database_service.dart';

/// 播放位置仓库
class PlaybackRepository {
  final DatabaseService _db;

  PlaybackRepository({DatabaseService? db}) : _db = db ?? DatabaseService.instance;

  /// 保存播放位置
  Future<void> savePosition({
    required String fileId,
    required String fileType,
    required int position,
    int? duration,
  }) async {
    final db = await _db.database;
    await db.insert('playback_positions', {
      'file_id': fileId,
      'file_type': fileType,
      'position': position,
      'duration': duration ?? 0,
    });
  }

  /// 获取播放位置
  Future<Map<String, dynamic>?> getPosition(String fileId) async {
    final results = await _db.query(
      'playback_positions',
      where: 'file_id = ?',
      whereArgs: [fileId],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// 删除播放位置
  Future<void> removePosition(String fileId) async {
    await _db.delete(
      'playback_positions',
      where: 'file_id = ?',
      whereArgs: [fileId],
    );
  }

  /// 获取最近播放
  Future<List<Map<String, dynamic>>> getRecentHistory({int limit = 20}) async {
    final results = await _db.query(
      'playback_positions',
      orderBy: 'last_played DESC',
      limit: limit,
    );
    return results;
  }
}

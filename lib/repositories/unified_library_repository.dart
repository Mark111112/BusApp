import 'package:sqflite/sqflite.dart';
import '../services/database_service.dart';
import '../models/unified_library_item.dart';

/// 统一库数据仓库
class UnifiedLibraryRepository {
  final DatabaseService _db = DatabaseService.instance;

  /// 确保表存在
  Future<void> ensureTable() async {
    // 表已由 DatabaseService 创建，这里可以预留扩展
  }

  /// 插入或更新项目（使用 CONFLICT REPLACE）
  Future<void> insertOrUpdate(UnifiedLibraryItem item) async {
    final db = await _db.database;
    await db.insert(
      'unified_library',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 批量插入或更新
  Future<void> insertOrUpdateBatch(List<UnifiedLibraryItem> items) async {
    final db = await _db.database;
    final batch = db.batch();

    for (final item in items) {
      batch.insert(
        'unified_library',
        item.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  /// 根据 unified_id 获取项目
  Future<UnifiedLibraryItem?> getByUnifiedId(String unifiedId) async {
    final results = await _db.query(
      'unified_library',
      where: 'unified_id = ?',
      whereArgs: [unifiedId],
      limit: 1,
    );

    if (results.isEmpty) return null;
    return UnifiedLibraryItem.fromMap(results.first);
  }

  /// 根据 video_id 获取项目
  Future<UnifiedLibraryItem?> getByVideoId(String videoId) async {
    return getByUnifiedId(videoId);
  }

  /// 获取所有项目
  Future<List<UnifiedLibraryItem>> getAll({
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final results = await _db.query(
      'unified_library',
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );

    return results.map((e) => UnifiedLibraryItem.fromMap(e)).toList();
  }

  /// 搜索项目
  Future<List<UnifiedLibraryItem>> search({
    String? keyword,
    String? source, // 'cloud115', 'jellyfin', 'strm'
    String? libraryId, // Jellyfin 库 ID（需要与 source='jellyfin' 一起使用）
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    String? where;
    List<Object?>? whereArgs;

    if (keyword != null && keyword.isNotEmpty) {
      where = '(title LIKE ? OR unified_id LIKE ?)';
      whereArgs = ['%$keyword%', '%$keyword%'];
    }

    // 根据来源筛选（通过 JSON 查询）
    if (source != null) {
      final sourceCondition = "sources_json LIKE ?";
      // ignore: prefer_const_declarations
      final sourcePattern = '%"source":"$source"%';

      if (where != null) {
        where = '($where) AND $sourceCondition';
        whereArgs = [...whereArgs!, sourcePattern];
      } else {
        where = sourceCondition;
        whereArgs = [sourcePattern];
      }
    }

    // 根据 Jellyfin 库 ID 筛选（通过 JSON 查询）
    if (libraryId != null) {
      final libraryCondition = "sources_json LIKE ?";
      // ignore: prefer_const_declarations
      final libraryPattern = '%"libraryId":"$libraryId"%';

      if (where != null) {
        where = '($where) AND $libraryCondition';
        whereArgs = [...whereArgs!, libraryPattern];
      } else {
        where = libraryCondition;
        whereArgs = [libraryPattern];
      }
    }

    final results = await _db.query(
      'unified_library',
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );

    return results.map((e) => UnifiedLibraryItem.fromMap(e)).toList();
  }

  /// 更新播放计数
  Future<bool> updatePlayCount(String unifiedId) async {
    final db = await _db.database;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final count = await db.update(
      'unified_library',
      {
        'play_count': db.rawUpdate('''
          UPDATE unified_library
          SET play_count = play_count + 1,
              last_played = ?
          WHERE unified_id = ?
        ''', [now, unifiedId]),
        'last_played': now,
        'updated_at': now,
      },
      where: 'unified_id = ?',
      whereArgs: [unifiedId],
    );

    return count > 0;
  }

  /// 删除项目
  Future<bool> delete(String unifiedId) async {
    final count = await _db.delete(
      'unified_library',
      where: 'unified_id = ?',
      whereArgs: [unifiedId],
    );
    return count > 0;
  }

  /// 清空所有数据
  Future<void> clear() async {
    await _db.delete('unified_library');
  }

  /// 获取统计信息
  Future<Map<String, int>> getStatistics() async {
    final db = await _db.database;

    final total = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM unified_library'),
    ) ?? 0;

    final withVideoId = Sqflite.firstIntValue(
      await db.rawQuery("SELECT COUNT(*) FROM unified_library WHERE unified_id NOT LIKE 'local_%'"),
    ) ?? 0;

    final withCloud115 = Sqflite.firstIntValue(
      await db.rawQuery("SELECT COUNT(*) FROM unified_library WHERE sources_json LIKE '%\"source\":\"cloud115\"%'"),
    ) ?? 0;

    final withJellyfin = Sqflite.firstIntValue(
      await db.rawQuery("SELECT COUNT(*) FROM unified_library WHERE sources_json LIKE '%\"source\":\"jellyfin\"%'"),
    ) ?? 0;

    final withStrm = Sqflite.firstIntValue(
      await db.rawQuery("SELECT COUNT(*) FROM unified_library WHERE sources_json LIKE '%\"source\":\"strm\"%'"),
    ) ?? 0;

    return {
      'total': total,
      'withVideoId': withVideoId,
      'withCloud115': withCloud115,
      'withJellyfin': withJellyfin,
      'withStrm': withStrm,
    };
  }

  /// 获取所有 unified_id 列表
  Future<List<String>> getAllUnifiedIds() async {
    final results = await _db.query(
      'unified_library',
      columns: ['unified_id'],
    );

    return results.map((e) => e['unified_id'] as String).toList();
  }

  /// 检查是否存在某个 unified_id
  Future<bool> exists(String unifiedId) async {
    final results = await _db.query(
      'unified_library',
      where: 'unified_id = ?',
      whereArgs: [unifiedId],
      columns: ['id'],
      limit: 1,
    );
    return results.isNotEmpty;
  }
}

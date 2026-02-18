import 'package:sqflite/sqflite.dart';
import '../models/library_item.dart';
import '../models/sort_option.dart';
import '../services/database_service.dart';

/// 115 网盘数据库仓储
class Cloud115LibraryRepository {
  final DatabaseService _db;

  Cloud115LibraryRepository({DatabaseService? db}) : _db = db ?? DatabaseService.instance;

  /// 获取数据库实例
  Future<Database> get _database async => await _db.database;

  /// 确保表存在
  Future<void> ensureTables() async {
    final db = await _database;

    // 创建 cloud115_library 表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cloud115_library (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        filepath TEXT NOT NULL,
        url TEXT NOT NULL,
        thumbnail TEXT,
        description TEXT,
        category TEXT DEFAULT 'movies',
        date_added INTEGER,
        last_played INTEGER DEFAULT 0,
        play_count INTEGER DEFAULT 0,
        video_id TEXT,
        cover_image TEXT,
        actors TEXT,
        date TEXT,
        file_id TEXT NOT NULL,
        pickcode TEXT NOT NULL,
        size TEXT,
        UNIQUE(file_id)
      )
    ''');
  }

  /// 保存或更新单个库项目
  Future<void> saveItem(LibraryItem item) async {
    final db = await _database;
    await db.insert(
      'cloud115_library',
      {
        'title': item.title,
        'filepath': item.filepath,
        'url': item.url,
        'thumbnail': item.thumbnail,
        'description': item.description,
        'category': item.category ?? 'movies',
        'date_added': item.dateAdded ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'last_played': item.lastPlayed ?? 0,
        'play_count': item.playCount ?? 0,
        'video_id': item.videoId,
        'cover_image': item.coverImage,
        'actors': item.actors,
        'date': item.date,
        'file_id': item.fileId ?? '',
        'pickcode': item.pickcode ?? '',
        'size': item.size,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 批量保存库项目
  Future<void> saveItems(List<LibraryItem> items) async {
    final db = await _database;
    final batch = db.batch();

    for (final item in items) {
      batch.insert(
        'cloud115_library',
        {
          'title': item.title,
          'filepath': item.filepath,
          'url': item.url,
          'thumbnail': item.thumbnail,
          'description': item.description,
          'category': item.category ?? 'movies',
          'date_added': item.dateAdded ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'last_played': item.lastPlayed ?? 0,
          'play_count': item.playCount ?? 0,
          'video_id': item.videoId,
          'cover_image': item.coverImage,
          'actors': item.actors,
          'date': item.date,
          'file_id': item.fileId ?? '',
          'pickcode': item.pickcode ?? '',
          'size': item.size,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  /// 获取所有库项目
  Future<List<LibraryItem>> getAllItems({
    int start = 0,
    int limit = 50,
    String? searchTerm,
    String? category,
    SortOption? sortBy,
  }) async {
    final db = await _database;
    final List<dynamic> params = [];
    final List<String> whereClauses = [];

    if (searchTerm != null && searchTerm.isNotEmpty) {
      whereClauses.add('(title LIKE ? OR video_id LIKE ?)');
      params.addAll(['%$searchTerm%', '%$searchTerm%']);
    }

    if (category != null) {
      whereClauses.add('category = ?');
      params.add(category);
    }

    final whereClause = whereClauses.isNotEmpty
        ? 'WHERE ${whereClauses.join(' AND ')}'
        : '';

    // 使用排序选项，默认为入库时间降序
    final sortOption = sortBy ?? const SortOption(field: SortField.dateAdded);
    final orderByClause = sortOption.getOrderByClause();

    final rows = await db.rawQuery('''
      SELECT * FROM cloud115_library
      $whereClause
      ORDER BY $orderByClause
      LIMIT ? OFFSET ?
    ''', [...params, limit, start]);

    return rows.map((row) => LibraryItem.fromJson({
      ...row,
      'type': 'cloud115',
    })).toList();
  }

  /// 获取所有项目（无分页限制）
  Future<List<LibraryItem>> getAllItemsUnbounded() async {
    final db = await _database;
    final rows = await db.query('cloud115_library');
    return rows.map((row) => LibraryItem.fromJson({
      ...row,
      'type': 'cloud115',
    })).toList();
  }

  /// 获取库项目总数
  Future<int> getItemsCount({
    String? searchTerm,
    String? category,
  }) async {
    final db = await _database;
    final List<dynamic> params = [];
    final List<String> whereClauses = [];

    if (searchTerm != null && searchTerm.isNotEmpty) {
      whereClauses.add('(title LIKE ? OR video_id LIKE ?)');
      params.addAll(['%$searchTerm%', '%$searchTerm%']);
    }

    if (category != null) {
      whereClauses.add('category = ?');
      params.add(category);
    }

    final whereClause = whereClauses.isNotEmpty
        ? 'WHERE ${whereClauses.join(' AND ')}'
        : '';

    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM cloud115_library $whereClause',
      params,
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// 根据 video_id 查找项目
  Future<List<LibraryItem>> findItemsByVideoId(String videoId) async {
    final db = await _database;
    final rows = await db.query(
      'cloud115_library',
      where: 'video_id = ?',
      whereArgs: [videoId],
      orderBy: 'title',
    );

    return rows.map((row) => LibraryItem.fromJson({
      ...row,
      'type': 'cloud115',
    })).toList();
  }

  /// 根据 file_id 获取单个项目
  Future<LibraryItem?> getItemByFileId(String fileId) async {
    final db = await _database;
    final rows = await db.query(
      'cloud115_library',
      where: 'file_id = ?',
      whereArgs: [fileId],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return LibraryItem.fromJson({
      ...rows.first,
      'type': 'cloud115',
    });
  }

  /// 根据 pickcode 获取单个项目
  Future<LibraryItem?> getItemByPickcode(String pickcode) async {
    final db = await _database;
    final rows = await db.query(
      'cloud115_library',
      where: 'pickcode = ?',
      whereArgs: [pickcode],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return LibraryItem.fromJson({
      ...rows.first,
      'type': 'cloud115',
    });
  }

  /// 删除单个项目
  Future<bool> deleteItem(String fileId) async {
    final db = await _database;
    final result = await db.delete(
      'cloud115_library',
      where: 'file_id = ?',
      whereArgs: [fileId],
    );
    return result > 0;
  }

  /// 清空所有项目
  Future<int> clearAll() async {
    final db = await _database;
    return await db.delete('cloud115_library');
  }

  /// 更新项目的 video_id
  Future<bool> updateVideoId(String fileId, String videoId) async {
    final db = await _database;
    final result = await db.update(
      'cloud115_library',
      {'video_id': videoId},
      where: 'file_id = ?',
      whereArgs: [fileId],
    );
    return result > 0;
  }

  /// 更新播放计数
  Future<bool> updatePlayCount(String fileId) async {
    final db = await _database;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // 先获取当前计数
    final item = await getItemByFileId(fileId);
    final currentCount = item?.playCount ?? 0;

    final result = await db.update(
      'cloud115_library',
      {
        'play_count': currentCount + 1,
        'last_played': now,
      },
      where: 'file_id = ?',
      whereArgs: [fileId],
    );

    return result > 0;
  }

  /// 更新项目的封面图片
  Future<bool> updateCoverImage(String fileId, String coverImage) async {
    final db = await _database;
    final result = await db.update(
      'cloud115_library',
      {'cover_image': coverImage},
      where: 'file_id = ?',
      whereArgs: [fileId],
    );
    return result > 0;
  }

  /// 获取统计信息
  Future<Map<String, int>> getStats() async {
    final db = await _database;
    final totalCountResult = await db.rawQuery('SELECT COUNT(*) as count FROM cloud115_library');
    final totalCount = Sqflite.firstIntValue(totalCountResult) ?? 0;

    final withVideoIdResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM cloud115_library WHERE video_id IS NOT NULL AND video_id != ""'
    );
    final withVideoId = Sqflite.firstIntValue(withVideoIdResult) ?? 0;

    return {
      'total': totalCount,
      'with_video_id': withVideoId,
      'without_video_id': totalCount - withVideoId,
    };
  }
}

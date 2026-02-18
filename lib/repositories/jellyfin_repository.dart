import 'package:sqflite/sqflite.dart';
import 'dart:convert';
import '../models/jellyfin.dart';
import '../models/sort_option.dart';
import '../services/database_service.dart';

/// Jellyfin 数据库仓储
class JellyfinRepository {
  final DatabaseService _db;

  JellyfinRepository({DatabaseService? db}) : _db = db ?? DatabaseService.instance;

  /// 获取数据库实例
  Future<Database> get _database async => await _db.database;

  /// 确保表存在
  Future<void> ensureTables() async {
    final db = await _database;

    // 创建 jelmovie 表（包含所有字段）
    await db.execute('''
      CREATE TABLE IF NOT EXISTS jelmovie (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        jellyfin_id TEXT NOT NULL,
        item_id TEXT NOT NULL,
        video_id TEXT,
        library_name TEXT NOT NULL,
        library_id TEXT NOT NULL,
        play_url TEXT,
        path TEXT,
        cover_image TEXT,
        actors TEXT,
        date TEXT,
        date_added INTEGER,
        last_played INTEGER DEFAULT 0,
        play_count INTEGER DEFAULT 0,
        overview TEXT,
        runtime_seconds INTEGER,
        runtime_text TEXT,
        file_size_bytes INTEGER,
        file_size_text TEXT,
        genres TEXT,
        resolution TEXT,
        UNIQUE(item_id)
      )
    ''');

    // 为已存在的表添加缺失的列（迁移）
    final columns = await db.rawQuery('PRAGMA table_info(jelmovie)');
    final columnNames = columns.map((col) => col['name'] as String).toSet();

    // 添加缺失的列
    if (!columnNames.contains('overview')) {
      await db.execute('ALTER TABLE jelmovie ADD COLUMN overview TEXT');
    }
    if (!columnNames.contains('runtime_seconds')) {
      await db.execute('ALTER TABLE jelmovie ADD COLUMN runtime_seconds INTEGER');
    }
    if (!columnNames.contains('runtime_text')) {
      await db.execute('ALTER TABLE jelmovie ADD COLUMN runtime_text TEXT');
    }
    if (!columnNames.contains('file_size_bytes')) {
      await db.execute('ALTER TABLE jelmovie ADD COLUMN file_size_bytes INTEGER');
    }
    if (!columnNames.contains('file_size_text')) {
      await db.execute('ALTER TABLE jelmovie ADD COLUMN file_size_text TEXT');
    }
    if (!columnNames.contains('genres')) {
      await db.execute('ALTER TABLE jelmovie ADD COLUMN genres TEXT');
    }
    if (!columnNames.contains('resolution')) {
      await db.execute('ALTER TABLE jelmovie ADD COLUMN resolution TEXT');
    }

    // 创建 jelibrary_sync 表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS jelibrary_sync (
        library_id TEXT PRIMARY KEY,
        last_sync_date_created TEXT,
        last_sync_date_last_saved TEXT,
        last_sync_ts INTEGER
      )
    ''');
  }

  /// 保存或更新单个电影
  Future<void> saveMovie(JellyfinMovie movie) async {
    final db = await _database;
    final map = movie.toDbMap();

    await db.insert(
      'jelmovie',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 批量保存电影
  Future<void> saveMovies(List<JellyfinMovie> movies) async {
    final db = await _database;
    final batch = db.batch();

    for (final movie in movies) {
      batch.insert(
        'jelmovie',
        movie.toDbMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  /// 删除库中的所有电影
  Future<int> deleteLibrary(String libraryId) async {
    final db = await _database;
    final result = await db.delete(
      'jelmovie',
      where: 'library_id = ?',
      whereArgs: [libraryId],
    );
    return result;
  }

  /// 获取已导入的库列表
  Future<List<ImportedLibrary>> getImportedLibraries() async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT DISTINCT library_id, library_name, jellyfin_id,
      COUNT(*) as item_count,
      MAX(date_added) as last_updated
      FROM jelmovie
      GROUP BY library_id
      ORDER BY last_updated DESC
    ''');

    return rows.map((row) => ImportedLibrary.fromDbMap(row)).toList();
  }

  /// 获取库中的电影列表
  Future<List<JellyfinMovie>> getLibraryMovies({
    String? libraryId,
    int start = 0,
    int limit = 50,
    String? searchTerm,
    SortOption? sortBy,
  }) async {
    final db = await _database;
    final List<dynamic> params = [];
    final List<String> whereClauses = [];

    if (libraryId != null) {
      whereClauses.add('library_id = ?');
      params.add(libraryId);
    }

    if (searchTerm != null && searchTerm.isNotEmpty) {
      whereClauses.add('(title LIKE ? OR video_id LIKE ?)');
      params.addAll(['%$searchTerm%', '%$searchTerm%']);
    }

    final whereClause = whereClauses.isNotEmpty
        ? 'WHERE ${whereClauses.join(' AND ')}'
        : '';

    // 使用排序选项，默认为入库时间降序
    final sortOption = sortBy ?? const SortOption(field: SortField.dateAdded);
    final orderByClause = sortOption.getOrderByClause();

    final rows = await db.rawQuery('''
      SELECT * FROM jelmovie
      $whereClause
      ORDER BY $orderByClause
      LIMIT ? OFFSET ?
    ''', [...params, limit, start]);

    return rows.map((row) => JellyfinMovie.fromDbMap(row)).toList();
  }

  /// 获取所有电影（不分页）
  Future<List<JellyfinMovie>> getAllMovies() async {
    final db = await _database;
    final rows = await db.query('jelmovie');
    return rows.map((row) => JellyfinMovie.fromDbMap(row)).toList();
  }

  /// 获取库电影总数
  Future<int> getLibraryMoviesCount({
    String? libraryId,
    String? searchTerm,
  }) async {
    final db = await _database;
    final List<dynamic> params = [];
    final List<String> whereClauses = [];

    if (libraryId != null) {
      whereClauses.add('library_id = ?');
      params.add(libraryId);
    }

    if (searchTerm != null && searchTerm.isNotEmpty) {
      whereClauses.add('(title LIKE ? OR video_id LIKE ?)');
      params.addAll(['%$searchTerm%', '%$searchTerm%']);
    }

    final whereClause = whereClauses.isNotEmpty
        ? 'WHERE ${whereClauses.join(' AND ')}'
        : '';

    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM jelmovie $whereClause',
      params,
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// 根据 video_id 查找电影
  Future<List<JellyfinMovie>> findMoviesByVideoId(String videoId) async {
    final db = await _database;
    final rows = await db.query(
      'jelmovie',
      where: 'video_id = ?',
      whereArgs: [videoId],
      orderBy: 'title',
    );

    return rows.map((row) => JellyfinMovie.fromDbMap(row)).toList();
  }

  /// 根据 item_id 获取单个电影
  Future<JellyfinMovie?> getMovieByItemId(String itemId) async {
    final db = await _database;
    final rows = await db.query(
      'jelmovie',
      where: 'item_id = ?',
      whereArgs: [itemId],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return JellyfinMovie.fromDbMap(rows.first);
  }

  /// 更新播放计数
  Future<bool> updatePlayCount(String itemId) async {
    final db = await _database;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final result = await db.update(
      'jelmovie',
      {
        'play_count': 'play_count + 1',
        'last_played': now,
      },
      where: 'item_id = ?',
      whereArgs: [itemId],
    );

    return result > 0;
  }

  /// 获取库同步状态
  Future<LibrarySyncState?> getLibrarySyncState(String libraryId) async {
    final db = await _database;
    final rows = await db.query(
      'jelibrary_sync',
      where: 'library_id = ?',
      whereArgs: [libraryId],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return LibrarySyncState.fromDbMap(rows.first);
  }

  /// 更新库同步状态
  Future<void> upsertLibrarySyncState(LibrarySyncState state) async {
    final db = await _database;
    await db.insert(
      'jelibrary_sync',
      {
        'library_id': state.libraryId,
        'last_sync_date_created': state.lastSyncDateCreated,
        'last_sync_date_last_saved': state.lastSyncDateLastSaved,
        'last_sync_ts': state.lastSyncTs ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 删除库同步状态
  Future<void> deleteLibrarySyncState(String libraryId) async {
    final db = await _database;
    await db.delete(
      'jelibrary_sync',
      where: 'library_id = ?',
      whereArgs: [libraryId],
    );
  }
}

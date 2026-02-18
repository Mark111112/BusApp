import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

/// 数据库服务
class DatabaseService {
  static DatabaseService? _instance;
  static Database? _database;

  DatabaseService._();

  factory DatabaseService() {
    _instance ??= DatabaseService._();
    return _instance!;
  }

  static DatabaseService get instance {
    _instance ??= DatabaseService._();
    return _instance!;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final Directory appDocDir = await getApplicationDocumentsDirectory();
    final dbPath = join(appDocDir.path, 'bus115.db');

    return await openDatabase(
      dbPath,
      version: 3,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // 创建影片表（完整版本）
    await db.execute('''
      CREATE TABLE IF NOT EXISTS movies (
        id TEXT PRIMARY KEY,
        title TEXT,
        cover TEXT,
        date TEXT,
        publisher TEXT,
        producer TEXT,
        last_updated INTEGER,
        description TEXT,
        director TEXT,
        series TEXT,
        duration INTEGER,
        translation TEXT,
        gid TEXT,
        uc TEXT,
        actors_json TEXT,
        genres_json TEXT,
        samples_json TEXT,
        magnets_json TEXT
      )
    ''');

    // 创建演员表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS stars (
        id TEXT PRIMARY KEY,
        data TEXT,
        name TEXT,
        avatar TEXT,
        birthday TEXT,
        age TEXT,
        height TEXT,
        bust TEXT,
        waistline TEXT,
        hipline TEXT,
        birthplace TEXT,
        hobby TEXT,
        last_updated INTEGER
      )
    ''');

    // 创建演员-影片关系表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS star_movie (
        star_id TEXT,
        movie_id TEXT,
        PRIMARY KEY (star_id, movie_id),
        FOREIGN KEY (star_id) REFERENCES stars (id) ON DELETE CASCADE,
        FOREIGN KEY (movie_id) REFERENCES movies (id) ON DELETE CASCADE
      )
    ''');

    // 创建搜索历史表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS search_history (
        keyword TEXT PRIMARY KEY,
        search_time INTEGER
      )
    ''');

    // 创建收藏表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS favorites (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL DEFAULT 'movie',
        created_at INTEGER DEFAULT (strftime('%s', 'now'))
      )
    ''');

    // 创建播放位置表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS playback_positions (
        file_id TEXT PRIMARY KEY,
        file_type TEXT NOT NULL,
        position INTEGER DEFAULT 0,
        duration INTEGER DEFAULT 0,
        last_played INTEGER DEFAULT (strftime('%s', 'now'))
      )
    ''');

    // 创建 STRM 文件库表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS strm_library (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        filepath TEXT NOT NULL,
        url TEXT NOT NULL,
        thumbnail TEXT,
        description TEXT,
        category TEXT,
        date_added INTEGER,
        last_played INTEGER DEFAULT 0,
        play_count INTEGER DEFAULT 0,
        video_id TEXT,
        cover_image TEXT,
        actors TEXT,
        date TEXT,
        UNIQUE(filepath)
      )
    ''');

    // 创建 115 网盘文件库表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cloud115_library (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        filepath TEXT NOT NULL,
        url TEXT NOT NULL,
        thumbnail TEXT,
        description TEXT,
        category TEXT,
        date_added INTEGER,
        last_played INTEGER DEFAULT 0,
        play_count INTEGER DEFAULT 0,
        video_id TEXT,
        cover_image TEXT,
        actors TEXT,
        date TEXT,
        file_id TEXT,
        pickcode TEXT,
        size TEXT DEFAULT '',
        UNIQUE(filepath)
      )
    ''');

    // 创建 Jellyfin 电影表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS jellyfin_movies (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        jellyfin_id TEXT,
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
        UNIQUE(item_id)
      )
    ''');

    // 创建配置表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_config (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // 创建统一库表 - 整合 115、Jellyfin、STRM 的所有影片
    await db.execute('''
      CREATE TABLE IF NOT EXISTS unified_library (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        unified_id TEXT NOT NULL UNIQUE,
        title TEXT NOT NULL,
        cover_image TEXT,
        actors TEXT,
        date TEXT,
        duration INTEGER,
        description TEXT,
        sources_json TEXT NOT NULL,
        play_count INTEGER DEFAULT 0,
        last_played INTEGER DEFAULT 0,
        date_added INTEGER DEFAULT (strftime('%s', 'now')),
        created_at INTEGER DEFAULT (strftime('%s', 'now')),
        updated_at INTEGER DEFAULT (strftime('%s', 'now'))
      )
    ''');

    // 创建索引
    await _createIndexes(db);
  }

  Future<void> _createIndexes(Database db) async {
    await db.execute('CREATE INDEX IF NOT EXISTS idx_movies_date ON movies(date DESC)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_movies_updated ON movies(last_updated DESC)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_search_history_time ON search_history(search_time DESC)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_favorites_created ON favorites(created_at DESC)');

    // 统一库索引
    await db.execute('CREATE INDEX IF NOT EXISTS idx_unified_unified_id ON unified_library(unified_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_unified_date ON unified_library(date DESC)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_unified_play_count ON unified_library(play_count DESC)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_unified_last_played ON unified_library(last_played DESC)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_unified_title ON unified_library(title)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // 版本升级逻辑
    if (oldVersion < 2) {
      // 升级到版本 2：添加影片详情相关字段
      // 先删除旧表，重新创建（简单粗暴的方法，开发阶段可接受）
      await db.execute('DROP TABLE IF EXISTS movies');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS movies (
          id TEXT PRIMARY KEY,
          title TEXT,
          cover TEXT,
          date TEXT,
          publisher TEXT,
          producer TEXT,
          last_updated INTEGER,
          description TEXT,
          director TEXT,
          series TEXT,
          duration INTEGER,
          translation TEXT,
          gid TEXT,
          uc TEXT,
          actors_json TEXT,
          genres_json TEXT,
          samples_json TEXT,
          magnets_json TEXT
        )
      ''');
    }

    if (oldVersion < 3) {
      // 升级到版本 3：添加统一库表
      await db.execute('''
        CREATE TABLE IF NOT EXISTS unified_library (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          unified_id TEXT NOT NULL UNIQUE,
          title TEXT NOT NULL,
          cover_image TEXT,
          actors TEXT,
          date TEXT,
          duration INTEGER,
          description TEXT,
          sources_json TEXT NOT NULL,
          play_count INTEGER DEFAULT 0,
          last_played INTEGER DEFAULT 0,
          date_added INTEGER DEFAULT (strftime('%s', 'now')),
          created_at INTEGER DEFAULT (strftime('%s', 'now')),
          updated_at INTEGER DEFAULT (strftime('%s', 'now'))
        )
      ''');
      // 创建索引
      await db.execute('CREATE INDEX IF NOT EXISTS idx_unified_unified_id ON unified_library(unified_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_unified_date ON unified_library(date DESC)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_unified_play_count ON unified_library(play_count DESC)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_unified_last_played ON unified_library(last_played DESC)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_unified_title ON unified_library(title)');
    }
  }

  // 通用查询方法
  Future<List<Map<String, dynamic>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final db = await database;
    return await db.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  Future<int> insert(String table, Map<String, Object?> values) async {
    final db = await database;
    return await db.insert(table, values, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final db = await database;
    return await db.update(table, values, where: where, whereArgs: whereArgs);
  }

  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final db = await database;
    return await db.delete(table, where: where, whereArgs: whereArgs);
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }

  // 获取影片
  Future<Map<String, dynamic>?> getMovie(String id) async {
    final results = await query(
      'movies',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return results.first;
  }

  // 保存影片
  Future<void> saveMovie(Map<String, dynamic> movie) async {
    await insert('movies', movie);
  }
}

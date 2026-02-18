import 'dart:convert';

/// Jellyfin 库信息
class JellyfinLibrary {
  final String id;
  final String name;
  final String type; // movies, tvshows, etc.
  final int itemCount;

  JellyfinLibrary({
    required this.id,
    required this.name,
    required this.type,
    this.itemCount = 0,
  });

  factory JellyfinLibrary.fromJson(Map<String, dynamic> json) {
    return JellyfinLibrary(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? '',
      itemCount: json['itemCount'] as int? ?? json['childCount'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'itemCount': itemCount,
    };
  }
}

/// Jellyfin 电影项目
class JellyfinMovie {
  final int? id;           // 本地数据库 ID
  final String title;
  final String jellyfinId;  // 服务器 URL
  final String itemId;      // Jellyfin Item ID
  final String? videoId;    // 提取的视频番号
  final String libraryName;
  final String libraryId;
  final String? playUrl;
  final String? path;
  final String? coverImage;
  final List<String> actors;
  final String? date;
  final int? dateAdded;
  final int? lastPlayed;
  final int playCount;
  final String? overview;
  final int? runtimeSeconds;
  final String? runtimeText;
  final int? fileSizeBytes;
  final String? fileSizeText;
  final List<String> genres;
  final String? resolution;  // 视频分辨率，如 "1920x1080"

  JellyfinMovie({
    this.id,
    required this.title,
    required this.jellyfinId,
    required this.itemId,
    this.videoId,
    required this.libraryName,
    required this.libraryId,
    this.playUrl,
    this.path,
    this.coverImage,
    this.actors = const [],
    this.date,
    this.dateAdded,
    this.lastPlayed,
    this.playCount = 0,
    this.overview,
    this.runtimeSeconds,
    this.runtimeText,
    this.fileSizeBytes,
    this.fileSizeText,
    this.genres = const [],
    this.resolution,
  });

  factory JellyfinMovie.fromJson(Map<String, dynamic> json) {
    // 解析 actors
    List<String> actorsList = [];
    if (json['actors'] is String) {
      try {
        actorsList = (jsonDecode(json['actors']) as List<dynamic>)
            .map((e) => e.toString())
            .toList();
      } catch (_) {
        actorsList = [];
      }
    } else if (json['actors'] is List) {
      actorsList = (json['actors'] as List<dynamic>)
          .map((e) => e.toString())
          .toList();
    }

    // 解析 genres
    List<String> genresList = [];
    if (json['genres'] is List) {
      genresList = (json['genres'] as List<dynamic>)
          .map((e) => e.toString())
          .toList();
    }

    return JellyfinMovie(
      id: json['id'] as int?,
      title: json['title'] as String? ?? '',
      jellyfinId: json['jellyfin_id'] as String? ?? '',
      itemId: json['item_id'] as String? ?? '',
      videoId: json['video_id'] as String?,
      libraryName: json['library_name'] as String? ?? '',
      libraryId: json['library_id'] as String? ?? '',
      playUrl: json['play_url'] as String?,
      path: json['path'] as String?,
      coverImage: json['cover_image'] as String?,
      actors: actorsList,
      date: json['date'] as String?,
      dateAdded: json['date_added'] as int?,
      lastPlayed: json['last_played'] as int?,
      playCount: json['play_count'] as int? ?? 0,
      overview: json['overview'] as String?,
      runtimeSeconds: json['runtime_seconds'] as int?,
      runtimeText: json['runtime_text'] as String?,
      fileSizeBytes: json['file_size_bytes'] as int?,
      fileSizeText: json['file_size_text'] as String?,
      genres: genresList,
      resolution: json['resolution'] as String?,
    );
  }

  /// 从数据库 Map 创建
  factory JellyfinMovie.fromDbMap(Map<String, dynamic> map) {
    // 解析 actors JSON 字符串
    List<String> actorsList = [];
    final actorsJson = map['actors'] as String?;
    if (actorsJson != null && actorsJson.isNotEmpty) {
      try {
        actorsList = (jsonDecode(actorsJson) as List<dynamic>)
            .map((e) => e.toString())
            .toList();
      } catch (_) {}
    }

    // 解析 genres JSON 字符串
    List<String> genresList = [];
    final genresJson = map['genres'] as String?;
    if (genresJson != null && genresJson.isNotEmpty) {
      try {
        genresList = (jsonDecode(genresJson) as List<dynamic>)
            .map((e) => e.toString())
            .toList();
      } catch (_) {}
    }

    // 安全的整数转换函数
    int? safeInt(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is double) return value.toInt();
      if (value is String) return int.tryParse(value);
      return null;
    }

    return JellyfinMovie(
      id: safeInt(map['id']),
      title: map['title'] as String? ?? '',
      jellyfinId: map['jellyfin_id'] as String? ?? '',
      itemId: map['item_id'] as String? ?? '',
      videoId: map['video_id'] as String?,
      libraryName: map['library_name'] as String? ?? '',
      libraryId: map['library_id'] as String? ?? '',
      playUrl: map['play_url'] as String?,
      path: map['path'] as String?,
      coverImage: map['cover_image'] as String?,
      actors: actorsList,
      date: map['date'] as String?,
      dateAdded: safeInt(map['date_added']),
      lastPlayed: safeInt(map['last_played']),
      playCount: safeInt(map['play_count']) ?? 0,
      overview: map['overview'] as String?,
      runtimeSeconds: safeInt(map['runtime_seconds']),
      runtimeText: map['runtime_text'] as String?,
      fileSizeBytes: safeInt(map['file_size_bytes']),
      fileSizeText: map['file_size_text'] as String?,
      genres: genresList,
      resolution: map['resolution'] as String?,
    );
  }

  /// 转换为数据库 Map
  Map<String, dynamic> toDbMap() {
    return {
      if (id != null) 'id': id,
      'title': title,
      'jellyfin_id': jellyfinId,
      'item_id': itemId,
      if (videoId != null) 'video_id': videoId,
      'library_name': libraryName,
      'library_id': libraryId,
      if (playUrl != null) 'play_url': playUrl,
      if (path != null) 'path': path,
      if (coverImage != null) 'cover_image': coverImage,
      if (actors.isNotEmpty) 'actors': jsonEncode(actors),
      if (date != null) 'date': date,
      'date_added': dateAdded,
      if (lastPlayed != null) 'last_played': lastPlayed,
      'play_count': playCount,
      if (overview != null) 'overview': overview,
      if (runtimeSeconds != null) 'runtime_seconds': runtimeSeconds,
      if (runtimeText != null) 'runtime_text': runtimeText,
      if (fileSizeBytes != null) 'file_size_bytes': fileSizeBytes,
      if (fileSizeText != null) 'file_size_text': fileSizeText,
      if (genres.isNotEmpty) 'genres': jsonEncode(genres),
      if (resolution != null) 'resolution': resolution,
    };
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'title': title,
      'jellyfinId': jellyfinId,
      'itemId': itemId,
      if (videoId != null) 'videoId': videoId,
      'libraryName': libraryName,
      'libraryId': libraryId,
      if (playUrl != null) 'playUrl': playUrl,
      if (path != null) 'path': path,
      if (coverImage != null) 'coverImage': coverImage,
      'actors': actors,
      if (date != null) 'date': date,
      if (dateAdded != null) 'dateAdded': dateAdded,
      if (lastPlayed != null) 'lastPlayed': lastPlayed,
      'playCount': playCount,
      if (overview != null) 'overview': overview,
      if (runtimeSeconds != null) 'runtimeSeconds': runtimeSeconds,
      if (runtimeText != null) 'runtimeText': runtimeText,
      if (fileSizeBytes != null) 'fileSizeBytes': fileSizeBytes,
      if (fileSizeText != null) 'fileSizeText': fileSizeText,
      'genres': genres,
      if (resolution != null) 'resolution': resolution,
    };
  }

  JellyfinMovie copyWith({
    int? id,
    String? title,
    String? jellyfinId,
    String? itemId,
    String? videoId,
    String? libraryName,
    String? libraryId,
    String? playUrl,
    String? path,
    String? coverImage,
    List<String>? actors,
    String? date,
    int? dateAdded,
    int? lastPlayed,
    int? playCount,
    String? overview,
    int? runtimeSeconds,
    String? runtimeText,
    int? fileSizeBytes,
    String? fileSizeText,
    List<String>? genres,
    String? resolution,
  }) {
    return JellyfinMovie(
      id: id ?? this.id,
      title: title ?? this.title,
      jellyfinId: jellyfinId ?? this.jellyfinId,
      itemId: itemId ?? this.itemId,
      videoId: videoId ?? this.videoId,
      libraryName: libraryName ?? this.libraryName,
      libraryId: libraryId ?? this.libraryId,
      playUrl: playUrl ?? this.playUrl,
      path: path ?? this.path,
      coverImage: coverImage ?? this.coverImage,
      actors: actors ?? this.actors,
      date: date ?? this.date,
      dateAdded: dateAdded ?? this.dateAdded,
      lastPlayed: lastPlayed ?? this.lastPlayed,
      playCount: playCount ?? this.playCount,
      overview: overview ?? this.overview,
      runtimeSeconds: runtimeSeconds ?? this.runtimeSeconds,
      runtimeText: runtimeText ?? this.runtimeText,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      fileSizeText: fileSizeText ?? this.fileSizeText,
      genres: genres ?? this.genres,
      resolution: resolution ?? this.resolution,
    );
  }
}

/// 已导入的库信息
class ImportedLibrary {
  final String id;
  final String name;
  final String server;
  final int itemCount;
  final int? lastUpdated;

  ImportedLibrary({
    required this.id,
    required this.name,
    required this.server,
    required this.itemCount,
    this.lastUpdated,
  });

  factory ImportedLibrary.fromJson(Map<String, dynamic> json) {
    return ImportedLibrary(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      server: json['server'] as String? ?? '',
      itemCount: json['itemCount'] as int? ?? 0,
      lastUpdated: json['lastUpdated'] as int?,
    );
  }

  factory ImportedLibrary.fromDbMap(Map<String, dynamic> map) {
    // 安全的整数转换函数
    int? safeInt(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is double) return value.toInt();
      if (value is String) return int.tryParse(value);
      return null;
    }

    return ImportedLibrary(
      id: map['library_id'] as String? ?? '',
      name: map['library_name'] as String? ?? '',
      server: map['jellyfin_id'] as String? ?? '',
      itemCount: safeInt(map['item_count']) ?? 0,
      lastUpdated: safeInt(map['last_updated']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'server': server,
      'itemCount': itemCount,
      if (lastUpdated != null) 'lastUpdated': lastUpdated,
    };
  }
}

/// 库同步状态
class LibrarySyncState {
  final String libraryId;
  final String? lastSyncDateCreated;
  final String? lastSyncDateLastSaved;
  final int? lastSyncTs;

  LibrarySyncState({
    required this.libraryId,
    this.lastSyncDateCreated,
    this.lastSyncDateLastSaved,
    this.lastSyncTs,
  });

  factory LibrarySyncState.fromJson(Map<String, dynamic> json) {
    return LibrarySyncState(
      libraryId: json['library_id'] as String? ?? json['libraryId'] as String? ?? '',
      lastSyncDateCreated: json['last_sync_date_created'] as String? ?? json['lastSyncDateCreated'] as String?,
      lastSyncDateLastSaved: json['last_sync_date_last_saved'] as String? ?? json['lastSyncDateLastSaved'] as String?,
      lastSyncTs: json['last_sync_ts'] as int? ?? json['lastSyncTs'] as int?,
    );
  }

  factory LibrarySyncState.fromDbMap(Map<String, dynamic> map) {
    // 安全的整数转换函数
    int? safeInt(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is double) return value.toInt();
      if (value is String) return int.tryParse(value);
      return null;
    }

    return LibrarySyncState(
      libraryId: map['library_id'] as String? ?? '',
      lastSyncDateCreated: map['last_sync_date_created'] as String?,
      lastSyncDateLastSaved: map['last_sync_date_last_saved'] as String?,
      lastSyncTs: safeInt(map['last_sync_ts']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'libraryId': libraryId,
      if (lastSyncDateCreated != null) 'lastSyncDateCreated': lastSyncDateCreated,
      if (lastSyncDateLastSaved != null) 'lastSyncDateLastSaved': lastSyncDateLastSaved,
      if (lastSyncTs != null) 'lastSyncTs': lastSyncTs,
    };
  }
}

/// 导入结果
class ImportResult {
  final int imported;
  final int failed;
  final Map<String, dynamic> details;
  final String? message;
  final bool needsFullImport;

  ImportResult({
    this.imported = 0,
    this.failed = 0,
    this.details = const {},
    this.message,
    this.needsFullImport = false,
  });

  factory ImportResult.fromJson(Map<String, dynamic> json) {
    return ImportResult(
      imported: json['imported'] as int? ?? 0,
      failed: json['failed'] as int? ?? 0,
      details: json['details'] as Map<String, dynamic>? ?? {},
      message: json['message'] as String?,
      needsFullImport: json['needs_full_import'] as bool? ?? json['needsFullImport'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'imported': imported,
      'failed': failed,
      if (details.isNotEmpty) 'details': details,
      if (message != null) 'message': message,
      if (needsFullImport) 'needs_full_import': needsFullImport,
    };
  }
}

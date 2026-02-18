import 'dart:convert';
import 'package:crypto/crypto.dart';

/// 媒体来源枚举
enum MediaSource {
  cloud115,
  jellyfin,
  strm,
}

/// 媒体来源信息
class MediaSourceInfo {
  final MediaSource source;
  final String? fileId;      // 115: file_id
  final String? pickcode;    // 115: pickcode
  final String? itemId;      // Jellyfin: item_id
  final String? filepath;    // 原始文件名
  final String? size;        // 文件大小
  final String? libraryId;   // Jellyfin: library_id
  final String? libraryName; // Jellyfin: library_name
  final String? url;         // STRM: url

  MediaSourceInfo({
    required this.source,
    this.fileId,
    this.pickcode,
    this.itemId,
    this.filepath,
    this.size,
    this.libraryId,
    this.libraryName,
    this.url,
  });

  Map<String, dynamic> toJson() {
    return {
      'source': source.name,
      'fileId': fileId,
      'pickcode': pickcode,
      'itemId': itemId,
      'filepath': filepath,
      'size': size,
      'libraryId': libraryId,
      'libraryName': libraryName,
      'url': url,
    };
  }

  factory MediaSourceInfo.fromJson(Map<String, dynamic> json) {
    return MediaSourceInfo(
      source: MediaSource.values.firstWhere(
        (e) => e.name == json['source'],
        orElse: () => MediaSource.cloud115,
      ),
      fileId: json['fileId'],
      pickcode: json['pickcode'],
      itemId: json['itemId'],
      filepath: json['filepath'],
      size: json['size'],
      libraryId: json['libraryId'],
      libraryName: json['libraryName'],
      url: json['url'],
    );
  }

  /// 是否来自 115
  bool get isCloud115 => source == MediaSource.cloud115;

  /// 是否来自 Jellyfin
  bool get isJellyfin => source == MediaSource.jellyfin;

  /// 是否来自 STRM
  bool get isStrm => source == MediaSource.strm;
}

/// 统一库项目 - 整合所有来源的影片
class UnifiedLibraryItem {
  final int? id;
  final String unifiedId;        // 统一ID (videoId 或 local_xxx)
  final String title;
  final String? coverImage;
  final String? actors;          // 演员 JSON 字符串
  final String? date;            // 发行日期
  final int? duration;           // 时长（分钟）
  final String? description;
  final List<MediaSourceInfo> sources;  // 所有来源
  final int playCount;
  final int lastPlayed;
  final int dateAdded;
  final int createdAt;
  final int updatedAt;

  UnifiedLibraryItem({
    this.id,
    required this.unifiedId,
    required this.title,
    this.coverImage,
    this.actors,
    this.date,
    this.duration,
    this.description,
    required this.sources,
    this.playCount = 0,
    this.lastPlayed = 0,
    this.dateAdded = 0,
    this.createdAt = 0,
    this.updatedAt = 0,
  });

  /// 从数据库行创建
  factory UnifiedLibraryItem.fromMap(Map<String, dynamic> map) {
    List<MediaSourceInfo> parseSources(String sourcesJson) {
      try {
        final List<dynamic> json = jsonDecode(sourcesJson);
        return json.map((e) => MediaSourceInfo.fromJson(Map<String, dynamic>.from(e))).toList();
      } catch (_) {
        return [];
      }
    }

    return UnifiedLibraryItem(
      id: map['id'] as int?,
      unifiedId: map['unified_id'] as String,
      title: map['title'] as String,
      coverImage: map['cover_image'] as String?,
      actors: map['actors'] as String?,
      date: map['date'] as String?,
      duration: map['duration'] as int?,
      description: map['description'] as String?,
      sources: parseSources(map['sources_json'] as String? ?? '[]'),
      playCount: map['play_count'] as int? ?? 0,
      lastPlayed: map['last_played'] as int? ?? 0,
      dateAdded: map['date_added'] as int? ?? 0,
      createdAt: map['created_at'] as int? ?? 0,
      updatedAt: map['updated_at'] as int? ?? 0,
    );
  }

  /// 转换为数据库行
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'unified_id': unifiedId,
      'title': title,
      'cover_image': coverImage,
      'actors': actors,
      'date': date,
      'duration': duration,
      'description': description,
      'sources_json': jsonEncode(sources.map((e) => e.toJson()).toList()),
      'play_count': playCount,
      'last_played': lastPlayed,
      'date_added': dateAdded,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  /// 获取番号（如果有）
  String? get videoId {
    if (unifiedId.startsWith('local_')) return null;
    return unifiedId;
  }

  /// 是否有番号
  bool get hasVideoId => !unifiedId.startsWith('local_');

  /// 获取 115 来源
  List<MediaSourceInfo> get cloud115Sources =>
      sources.where((s) => s.isCloud115).toList();

  /// 获取 Jellyfin 来源
  List<MediaSourceInfo> get jellyfinSources =>
      sources.where((s) => s.isJellyfin).toList();

  /// 获取 STRM 来源
  List<MediaSourceInfo> get strmSources =>
      sources.where((s) => s.isStrm).toList();

  /// 是否有 115 来源
  bool get hasCloud115 => cloud115Sources.isNotEmpty;

  /// 是否有 Jellyfin 来源
  bool get hasJellyfin => jellyfinSources.isNotEmpty;

  /// 是否有 STRM 来源
  bool get hasStrm => strmSources.isNotEmpty;

  /// 来源显示名称
  String get sourceDisplayName {
    final parts = <String>[];
    if (hasCloud115) parts.add('115');
    if (hasJellyfin) parts.add('Jellyfin');
    if (hasStrm) parts.add('STRM');
    return parts.join(', ');
  }

  /// 来源颜色
  int get sourceColor {
    if (hasCloud115 && hasJellyfin) return 0xFF9C27B0; // 紫色
    if (hasCloud115) return 0xFFFF9800; // 橙色
    if (hasJellyfin) return 0xFF2196F3; // 蓝色
    return 0xFF9E9E9E; // 灰色
  }

  /// 生成统一ID
  static String generateUnifiedId(String? videoId, String filepath) {
    if (videoId != null && videoId.isNotEmpty) {
      return videoId;
    }
    // 无番号时，使用文件路径哈希
    final digest = md5.convert(const Utf8Encoder().convert(filepath));
    final hash = digest.toString().substring(0, 12);
    return 'local_$hash';
  }

  /// 选择最佳标题
  static String selectBestTitle({
    required String? javbusTitle,
    required String? jellyfinTitle,
    required String cloud115Title,
  }) {
    // 优先：JavBus 爬取的标题（通常是最准确的）
    if (javbusTitle != null && javbusTitle.isNotEmpty) {
      return javbusTitle;
    }
    // 次选：Jellyfin 标题
    if (jellyfinTitle != null && jellyfinTitle.isNotEmpty) {
      return jellyfinTitle;
    }
    // 兜底：115 文件名
    return cloud115Title;
  }
}

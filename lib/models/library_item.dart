/// 媒体库项目类型
enum LibraryType { strm, cloud115, jellyfin }

/// 媒体库项目
class LibraryItem {
  final int? id;
  final String title;
  final String filepath;
  final String url;
  final String? thumbnail;
  final String? description;
  final String? category;
  final int? dateAdded;
  final int? lastPlayed;
  final int? playCount;
  final String? videoId;
  final String? coverImage;
  final String? actors;
  final String? date;
  final LibraryType type;

  // 115 网盘特有字段
  final String? fileId;
  final String? pickcode;
  final String? size;

  LibraryItem({
    this.id,
    required this.title,
    required this.filepath,
    required this.url,
    this.thumbnail,
    this.description,
    this.category,
    this.dateAdded,
    this.lastPlayed,
    this.playCount,
    this.videoId,
    this.coverImage,
    this.actors,
    this.date,
    required this.type,
    this.fileId,
    this.pickcode,
    this.size,
  });

  factory LibraryItem.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String? ?? 'cloud115';
    LibraryType type;
    switch (typeStr) {
      case 'strm':
        type = LibraryType.strm;
        break;
      case 'jellyfin':
        type = LibraryType.jellyfin;
        break;
      default:
        type = LibraryType.cloud115;
    }

    return LibraryItem(
      id: json['id'] as int?,
      title: json['title'] as String? ?? '',
      filepath: json['filepath'] as String? ?? '',
      url: json['url'] as String? ?? '',
      thumbnail: json['thumbnail'] as String?,
      description: json['description'] as String?,
      category: json['category'] as String?,
      dateAdded: json['date_added'] as int?,
      lastPlayed: json['last_played'] as int?,
      playCount: json['play_count'] as int?,
      videoId: json['video_id'] as String?,
      coverImage: json['cover_image'] as String?,
      actors: json['actors'] as String?,
      date: json['date'] as String?,
      type: type,
      fileId: json['file_id'] as String?,
      pickcode: json['pickcode'] as String?,
      size: json['size'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'filepath': filepath,
      'url': url,
      'thumbnail': thumbnail,
      'description': description,
      'category': category,
      'date_added': dateAdded,
      'last_played': lastPlayed,
      'play_count': playCount,
      'video_id': videoId,
      'cover_image': coverImage,
      'actors': actors,
      'date': date,
      'type': type.name,
      'file_id': fileId,
      'pickcode': pickcode,
      'size': size,
    };
  }

  LibraryItem copyWith({
    int? id,
    String? title,
    String? filepath,
    String? url,
    String? thumbnail,
    String? description,
    String? category,
    int? dateAdded,
    int? lastPlayed,
    int? playCount,
    String? videoId,
    String? coverImage,
    String? actors,
    String? date,
    LibraryType? type,
    String? fileId,
    String? pickcode,
    String? size,
  }) {
    return LibraryItem(
      id: id ?? this.id,
      title: title ?? this.title,
      filepath: filepath ?? this.filepath,
      url: url ?? this.url,
      thumbnail: thumbnail ?? this.thumbnail,
      description: description ?? this.description,
      category: category ?? this.category,
      dateAdded: dateAdded ?? this.dateAdded,
      lastPlayed: lastPlayed ?? this.lastPlayed,
      playCount: playCount ?? this.playCount,
      videoId: videoId ?? this.videoId,
      coverImage: coverImage ?? this.coverImage,
      actors: actors ?? this.actors,
      date: date ?? this.date,
      type: type ?? this.type,
      fileId: fileId ?? this.fileId,
      pickcode: pickcode ?? this.pickcode,
      size: size ?? this.size,
    );
  }
}

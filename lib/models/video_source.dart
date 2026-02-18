/// 视频源类型
enum VideoSourceType {
  strm,
  cloud115,
  jellyfin,
  url,
}

/// 视频源数据模型
class VideoSource {
  final String id;
  final VideoSourceType type;
  final String title;
  final String url;
  final String? thumbnail;
  final String? duration;
  final String? size;
  final int? dateAdded;
  final String? videoId;
  final Map<String, dynamic>? extra;

  VideoSource({
    required this.id,
    required this.type,
    required this.title,
    required this.url,
    this.thumbnail,
    this.duration,
    this.size,
    this.dateAdded,
    this.videoId,
    this.extra,
  });

  factory VideoSource.fromJson(Map<String, dynamic> json) {
    return VideoSource(
      id: json['id'] as String,
      type: VideoSourceType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => VideoSourceType.url,
      ),
      title: json['title'] as String,
      url: json['url'] as String,
      thumbnail: json['thumbnail'] as String?,
      duration: json['duration'] as String?,
      size: json['size'] as String?,
      dateAdded: json['date_added'] as int?,
      videoId: json['video_id'] as String?,
      extra: json['extra'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'title': title,
      'url': url,
      'thumbnail': thumbnail,
      'duration': duration,
      'size': size,
      'date_added': dateAdded,
      'video_id': videoId,
      'extra': extra,
    };
  }

  VideoSource copyWith({
    String? id,
    VideoSourceType? type,
    String? title,
    String? url,
    String? thumbnail,
    String? duration,
    String? size,
    int? dateAdded,
    String? videoId,
    Map<String, dynamic>? extra,
  }) {
    return VideoSource(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      url: url ?? this.url,
      thumbnail: thumbnail ?? this.thumbnail,
      duration: duration ?? this.duration,
      size: size ?? this.size,
      dateAdded: dateAdded ?? this.dateAdded,
      videoId: videoId ?? this.videoId,
      extra: extra ?? this.extra,
    );
  }
}

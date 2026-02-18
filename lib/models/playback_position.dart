/// 播放位置模型
class PlaybackPosition {
  final String fileId;
  final String fileType; // '115', 'strm', 'jellyfin'
  final double position; // 播放位置（秒）
  final double duration; // 总时长（秒）
  final int lastPlayedAt; // 最后播放时间
  final int updatedAt;
  final String? title;
  final String? fileSize;

  PlaybackPosition({
    required this.fileId,
    required this.fileType,
    required this.position,
    required this.duration,
    required this.lastPlayedAt,
    required this.updatedAt,
    this.title,
    this.fileSize,
  });

  factory PlaybackPosition.fromJson(Map<String, dynamic> json) {
    return PlaybackPosition(
      fileId: json['file_id'] as String? ?? '',
      fileType: json['file_type'] as String? ?? '115',
      position: (json['position'] as num?)?.toDouble() ?? 0.0,
      duration: (json['duration'] as num?)?.toDouble() ?? 0.0,
      lastPlayedAt: json['last_played_at'] as int? ??
          DateTime.now().millisecondsSinceEpoch ~/ 1000,
      updatedAt: json['updated_at'] as int? ??
          DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: json['title'] as String?,
      fileSize: json['file_size'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'file_id': fileId,
      'file_type': fileType,
      'position': position,
      'duration': duration,
      'last_played_at': lastPlayedAt,
      'updated_at': updatedAt,
      'title': title,
      'file_size': fileSize,
    };
  }

  // 计算播放进度百分比
  double get progressPercent {
    if (duration <= 0) return 0.0;
    return (position / duration * 100).clamp(0.0, 100.0);
  }

  // 是否已播放完成（超过90%）
  bool get isCompleted => progressPercent >= 90.0;
}

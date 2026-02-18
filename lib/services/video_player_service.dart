import 'package:video_player/video_player.dart';

/// 视频播放服务 - 管理视频播放器
class VideoPlayerService {
  VideoPlayerController? _controller;
  String? _currentUrl;

  VideoPlayerController? get controller => _controller;
  bool get isInitialized => _controller?.value.isInitialized ?? false;
  String? get currentUrl => _currentUrl;

  /// 加载视频
  Future<void> loadVideo(String url) async {
    if (_currentUrl == url && isInitialized) {
      return; // 已经加载了相同的视频
    }

    await dispose();

    _currentUrl = url;
    _controller = VideoPlayerController.networkUrl(Uri.parse(url));
    await _controller!.initialize();
  }

  /// 播放
  void play() {
    _controller?.play();
  }

  /// 暂停
  void pause() {
    _controller?.pause();
  }

  /// 跳转到指定位置
  void seekTo(Duration position) {
    _controller?.seekTo(position);
  }

  /// 设置播放速度
  void setPlaybackSpeed(double speed) {
    _controller?.setPlaybackSpeed(speed);
  }

  /// 获取当前播放位置
  Duration get position => _controller?.value.position ?? Duration.zero;

  /// 获取视频总时长
  Duration get duration => _controller?.value.duration ?? Duration.zero;

  /// 是否正在播放
  bool get isPlaying => _controller?.value.isPlaying ?? false;

  /// 释放资源
  Future<void> dispose() async {
    await _controller?.dispose();
    _controller = null;
    _currentUrl = null;
  }

  /// 保存播放位置
  Map<String, dynamic> getPlaybackPosition(String fileId) {
    return {
      'file_id': fileId,
      'file_type': 'network',
      'position': position.inSeconds.toDouble(),
      'duration': duration.inSeconds.toDouble(),
      'last_played_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    };
  }

  /// 恢复播放位置
  Future<void> restorePlaybackPosition(String url, double positionInSeconds) async {
    await loadVideo(url);
    seekTo(Duration(seconds: positionInSeconds.toInt()));
  }
}

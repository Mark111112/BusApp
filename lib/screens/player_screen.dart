import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
// 使用 ExoPlayer (video_player) 而不是 libmpv (media_kit)
// 如果要切换回 media_kit，取消注释下面两行并注释 video_player 导入
import 'package:video_player/video_player.dart';
// import 'package:media_kit/media_kit.dart';
// import 'package:media_kit_video/media_kit_video.dart';
import '../providers/providers.dart';
import '../services/cloud115_transcode_service.dart';

/// 播放器页面
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  // video_player (ExoPlayer)
  VideoPlayerController? _controller;
  bool _hasInitialized = false;
  String _title = '播放';
  bool _showControls = true;

  // 转码相关
  bool _isTranscoded = false;  // 是否已尝试转码
  bool _isTranscoding = false;  // 是否正在使用转码流
  String? _itemId;             // Jellyfin 项目ID
  String? _originalUrl;        // 原始播放 URL
  String? _transcodedUrl;      // 转码播放 URL

  // 115 转码相关
  String? _pickcode;           // 115 文件 pickcode
  String? _fileId;             // 115 文件 ID
  Map<String, dynamic>? _downloadData;  // 115 直链信息
  String? _transcodeTaskId;    // 转码任务 ID
  bool _is115Transcoding = false;  // 是否正在使用 115 转码流
  Duration? _videoTotalDuration;  // 视频总时长（用于转码流进度条）
  double _currentStartTime = 0.0;  // 当前 HLS 流的起始时间（秒），对应后端返回的 start_time
  final Cloud115TranscodeService _transcodeService = Cloud115TranscodeService();

  // VOD 模式说明：
  // 后端使用 VOD 模式转码，分片会保留。当用户 seek 时：
  // - 如果目标分片已存在 → needsReload=false，直接本地 seek（秒开）
  // - 如果目标分片不存在 → needsReload=true，需要重新加载播放器
  //
  // 显示时间计算：显示时间 = player.position + _currentStartTime
  // 例如：start_time=300s，player.position=100s → 显示 400s

  // 控制层自动隐藏定时器
  Timer? _hideTimer;

  // 进度条拖动状态
  bool _isDragging = false;
  double _dragValue = 0.0;

  // 全屏状态
  bool _isFullscreen = false;

  // media_kit (libmpv) - 如需切换回 libmpv，取消注释以下内容
  // late final Player _player;
  // late final VideoController _videoController;

  @override
  void initState() {
    super.initState();
    // 默认竖屏窗口模式
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // 恢复状态栏（窗口模式）
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // 启动自动隐藏计时器
    _startHideTimer();
    // 加载转码服务配置
    _transcodeService.loadConfig();
  }

  /// 切换全屏
  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
      if (_isFullscreen) {
        // 进入全屏：横屏 + 隐藏状态栏
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        // 退出全屏：允许任意方向 + 显示状态栏
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    });
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _controller != null && _controller!.value.isPlaying) {
        if (!_isDragging) {
          setState(() {
            _showControls = false;
          });
        }
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (_showControls) {
        _startHideTimer();
      }
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasInitialized) {
      _hasInitialized = true;

      final args = ModalRoute.of(context)?.settings.arguments;
      String? url;
      bool isLocal = false;

      // 支持两种参数格式：
      // 1. String (直接URL) - 向后兼容
      // 2. Map<String, dynamic> - 包含 url, title, isLocal, itemId
      //    - 115 转码: pickcode, fileId, downloadData
      if (args is String) {
        url = args;
      } else if (args is Map<String, dynamic>) {
        url = args['url']?.toString();
        _title = args['title']?.toString() ?? '播放';
        isLocal = args['isLocal'] == true;
        _itemId = args['itemId']?.toString();
        // 115 相关参数
        _pickcode = args['pickcode']?.toString();
        _fileId = args['fileId']?.toString();
        _downloadData = args['downloadData'] as Map<String, dynamic>?;
      }

      if (url != null && url.isNotEmpty) {
        // 保存原始 URL
        _originalUrl = url;

        print('[Player] 播放URL: $url');
        print('[Player] 是否本地: $isLocal');
        print('[Player] 使用播放器: ExoPlayer (video_player)');
        if (_itemId != null) {
          print('[Player] Jellyfin ItemId: $_itemId');
        }
        if (_pickcode != null) {
          print('[Player] 115 Pickcode: $_pickcode');
        }

        // video_player (ExoPlayer)
        _initializePlayer(url, isLocal: isLocal);
      }
    }
  }

  /// video_player 初始化
  /// [autoPlay] 初始化完成后是否自动播放（seek 后可能设为 false，由调用者控制播放时机）
  Future<void> _initializePlayer(String url, {bool isLocal = false, bool autoPlay = true}) async {
    print('[Player] _initializePlayer 开始: url=$url, isLocal=$isLocal, autoPlay=$autoPlay');
    try {
      // 释放旧控制器
      if (_controller != null) {
        print('[Player] 释放旧控制器...');
        // 先移除监听器，避免 dispose 期间触发回调
        _controller!.removeListener(_onControllerUpdate);
        await _controller!.dispose();
        _controller = null;
        print('[Player] 旧控制器已释放');
      }

      final parsedUrl = Uri.parse(url);
      print('[Player] 解析URL: scheme=${parsedUrl.scheme}, host=${parsedUrl.host}, path=${parsedUrl.path}');

      if (isLocal) {
        print('[Player] 使用本地文件模式');
        _controller = VideoPlayerController.file(File(url));
      } else {
        print('[Player] 使用网络模式，创建 VideoPlayerController.networkUrl...');
        _controller = VideoPlayerController.networkUrl(parsedUrl);
        print('[Player] VideoPlayerController 已创建');
      }

      print('[Player] 开始初始化播放器 (await initialize)...');
      await _controller!.initialize();
      print('[Player] 播放器初始化成功!');
      print('[Player] 视频时长: ${_controller!.value.duration}');
      print('[Player] 视频尺寸: ${_controller!.value.size}');
      print('[Player] 是否已初始化: ${_controller!.value.isInitialized}');

      // 监听播放状态（在 setState 和 play 之前添加，确保不会错过事件）
      _controller!.addListener(_onControllerUpdate);
      print('[Player] 已添加播放状态监听器');

      if (mounted) setState(() {});

      // 根据参数决定是否自动播放
      if (autoPlay) {
        _controller!.play();
        print('[Player] 开始播放');
      } else {
        print('[Player] 跳过自动播放，等待外部控制');
      }
    } catch (e) {
      print('[Player] ========== 播放器初始化失败 ==========');
      print('[Player] 错误类型: ${e.runtimeType}');
      print('[Player] 错误详情: $e');
      if (e is Exception) {
        print('[Player] 异常消息: ${e.toString()}');
      }
      print('[Player] 播放URL: $url');
      print('[Player] 是否本地: $isLocal');
      print('[Player] 当前转码状态: _is115Transcoding=$_is115Transcoding, _isTranscoding=$_isTranscoding');
      print('[Player] =======================================');
      // 如果是 Jellyfin 源且未尝试转码，尝试转码
      if (_itemId != null && !_isTranscoded) {
        print('[Player] 尝试使用 Jellyfin 转码播放...');
        await _tryTranscodePlayback();
      }
      // 如果是 115 文件且未尝试转码，尝试转码
      else if (_pickcode != null && !_is115Transcoding) {
        print('[Player] 尝试使用 115 转码播放...');
        await _try115TranscodePlayback();
      } else {
        _showErrorDialog('播放失败', '无法播放此视频，可能格式不支持。');
      }
    }
  }

  /// 尝试转码播放
  Future<void> _tryTranscodePlayback() async {
    if (_itemId == null) return;

    try {
      final jellyfinProvider = context.read<JellyfinProvider>();
      final transcodedUrl = jellyfinProvider.service.getTranscodedPlayUrl(_itemId!);

      if (transcodedUrl != null) {
        // 保存转码 URL 用于切换
        _transcodedUrl = transcodedUrl;

        print('[Player] ========== 转码调试信息 ==========');
        print('[Player] 转码质量: 720p (2.5Mbps)');
        print('[Player] 转码URL: $transcodedUrl');
        print('[Player] 初始化转码播放器...');

        _isTranscoded = true;
        _isTranscoding = true;
        setState(() {});

        // 重新初始化播放器（转码流始终是网络流）
        _controller = VideoPlayerController.networkUrl(Uri.parse(transcodedUrl));
        await _controller!.initialize();

        // 输出视频信息用于调试
        print('[Player] 转码播放器初始化完成');
        print('[Player] 视频时长: ${_controller!.value.duration}');
        print('[Player] 视频尺寸: ${_controller!.value.size}');
        print('[Player] ===================================');

        setState(() {});
        _controller!.play();
        _controller!.addListener(_onControllerUpdate);
      } else {
        print('[Player] 无法获取转码URL');
        _showErrorDialog('播放失败', '无法获取转码流。');
      }
    } catch (e) {
      print('[Player] 转码播放失败: $e');
      _showErrorDialog('播放失败', '转码播放失败：$e');
    }
  }

  /// 尝试 115 转码播放
  Future<void> _try115TranscodePlayback() async {
    if (_pickcode == null) return;

    try {
      // 重置 115 转码相关状态
      _transcodeTaskId = null;
      _is115Transcoding = false;
      _videoTotalDuration = null;
      _currentStartTime = 0.0;

      // 确保加载最新配置
      await _transcodeService.loadConfig();

      if (!_transcodeService.isConfigured) {
        _showErrorDialog('未配置后端', '请在设置中配置 Python 后端地址以使用转码功能。');
        return;
      }

      print('[Player] ========== 115 转码启动 ==========');
      print('[Player] Pickcode: $_pickcode');

      _showSnackBar('正在启动转码...', const Duration(seconds: 3));

      // 调用后端启动转码（不传 downloadData，让后端重新获取）
      var response = await _transcodeService.startTranscode(
        pickcode: _pickcode!,
        fileId: _fileId,
        fileName: _title,
        force: false,
      );

      // 如果后端认为无需转码，强制转码
      if (!response.success && response.message?.contains('无需转码') == true) {
        print('[Player] 强制转码...');
        response = await _transcodeService.startTranscode(
          pickcode: _pickcode!,
          fileId: _fileId,
          fileName: _title,
          force: true,
        );
      }

      if (!response.success || response.task == null) {
        print('[Player] 启动转码失败: ${response.message}');
        if (response.code == 'concurrency_limit') {
          _showErrorDialog('转码任务已满', '转码服务繁忙，请稍后重试或停止其他转码任务。');
        } else {
          _showErrorDialog('转码失败', response.message ?? '无法启动转码任务。');
        }
        return;
      }

      final task = response.task!;
      _transcodeTaskId = task.taskId;
      print('[Player] 任务ID: ${task.taskId}, 状态: ${task.status}');

      // 等待任务就绪并播放
      await _waitForAndPlayTranscode(task);
    } on Cloud115TranscodeException catch (e) {
      print('[Player] 115 转码失败: $e');
      _showTranscodeErrorDialog(e.toString());
    } catch (e) {
      print('[Player] 115 转码播放失败: $e');
      _showErrorDialog('播放失败', '转码播放失败：$e');
    }
  }

  /// 等待转码任务就绪并播放
  Future<void> _waitForAndPlayTranscode(TranscodeTask task, {bool autoPlay = true}) async {
    if (!mounted) {
      print('[Player] Widget 已 dispose，取消等待转码');
      return;
    }

    if (task.ready) {
      print('[Player] 任务已就绪，直接加载流');
      await _loadTranscodeStream(task, autoPlay: autoPlay);
      return;
    }

    _showSnackBar('转码中，请稍候...', const Duration(seconds: 120));

    print('[Player] 等待任务就绪...');
    TranscodeTask? readyTask;
    try {
      readyTask = await _transcodeService.waitForReady(
        task.taskId,
        timeout: 120,
        onProgress: (status) {
          if (mounted) {
            print('[Player] 转码进度: $status');
          }
        },
      );
    } catch (e) {
      print('[Player] 等待转码任务异常: $e');
      if (mounted) ScaffoldMessenger.of(context).clearSnackBars();
      rethrow;
    }

    if (!mounted) {
      print('[Player] Widget 已 dispose，取消加载转码流');
      return;
    }

    ScaffoldMessenger.of(context).clearSnackBars();

    if (readyTask != null) {
      await _loadTranscodeStream(readyTask, autoPlay: autoPlay);
    } else {
      throw Cloud115TranscodeException('等待转码超时');
    }
  }

  /// 显示转码错误对话框（带重试选项）
  void _showTranscodeErrorDialog(String error) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('转码失败'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(error),
            const SizedBox(height: 12),
            const Text(
              '可能的原因：\n'
              '• 115 直链已过期\n'
              '• 视频文件格式问题\n'
              '• 后端转码服务异常\n\n'
              '请检查 Python 后端日志获取详细信息',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('返回'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // 重试转码
              _try115TranscodePlayback();
            },
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  /// 加载 115 转码流
  /// [task] 转码任务（必须已就绪）
  /// [autoPlay] 是否自动开始播放（默认 true，seek 后可能设为 false）
  Future<void> _loadTranscodeStream(TranscodeTask task, {bool autoPlay = true}) async {
    // 构建转码流 URL
    String streamUrl = task.absStreamUrl ?? task.streamUrl;
    if (streamUrl.startsWith('/')) {
      final backendUrl = _transcodeService.backendUrl;
      if (backendUrl != null) {
        streamUrl = '$backendUrl$streamUrl';
      }
    }
    if (!streamUrl.endsWith('.m3u8')) {
      streamUrl = '$streamUrl.m3u8';
    }

    print('[Player] ========== 加载转码流 ==========');
    print('[Player] URL: $streamUrl');
    print('[Player] 任务ID: ${task.taskId}');
    print('[Player] 时长: ${task.duration}s');
    print('[Player] start_time: ${task.startTime}s');
    print('[Player] autoPlay: $autoPlay');
    print('[Player] ===================================');

    // 保存视频总时长
    if (task.duration != null) {
      _videoTotalDuration = Duration(milliseconds: (task.duration! * 1000).round());
    }

    // 更新当前 HLS 流的起始时间
    // 如果后端返回了 startTime（V2 API），使用它；否则使用 task.startOffset
    _currentStartTime = task.startTime ?? task.startOffset;
    print('[Player] _currentStartTime 设为: $_currentStartTime');

    // 标记为转码模式
    _is115Transcoding = true;
    if (mounted) setState(() {});

    // 初始化播放器
    await _initializePlayer(streamUrl, isLocal: false, autoPlay: autoPlay);

    print('[Player] ========== 转码流加载完成 ==========');
  }

  /// 获取转码流的当前显示时间（秒）
  /// 显示时间 = player.position + _currentStartTime
  double _getTranscodeDisplayTime() {
    if (_controller == null || !_controller!.value.isInitialized) {
      return _currentStartTime;
    }
    return _controller!.value.position.inMilliseconds / 1000.0 + _currentStartTime;
  }

  /// 显示错误对话框
  void _showErrorDialog(String title, String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('确定'),
          ),
        ],
      ),
    ).then((_) {
      // 对话框关闭后返回上一页
      if (mounted) Navigator.pop(context);
    });
  }

  /// 切换转码播放（手动切换按钮）
  /// 支持 Jellyfin 和 115 两种转码
  Future<void> _toggleTranscode() async {
    try {
      // Jellyfin 转码切换
      if (_itemId != null) {
        if (_isTranscoding) {
          // 当前是转码模式，切换回原始播放
          if (_originalUrl != null) {
            print('[Player] 切换回原始播放 (Jellyfin)');
            _isTranscoding = false;
            setState(() {});
            await _initializePlayer(_originalUrl!, isLocal: false);
          }
        } else {
          // 当前是原始播放，切换到转码模式
          if (_transcodedUrl == null) {
            final jellyfinProvider = context.read<JellyfinProvider>();
            _transcodedUrl = jellyfinProvider.service.getTranscodedPlayUrl(_itemId!);
          }

          if (_transcodedUrl != null) {
            print('[Player] 切换到转码播放 (Jellyfin)');
            _isTranscoding = true;
            setState(() {});
            await _initializePlayer(_transcodedUrl!, isLocal: false);
          }
        }
        return;
      }

      // 115 转码切换
      if (_pickcode != null) {
        if (_is115Transcoding) {
          // 当前是转码模式，切换回原始播放
          if (_originalUrl != null) {
            print('[Player] 切换回原始播放 (115)');
            _is115Transcoding = false;
            setState(() {});
            await _initializePlayer(_originalUrl!, isLocal: false);
          }
        } else {
          // 切换到转码模式
          print('[Player] 切换到转码播放 (115)');
          await _try115TranscodePlayback();
        }
      }
    } catch (e) {
      print('[Player] 切换转码失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('切换失败: $e')),
        );
      }
    }
  }

  void _onControllerUpdate() {
    if (_controller == null) return;
    // 只有在非拖动状态下才更新UI，避免拖动时跳动
    if (!_isDragging) {
      setState(() {});
    }
    // 播放完成时重置到开头
    if (_controller!.value.position >= _controller!.value.duration) {
      setState(() {});
    }
  }

  void _playPause() {
    if (_controller == null) return;
    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
        print('[Player] 暂停');
      } else {
        _controller!.play();
        print('[Player] 播放');
        _startHideTimer();
      }
    });
  }

  /// 显示 SnackBar 提示
  void _showSnackBar(String message, Duration duration) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: duration),
      );
    }
  }

  /// 执行 115 转码流的跳转
  /// 参考 HTML 版本的 handleTranscodeSeekV2
  Future<void> _do115TranscodeSeek(double targetTimeSeconds) async {
    if (_transcodeTaskId == null) return;

    print('[Player] ========== 115 转码 Seek ==========');
    print('[Player] 目标时间: ${targetTimeSeconds}s');
    print('[Player] 当前 start_time: $_currentStartTime');

    _showSnackBar('正在跳转...', const Duration(seconds: 30));

    // 保存旧的 start_time，如果失败可以恢复
    final oldStartTime = _currentStartTime;

    try {
      final seekResult = await _transcodeService.seekTranscode(_transcodeTaskId!, targetTimeSeconds);

      if (mounted) ScaffoldMessenger.of(context).clearSnackBars();

      print('[Player] 后端返回: start_time=${seekResult.startTime}, needsReload=${seekResult.needsReload}');

      if (seekResult.needsReload && seekResult.task != null) {
        // 需要重新加载播放器（分片不存在，需要从新位置转码）
        print('[Player] 需要重新加载播放器');

        // 更新起始时间
        _currentStartTime = seekResult.startTime;
        print('[Player] 更新 _currentStartTime 为: $_currentStartTime');

        // 计算在新流中的本地位置
        final localPosition = targetTimeSeconds - _currentStartTime;
        print('[Player] 在新流中的目标本地位置: ${localPosition}s');

        // 等待转码并加载新流（不自动播放，由 _waitForPlayerReadyAndSeek 控制）
        await _waitForAndPlayTranscode(seekResult.task!, autoPlay: false);

        if (!mounted) {
          print('[Player] Widget 已 dispose，中止 seek');
          return;
        }

        ScaffoldMessenger.of(context).clearSnackBars();

        // 关键修复：等待播放器真正准备好后再 seek
        // HLS 流需要时间加载，ExoPlayer 需要时间解析 m3u8
        await _waitForPlayerReadyAndSeek(localPosition);
      } else {
        // 分片已存在，直接本地 seek（秒开）
        print('[Player] 分片已存在，直接本地 seek');

        // 计算在当前 HLS 流中的本地位置
        final localPosition = targetTimeSeconds - _currentStartTime;
        print('[Player] 本地位置: ${localPosition}s');

        if (_controller != null && _controller!.value.isInitialized) {
          await _controller!.seekTo(Duration(milliseconds: (localPosition * 1000).round()));
          // 确保播放
          _controller!.play();
        }
      }

      print('[Player] ========== Seek 完成 ==========');
    } catch (e) {
      print('[Player] 转码跳转失败: $e');
      // 恢复旧的 start_time
      _currentStartTime = oldStartTime;
      print('[Player] 恢复 _currentStartTime 为: $_currentStartTime');

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        _showSnackBar('跳转失败: $e', const Duration(seconds: 2));
      }
    }
  }

  /// 等待播放器准备好并执行 seek
  /// 解决 HLS 流重新加载后立即 seek 导致 404 的问题
  Future<void> _waitForPlayerReadyAndSeek(double localPositionSeconds) async {
    if (_controller == null || !_controller!.value.isInitialized) {
      print('[Player] 播放器未初始化，跳过 seek');
      return;
    }

    print('[Player] 等待播放器准备好...');

    // 等待播放器能够正常播放
    // 通过检查播放器的 duration 是否大于 0 来判断
    int retries = 0;
    const maxRetries = 30; // 最多等待 15 秒

    while (retries < maxRetries) {
      // 每次循环前检查 widget 是否还在
      if (!mounted) {
        print('[Player] Widget 已 dispose，停止等待');
        return;
      }

      await Future.delayed(const Duration(milliseconds: 500));

      // 检查控制器是否仍然有效
      if (_controller == null || !_controller!.value.isInitialized) {
        retries++;
        continue;
      }

      try {
        // 检查播放器是否准备好（duration > 0）
        final duration = _controller!.value.duration;
        if (duration.inMilliseconds > 0) {
          print('[Player] 播放器已准备好，duration: ${duration.inSeconds}s');

          // 再等待一小段时间确保 HLS 流已开始加载
          await Future.delayed(const Duration(milliseconds: 500));

          // 再次检查状态
          if (!mounted || _controller == null || !_controller!.value.isInitialized) {
            print('[Player] 状态已改变，取消 seek');
            return;
          }

          // 执行 seek
          final seekPosition = Duration(milliseconds: (localPositionSeconds * 1000).round());
          print('[Player] 执行 seek 到: ${seekPosition.inSeconds}s');

          await _controller!.seekTo(seekPosition);
          _controller!.play();
          print('[Player] Seek 完成，开始播放');
          return;
        }
      } catch (e) {
        print('[Player] 检查播放器状态时出错: $e');
        // 继续等待，不中断循环
      }

      retries++;
      print('[Player] 等待播放器... $retries/$maxRetries');
    }

    // 超时后的处理
    print('[Player] 播放器准备超时，尝试直接 seek');

    if (!mounted || _controller == null || !_controller!.value.isInitialized) {
      print('[Player] 状态已改变，取消 seek');
      return;
    }

    try {
      // 超时后直接 seek，让播放器自己处理
      final seekPosition = Duration(milliseconds: (localPositionSeconds * 1000).round());
      await _controller!.seekTo(seekPosition);
      _controller!.play();
      print('[Player] 超时 seek 完成');
    } catch (e) {
      print('[Player] 超时 seek 失败: $e');
      // 如果 seek 失败，至少尝试播放
      try {
        _controller!.play();
      } catch (_) {
        // 忽略播放错误
      }
    }
  }

  void _seekTo(double value) async {
    if (_controller == null) return;

    // 获取有效时长
    final effectiveDuration = _videoTotalDuration ?? _controller!.value.duration;
    if (effectiveDuration.inMilliseconds <= 0) return;

    // 计算目标时间（视频中的绝对时间）
    final position = Duration(milliseconds: (value * effectiveDuration.inMilliseconds).round());
    final targetTimeSeconds = position.inMilliseconds / 1000.0;
    print('[Player] Seek 到: ${_formatDuration(position)} (${value.toStringAsFixed(2)})');

    // 转码流需要特殊处理
    if (_is115Transcoding && _transcodeTaskId != null) {
      await _do115TranscodeSeek(targetTimeSeconds);
      return;
    }

    // 普通视频直接 seek
    _controller!.seekTo(position).then((_) {
      print('[Player] Seek 完成');
    }).catchError((e) {
      print('[Player] Seek 失败: $e');
    });
  }

  void _seekRelative(double offset) async {
    if (_controller == null) return;

    // 获取有效时长
    final effectiveDuration = _videoTotalDuration ?? _controller!.value.duration;
    if (effectiveDuration.inMilliseconds <= 0) return;

    // 计算当前显示时间和新位置
    double currentTimeSeconds;
    if (_is115Transcoding) {
      currentTimeSeconds = _getTranscodeDisplayTime();
    } else {
      currentTimeSeconds = _controller!.value.position.inMilliseconds / 1000.0;
    }

    final newTimeSeconds = currentTimeSeconds + offset;
    final clampedTime = newTimeSeconds.clamp(0.0, effectiveDuration.inMilliseconds / 1000.0);

    print('[Player] 相对 Seek: ${offset > 0 ? '+' : ''}${offset.toInt()}秒 → ${clampedTime.toInt()}s');

    // 转码流需要特殊处理
    if (_is115Transcoding && _transcodeTaskId != null) {
      await _do115TranscodeSeek(clampedTime);
      return;
    }

    // 普通视频直接 seek
    _controller!.seekTo(Duration(milliseconds: (clampedTime * 1000).round()));
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    // 停止 115 转码任务
    if (_transcodeTaskId != null && _pickcode != null) {
      print('[Player] 停止 115 转码任务: $_transcodeTaskId');
      _transcodeService.stopTranscode(_transcodeTaskId!, reason: '用户退出播放');
    }
    // 恢复默认方向和状态栏
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        // opaque 让透明区域也能响应点击
        behavior: HitTestBehavior.opaque,
        child: Stack(
          // 让 Stack 填满整个父容器
          fit: StackFit.expand,
          children: [
            // 视频播放器
            _buildVideoPlayer(),
            // 控制层
            if (_showControls) _buildControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPlayer() {
    if (_controller != null && _controller!.value.isInitialized) {
      // 使用 SizedBox.expand 让视频区域填满整个屏幕
      // 这样点击屏幕任何位置都能激活控件
      return SizedBox.expand(
        child: Center(
          child: AspectRatio(
            aspectRatio: _controller!.value.aspectRatio,
            child: VideoPlayer(_controller!),
          ),
        ),
      );
    }
    return const Center(
      child: CircularProgressIndicator(color: Colors.white),
    );
  }

  Widget _buildControls() {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // 顶部栏
        _buildTopBar(),
        // 底部控制栏
        _buildBottomBar(),
      ],
    );
  }

  Widget _buildTopBar() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.7),
            Colors.transparent,
          ],
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      _title,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // 转码状态指示器
                  if (_isTranscoding || _is115Transcoding) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.hd, color: Colors.white, size: 12),
                          const SizedBox(width: 2),
                          Text(
                            _isTranscoding ? 'JF转码' : '115转码',
                            style: const TextStyle(color: Colors.white, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // 转码切换按钮（Jellyfin 源或 115 源显示）
            if (_itemId != null || _pickcode != null)
              IconButton(
                icon: Icon(
                  (_isTranscoding || _is115Transcoding) ? Icons.hd : Icons.hd_outlined,
                  color: (_isTranscoding || _is115Transcoding) ? Colors.orange : Colors.white70,
                ),
                onPressed: _toggleTranscode,
                tooltip: (_isTranscoding || _is115Transcoding) ? '切换到原画' : '切换到转码',
              ),
            // 全屏切换按钮
            IconButton(
              icon: Icon(
                _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                color: Colors.white,
              ),
              onPressed: _toggleFullscreen,
              tooltip: _isFullscreen ? '退出全屏' : '全屏',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.8),
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 进度条
            _buildProgressBar(),
            const SizedBox(height: 8),
            // 控制按钮行
            _buildControlButtons(),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    // 对于转码流，显示时间 = player.position + _currentStartTime
    // 对于普通视频，显示时间 = player.position
    final Duration position;
    if (_is115Transcoding) {
      final displayTimeSeconds = _getTranscodeDisplayTime();
      position = Duration(milliseconds: (displayTimeSeconds * 1000).round());
    } else {
      position = _controller!.value.position;
    }

    // 对于转码流，使用后端返回的总时长；否则使用播放器的时长
    final effectiveDuration = _videoTotalDuration ?? _controller!.value.duration;

    // 计算进度值
    final double value = _isDragging
        ? _dragValue
        : effectiveDuration.inMilliseconds > 0
            ? position.inMilliseconds / effectiveDuration.inMilliseconds
            : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(
            _formatDuration(_isDragging
                ? Duration(milliseconds: (value * effectiveDuration.inMilliseconds).round())
                : position),
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                activeTrackColor: Colors.red,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
                overlayColor: Colors.white.withValues(alpha: 0.3),
              ),
              child: Slider(
                value: value.clamp(0.0, 1.0),
                onChanged: (newValue) {
                  print('[Player] 拖动进度条: ${newValue.toStringAsFixed(2)}');
                  setState(() {
                    _isDragging = true;
                    _dragValue = newValue;
                  });
                },
                onChangeEnd: (newValue) {
                  print('[Player] 松手，执行 seek');
                  setState(() {
                    _isDragging = false;
                  });
                  _seekTo(newValue);
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatDuration(effectiveDuration),
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButtons() {
    final isPlaying = _controller!.value.isPlaying;

    // 计算当前显示时间（秒）和总时长（秒），用于判断快进/快退按钮状态
    final currentTimeSeconds = _is115Transcoding
        ? _getTranscodeDisplayTime()
        : _controller!.value.position.inMilliseconds / 1000.0;
    final totalDurationSeconds = (_videoTotalDuration ?? _controller!.value.duration).inMilliseconds / 1000.0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // 快退10秒
        IconButton(
          icon: const Icon(Icons.replay_10, color: Colors.white, size: 32),
          onPressed: currentTimeSeconds >= 10 ? () => _seekRelative(-10) : null,
        ),
        // 播放/暂停
        IconButton(
          icon: Icon(
            isPlaying ? Icons.pause : Icons.play_arrow,
            color: Colors.white,
            size: 48,
          ),
          onPressed: _playPause,
        ),
        // 快进10秒
        IconButton(
          icon: const Icon(Icons.forward_10, color: Colors.white, size: 32),
          onPressed: currentTimeSeconds <= totalDurationSeconds - 10 ? () => _seekRelative(10) : null,
        ),
      ],
    );
  }
}

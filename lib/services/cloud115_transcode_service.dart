import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 配置 key 前缀（与 ConfigService 保持一致）
const String _configPrefix = 'bus115_';

/// 构建带前缀的配置 key
String _configKey(String key) => '$_configPrefix$key';

/// 115 转码任务状态
enum TranscodeStatus {
  queued,
  starting,
  running,
  ready,
  completed,
  error,
  cancelled,
}

/// 转码任务信息
class TranscodeTask {
  final String taskId;
  final TranscodeStatus status;
  final String? reason;
  final int createdAt;
  final int? readyAt;
  final String streamUrl;
  final String? absStreamUrl;
  final String statusUrl;
  final bool ready;
  final String? fileName;
  final double? duration;
  final double startOffset;  // 转码起始偏移（秒），用于 seek 后计算实际时间
  final double? startTime;   // V2: HLS流的起始时间（0表示从头开始的完整流）

  TranscodeTask({
    required this.taskId,
    required this.status,
    this.reason,
    required this.createdAt,
    this.readyAt,
    required this.streamUrl,
    this.absStreamUrl,
    required this.statusUrl,
    required this.ready,
    this.fileName,
    this.duration,
    this.startOffset = 0.0,
    this.startTime,  // V2 新增
  });

  /// 将 URL 从 http 转换为 https（无认证）
  static String _toHttps(String url) {
    if (url.startsWith('http://')) {
      return 'https://${url.substring(7)}';
    }
    return url;
  }

  /// 创建使用 HTTPS 的 TranscodeTask（后端 URL 已包含 token）
  factory TranscodeTask.withHttps(TranscodeTask original) {
    // 处理 absStreamUrl：如果为 null 但有 streamUrl，则使用 streamUrl
    final effectiveAbsUrl = original.absStreamUrl ?? original.streamUrl;
    return TranscodeTask(
      taskId: original.taskId,
      status: original.status,
      reason: original.reason,
      createdAt: original.createdAt,
      readyAt: original.readyAt,
      streamUrl: _toHttps(original.streamUrl),
      absStreamUrl: effectiveAbsUrl.isNotEmpty
          ? _toHttps(effectiveAbsUrl)
          : null,
      statusUrl: original.statusUrl,
      ready: original.ready,
      fileName: original.fileName,
      duration: original.duration,
      startOffset: original.startOffset,
      startTime: original.startTime,
    );
  }

  factory TranscodeTask.fromJson(Map<String, dynamic> json) {
    final createdAtValue = json['created_at'];
    int createdAtTimestamp;
    if (createdAtValue is int) {
      createdAtTimestamp = createdAtValue;
    } else {
      createdAtTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    }

    final statusStr = json['status'] as String?;
    final parsedStatus = _parseStatus(statusStr);
    final readyValue = json['ready'] as bool? ?? false;

    if (kDebugMode) {
      print('[Cloud115Transcode] fromJson: statusStr=$statusStr, parsedStatus=$parsedStatus, readyValue=$readyValue');
    }

    // 解析 ready_at - 后端返回的是 double（时间戳），需要转换为 int
    int? readyAtValue;
    final readyAtRaw = json['ready_at'];
    if (readyAtRaw != null) {
      if (readyAtRaw is int) {
        readyAtValue = readyAtRaw;
      } else if (readyAtRaw is double) {
        readyAtValue = readyAtRaw.toInt();
      } else if (readyAtRaw is String) {
        readyAtValue = int.tryParse(readyAtRaw);
      }
    }

    return TranscodeTask(
      taskId: json['task_id'] as String? ?? json['id'] as String? ?? '',
      status: parsedStatus,
      reason: json['reason'] as String?,
      createdAt: createdAtTimestamp,
      readyAt: readyAtValue,
      streamUrl: json['stream_url'] as String? ?? '',
      absStreamUrl: json['abs_stream_url'] as String?,
      statusUrl: json['status_url'] as String? ?? '',
      ready: readyValue,
      fileName: json['file_name'] as String?,
      duration: (json['duration'] as num?)?.toDouble(),
      startOffset: (json['start_offset'] as num?)?.toDouble() ?? 0.0,
      startTime: (json['start_time'] as num?)?.toDouble(),  // V2 新增
    );
  }

  static TranscodeStatus _parseStatus(String? status) {
    if (status == null) return TranscodeStatus.queued;
    return TranscodeStatus.values.firstWhere(
      (e) => e.name == status,
      orElse: () => TranscodeStatus.queued,
    );
  }

  bool get isActive => status == TranscodeStatus.queued ||
      status == TranscodeStatus.starting ||
      status == TranscodeStatus.running;
}

/// 启动转码响应
class StartTranscodeResponse {
  final bool success;
  final bool created;
  final TranscodeTask? task;
  final String? message;
  final String? code;
  final Map<String, dynamic>? meta;

  StartTranscodeResponse({
    required this.success,
    this.created = false,
    this.task,
    this.message,
    this.code,
    this.meta,
  });

  factory StartTranscodeResponse.fromJson(Map<String, dynamic> json) {
    TranscodeTask? task;
    if (json['task'] != null) {
      // 合并根级别的 ready/stream_url 字段到 task 对象
      final taskJson = Map<String, dynamic>.from(json['task'] as Map<String, dynamic>);
      if (json.containsKey('ready')) {
        taskJson['ready'] = json['ready'] as bool? ?? false;
      }
      if (json.containsKey('stream_url')) {
        taskJson['stream_url'] = json['stream_url'] as String? ?? '';
      }
      task = TranscodeTask.fromJson(taskJson);
    }

    return StartTranscodeResponse(
      success: json['success'] as bool? ?? false,
      created: json['created'] as bool? ?? false,
      task: task,
      message: json['message'] as String?,
      code: json['code'] as String?,
      meta: json['meta'] as Map<String, dynamic>?,
    );
  }

  /// 创建一个副本，可选择性地替换某些字段
  StartTranscodeResponse copyWith({
    bool? success,
    bool? created,
    TranscodeTask? task,
    String? message,
    String? code,
    Map<String, dynamic>? meta,
  }) {
    return StartTranscodeResponse(
      success: success ?? this.success,
      created: created ?? this.created,
      task: task ?? this.task,
      message: message ?? this.message,
      code: code ?? this.code,
      meta: meta ?? this.meta,
    );
  }
}

/// Seek 跳转响应（V2）
/// 用于处理单一任务模式下的 seek 操作
class SeekTranscodeResult {
  final bool success;
  final bool needsReload;       // 是否需要重新加载播放器
  final TranscodeTask? task;    // 新的任务信息（task_id 相同但状态可能不同）
  final double startTime;       // HLS流的起始时间
  final String? message;        // 后端返回的消息

  SeekTranscodeResult({
    required this.success,
    required this.needsReload,
    this.task,
    required this.startTime,
    this.message,
  });

  @override
  String toString() {
    return 'SeekTranscodeResult(success: $success, needsReload: $needsReload, startTime: $startTime, message: $message)';
  }
}

/// 115 转码服务异常
class Cloud115TranscodeException implements Exception {
  final String message;
  final int? statusCode;
  final String? code;

  Cloud115TranscodeException(this.message, {this.statusCode, this.code});

  @override
  String toString() => 'Cloud115TranscodeException: $message${statusCode != null ? " ($statusCode)" : ""}';
}

/// 115 转码服务
/// 连接到 Python 后端 (C:/Intel/QA/bus) 进行视频转码
class Cloud115TranscodeService {
  final Dio _dio;
  String? _backendUrl;
  String? _authUser;
  String? _authPass;

  Cloud115TranscodeService({Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
          headers: {
            'Content-Type': 'application/json',
          },
        ));

  /// 从 SharedPreferences 加载配置
  Future<void> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    _backendUrl = prefs.getString(_configKey('python_backend_url'));
    if (kDebugMode) {
      print('[Cloud115Transcode] 加载配置: url=$_backendUrl');
    }
    if (_backendUrl != null && _backendUrl!.isNotEmpty) {
      _dio.options.baseUrl = _backendUrl!;
    }
    // 加载 Basic Auth 认证信息
    _authUser = prefs.getString(_configKey('python_backend_user'));
    _authPass = prefs.getString(_configKey('python_backend_pass'));
    if (kDebugMode) {
      print('[Cloud115Transcode] 认证信息: user=$_authUser, hasPass=${_authPass != null && _authPass!.isNotEmpty}');
    }
    if (_authUser != null && _authPass != null && _authUser!.isNotEmpty && _authPass!.isNotEmpty) {
      _setBasicAuth(_authUser!, _authPass!);
    }
  }

  /// 设置 Basic Auth 认证
  void _setBasicAuth(String user, String pass) {
    final credentials = base64.encode(utf8.encode('$user:$pass'));
    _dio.options.headers['Authorization'] = 'Basic $credentials';
  }

  /// 清除 Basic Auth 认证
  void _clearBasicAuth() {
    _dio.options.headers.remove('Authorization');
  }

  /// 设置后端 URL
  void setBackendUrl(String url, {String? user, String? pass}) {
    _backendUrl = url.replaceAll(RegExp(r'/+$'), '');
    _dio.options.baseUrl = _backendUrl!;
    if (user != null && pass != null && user.isNotEmpty && pass.isNotEmpty) {
      _setBasicAuth(user, pass);
    }
  }

  /// 保存配置到 SharedPreferences
  Future<void> _saveConfig() async {
    final prefs = await SharedPreferences.getInstance();
    if (_backendUrl != null) {
      await prefs.setString(_configKey('python_backend_url'), _backendUrl!);
    }
  }

  /// 获取后端 URL
  String? get backendUrl => _backendUrl;

  /// 是否已配置
  bool get isConfigured => _backendUrl != null && _backendUrl!.isNotEmpty;

  /// 启动转码任务
  ///
  /// [pickcode] - 115 文件的 pickcode
  /// [fileId] - 115 文件的 ID (可选)
  /// [fileName] - 文件名 (可选，用于检测格式)
  /// [downloadData] - 直链信息 (可选，如果已获取)
  /// [force] - 是否强制转码（忽略格式检测）
  /// [useAndroidApi] - 是否使用 Android API
  Future<StartTranscodeResponse> startTranscode({
    required String pickcode,
    String? fileId,
    String? fileName,
    Map<String, dynamic>? downloadData,
    bool force = false,
    bool useAndroidApi = false,  // 改为 false，使用普通 web API
  }) async {
    if (!isConfigured) {
      throw Cloud115TranscodeException('未配置 Python 后端 URL');
    }

    try {
      final payload = {
        'pickcode': pickcode,
        if (fileId != null) 'file_id': fileId,
        if (fileName != null) 'file_name': fileName,
        if (downloadData != null) 'download_data': downloadData,
        'force': force,
        'android_api': useAndroidApi,
      };

      if (kDebugMode) {
        print('[Cloud115Transcode] 启动转码: $pickcode');
        print('[Cloud115Transcode] 完整请求URL: $_backendUrl/api/cloud115/transcode/start');
        print('[Cloud115Transcode] 请求payload: ${payload.keys.join(", ")}');
      }

      final response = await _dio.post(
        '/api/cloud115/transcode/start',
        data: payload,
      );

      var result = StartTranscodeResponse.fromJson(response.data);

      // 如果任务已创建，将 http 替换为 https（后端 URL 已包含 token）
      if (result.task != null) {
        final taskWithHttps = TranscodeTask.withHttps(result.task!);
        result = result.copyWith(task: taskWithHttps);
        if (kDebugMode) {
          print('[Cloud115Transcode] 转换为HTTPS (startTranscode)');
        }
      }

      if (kDebugMode) {
        print('[Cloud115Transcode] 响应: success=${result.success}, created=${result.created}');
        if (result.task != null) {
          print('[Cloud115Transcode] 任务ID: ${result.task!.taskId}, 状态: ${result.task!.status}');
        }
      }

      return result;
    } on DioException catch (e) {
      if (kDebugMode) {
        print('[Cloud115Transcode] 请求失败: ${e.message}');
        print('[Cloud115Transcode] 响应状态码: ${e.response?.statusCode}');
        print('[Cloud115Transcode] 响应数据: ${e.response?.data}');
      }

      // 处理并发限制 (429)
      if (e.response?.statusCode == 429) {
        final responseData = e.response?.data as Map<String, dynamic>? ?? {};
        return StartTranscodeResponse(
          success: false,
          message: responseData['message'] as String? ?? '转码任务并发限制',
          code: 'concurrency_limit',
        );
      }

      // 处理 400 错误（参数错误）
      if (e.response?.statusCode == 400) {
        final responseData = e.response?.data as Map<String, dynamic>? ?? {};
        final backendError = responseData['error'] as String? ?? responseData['message'] as String?;
        throw Cloud115TranscodeException(
          '启动转码失败: ${backendError ?? e.message}',
          statusCode: 400,
        );
      }

      throw Cloud115TranscodeException(
        '启动转码失败: ${e.message}',
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// 查询转码任务状态
  Future<TranscodeTask> getTaskStatus(String taskId) async {
    if (!isConfigured) {
      throw Cloud115TranscodeException('未配置 Python 后端 URL');
    }

    try {
      final response = await _dio.get('/api/cloud115/transcode/status/$taskId');
      if (kDebugMode) {
        print('[Cloud115Transcode] 任务状态响应: ${response.data}');
      }

      // 合并响应：task 对象 + 根级别的 ready/stream_url 等字段
      final taskJson = Map<String, dynamic>.from(response.data['task'] as Map<String, dynamic>);
      // 根级别的字段优先级更高（覆盖 task 内的字段）
      if (response.data.containsKey('ready')) {
        taskJson['ready'] = response.data['ready'] as bool? ?? false;
      }
      if (response.data.containsKey('stream_url')) {
        taskJson['stream_url'] = response.data['stream_url'] as String? ?? '';
      }

      final task = TranscodeTask.fromJson(taskJson);

      // 将 http 替换为 https（后端 URL 已包含 token）
      final taskWithHttps = TranscodeTask.withHttps(task);
      if (kDebugMode) {
        print('[Cloud115Transcode] 转换为HTTPS');
        print('[Cloud115Transcode] 原始URL: ${task.absStreamUrl}');
        print('[Cloud115Transcode] HTTPS URL: ${taskWithHttps.absStreamUrl}');
      }
      return taskWithHttps;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        throw Cloud115TranscodeException('任务不存在', statusCode: 404);
      }
      throw Cloud115TranscodeException(
        '查询任务状态失败: ${e.message}',
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// 停止转码任务
  Future<bool> stopTranscode(String taskId, {String reason = '客户端停止'}) async {
    if (!isConfigured) {
      throw Cloud115TranscodeException('未配置 Python 后端 URL');
    }

    try {
      if (kDebugMode) {
        print('[Cloud115Transcode] 停止转码: $taskId, 原因: $reason');
      }

      await _dio.post(
        '/api/cloud115/transcode/stop/$taskId',
        data: {'reason': reason},
      );
      return true;
    } on DioException catch (e) {
      // 即使失败也记录日志，不抛出异常（避免影响用户体验）
      if (kDebugMode) {
        print('[Cloud115Transcode] 停止转码失败: ${e.message}');
      }
      return false;
    }
  }

  /// 跳转转码任务到指定时间点
  ///
  /// [taskId] - 任务 ID
  /// [targetTime] - 目标时间点（秒）
  /// 返回 Seek 结果，包含是否需要重新加载、新的任务信息、HLS流起始时间
  Future<SeekTranscodeResult> seekTranscode(String taskId, double targetTime) async {
    if (!isConfigured) {
      throw Cloud115TranscodeException('未配置 Python 后端 URL');
    }

    try {
      if (kDebugMode) {
        print('[Cloud115Transcode] 跳转转码: $taskId, 时间: ${targetTime}s');
      }

      final response = await _dio.post(
        '/api/cloud115/transcode/seek/$taskId',
        data: {'time': targetTime},
      );

      final data = response.data as Map<String, dynamic>;
      if (data['success'] == true) {
        final startTime = (data['start_time'] as num?)?.toDouble() ?? 0.0;
        TranscodeTask? task;

        if (data['task'] != null) {
          // 合并根级别的 ready/stream_url 字段到 task 对象
          final taskJson = Map<String, dynamic>.from(data['task'] as Map<String, dynamic>);
          if (data.containsKey('ready')) {
            taskJson['ready'] = data['ready'] as bool? ?? false;
          }
          if (data.containsKey('stream_url')) {
            taskJson['stream_url'] = data['stream_url'] as String? ?? '';
          }
          task = TranscodeTask.fromJson(taskJson);
          // 转换为 HTTPS
          task = TranscodeTask.withHttps(task);
        }

        if (kDebugMode) {
          print('[Cloud115Transcode] Seek 成功: start_time=$startTime, taskId=${task?.taskId}');
        }

        return SeekTranscodeResult(
          success: true,
          needsReload: _shouldReloadAfterSeek(task, startTime),
          task: task,
          startTime: startTime,
          message: data['message'] as String?,
        );
      }

      throw Cloud115TranscodeException(data['message'] ?? '跳转失败');
    } on DioException catch (e) {
      if (kDebugMode) {
        print('[Cloud115Transcode] 跳转转码失败: ${e.message}');
      }
      throw Cloud115TranscodeException(
        '跳转转码失败: ${e.message}',
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// 判断 seek 后是否需要重新加载播放器
  /// V2 单一任务模式：task_id 相同，需要检查 start_time 是否变化
  bool _shouldReloadAfterSeek(TranscodeTask? newTask, double newStartTime) {
    if (newTask == null) return false;
    // 如果 start_time 变化了，需要重新加载
    // 使用当前保存的 startOffset 与新的 startTime 比较
    // 这里简化处理：假设 start_time != 0 或 start_time 与之前不同时需要重新加载
    return true;  // 后端 V2 会正确判断，这里返回 true 让播放器处理
  }

  /// 轮询等待任务就绪
  ///
  /// [taskId] - 任务 ID
  /// [timeout] - 超时时间（秒）
  /// [onProgress] - 进度回调
  Future<TranscodeTask?> waitForReady(
    String taskId, {
    int timeout = 120,
    void Function(TranscodeStatus)? onProgress,
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: timeout));

    while (DateTime.now().isBefore(deadline)) {
      try {
        final task = await getTaskStatus(taskId);

        if (kDebugMode) {
          print('[Cloud115Transcode] waitForReady检查: status=${task.status}, ready=${task.ready}');
        }

        if (onProgress != null) {
          onProgress(task.status);
        }

        if (task.ready || task.status == TranscodeStatus.completed) {
          print('[Cloud115Transcode] 任务就绪，返回');
          return task;
        }

        if (task.status == TranscodeStatus.error ||
            task.status == TranscodeStatus.cancelled) {
          throw Cloud115TranscodeException('转码失败: ${task.reason ?? task.status}');
        }
      } catch (e) {
        if (e is Cloud115TranscodeException) {
          rethrow;
        }
        // 其他错误继续轮询
        if (kDebugMode) {
          print('[Cloud115Transcode] waitForReady异常: $e');
        }
      }

      // 等待 1 秒后重试
      await Future.delayed(const Duration(seconds: 1));
    }

    throw Cloud115TranscodeException('等待转码超时');
  }

  /// 清除配置
  Future<void> clearConfig() async {
    _backendUrl = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_configKey('python_backend_url'));
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'crypto/m115_crypto.dart';
import '../../models/models.dart';
import '../../core/constants.dart';

/// 115 认证错误
class Cloud115AuthError implements Exception {
  final String message;
  Cloud115AuthError(this.message);

  @override
  String toString() => 'Cloud115AuthError: $message';
}

/// 115 限流错误
class Cloud115RateLimitError implements Exception {
  final String message;
  Cloud115RateLimitError(this.message);

  @override
  String toString() => 'Cloud115RateLimitError: $message';
}

/// 115 Driver 凭据
class DriverCredential {
  final String uid;
  final String cid;
  final String seid;
  final String kid;

  DriverCredential({
    required this.uid,
    required this.cid,
    required this.seid,
    this.kid = '',
  });

  /// 从 Cookie 字符串解析
  factory DriverCredential.fromCookie(String cookie) {
    final pairs = <String, String>{};
    for (final item in cookie.split(';')) {
      final parts = item.split('=');
      if (parts.length != 2) continue;
      final key = parts[0].trim().toUpperCase();
      final value = parts[1].trim();
      if (value.isNotEmpty) {
        pairs[key] = value;
      }
    }

    final requiredKeys = ['UID', 'CID', 'SEID'];
    final missing = requiredKeys.where((k) => !pairs.containsKey(k) || pairs[k]!.isEmpty);

    if (missing.isNotEmpty) {
      throw Cloud115AuthError('115driver Cookie 缺少字段: ${missing.join(', ')}');
    }

    return DriverCredential(
      uid: pairs['UID']!,
      cid: pairs['CID']!,
      seid: pairs['SEID']!,
      kid: pairs['KID'] ?? '',
    );
  }

  Map<String, String> toCookieMap() {
    return {
      'UID': uid,
      'CID': cid,
      'SEID': seid,
      if (kid.isNotEmpty) 'KID': kid,
    };
  }

  String toCookieString() {
    final cookies = <String>[];
    if (uid.isNotEmpty) cookies.add('UID=$uid');
    if (cid.isNotEmpty) cookies.add('CID=$cid');
    if (seid.isNotEmpty) cookies.add('SEID=$seid');
    if (kid.isNotEmpty) cookies.add('KID=$kid');
    return cookies.join('; ');
  }
}

/// 文件信息
class Cloud115FileInfo {
  final String fileId;
  final String? parentId;
  final String name;
  final int size;
  final String pickCode;
  final String? thumbnail;
  final String? thumbnailOriginal;
  final int updateTime;
  final bool isFile;
  final bool isVideo;

  Cloud115FileInfo({
    required this.fileId,
    this.parentId,
    required this.name,
    required this.size,
    required this.pickCode,
    this.thumbnail,
    this.thumbnailOriginal,
    required this.updateTime,
    required this.isFile,
    required this.isVideo,
  });

  /// 安全获取字符串值
  static String _asString(dynamic value) {
    if (value == null) return '';
    if (value is String) return value as String;
    return value.toString();
  }

  /// 安全获取整数值
  static int _asInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value as int;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  /// 安全获取布尔值
  static bool _asBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value as bool;
    if (value is String) return value == '1' || value.toLowerCase() == 'true';
    if (value is int) return value == 1;
    return false;
  }

  /// 检查文件是否是视频（根据扩展名）
  static bool _isVideo(String fileName) {
    final ext = fileName.toLowerCase();
    final videoExtensions = [
      '.mp4', '.mkv', '.avi', '.mov', '.flv', '.wmv', '.rmvb', '.rm',
      '.mpeg', '.mpg', '.m4v', '.3gp', '.ts', '.m2ts', '.webm', '.ogv',
      '.f4v', '.asf', '.divx', '.xvid', '.dat', '.qsv', '.hevc',
      '.strm', '.nfo'
    ];
    return videoExtensions.any((e) => ext.endsWith(e));
  }

  factory Cloud115FileInfo.fromJson(Map<String, dynamic> json) {
    if (kDebugMode) print('[Cloud115FileInfo] 解析数据: $json');

    final isFile = _asBool(json['fc']);
    final name = _asString(json['n'] ?? json['name']);
    final isVideoMark = _asInt(json['isv']) == 1;

    return Cloud115FileInfo(
      fileId: _asString(json['fid'] ?? json['cid']),
      parentId: json['pid'] != null ? _asString(json['pid']) : null,
      name: name,
      size: _asInt(json['s'] ?? json['size']),
      pickCode: _asString(json['pc'] ?? json['pick_code']),
      thumbnail: json['u'] != null ? _asString(json['u']) : null,
      thumbnailOriginal: json['uo'] != null ? _asString(json['uo']) : null,
      updateTime: _asInt(json['t'] ?? json['update_time']),
      isFile: isFile,
      isVideo: isVideoMark || _isVideo(name),
    );
  }

  // 格式化文件大小
  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// 下载信息
class Cloud115DownloadInfo {
  final String fileName;
  final int fileSize;
  final String pickCode;
  final String url;
  final String? client;
  final String? ossId;
  final String? authCookie;

  Cloud115DownloadInfo({
    required this.fileName,
    required this.fileSize,
    required this.pickCode,
    required this.url,
    this.client,
    this.ossId,
    this.authCookie,
  });
}

/// 115 网盘服务
class Cloud115Service {
  final Dio _dio;
  DriverCredential? _credential;
  String? _cookieCache;
  DateTime? _lastLoginCheck;

  static const String _statusCheckUrl = 'https://my.115.com/?ct=guide&ac=status';
  static const List<String> _fileListUrls = [
    'https://webapi.115.com/files',
    'http://web.api.115.com/files',
  ];
  static const String _fileInfoUrl = 'https://webapi.115.com/files/get_info';
  static const String _folderInfoUrl = 'https://webapi.115.com/category/get';
  static const String _downloadApiUrl = 'https://proapi.115.com/app/chrome/downurl';
  static const String _downloadAndroidApiUrl = 'https://proapi.115.com/android/2.0/ufile/download';
  static const String _deleteUrl = 'https://webapi.115.com/rb/delete';

  Cloud115Service({Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          headers: {
            'User-Agent': AppConstants.cloud115UserAgent,
            'Referer': 'https://115.com/',
            'Accept': 'application/json, text/plain, */*',
          },
          // 允许自动跟随重定向
          followRedirects: true,
          maxRedirects: 5,
          // 接受所有状态码，让手动处理
          validateStatus: (status) => status != null && status < 600,
        ));

  /// 初始化（从本地加载 Cookie）
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final cookie = prefs.getString('cloud115_cookie');
    if (cookie != null && cookie.isNotEmpty) {
      try {
        _credential = DriverCredential.fromCookie(cookie);
        _cookieCache = cookie;
      } catch (_) {}
    }
  }

  /// 设置 Cookie
  Future<void> setCookie(String cookie) async {
    _credential = DriverCredential.fromCookie(cookie);
    _cookieCache = cookie;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cloud115_cookie', cookie);
  }

  /// 清除认证
  Future<void> clearAuth() async {
    _credential = null;
    _cookieCache = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cloud115_cookie');
  }

  /// 检查登录状态
  Future<bool> ensureLogin() async {
    if (_credential == null) {
      throw Cloud115AuthError('115driver Cookie 未设置');
    }

    final now = DateTime.now();
    if (_lastLoginCheck != null &&
        now.difference(_lastLoginCheck!).inSeconds < 300) {
      return true;
    }

    try {
      final response = await _dio.get(
        _statusCheckUrl,
        queryParameters: {'_': now.millisecondsSinceEpoch.toString()},
        options: Options(
          headers: _getAuthHeaders(),
        ),
      );

      if (response.statusCode == 401 || response.statusCode == 511) {
        throw Cloud115AuthError('115driver Cookie 已失效');
      }

      // 处理响应：可能是 JSON 字符串或已解析的对象
      dynamic responseData = response.data;
      if (responseData is String) {
        try {
          responseData = jsonDecode(responseData);
        } catch (_) {
          // 如果解析失败，视为成功
        }
      }

      if (responseData is Map && responseData['state'] == false) {
        throw Cloud115AuthError('115driver Cookie 已失效');
      }

      _lastLoginCheck = now;
      return true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 || e.response?.statusCode == 511) {
        throw Cloud115AuthError('115driver Cookie 已失效');
      }
      rethrow;
    }
  }

  /// 获取认证头
  Map<String, String> _getAuthHeaders() {
    if (_cookieCache == null) return {};
    return {'Cookie': _cookieCache!};
  }

  /// 列出文件
  Future<List<Cloud115FileInfo>> listFiles({
    String cid = '0',
    int limit = 1150,
    int offset = 0,
    String order = 'user_utime',
    bool asc = false,
    bool showDir = true,
  }) async {
    await ensureLogin();

    final params = {
      'aid': '1',
      'cid': cid,
      'o': order,
      'asc': asc ? '1' : '0',
      'offset': offset.toString(),
      'show_dir': showDir ? '1' : '0',
      'limit': limit.clamp(1, 1150).toString(),
      'fc_mix': '0',
      'format': 'json',
      'record_open_time': '1',
      'snap': '0',
    };

    if (kDebugMode) print('[Cloud115Service] 请求文件列表: $params');

    dynamic lastError;

    for (final apiUrl in _fileListUrls) {
      try {
        if (kDebugMode) print('[Cloud115Service] 尝试 API: $apiUrl');
        final response = await _dio.get(
          apiUrl,
          queryParameters: params,
          options: Options(headers: _getAuthHeaders()),
        );

        if (kDebugMode) print('[Cloud115Service] 响应状态: ${response.statusCode}');

        if (response.statusCode == 403) {
          throw Cloud115RateLimitError('115driver 限流 (HTTP 403)');
        }

        // 处理响应：可能是 JSON 字符串或已解析的对象
        dynamic responseData = response.data;
        if (responseData is String) {
          if (kDebugMode) print('[Cloud115Service] 响应是字符串，需要解析 JSON');
          try {
            responseData = jsonDecode(responseData);
          } catch (e) {
            if (kDebugMode) print('[Cloud115Service] JSON 解析失败: $e');
            continue;
          }
        }

        final data = responseData as Map<String, dynamic>?;
        if (kDebugMode) {
          print('[Cloud115Service] 响应数据 keys: ${data?.keys.join(", ")}');
          print('[Cloud115Service] state: ${data?['state']}, errNo: ${data?['errNo']}, error: ${data?['error']}');
        }

        if (data == null) {
          if (kDebugMode) print('[Cloud115Service] 响应数据为 null，继续下一个 API');
          continue;
        }

        // 检查错误状态 - 115 使用 errNo 而不是 errno
        final state = data['state'];
        final errNo = data['errNo'];
        final error = data['error'];

        if (state == false || errNo != 0) {
          final errorMsg = error?.toString() ?? '未知错误';
          if (kDebugMode) print('[Cloud115Service] API 返回错误: $errorMsg (errNo: $errNo)');
          // 可能是权限问题，继续尝试下一个 API
          continue;
        }

        final files = data['data'] as List<dynamic>?;
        if (kDebugMode) print('[Cloud115Service] 文件数量: ${files?.length ?? 0}');

        if (files == null) {
          if (kDebugMode) print('[Cloud115Service] data 字段为 null，继续下一个 API');
          continue;
        }

        return files
            .map((e) => Cloud115FileInfo.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (e) {
        if (kDebugMode) print('[Cloud115Service] 请求异常: $e');
        lastError = e;
        if (e is! Cloud115RateLimitError) continue;
      }
    }

    if (lastError != null) throw lastError;
    throw Exception('获取文件列表失败');
  }

  /// 获取下载信息
  Future<Cloud115DownloadInfo> getDownloadInfo(
    String pickCode, {
    bool useAndroidApi = false,  // 先尝试Chrome API
  }) async {
    await ensureLogin();

    if (pickCode.isEmpty) {
      throw ArgumentError('pickcode 不能为空');
    }

    final endpoint = useAndroidApi ? _downloadAndroidApiUrl : _downloadApiUrl;
    final key = M115Crypto.generateKey();

    final requestData = useAndroidApi
        ? {'pick_code': pickCode}
        : {'pickcode': pickCode};

    final encodedData = M115Crypto.encode(
      Uint8List.fromList(utf8.encode(jsonEncode(requestData))),
      key,
    );

    final params = {'t': DateTime.now().millisecondsSinceEpoch.toString()};
    final formData = {'data': encodedData};

    if (kDebugMode) {
      print('[Cloud115] ========== 获取下载信息 ==========');
      print('[Cloud115] endpoint: $endpoint');
      print('[Cloud115] pickCode: $pickCode');
      print('[Cloud115] useAndroidApi: $useAndroidApi');
    }

    try {
      final response = await _dio.post(
        endpoint,
        queryParameters: params,
        data: formData,
        options: Options(
          headers: {
            ..._getAuthHeaders(),
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          },
          // 对于下载API，禁用自动重定向，手动处理
          followRedirects: false,
          validateStatus: (status) => status != null && status < 600,
        ),
      );

      if (kDebugMode) {
        print('[Cloud115] 响应状态: ${response.statusCode}');
        print('[Cloud115] 响应类型: ${response.data.runtimeType}');
        print('[Cloud115] 响应数据: ${response.data}');
        print('[Cloud115] 重定向: ${response.headers['location']}');
      }

      // 检查是否是重定向
      if (response.statusCode == 302 || response.statusCode == 301) {
        final redirectUrl = response.headers['location']?.first;
        if (redirectUrl != null) {
          if (kDebugMode) print('[Cloud115] 重定向到: $redirectUrl');
          // 跟随重定向，获取实际的 JSON 响应
          final redirectResponse = await _dio.get(
            redirectUrl,
            options: Options(
              headers: _getAuthHeaders(),
              validateStatus: (status) => status != null && status < 600,
            ),
          );

          if (kDebugMode) {
            print('[Cloud115] 重定向响应状态: ${redirectResponse.statusCode}');
            print('[Cloud115] 重定向响应类型: ${redirectResponse.data.runtimeType}');
          }

          // 处理响应 - 可能是 String 也可能是 Map
          final redirectData = redirectResponse.data;
          final Map<String, dynamic> redirectPayload;

          if (redirectData is String) {
            if (kDebugMode) {
              print('[Cloud115] 重定向响应是 String，需要解析 JSON');
              print('[Cloud115] 响应内容: ${redirectData.substring(0, redirectData.length > 200 ? 200 : redirectData.length)}');
            }
            try {
              redirectPayload = jsonDecode(redirectData) as Map<String, dynamic>;
            } catch (e) {
              throw Exception('解析重定向响应 JSON 失败: $e');
            }
          } else if (redirectData is Map) {
            redirectPayload = redirectData as Map<String, dynamic>;
          } else {
            throw Exception('重定向响应格式异常: ${redirectData.runtimeType}');
          }

          if (redirectPayload['state'] != true) {
            final errorMsg = redirectPayload['msg'] ?? redirectPayload['message'] ?? '未知错误';
            throw Exception('获取重定向响应失败: $errorMsg');
          }

          final encodedResponse = redirectPayload['data'] as String?;
          if (encodedResponse == null || encodedResponse.isEmpty) {
            throw Exception('重定向响应数据为空');
          }

          // 解密响应 - 使用同一个 key
          if (kDebugMode) print('[Cloud115] 解密重定向响应...');
          final decrypted = M115Crypto.decode(encodedResponse, key);
          final downloadData = jsonDecode(utf8.decode(decrypted));

          if (downloadData is! Map) {
            throw Exception('下载信息格式异常');
          }

          // 查找文件信息
          for (final entry in downloadData.values) {
            if (entry is! Map) continue;
            final fileSize = entry['file_size'];
            if (fileSize is int && fileSize < 0) {
              throw Exception('文件大小无效');
            }

            // 处理 url 字段
            final urlObj = entry['url'];
            String downloadUrl;
            String? authCookie;

            if (urlObj is Map) {
              downloadUrl = urlObj['url']?.toString() ?? '';
              // auth_cookie 可能是 Map {name: xxx, value: xxx} 或 String
              final authCookieObj = urlObj['auth_cookie'];
              if (authCookieObj is Map) {
                final name = authCookieObj['name']?.toString() ?? '';
                final value = authCookieObj['value']?.toString() ?? '';
                authCookie = name.isNotEmpty && value.isNotEmpty ? '$name=$value' : null;
              } else if (authCookieObj is String && authCookieObj.isNotEmpty) {
                authCookie = authCookieObj;
              }
            } else {
              downloadUrl = urlObj?.toString() ?? '';
              final authCookieObj = entry['auth_cookie'];
              if (authCookieObj is Map) {
                final name = authCookieObj['name']?.toString() ?? '';
                final value = authCookieObj['value']?.toString() ?? '';
                authCookie = name.isNotEmpty && value.isNotEmpty ? '$name=$value' : null;
              } else if (authCookieObj is String && authCookieObj.isNotEmpty) {
                authCookie = authCookieObj;
              }
            }

            if (downloadUrl.isEmpty) {
              throw Exception('未找到下载链接');
            }

            if (kDebugMode) {
              print('[Cloud115] 解密成功，获取到下载链接');
              print('[Cloud115] URL: $downloadUrl');
              print('[Cloud115] authCookie: ${authCookie?.substring(0, authCookie.length > 30 ? 30 : authCookie.length) ?? 'null'}...');
            }

            return Cloud115DownloadInfo(
              fileName: entry['file_name']?.toString() ?? pickCode,
              fileSize: (fileSize is int) ? fileSize : 0,
              pickCode: pickCode,
              url: downloadUrl,
              authCookie: authCookie ?? _cookieCache,
            );
          }

          throw Exception('未找到文件记录');
        }
      }

      final payload = response.data as Map<String, dynamic>?;
      if (kDebugMode) {
        print('[Cloud115] payload keys: ${payload?.keys.join(", ")}');
        print('[Cloud115] payload state: ${payload?['state']}');
        print('[Cloud115] payload data type: ${payload?['data'].runtimeType}');
      }
      if (payload == null || payload['state'] != true) {
        final errorMsg = payload?['msg'] ?? payload?['message'] ?? payload?['error'] ?? '未知错误';
        final errNo = payload?['errNo'] ?? payload?['errno'] ?? payload?['errno'];
        throw Exception('获取下载信息失败: $errorMsg (errNo: $errNo)');
      }

      final encodedResponse = payload['data'] as String?;
      if (encodedResponse == null || encodedResponse.isEmpty) {
        throw Exception('返回数据为空');
      }

      // 解密响应
      final decrypted = M115Crypto.decode(encodedResponse, key);
      final downloadData = jsonDecode(utf8.decode(decrypted));

      if (downloadData is! Map) {
        throw Exception('下载信息格式异常');
      }

      // 查找文件信息
      for (final entry in downloadData.values) {
        if (entry is! Map) continue;

        final urlObj = entry['url'];
        String downloadUrl;
        String? client, ossId, authCookie;

        if (urlObj is Map) {
          downloadUrl = urlObj['url'] as String? ?? '';
          client = urlObj['client'] as String?;
          ossId = urlObj['oss_id'] as String?;
          authCookie = urlObj['auth_cookie'] as String?;
        } else {
          downloadUrl = urlObj.toString();
        }

        if (downloadUrl.isEmpty) continue;

        final fileSize = entry['file_size'] as int? ?? -1;
        if (fileSize < 0) {
          throw Exception('文件大小无效');
        }

        if (kDebugMode) print('[Cloud115] 获取下载信息成功');

        // 如果没有authCookie，使用缓存的Cookie
        if (authCookie == null || authCookie.isEmpty) {
          authCookie = _cookieCache;
        }

        return Cloud115DownloadInfo(
          fileName: entry['file_name'] as String? ?? '',
          fileSize: fileSize,
          pickCode: entry['pick_code'] as String? ?? pickCode,
          url: downloadUrl,
          client: client,
          ossId: ossId,
          authCookie: authCookie,
        );
      }

      throw Exception('未找到文件记录');
    } on DioException catch (e) {
      if (kDebugMode) {
        print('[Cloud115] DioException: ${e.message}');
        print('[Cloud115] 响应状态: ${e.response?.statusCode}');
        print('[Cloud115] 响应头: ${e.response?.headers}');
      }
      throw Exception('请求失败: ${e.message}');
    }
  }

  /// 获取视频播放信息
  Future<Map<String, dynamic>> getVideoPlay(String pickCode) async {
    await ensureLogin();

    if (pickCode.isEmpty) {
      throw ArgumentError('pickcode 不能为空');
    }

    if (kDebugMode) {
      print('[Cloud115] ========== 开始获取视频播放信息 ==========');
      print('[Cloud115] pickCode: $pickCode');
    }

    // 首先尝试简单的下载API
    try {
      final result = await _getVideoPlaySimple(pickCode);
      if (kDebugMode) print('[Cloud115] 简单API成功');
      return result;
    } catch (e) {
      if (kDebugMode) print('[Cloud115] 简单API失败: $e，尝试加密API');
      // 简单API失败，尝试使用加密下载API
      Cloud115DownloadInfo? downloadInfo;

      // 先尝试Chrome API
      try {
        downloadInfo = await getDownloadInfo(pickCode, useAndroidApi: false);
        if (kDebugMode) print('[Cloud115] Chrome加密API成功');
      } catch (e2) {
        if (kDebugMode) print('[Cloud115] Chrome加密API失败: $e2，尝试Android API');
        // Chrome API失败，尝试Android API
        downloadInfo = await getDownloadInfo(pickCode, useAndroidApi: true);
        if (kDebugMode) print('[Cloud115] Android加密API成功');
      }

      return {
        'state': 1,
        'data': {
          'video_url': [
            {
              'definition': 100,
              'title': '原画',
              'url': downloadInfo.url,
            }
          ]
        }
      };
    }
  }

  /// 使用简单API获取视频播放信息
  Future<Map<String, dynamic>> _getVideoPlaySimple(String pickCode) async {
    final url = 'https://webapi.115.com/files/download';
    final params = {'pickcode': pickCode};

    if (kDebugMode) {
      print('[Cloud115] 尝试简单API: $url');
    }

    final response = await _dio.get(
      url,
      queryParameters: params,
      options: Options(headers: _getAuthHeaders()),
    );

    if (kDebugMode) {
      print('[Cloud115] 响应状态: ${response.statusCode}');
      print('[Cloud115] 响应数据类型: ${response.data.runtimeType}');
    }

    // 处理响应：可能是 JSON 字符串或已解析的对象
    dynamic responseData = response.data;
    if (responseData is String) {
      if (kDebugMode) print('[Cloud115] 响应是字符串，需要解析 JSON');
      try {
        responseData = jsonDecode(responseData);
      } catch (e) {
        if (kDebugMode) print('[Cloud115] JSON 解析失败: $e');
        throw Exception('响应数据解析失败');
      }
    }

    final payload = responseData as Map<String, dynamic>?;
    if (kDebugMode) {
      print('[Cloud115] payload keys: ${payload?.keys.join(", ")}');
      print('[Cloud115] payload state: ${payload?['state']}');
    }

    if (payload == null) {
      throw Exception('返回数据为空');
    }

    // 检查 state 字段（可能是 bool 或 int）
    final state = payload['state'];
    final isSuccess = state == true || state == 1 || state == '1';
    if (!isSuccess) {
      // 打印完整的错误响应用于调试
      if (kDebugMode) {
        print('[Cloud115] API 返回错误状态');
        print('[Cloud115] msg: ${payload['msg']}');
        print('[Cloud115] msg_code: ${payload['msg_code']}');
        print('[Cloud115] errtype: ${payload['errtype']}');
        print('[Cloud115] is_vip: ${payload['is_vip']}');
        print('[Cloud115] is_115chrome: ${payload['is_115chrome']}');
      }
      final errorMsg = payload['msg'] ??
          payload['error'] ??
          payload['message'] ??
          payload['errNo']?.toString() ??
          payload['msg_code']?.toString() ??
          '未知错误';
      throw Exception('获取播放信息失败: $errorMsg');
    }

    final data = payload['data'];
    if (kDebugMode) {
      print('[Cloud115] data 类型: ${data.runtimeType}');
      if (data is Map) {
        print('[Cloud115] data keys: ${data.keys.join(", ")}');
      }
    }

    String? downloadUrl;

    // 尝试多种可能的返回格式（参考 Python 实现）
    if (data is Map) {
      final dataMap = data as Map<String, dynamic>;

      // 格式1: data.url.url (字典嵌套)
      if (dataMap['url'] is Map) {
        final urlObj = dataMap['url'] as Map<String, dynamic>;
        downloadUrl = urlObj['url']?.toString();
        if (kDebugMode) print('[Cloud115] 格式1: data.url.url = $downloadUrl');
      }
      // 格式2: data.url (直接是字符串)
      else if (dataMap['url'] is String) {
        downloadUrl = dataMap['url'] as String;
        if (kDebugMode) print('[Cloud115] 格式2: data.url = $downloadUrl');
      }
      // 格式3: data[pickCode].url
      else if (dataMap.containsKey(pickCode) && dataMap[pickCode] is Map) {
        final pickCodeData = dataMap[pickCode] as Map<String, dynamic>;
        final urlData = pickCodeData['url'];
        if (urlData is Map) {
          downloadUrl = urlData['url']?.toString();
        } else if (urlData is String) {
          downloadUrl = urlData;
        }
        if (kDebugMode) print('[Cloud115] 格式3: data[$pickCode].url = $downloadUrl');
      }
      // 格式4: data.download_url 或 data.file_url
      else {
        downloadUrl = dataMap['download_url']?.toString() ?? dataMap['file_url']?.toString();
        if (kDebugMode) print('[Cloud115] 格式4: download_url/file_url = $downloadUrl');
      }
    } else if (data is String) {
      downloadUrl = data;
      if (kDebugMode) print('[Cloud115] data 直接是字符串: $downloadUrl');
    }

    if (downloadUrl == null || downloadUrl.isEmpty) {
      if (kDebugMode) {
        print('[Cloud115] 未能从响应中提取下载地址');
        print('[Cloud115] 完整响应: $responseData');
      }
      throw Exception('未找到下载地址');
    }

    if (kDebugMode) {
      print('[Cloud115] ========== 成功获取播放地址 ==========');
      print('[Cloud115] downloadUrl: $downloadUrl');
    }

    return {
      'state': 1,
      'data': {
        'video_url': [
          {
            'definition': 100,
            'title': '原画',
            'url': downloadUrl,
          }
        ]
      }
    };
  }

  /// 删除文件
  Future<bool> deleteFile(String fileId) async {
    await ensureLogin();

    final params = {'fid': fileId};

    try {
      final response = await _dio.post(
        _deleteUrl,
        data: params,
        options: Options(headers: _getAuthHeaders()),
      );

      if (response.statusCode == 403) {
        throw Cloud115RateLimitError('删除文件限流');
      }

      // 处理响应：可能是 JSON 字符串或已解析的对象
      dynamic responseData = response.data;
      if (responseData is String) {
        try {
          responseData = jsonDecode(responseData);
        } catch (_) {
          // 忽略解析错误
        }
      }

      final payload = responseData as Map<String, dynamic>?;
      // 检查 errNo 和 state 字段
      return payload?['state'] == true || payload?['errNo'] == 0;
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        throw Cloud115RateLimitError('删除文件限流');
      }
      return false;
    }
  }

  /// 是否已登录
  bool get isLoggedIn => _credential != null;

  /// 获取当前凭据
  DriverCredential? get credential => _credential;
}

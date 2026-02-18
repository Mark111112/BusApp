import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../repositories/jellyfin_repository.dart';
import '../utils/video_id_matcher.dart';

/// Jellyfin 服务
/// 移植自 jellyfin_library.py
class JellyfinService {
  late final Dio _dio;
  String? _serverUrl;
  String? _userId;
  String? _apiKey;
  String? _username;
  String? _password;
  String? _accessToken;

  final Map<String, dynamic> _config = {
    'client_id': 'bus115-flutter',
    'client_name': 'Bus115',
    'device_name': 'Flutter App',
  };

  late final VideoIDMatcher _videoIdMatcher;
  late final JellyfinRepository _repository;

  JellyfinService({
    Dio? dio,
    VideoIDMatcher? videoIdMatcher,
    JellyfinRepository? repository,
  }) {
    _dio = dio ?? Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Accept': 'application/json',
      },
      validateStatus: (status) {
        // 接受所有状态码，手动处理错误
        return status != null && status < 500;
      },
    ));

    // 禁用 SSL 证书验证（仅用于开发环境）
    // 真机可能对自签名证书更严格
    if (!kDebugMode) {
      // 生产环境下禁用 SSL 验证（如果使用自签名证书）
      (_dio.httpClientAdapter as IOHttpClientAdapter).onHttpClientCreate = (client) {
        client.badCertificateCallback = (cert, host, port) => true;
        return client;
      };
    }

    _videoIdMatcher = videoIdMatcher ?? VideoIDMatcher();
    _repository = repository ?? JellyfinRepository();
  }

  /// 初始化配置
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _serverUrl = prefs.getString('jellyfin_server_url');
    _userId = prefs.getString('jellyfin_user_id');
    _apiKey = prefs.getString('jellyfin_api_key');
    _username = prefs.getString('jellyfin_username');
    _password = prefs.getString('jellyfin_password');

    if (_serverUrl != null && _serverUrl!.isNotEmpty) {
      _dio.options.baseUrl = _serverUrl!;
    }

    if (_apiKey != null && _apiKey!.isNotEmpty) {
      _updateAuthHeader();
    }
  }

  /// 更新认证头
  void _updateAuthHeader() {
    if (_apiKey == null || _apiKey!.isEmpty) {
      if (kDebugMode) {
        print('[Jellyfin] _updateAuthHeader: apiKey 为空，跳过');
      }
      return;
    }

    _dio.options.headers['X-MediaBrowser-Token'] = _apiKey!;
    _dio.options.headers['X-Emby-Token'] = _apiKey!;
    _dio.options.headers['X-Emby-Authorization'] =
        'MediaBrowser Client="${_config['client_name']}", Device="${_config['device_name']}", DeviceId="${_config['client_id']}", Version="1.0.0", Token="$_apiKey"';

    if (kDebugMode) {
      final preview = _apiKey!.length > 10 ? _apiKey!.substring(0, 10) : _apiKey!;
      print('[Jellyfin] 认证头已设置: X-MediaBrowser-Token=$preview...');
      print('[Jellyfin] 当前 headers keys: ${_dio.options.headers.keys.toList()}');
      print('[Jellyfin] userId: $_userId');
    }
  }

  /// 连接到服务器
  Future<bool> connect({
    required String serverUrl,
    String? username,
    String? password,
    String? apiKey,
  }) async {
    try {
      _serverUrl = serverUrl.replaceAll(RegExp(r'/+$'), '');
      _dio.options.baseUrl = _serverUrl!;

      // 优先使用 API Key
      if (apiKey != null && apiKey.isNotEmpty) {
        _apiKey = apiKey;
        // 先设置认证头
        _updateAuthHeader();
        // 然后获取用户信息验证连接
        if (kDebugMode) {
          print('[Jellyfin] 使用 API Key 连接: $_serverUrl');
        }
        _userId = await _getUserId();
        if (_userId != null) {
          if (kDebugMode) {
            print('[Jellyfin] API Key 连接成功: userId=$_userId');
          }
          await _saveConfig();
          return true;
        }
        return false;
      }

      // 使用用户名密码登录
      if (username != null && password != null) {
        _username = username;
        _password = password;
        return await _login();
      }

      return false;
    } catch (e) {
      if (kDebugMode) {
        print('[Jellyfin] 连接失败: $e');
      }
      return false;
    }
  }

  /// 登录
  Future<bool> _login() async {
    try {
      if (kDebugMode) {
        print('[Jellyfin] 开始登录: $_username');
        print('[Jellyfin] 服务器 URL: $_serverUrl');
      }

      final requestData = {
        'Username': _username,
        'Pw': _password,
        'Client': _config['client_name'],
        'Device': _config['device_name'],
        'DeviceId': _config['client_id'],
      };

      if (kDebugMode) {
        print('[Jellyfin] 请求数据: $requestData');
      }

      final response = await _dio.post(
        '/Users/authenticateByName',
        data: requestData,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'X-Emby-Authorization': 'MediaBrowser Client="${_config['client_name']}", Device="${_config['device_name']}", DeviceId="${_config['client_id']}", Version="1.0.0"',
          },
        ),
      );

      final data = response.data as Map<String, dynamic>;
      _accessToken = data['AccessToken'];
      _userId = data['User']['Id'];

      if (kDebugMode) {
        print('[Jellyfin] 登录成功: userId=$_userId, token=${_accessToken?.substring(0, 10)}...');
      }

      // 使用 AccessToken 作为 API Key
      _apiKey = _accessToken;
      _updateAuthHeader();
      await _saveConfig();
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('[Jellyfin] 登录失败: $e');
        if (e is DioException) {
          print('[Jellyfin] 响应状态码: ${e.response?.statusCode}');
          print('[Jellyfin] 响应数据: ${e.response?.data}');
          print('[Jellyfin] 请求头: ${e.requestOptions.headers}');
        }
      }
      return false;
    }
  }

  /// 获取用户 ID
  Future<String> _getUserId() async {
    try {
      final response = await _dio.get('/Users');
      final users = response.data as List;
      if (users.isNotEmpty) {
        return users[0]['Id'];
      }
    } catch (_) {}
    throw Exception('获取用户 ID 失败');
  }

  /// 保存配置
  Future<void> _saveConfig() async {
    final prefs = await SharedPreferences.getInstance();
    if (_serverUrl != null) prefs.setString('jellyfin_server_url', _serverUrl!);
    if (_userId != null) prefs.setString('jellyfin_user_id', _userId!);
    if (_apiKey != null) prefs.setString('jellyfin_api_key', _apiKey!);
    if (_username != null) prefs.setString('jellyfin_username', _username!);
    if (_password != null) prefs.setString('jellyfin_password', _password!);
  }

  /// 断开连接
  void disconnect() {
    _serverUrl = null;
    _userId = null;
    _apiKey = null;
    _username = null;
    _password = null;
    _accessToken = null;
  }

  /// 获取媒体库列表
  /// 对应 Python: get_libraries() -> client.jellyfin.get_views()
  Future<List<JellyfinLibrary>> getLibraries() async {
    if (_userId == null) {
      if (kDebugMode) {
        print('[Jellyfin] userId 为空，无法获取媒体库');
      }
      throw Exception('未登录');
    }

    if (_apiKey == null) {
      if (kDebugMode) {
        print('[Jellyfin] apiKey 为空，无法获取媒体库');
      }
      throw Exception('未认证');
    }

    try {
      // 确保认证头已设置
      _updateAuthHeader();

      // 对应 Python: self.client.jellyfin.get_views()
      // API 端点: GET /Users/{UserId}/Views
      final response = await _dio.get(
        '/Users/$_userId/Views',
        options: Options(
          headers: {
            'X-MediaBrowser-Token': _apiKey!,
            'X-Emby-Token': _apiKey!,
            'Accept': 'application/json',
          },
        ),
      );

      // Python: libraries.get('Items', [])
      final data = response.data as Map<String, dynamic>;
      final items = data['Items'] as List<dynamic>? ?? [];

      if (kDebugMode) {
        print('[Jellyfin] get_views 返回 ${items.length} 个项目');
      }

      // Python 版本的数据结构处理
      final result = items.map((item) {
        // 获取基本信息
        final id = item['Id'] as String? ?? '';
        final name = item['Name'] as String? ?? '';
        final collectionType = item['CollectionType'] as String? ?? '';

        // 获取项目数量 - ChildCount 可能是 int 或 double
        int itemCount = 0;
        final childCount = item['ChildCount'];
        if (childCount is int) {
          itemCount = childCount;
        } else if (childCount is double) {
          itemCount = childCount.toInt();
        }

        // 如果没有 ChildCount，尝试 RecursiveItemCount
        if (itemCount == 0) {
          final recursiveCount = item['RecursiveItemCount'];
          if (recursiveCount is int) {
            itemCount = recursiveCount;
          } else if (recursiveCount is double) {
            itemCount = recursiveCount.toInt();
          }
        }

        return JellyfinLibrary(
          id: id,
          name: name,
          type: collectionType,
          itemCount: itemCount,
        );
      }).toList();

      if (kDebugMode) {
        print('[Jellyfin] 解析到 ${result.length} 个媒体库');
      }

      return result;
    } catch (e) {
      if (kDebugMode) {
        print('[Jellyfin] 获取媒体库列表失败: $e');
      }
      throw Exception('获取媒体库列表失败: $e');
    }
  }

  /// 获取媒体库项目
  /// 对应 Python: get_library_items()
  Future<Map<String, dynamic>> getLibraryItems({
    required String libraryId,
    int startIndex = 0,
    int limit = 100,
    String sortBy = 'DateCreated',
    String sortOrder = 'Descending',
    String? minDateCreated,
    String? minDateLastSaved,
  }) async {
    try {
      // 确保认证头已设置
      _updateAuthHeader();

      // 对应 Python 版本的参数
      final params = <String, dynamic>{
        'ParentId': libraryId,
        'StartIndex': startIndex,
        'Limit': limit,
        'Recursive': true,  // 确保递归获取所有子项目
        'IncludeItemTypes': 'Movie,Episode,Video',  // 明确指定需要的项目类型
        'Fields': 'Path,Overview,PremiereDate,MediaSources,ProviderIds,MediaStreams,ImageTags,BackdropImageTags,DateCreated,DateLastSaved,People,Genres',
      };

      // 添加可选参数
      if (sortBy.isNotEmpty) {
        params['SortBy'] = sortBy;
      }
      if (sortOrder.isNotEmpty) {
        params['SortOrder'] = sortOrder;
      }
      if (minDateCreated != null && minDateCreated.isNotEmpty) {
        params['MinDateCreated'] = minDateCreated;
      }
      if (minDateLastSaved != null && minDateLastSaved.isNotEmpty) {
        params['MinDateLastSaved'] = minDateLastSaved;
      }

      final response = await _dio.get(
        '/Users/$_userId/Items',
        queryParameters: params,
        options: Options(
          headers: {
            'X-MediaBrowser-Token': _apiKey!,
            'X-Emby-Token': _apiKey!,
            'Accept': 'application/json',
          },
        ),
      );

      final items = response.data['Items'] as List? ?? [];
      final totalCount = response.data['TotalRecordCount'] ?? items.length;

      if (kDebugMode) {
        print('[Jellyfin] get_library_items: 获取到 ${items.length} 个项目，总计: $totalCount');
      }

      return {
        'items': items,
        'total_count': totalCount,
      };
    } catch (e) {
      if (kDebugMode) {
        print('[Jellyfin] 获取库项目列表错误: $e');
      }
      return {'items': [], 'total_count': 0};
    }
  }

  /// 搜索项目
  Future<List<Map<String, dynamic>>> search(String query) async {
    try {
      _updateAuthHeader();

      final response = await _dio.get(
        '/Users/$_userId/Items',
        queryParameters: {
          'SearchTerm': query,
          'IncludeItemTypes': 'Movie,Video',
          'Recursive': true,
          'Limit': 50,
          'Fields': 'Path,Overview,PremiereDate,RunTimeTicks,MediaSources,ProviderIds,MediaStreams,ImageTags,BackdropImageTags,Genres,People',
        },
        options: Options(
          headers: {
            'X-MediaBrowser-Token': _apiKey!,
            'X-Emby-Token': _apiKey!,
            'Accept': 'application/json',
          },
        ),
      );

      final items = response.data['Items'] as List? ?? [];
      return items.map((e) => {
        'id': e['Id'],
        'name': e['Name'],
        'type': e['Type'],
        'overview': e['Overview'],
      }).toList();
    } catch (e) {
      throw Exception('搜索失败: $e');
    }
  }

  /// 获取单个项目的详细元数据
  /// 对应 Python: get_item_metadata()
  /// 用于播放或查看详情时获取完整信息（Genres, People, Overview, Runtime, etc.）
  Future<Map<String, dynamic>?> getItemMetadata(String itemId) async {
    if (!isConnected) return null;

    try {
      _updateAuthHeader();

      final response = await _dio.get(
        '/Users/$_userId/Items',
        queryParameters: {
          'Ids': itemId,
          'Fields': 'Overview,Genres,People,PremiereDate,RunTimeTicks,MediaSources,MediaStreams,Path',
        },
        options: Options(
          headers: {
            'X-MediaBrowser-Token': _apiKey!,
            'X-Emby-Token': _apiKey!,
            'Accept': 'application/json',
          },
        ),
      );

      final items = response.data['Items'] as List?;
      if (items == null || items.isEmpty) return null;

      return items[0] as Map<String, dynamic>;
    } catch (e) {
      if (kDebugMode) {
        print('[Jellyfin] 获取项目元数据失败: $e');
      }
      return null;
    }
  }

  /// 清除配置
  Future<void> clearConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jellyfin_server_url');
    await prefs.remove('jellyfin_user_id');
    await prefs.remove('jellyfin_api_key');
    await prefs.remove('jellyfin_username');
    await prefs.remove('jellyfin_password');

    _serverUrl = null;
    _userId = null;
    _apiKey = null;
    _username = null;
    _password = null;
  }

  /// 是否已连接
  bool get isConnected => _serverUrl != null && _apiKey != null;

  /// 获取服务器 URL
  String? get serverUrl => _serverUrl;

  /// 构建 API URL
  String _buildUrl(String path) {
    return '$_serverUrl$path';
  }

  /// 获取图片 URL
  String? getImageUrl({
    required String itemId,
    String imageType = 'Primary',
    int? maxWidth,
    int? maxHeight,
  }) {
    if (!isConnected) return null;

    final params = <String>[];
    if (maxWidth != null) params.add('maxWidth=$maxWidth');
    if (maxHeight != null) params.add('maxHeight=$maxHeight');
    if (_apiKey != null) params.add('api_key=$_apiKey');

    final queryString = params.isNotEmpty ? '?${params.join('&')}' : '';
    return '$_serverUrl/Items/$itemId/Images/$imageType$queryString';
  }

  /// 从 Jellyfin Item 创建 JellyfinMovie（公开方法，用于按需解析）
  JellyfinMovie? parseJellyfinItem(
    Map<String, dynamic> item,
    String libraryId,
    String libraryName,
  ) {
    try {
      final itemId = item['Id'] as String?;
      final title = item['Name'] as String?;

      if (itemId == null || title == null) return null;

      // 跳过文件夹
      if (item['IsFolder'] == true) return null;

      // 从标题中提取 video_id
      String? videoId = _videoIdMatcher.extractVideoId(title);

      // 如果提取失败，尝试从 ProviderIds 提取
      if (videoId == null || videoId.isEmpty) {
        final providerIds = item['ProviderIds'] as Map<String, dynamic>?;
        videoId = _videoIdMatcher.extractFromProviderIds(providerIds);
      }

      // 获取路径
      final mediaSources = item['MediaSources'] as List<dynamic>? ?? [];
      final path = mediaSources.isNotEmpty
          ? (mediaSources[0] as Map<String, dynamic>)['Path'] as String?
          : null;

      // 获取封面图
      String? coverImage;
      if (itemId.isNotEmpty) {
        // 优先使用 Backdrop
        final backdropTags = item['BackdropImageTags'] as List<dynamic>? ?? [];
        if (backdropTags.isNotEmpty) {
          coverImage = '$_serverUrl/Items/$itemId/Images/Backdrop/0?api_key=$_apiKey';
        } else {
          coverImage = '$_serverUrl/Items/$itemId/Images/Primary?api_key=$_apiKey';
        }
      }

      // 获取演员
      final people = item['People'] as List<dynamic>? ?? [];
      final actors = people
          .where((p) => p is Map<String, dynamic> && p['Type'] == 'Actor')
          .map((p) => p['Name'] as String? ?? '')
          .where((n) => n.isNotEmpty)
          .toList();

      // 获取日期
      String? date = item['PremiereDate'] as String?;
      if (date != null && date.contains('T')) {
        date = date.split('T')[0];
      }

      // 获取类别
      final genres = item['Genres'] as List<dynamic>? ?? [];
      final genreList = genres
          .map((g) => g.toString())
          .where((g) => g.isNotEmpty)
          .toList();

      // 获取运行时长
      int? runtimeSeconds;
      final runtimeTicks = item['RunTimeTicks'] as int?;
      if (runtimeTicks != null) {
        runtimeSeconds = runtimeTicks ~/ 10000000;
      }

      // 获取文件大小
      int? fileSizeBytes;
      if (mediaSources.isNotEmpty) {
        fileSizeBytes = mediaSources[0]['Size'] as int?;
      }

      // 获取视频分辨率
      String? resolution;
      if (mediaSources.isNotEmpty) {
        final mediaStreams = mediaSources[0]['MediaStreams'] as List<dynamic>? ?? [];
        for (final stream in mediaStreams) {
          if (stream is Map<String, dynamic> && stream['Type'] == 'Video') {
            final width = stream['Width'] as int?;
            final height = stream['Height'] as int?;
            if (width != null && height != null) {
              resolution = '${width}x$height';
              break;
            }
          }
        }
      }

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      return JellyfinMovie(
        title: title,
        jellyfinId: _serverUrl ?? '',
        itemId: itemId,
        videoId: videoId,
        libraryName: libraryName,
        libraryId: libraryId,
        playUrl: getPlayUrl(itemId),
        path: path,
        coverImage: coverImage,
        actors: actors,
        date: date,
        dateAdded: now,
        overview: item['Overview'] as String?,
        runtimeSeconds: runtimeSeconds,
        runtimeText: runtimeSeconds != null ? _formatDuration(runtimeSeconds) : null,
        fileSizeBytes: fileSizeBytes,
        fileSizeText: fileSizeBytes != null ? _formatSize(fileSizeBytes) : null,
        genres: genreList,
        resolution: resolution,
      );
    } catch (e) {
      if (kDebugMode) {
        print('[Jellyfin] 解析项目失败: $e');
      }
      return null;
    }
  }

  /// 格式化时长
  String _formatDuration(int seconds) {
    if (seconds <= 0) return '';
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  /// 格式化文件大小
  String _formatSize(int bytes) {
    if (bytes <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    int unitIndex = 0;
    double size = bytes.toDouble();

    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }

    if (unitIndex == 0) {
      return '${size.toInt()} ${units[unitIndex]}';
    }
    return '${size.toStringAsFixed(2)} ${units[unitIndex]}';
  }

  /// 获取播放 URL
  String? getPlayUrl(String itemId) {
    if (!isConnected) return null;
    return '$_serverUrl/Videos/$itemId/stream?Static=true&api_key=$_apiKey';
  }

  /// 获取转码播放 URL（HLS 格式）
  /// 当直接播放失败时使用此方法获取转码后的流
  /// 使用 master.m3u8 端点以获得正确的时长信息和可拖动进度条
  /// 默认使用 720p 2.5Mbps 质量，适合大多数移动设备
  String? getTranscodedPlayUrl(String itemId) {
    if (!isConnected) return null;
    return '$_serverUrl/Videos/$itemId/master.m3u8'
        '?api_key=$_apiKey'
        '&MediaSourceId=$itemId'
        '&Static=false'
        '&VideoCodec=h264'
        '&AudioCodec=aac'
        '&AudioBitrate=192000'
        '&VideoBitrate=2500000'
        '&MaxWidth=1280'
        '&MaxAudioChannels=2'
        '&PlaySessionId=${DateTime.now().millisecondsSinceEpoch}';
  }

  /// 获取转码播放 URL（带自定义质量参数）
  /// [quality] 质量档位：low(480p), medium(720p), high(1080p), max(原画)
  String? getTranscodedPlayUrlWithQuality(String itemId, {String quality = 'medium'}) {
    if (!isConnected) return null;

    final qualityParams = _getQualityParams(quality);
    final params = <String>[
      'api_key=$_apiKey',
      'MediaSourceId=$itemId',
      'Static=false',
      'VideoCodec=h264',
      'AudioCodec=aac',
      'MaxAudioChannels=2',
      'PlaySessionId=${DateTime.now().millisecondsSinceEpoch}',
      ...qualityParams,
    ];

    return '$_serverUrl/Videos/$itemId/master.m3u8?${params.join('&')}';
  }

  /// 根据质量档位获取转码参数
  List<String> _getQualityParams(String quality) {
    switch (quality.toLowerCase()) {
      case 'low': // 480p - 节省流量
        return [
          'VideoBitrate=1000000',  // 1Mbps
          'MaxWidth=854',           // 480p
          'AudioBitrate=128000',    // 128kbps
        ];
      case 'medium': // 720p - 平衡质量和流量
        return [
          'VideoBitrate=2500000',  // 2.5Mbps
          'MaxWidth=1280',          // 720p
          'AudioBitrate=192000',    // 192kbps
        ];
      case 'high': // 1080p - 高质量
        return [
          'VideoBitrate=5000000',  // 5Mbps
          'MaxWidth=1920',          // 1080p
          'AudioBitrate=192000',    // 192kbps
        ];
      case 'max': // 尽可能高
        return [
          'VideoBitrate=12000000', // 12Mbps
          'MaxWidth=4096',          // 4K
          'AudioBitrate=320000',    // 320kbps
        ];
      default: // 默认使用 medium
        return [
          'VideoBitrate=2500000',  // 2.5Mbps
          'MaxWidth=1280',          // 720p
          'AudioBitrate=192000',    // 192kbps
        ];
    }
  }

  /// 获取已导入的库列表
  Future<List<ImportedLibrary>> getImportedLibraries() async {
    try {
      await _repository.ensureTables();
      return await _repository.getImportedLibraries();
    } catch (e) {
      if (kDebugMode) {
        print('[Jellyfin] 获取已导入库列表失败: $e');
      }
      return [];
    }
  }

  /// 获取库中的电影列表
  Future<List<JellyfinMovie>> getLibraryMovies({
    String? libraryId,
    int start = 0,
    int limit = 50,
    String? searchTerm,
    SortOption? sortBy,
  }) async {
    try {
      await _repository.ensureTables();
      return await _repository.getLibraryMovies(
        libraryId: libraryId,
        start: start,
        limit: limit,
        searchTerm: searchTerm,
        sortBy: sortBy,
      );
    } catch (e) {
      if (kDebugMode) {
        print('[Jellyfin] 获取库电影列表失败: $e');
      }
      return [];
    }
  }

  /// 获取库电影总数
  Future<int> getLibraryMoviesCount({
    String? libraryId,
    String? searchTerm,
  }) async {
    try {
      return await _repository.getLibraryMoviesCount(
        libraryId: libraryId,
        searchTerm: searchTerm,
      );
    } catch (e) {
      return 0;
    }
  }

  /// 根据 video_id 查找电影
  Future<List<JellyfinMovie>> findMoviesByVideoId(String videoId) async {
    try {
      return await _repository.findMoviesByVideoId(videoId);
    } catch (e) {
      return [];
    }
  }

  /// 根据 item_id 获取本地存储的电影
  Future<JellyfinMovie?> getMovieByItemId(String itemId) async {
    try {
      return await _repository.getMovieByItemId(itemId);
    } catch (e) {
      return null;
    }
  }

  /// 删除导入的库
  Future<int> deleteLibrary(String libraryId) async {
    try {
      final count = await _repository.deleteLibrary(libraryId);
      await _repository.deleteLibrarySyncState(libraryId);
      return count;
    } catch (e) {
      if (kDebugMode) {
        print('[Jellyfin] 删除库失败: $e');
      }
      return 0;
    }
  }

  /// 导入库（全量）
  Future<ImportResult> importLibrary({
    required String libraryId,
    required String libraryName,
    void Function(int current, int total)? onProgress,
  }) async {
    if (!isConnected) {
      return ImportResult(
        message: '未连接到服务器',
        failed: 1,
      );
    }

    try {
      // 确保数据库表存在
      await _repository.ensureTables();

      int importedCount = 0;
      int failedCount = 0;
      final Map<String, dynamic> successItems = {};
      final List<String> failedItems = [];
      String? maxDateCreated;
      String? maxDateLastSaved;

      int startIndex = 0;
      const limit = 200;
      int totalProcessed = 0;

      if (kDebugMode) {
        print('[Jellyfin] 开始导入库 $libraryName (ID: $libraryId)');
      }

      while (true) {
        final result = await getLibraryItems(
          libraryId: libraryId,
          startIndex: startIndex,
          limit: limit,
        );

        final items = result['items'] as List<dynamic>? ?? [];
        final totalCount = result['total_count'] as int? ?? items.length;

        if (items.isEmpty) {
          if (kDebugMode) {
            print('[Jellyfin] 没有更多项目，总计处理: $totalProcessed/$totalCount');
          }
          break;
        }

        if (kDebugMode) {
          print('[Jellyfin] 正在处理批次: $startIndex-${startIndex + items.length}/$totalCount, 本批次项目数: ${items.length}');
        }

        // 解析并保存
        for (final item in items) {
          if (item is! Map<String, dynamic>) continue;

          try {
            final movie = parseJellyfinItem(item, libraryId, libraryName);
            if (movie != null) {
              await _repository.saveMovie(movie);
              importedCount++;
              successItems[movie.itemId] = {
                'title': movie.title,
                'video_id': movie.videoId,
              };

              // 更新最大日期
              final dateCreated = item['DateCreated'] as String?;
              final dateLastSaved = item['DateLastSaved'] as String?;
              if (dateCreated != null) {
                if (maxDateCreated == null || dateCreated.compareTo(maxDateCreated) > 0) {
                  maxDateCreated = dateCreated;
                }
              }
              if (dateLastSaved != null) {
                if (maxDateLastSaved == null || dateLastSaved.compareTo(maxDateLastSaved) > 0) {
                  maxDateLastSaved = dateLastSaved;
                }
              }
            } else {
              failedCount++;
            }
          } catch (e) {
            if (kDebugMode) {
              print('[Jellyfin] 保存项目失败: $e');
            }
            failedCount++;
            final title = item['Name'] as String? ?? 'Unknown';
            final id = item['Id'] as String? ?? '';
            failedItems.add('$title (ID: $id)');
          }
        }

        totalProcessed += items.length;
        startIndex += items.length;

        // 通知进度
        onProgress?.call(totalProcessed, totalCount);

        // 如果这批少于 limit，说明已经处理完毕
        if (items.length < limit) {
          if (kDebugMode) {
            print('[Jellyfin] 已处理所有项目: $totalProcessed/$totalCount');
          }
          break;
        }
      }

      // 更新同步状态
      await _repository.upsertLibrarySyncState(LibrarySyncState(
        libraryId: libraryId,
        lastSyncDateCreated: maxDateCreated,
        lastSyncDateLastSaved: maxDateLastSaved,
      ));

      if (kDebugMode) {
        print('[Jellyfin] 导入完成: 成功 $importedCount, 失败 $failedCount');
      }

      return ImportResult(
        imported: importedCount,
        failed: failedCount,
        details: {
          'success': successItems,
          'failed': failedItems,
        },
      );
    } catch (e) {
      if (kDebugMode) {
        print('[Jellyfin] 导入库失败: $e');
      }
      return ImportResult(
        failed: 1,
        message: '导入失败: $e',
      );
    }
  }

  /// 增量同步库
  Future<ImportResult> syncLibraryIncremental({
    required String libraryId,
    required String libraryName,
    void Function(int current, int total)? onProgress,
  }) async {
    if (!isConnected) {
      return ImportResult(
        message: '未连接到服务器',
        failed: 1,
      );
    }

    // 检查同步状态
    final syncState = await _repository.getLibrarySyncState(libraryId);
    final lastDateCreated = syncState?.lastSyncDateCreated;

    if (lastDateCreated == null || lastDateCreated.isEmpty) {
      return ImportResult(
        message: '未找到同步点，请先执行全量导入',
        needsFullImport: true,
      );
    }

    try {
      int importedCount = 0;
      int failedCount = 0;
      final Map<String, dynamic> successItems = {};
      String? maxDateCreated = lastDateCreated;
      String? maxDateLastSaved = syncState?.lastSyncDateLastSaved;

      int startIndex = 0;
      const limit = 200;

      if (kDebugMode) {
        print('[Jellyfin] 开始增量同步库 $libraryName, since=$lastDateCreated');
      }

      while (true) {
        final result = await getLibraryItems(
          libraryId: libraryId,
          startIndex: startIndex,
          limit: limit,
          sortBy: 'DateCreated',
          sortOrder: 'Ascending',
          minDateCreated: lastDateCreated.isNotEmpty ? lastDateCreated : null,
        );

        final items = result['items'] as List<dynamic>? ?? [];
        final totalCount = result['total_count'] as int? ?? items.length;

        if (items.isEmpty) break;

        for (final item in items) {
          if (item is! Map<String, dynamic>) continue;

          try {
            final movie = parseJellyfinItem(item, libraryId, libraryName);
            if (movie != null) {
              await _repository.saveMovie(movie);
              importedCount++;
              successItems[movie.itemId] = {
                'title': movie.title,
                'video_id': movie.videoId,
              };

              // 更新最大日期
              final dateCreated = item['DateCreated'] as String?;
              final dateLastSaved = item['DateLastSaved'] as String?;
              if (dateCreated != null) {
                if (maxDateCreated == null || dateCreated.compareTo(maxDateCreated) > 0) {
                  maxDateCreated = dateCreated;
                }
              }
              if (dateLastSaved != null) {
                if (maxDateLastSaved == null || dateLastSaved.compareTo(maxDateLastSaved) > 0) {
                  maxDateLastSaved = dateLastSaved;
                }
              }
            } else {
              failedCount++;
            }
          } catch (e) {
            failedCount++;
          }
        }

        startIndex += items.length;
        onProgress?.call(startIndex, totalCount);

        if (startIndex >= totalCount) break;
      }

      // 更新同步状态
      await _repository.upsertLibrarySyncState(LibrarySyncState(
        libraryId: libraryId,
        lastSyncDateCreated: maxDateCreated,
        lastSyncDateLastSaved: maxDateLastSaved,
      ));

      return ImportResult(
        imported: importedCount,
        failed: failedCount,
        details: {
          'success': successItems,
          'failed': [],
        },
        message: '增量同步完成',
      );
    } catch (e) {
      return ImportResult(
        failed: 1,
        message: '增量同步失败: $e',
      );
    }
  }

  /// 更新播放计数
  Future<bool> updatePlayCount(String itemId) async {
    try {
      return await _repository.updatePlayCount(itemId);
    } catch (e) {
      return false;
    }
  }
}

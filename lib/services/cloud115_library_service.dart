import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/library_item.dart';
import '../models/models.dart';
import '../repositories/cloud115_library_repository.dart';
import 'javbus_service.dart';

/// 115 库管理服务
/// 通过 Python 服务器 API 管理导入的 115 视频库
class Cloud115LibraryService {
  final Dio _dio;
  final Cloud115LibraryRepository _repository;
  final JavBusService _javbusService;

  Cloud115LibraryService({
    Dio? dio,
    Cloud115LibraryRepository? repository,
    JavBusService? javbusService,
  })  : _dio = dio ?? Dio(),
        _repository = repository ?? Cloud115LibraryRepository(),
        _javbusService = javbusService ?? JavBusService();

  /// 获取服务器基础 URL
  /// 优先使用 alist_url，否则使用 javbus_base_url
  Future<String> _getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final alistUrl = prefs.getString('bus115_cloud115_alist_url');
    final javbusUrl = prefs.getString('bus115_javbus_base_url');
    return (alistUrl ?? javbusUrl ?? 'http://localhost:5000').trim();
  }

  /// 导入 115 文件夹到库
  /// 返回导入任务 ID
  Future<String?> importDirectory({
    required String folderId,
    required String folderName,
    String category = 'movies',
  }) async {
    try {
      final baseUrl = await _getBaseUrl();
      final response = await _dio.post(
        '$baseUrl/api/cloud115/import_directory',
        data: {
          'folder_id': folderId,
          'folder_name': folderName,
          'category': category,
        },
        options: Options(
          headers: {'Content-Type': 'application/json'},
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        if (data['success'] == true) {
          return data['task_id']?.toString();
        }
      }
      return null;
    } catch (e) {
      if (kDebugMode) print('[Cloud115Library] 导入目录失败: $e');
      return null;
    }
  }

  /// 异步导入 115 文件夹到库
  Future<String?> importDirectoryAsync({
    required String folderId,
    required String folderName,
    String category = 'movies',
  }) async {
    try {
      final baseUrl = await _getBaseUrl();
      final response = await _dio.post(
        '$baseUrl/api/cloud115/import_directory_async',
        data: {
          'folder_id': folderId,
          'folder_name': folderName,
          'category': category,
        },
        options: Options(
          headers: {'Content-Type': 'application/json'},
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        if (data['success'] == true || data['state'] == true) {
          return data['task_id']?.toString();
        }
      }
      return null;
    } catch (e) {
      if (kDebugMode) print('[Cloud115Library] 异步导入目录失败: $e');
      return null;
    }
  }

  /// 获取导入任务状态
  Future<Map<String, dynamic>?> getImportStatus(String taskId) async {
    try {
      final baseUrl = await _getBaseUrl();
      final response = await _dio.get(
        '$baseUrl/api/cloud115/import_status/$taskId',
        options: Options(
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      if (kDebugMode) print('[Cloud115Library] 获取导入状态失败: $e');
      return null;
    }
  }

  /// 从服务器同步库数据到本地
  Future<bool> syncFromServer() async {
    try {
      final baseUrl = await _getBaseUrl();
      final response = await _dio.get(
        '$baseUrl/api/cloud115/library',
        options: Options(
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        if (data['success'] == true || data['state'] == true) {
          final items = data['data'] as List?;
          if (items != null) {
            final libraryItems = items.map((item) {
              return LibraryItem.fromJson({
                ...item as Map<String, dynamic>,
                'type': 'cloud115',
              });
            }).toList();

            await _repository.saveItems(libraryItems);
            return true;
          }
        }
      }
      return false;
    } catch (e) {
      if (kDebugMode) print('[Cloud115Library] 同步库数据失败: $e');
      return false;
    }
  }

  /// 从服务器获取库数据
  Future<List<LibraryItem>> fetchFromServer({
    int page = 1,
    int pageSize = 50,
    String? category,
  }) async {
    try {
      final baseUrl = await _getBaseUrl();
      final queryParams = <String, dynamic>{
        'page': page,
        'page_size': pageSize,
      };
      if (category != null) {
        queryParams['category'] = category;
      }

      final response = await _dio.get(
        '$baseUrl/api/cloud115/library',
        queryParameters: queryParams,
        options: Options(
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        if (data['success'] == true || data['state'] == true) {
          final items = data['data'] as List?;
          if (items != null) {
            return items.map((item) {
              return LibraryItem.fromJson({
                ...item as Map<String, dynamic>,
                'type': 'cloud115',
              });
            }).toList();
          }
        }
      }
      return [];
    } catch (e) {
      if (kDebugMode) print('[Cloud115Library] 获取库数据失败: $e');
      return [];
    }
  }

  /// 提取视频 ID
  Future<bool> extractVideoIds() async {
    try {
      final baseUrl = await _getBaseUrl();
      final response = await _dio.post(
        '$baseUrl/api/cloud115/extract_ids',
        options: Options(
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        return data['success'] == true || data['state'] == true;
      }
      return false;
    } catch (e) {
      if (kDebugMode) print('[Cloud115Library] 提取视频 ID 失败: $e');
      return false;
    }
  }

  /// 获取本地库项目
  /// [searchTerm] 搜索关键词
  /// [category] 分类筛选
  /// [sortBy] 排序选项
  Future<List<LibraryItem>> getLocalItems({
    int start = 0,
    int limit = 50,
    String? searchTerm,
    String? category,
    SortOption? sortBy,
  }) async {
    await _repository.ensureTables();
    return _repository.getAllItems(
      start: start,
      limit: limit,
      searchTerm: searchTerm,
      category: category,
      sortBy: sortBy,
    );
  }

  /// 获取本地库项目总数
  /// [searchTerm] 搜索关键词
  /// [category] 分类筛选
  Future<int> getLocalItemsCount({
    String? searchTerm,
    String? category,
  }) async {
    await _repository.ensureTables();
    return _repository.getItemsCount(
      searchTerm: searchTerm,
      category: category,
    );
  }

  /// 获取本地库项目总数（带排序，用于获取筛选后的总数）
  /// 注意：此方法返回的是应用搜索条件后的总数，排序不影响总数
  Future<int> getLocalItemsCountSorted({
    String? searchTerm,
    String? category,
    SortOption? sortBy,
  }) async {
    // 排序不影响总数，直接调用 getLocalItemsCount
    return getLocalItemsCount(
      searchTerm: searchTerm,
      category: category,
    );
  }

  /// 获取本地统计信息
  Future<Map<String, int>> getLocalStats() async {
    await _repository.ensureTables();
    return _repository.getStats();
  }

  /// 根据 video_id 查找项目
  Future<List<LibraryItem>> findItemsByVideoId(String videoId) async {
    await _repository.ensureTables();
    return _repository.findItemsByVideoId(videoId);
  }

  /// 删除项目
  Future<bool> deleteItem(String fileId) async {
    await _repository.ensureTables();
    return _repository.deleteItem(fileId);
  }

  /// 清空本地库
  Future<int> clearLocalLibrary() async {
    await _repository.ensureTables();
    return _repository.clearAll();
  }

  /// 更新播放计数
  Future<bool> updatePlayCount(String fileId) async {
    await _repository.ensureTables();
    return _repository.updatePlayCount(fileId);
  }

  /// 更新项目的封面图片
  Future<bool> updateCoverImage(String fileId, String coverImage) async {
    await _repository.ensureTables();
    return _repository.updateCoverImage(fileId, coverImage);
  }

  /// 从 115 文件夹创建库项目（本地处理）
  /// 用于直接从 115 网盘数据创建库记录
  /// [fetchMetadata] 是否从 JavBus 获取元数据（封面、演员等），默认 true
  /// [onProgress] 进度回调，参数：(当前索引, 总数, 当前文件名)
  Future<List<LibraryItem>> createItemsFrom115Files(
    List<Map<String, dynamic>> files, {
    String category = 'movies',
    List<String>? dictionary,
    bool fetchMetadata = true,
    void Function(int current, int total, String fileName)? onProgress,
  }) async {
    await _repository.ensureTables();

    final items = <LibraryItem>[];
    final matcher = _LibraryVideoIdMatcher(dictionary: dictionary);

    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      final title = file['n'] ?? file['name'] ?? '';
      final fileId = file['fid'] ?? file['id'] ?? '';
      final pickcode = file['pc'] ?? file['pick_code'] ?? '';
      final size = file['s'] ?? file['size'] ?? 0;
      final thumb = file['uo'] ?? file['u'] ?? '';

      if (fileId.isEmpty) continue;

      // 提取视频 ID
      final videoId = matcher.extractVideoId(title);

      // 通知进度
      if (onProgress != null) {
        onProgress(i + 1, files.length, title);
      }

      // 尝试从 JavBus 获取元数据
      String? coverImage;
      String? actors;
      String? releaseDate;
      String? displayTitle;

      if (fetchMetadata && videoId.isNotEmpty) {
        try {
          final movie = await _javbusService.getMovieDetail(videoId);
          if (movie != null) {
            coverImage = movie.cover;
            displayTitle = movie.title;
            if (movie.actors != null && movie.actors!.isNotEmpty) {
              actors = movie.actors!.map((a) => a.name).join(', ');
            }
            releaseDate = movie.date;
          }
        } catch (e) {
          if (kDebugMode) {
            print('[Cloud115Library] 获取 JavBus 元数据失败 [$videoId]: $e');
          }
        }
      }

      // 使用原始文件名作为标题，如果获取到了 JavBus 标题则使用它
      final finalTitle = displayTitle?.isNotEmpty == true ? displayTitle! : title;

      items.add(LibraryItem(
        id: null,
        title: finalTitle,
        filepath: title,
        url: '', // 将在播放时通过 115 API 获取
        thumbnail: thumb,
        category: category,
        dateAdded: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        videoId: videoId.isNotEmpty ? videoId : null,
        coverImage: coverImage,
        actors: actors,
        date: releaseDate,
        type: LibraryType.cloud115,
        fileId: fileId,
        pickcode: pickcode,
        size: size.toString(),
      ));

      // 限流，避免请求过快
      if (fetchMetadata && videoId.isNotEmpty && i < files.length - 1) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    return items;
  }

  /// 批量保存项目到本地库
  Future<void> saveItemsToLocal(List<LibraryItem> items) async {
    await _repository.ensureTables();
    await _repository.saveItems(items);
  }
}

/// 115 库视频 ID 匹配器
class _LibraryVideoIdMatcher {
  final List<String> _dictionary;

  _LibraryVideoIdMatcher({List<String>? dictionary}) : _dictionary = dictionary ?? [];

  String cleanFilename(String filename) {
    String cleaned = filename;
    for (final item in _dictionary) {
      cleaned = cleaned.replaceAll(item, '');
    }
    return cleaned;
  }

  String extractVideoId(String filename) {
    // Get just the filename part
    String baseName = filename;
    if (baseName.contains('/')) {
      baseName = baseName.substring(baseName.lastIndexOf('/') + 1);
    }
    if (baseName.contains('\\')) {
      baseName = baseName.substring(baseName.lastIndexOf('\\') + 1);
    }

    // Clean the filename
    String cleanedName = cleanFilename(baseName);

    // Pre-process: Remove suffixes like -1, -2, -3
    cleanedName = cleanedName.replaceAllMapped(
      RegExp(r'(.*?)(-\d)(\.(mp4|avi|mkv|wmv|rmvb|mov|m4v|flv|vob|ts|m2ts))$', caseSensitive: false),
      (match) => '${match.group(1)}${match.group(3)}',
    );
    cleanedName = cleanedName.replaceAllMapped(
      RegExp(r'(.*?)(-\d)$'),
      (match) => match.group(1) ?? '',
    );

    // Remove extension
    final videoExtensions = ['mp4', 'avi', 'mkv', 'wmv', 'rmvb', 'mov', 'm4v', 'flv', 'vob', 'ts', 'm2ts', 'strm'];
    String nameWithoutExt = cleanedName;
    for (final ext in videoExtensions) {
      nameWithoutExt = nameWithoutExt.replaceAll(RegExp('\\.$ext\$', caseSensitive: false), '');
    }

    // Try to match common video ID patterns
    final patterns = [
      RegExp(r'([A-Z0-9]+-\d+)', caseSensitive: false),
      RegExp(r'[\[\(]([A-Z0-9]+-\d+)[\]\)]', caseSensitive: false),
      RegExp(r'(\d{6}_\d{3})'),
      RegExp(r'(\d{6}-\d{3})'),
      RegExp(r'^([A-Z0-9]+-\d+)', caseSensitive: false),
      RegExp(r'([A-Z0-9]+-\d+)\$', caseSensitive: false),
      RegExp(r'([A-Z]+\d+)', caseSensitive: false),
      RegExp(r'((?:dphn|dph)\d+)', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(nameWithoutExt);
      if (match != null) {
        String videoId = match.group(1)!.toUpperCase();

        if (!videoId.contains('-')) {
          final dphnMatch = RegExp(r'(DPHN|DPH)(\d+)', caseSensitive: false).firstMatch(videoId);
          if (dphnMatch != null) {
            videoId = '${dphnMatch.group(1)}-${dphnMatch.group(2)}';
          } else {
            final alphaNumMatch = RegExp(r'([A-Z]+)(\d+)', caseSensitive: false).firstMatch(videoId);
            if (alphaNumMatch != null) {
              videoId = '${alphaNumMatch.group(1)}-${alphaNumMatch.group(2)}';
            }
          }
        }

        // Handle IDs like ABC-00123
        final fiveDigitMatch = RegExp(r'(.*?)-00(\d{3})\$').firstMatch(videoId);
        if (fiveDigitMatch != null) {
          videoId = '${fiveDigitMatch.group(1)}-${fiveDigitMatch.group(2)}';
        }

        // N-xxxx -> Nxxxx
        final nMatch = RegExp(r'^N-(\d+)\$').firstMatch(videoId);
        if (nMatch != null) {
          videoId = 'N${nMatch.group(1)}';
        }

        // K-xxxx -> Kxxxx
        final kMatch = RegExp(r'^K-(\d+)\$').firstMatch(videoId);
        if (kMatch != null) {
          videoId = 'K${kMatch.group(1)}';
        }

        return videoId;
      }
    }

    return '';
  }
}

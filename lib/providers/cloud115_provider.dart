import 'package:flutter/foundation.dart';
import '../services/cloud115_service.dart';
import '../services/cloud115_proxy_server.dart';

/// 115 网盘状态管理
class Cloud115Provider extends ChangeNotifier {
  final Cloud115Service _service = Cloud115Service();
  final Cloud115ProxyServer _proxyServer = Cloud115ProxyServer();

  bool _isLoading = false;
  bool _isLoggedIn = false;
  String? _errorMessage;
  List<Cloud115FileInfo> _files = [];
  String _currentFolderId = '0';
  String _currentFolderName = '根目录';
  List<String> _folderPath = ['根目录'];
  List<String> _folderIds = ['0'];

  bool get isLoading => _isLoading;
  bool get isLoggedIn => _isLoggedIn;
  String? get errorMessage => _errorMessage;
  List<Cloud115FileInfo> get files => _files;
  List<Cloud115FileInfo> get folders => _files.where((f) => !f.isFile).toList();
  List<Cloud115FileInfo> get onlyFiles => _files.where((f) => f.isFile).toList();
  String get currentFolderId => _currentFolderId;
  String get currentFolderName => _currentFolderName;
  List<String> get folderPath => _folderPath;

  /// 当前播放的 pickCode（用于 URL 刷新）
  String? _currentPickCode;

  /// 初始化
  Future<void> initialize() async {
    await _service.initialize();
    await checkLoginStatus();
  }

  /// 检查登录状态
  Future<void> checkLoginStatus() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final loggedIn = await _service.ensureLogin();
      _isLoggedIn = loggedIn;
      if (_isLoggedIn && _files.isEmpty) {
        await loadFiles();
      }
    } catch (e) {
      _isLoggedIn = false;
      if (e is Cloud115AuthError) {
        _errorMessage = e.message;
      } else {
        _errorMessage = '检查登录状态失败: $e';
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 设置 Cookie
  Future<bool> setCookie(String cookie) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _service.setCookie(cookie);
      await checkLoginStatus();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// 加载文件列表
  Future<void> loadFiles({String? folderId}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final targetFolderId = folderId ?? _currentFolderId;
      print('[Cloud115] 加载文件列表, folderId: $targetFolderId');
      final files = await _service.listFiles(cid: targetFolderId);
      print('[Cloud115] 获取到 ${files.length} 个文件');
      _files = files;
      if (folderId != null) {
        _currentFolderId = folderId;
      }
    } catch (e) {
      print('[Cloud115] 加载失败: $e');
      if (e is Cloud115AuthError) {
        _isLoggedIn = false;
        _errorMessage = e.message;
      } else if (e is Cloud115RateLimitError) {
        _errorMessage = e.message;
      } else {
        _errorMessage = '加载文件列表失败: $e';
      }
      _files = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 进入文件夹
  Future<void> enterFolder(Cloud115FileInfo folder) async {
    if (folder.isFile) return;

    _folderPath.add(folder.name);
    _folderIds.add(folder.fileId);
    _currentFolderId = folder.fileId;
    _currentFolderName = folder.name;

    await loadFiles(folderId: folder.fileId);
  }

  /// 返回上级文件夹
  Future<void> navigateUp() async {
    if (_folderIds.length <= 1) return;

    _folderPath.removeLast();
    _folderIds.removeLast();
    final parentId = _folderIds.last;
    _currentFolderId = parentId;
    _currentFolderName = _folderPath.last;

    await loadFiles(folderId: parentId);
  }

  /// 刷新当前目录
  Future<void> refresh() async {
    await loadFiles();
  }

  /// 播放视频
  /// 返回包含代理URL的Map
  Future<Map<String, dynamic>?> playVideo(Cloud115FileInfo file) async {
    if (!file.isVideo) {
      _errorMessage = '该文件不是视频文件';
      notifyListeners();
      return null;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      print('[Cloud115] 开始获取视频播放信息: ${file.name} (pickCode: ${file.pickCode})');

      // 保存当前 pickCode 用于 URL 刷新
      _currentPickCode = file.pickCode;

      // 获取下载信息（包含URL和Cookie）
      final downloadInfo = await _service.getDownloadInfo(file.pickCode);
      print('[Cloud115] 获取下载信息成功');
      print('[Cloud115] URL: ${downloadInfo.url}');
      print('[Cloud115] Cookie: ${downloadInfo.authCookie?.substring(0, 20)}...');

      // 设置 URL 过期刷新回调
      _proxyServer.setUrlExpiredCallback(() async {
        try {
          print('[Cloud115] URL 过期，正在刷新...');
          final newInfo = await _service.getDownloadInfo(_currentPickCode!);
          print('[Cloud115] URL 刷新成功');
          return {
            'url': newInfo.url,
            'cookie': newInfo.authCookie ?? '',
          };
        } catch (e) {
          print('[Cloud115] URL 刷新失败: $e');
          return null;
        }
      });

      // 启动本地代理服务器
      print('[Cloud115] 启动本地代理服务器...');
      await _proxyServer.stop(); // 先停止旧的

      // 测试：延迟启动，观察是否影响 pmt 错误（用于调试时序问题）
      // await Future.delayed(const Duration(seconds: 2));

      final port = await _proxyServer.start(
        url: downloadInfo.url,
        cookie: downloadInfo.authCookie ?? '',
      );

      print('[Cloud115] 代理服务器已启动，端口: $port');
      print('[Cloud115] 代理URL: ${_proxyServer.proxyUrl}');

      _errorMessage = null;
      notifyListeners();

      // 返回代理URL和转码所需的参数
      return {
        'url': _proxyServer.proxyUrl,
        'title': file.name,
        'isLocal': false,
        'pickcode': file.pickCode,
        'fileId': file.fileId,
        // 传递原始下载信息给转码服务使用
        'downloadData': {
          'download_url': downloadInfo.url,
          'file_name': downloadInfo.fileName,
          'file_size': downloadInfo.fileSize,
        },
      };
    } catch (e) {
      print('[Cloud115] 获取播放信息失败: $e');
      _errorMessage = '获取播放信息失败: $e';
      notifyListeners();
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 通过 pickcode 获取播放信息
  /// 用于从媒体库直接播放，无需 Cloud115FileInfo 对象
  Future<Map<String, dynamic>?> getPlayInfoByPickCode(String pickCode) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      print('[Cloud115] 开始获取视频播放信息 (pickCode: $pickCode)');

      // 保存当前 pickCode 用于 URL 刷新
      _currentPickCode = pickCode;

      // 获取下载信息（包含URL和Cookie）
      final downloadInfo = await _service.getDownloadInfo(pickCode);
      print('[Cloud115] 获取下载信息成功');
      print('[Cloud115] URL: ${downloadInfo.url}');

      // 设置 URL 过期刷新回调
      _proxyServer.setUrlExpiredCallback(() async {
        try {
          print('[Cloud115] URL 过期，正在刷新...');
          final newInfo = await _service.getDownloadInfo(_currentPickCode!);
          print('[Cloud115] URL 刷新成功');
          return {
            'url': newInfo.url,
            'cookie': newInfo.authCookie ?? '',
          };
        } catch (e) {
          print('[Cloud115] URL 刷新失败: $e');
          return null;
        }
      });

      // 启动本地代理服务器
      print('[Cloud115] 启动本地代理服务器...');
      await _proxyServer.stop(); // 先停止旧的

      // 测试：延迟启动，观察是否影响 pmt 错误（用于调试时序问题）
      // await Future.delayed(const Duration(seconds: 2));

      final port = await _proxyServer.start(
        url: downloadInfo.url,
        cookie: downloadInfo.authCookie ?? '',
      );

      print('[Cloud115] 代理服务器已启动，端口: $port');

      _errorMessage = null;
      notifyListeners();

      return {
        'url': _proxyServer.proxyUrl,
        'isLocal': false,
        'pickcode': pickCode,
        // 传递原始下载信息给转码服务使用
        'downloadData': {
          'download_url': downloadInfo.url,
          'file_name': downloadInfo.fileName,
          'file_size': downloadInfo.fileSize,
        },
      };
    } catch (e) {
      print('[Cloud115] 获取播放信息失败: $e');
      _errorMessage = '获取播放信息失败: $e';
      notifyListeners();
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 获取下载信息（不下载，仅获取信息）
  Future<Cloud115DownloadInfo?> getDownloadInfo(Cloud115FileInfo file) async {
    try {
      return await _service.getDownloadInfo(file.pickCode);
    } catch (e) {
      _errorMessage = '获取下载信息失败: $e';
      return null;
    }
  }

  /// 删除文件
  Future<bool> deleteFile(Cloud115FileInfo file) async {
    _isLoading = true;
    notifyListeners();

    try {
      final result = await _service.deleteFile(file.fileId);
      if (result) {
        _files.removeWhere((f) => f.fileId == file.fileId);
      }
      return result;
    } catch (e) {
      _errorMessage = '删除文件失败: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 清除错误信息
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// 递归获取文件夹中的所有视频文件
  /// [folderId] 起始文件夹ID，默认为当前文件夹
  /// [onProgress] 进度回调，参数：(当前数量, 总数, 当前文件夹名)
  /// [onFound] 发现文件时的回调，返回 true 继续收集，false 停止
  /// [onRateLimit] 触发风控时的回调，返回 true 继续等待后重试，false 停止
  Future<List<Cloud115FileInfo>> getAllVideosRecursively({
    String? folderId,
    void Function(int current, int total, String folderName)? onProgress,
    bool Function(Cloud115FileInfo)? onFound,
    Future<bool> Function(int count)? onRateLimit,
  }) async {
    final startFolderId = folderId ?? _currentFolderId;
    final allVideos = <Cloud115FileInfo>[];
    final visitedFolders = <String>{};
    int totalCount = 0;

    await _collectVideosRecursive(
      startFolderId,
      allVideos,
      visitedFolders,
      totalCount,
      onProgress: onProgress,
      onFound: onFound,
      onRateLimit: onRateLimit,
    );

    return allVideos;
  }

  /// 递归收集视频文件的内部实现
  /// [folderId] 文件夹ID
  /// [allVideos] 收集到的视频文件列表
  /// [visitedFolders] 已访问的文件夹集合（防止循环）
  /// [totalCount] 当前计数（未使用，保留参数兼容性）
  /// [requestCount] 请求计数器，用于控制风控
  /// [onProgress] 进度回调
  /// [onFound] 发现文件时的回调，返回 false 停止收集
  /// [onRateLimit] 触发风控时的回调，返回 true 等待后重试，false 直接停止
  Future<void> _collectVideosRecursive(
    String folderId,
    List<Cloud115FileInfo> allVideos,
    Set<String> visitedFolders,
    int totalCount, {
    int requestCount = 0,
    void Function(int current, int total, String folderName)? onProgress,
    bool Function(Cloud115FileInfo)? onFound,
    Future<bool> Function(int count)? onRateLimit,
  }) async {
    if (visitedFolders.contains(folderId)) {
      if (kDebugMode) print('[Cloud115] 文件夹已访问，跳过: $folderId');
      return;
    }
    visitedFolders.add(folderId);

    // 风控阈值：每 200 个请求触发一次检查
    const int rateLimitThreshold = 200;

    try {
      if (kDebugMode) print('[Cloud115] 递归扫描文件夹: $folderId (请求计数: $requestCount)');

      // 检查是否需要暂停以避免风控
      if (requestCount > 0 && requestCount % rateLimitThreshold == 0) {
        if (kDebugMode) print('[Cloud115] 已发送 $requestCount 个请求，暂停以防风控...');
        if (onRateLimit != null) {
          final shouldContinue = await onRateLimit(requestCount);
          if (!shouldContinue) {
            if (kDebugMode) print('[Cloud115] 用户选择停止扫描');
            return;
          }
        }
        // 暂停 5 秒
        await Future.delayed(const Duration(seconds: 5));
      }

      final files = await _service.listFiles(cid: folderId);
      requestCount++;

      if (kDebugMode) {
        final fileCount = files.length;
        final folderCount = files.where((f) => !f.isFile).length;
        final videoCount = files.where((f) => f.isFile && f.isVideo).length;
        print('[Cloud115] 文件夹 $folderId: 共 $fileCount 项，$folderCount 个子文件夹，$videoCount 个视频文件');
      }

      for (final file in files) {
        // 检查是否要继续
        if (onFound != null && !onFound(file)) {
          if (kDebugMode) print('[Cloud115] 用户停止收集');
          return; // 停止收集
        }

        if (file.isFile) {
          if (file.isVideo) {
            allVideos.add(file);
            totalCount++;
            if (kDebugMode) print('[Cloud115] 找到视频: ${file.name}');
            if (onProgress != null) {
              onProgress(totalCount, allVideos.length, file.name);
            }
          }
        } else {
          // 是文件夹，递归处理
          if (kDebugMode) print('[Cloud115] 进入子文件夹: ${file.name} (${file.fileId})');
          // 增加限流延迟：300ms
          await Future.delayed(const Duration(milliseconds: 300));
          await _collectVideosRecursive(
            file.fileId,
            allVideos,
            visitedFolders,
            totalCount,
            requestCount: requestCount,
            onProgress: onProgress,
            onFound: onFound,
            onRateLimit: onRateLimit,
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('[Cloud115] 递归获取文件夹失败 [$folderId]: $e');
      }
      // 检查是否是风控错误（405 或认证失败）
      if (e.toString().contains('405') || e.toString().contains('401') || e.toString().contains('403')) {
        if (onRateLimit != null) {
          if (kDebugMode) print('[Cloud115] 可能触发风控，询问用户是否继续...');
          final shouldContinue = await onRateLimit(requestCount);
          if (!shouldContinue) {
            return;
          }
          // 等待更长时间后重试
          await Future.delayed(const Duration(seconds: 10));
          // 重试当前文件夹
          await _collectVideosRecursive(
            folderId,
            allVideos,
            visitedFolders,
            totalCount,
            requestCount: requestCount,
            onProgress: onProgress,
            onFound: onFound,
            onRateLimit: onRateLimit,
          );
        }
      }
    }
  }
}

import 'package:flutter/foundation.dart';
import '../models/jellyfin.dart';
import '../services/jellyfin_service.dart';

/// Jellyfin 状态
enum JellyfinStatus {
  initial,
  connecting,
  connected,
  disconnected,
  localOnly,   // 新增：仅本地数据（未连接服务器但有本地缓存）
  error,
  loading,
  importing,
}

/// Jellyfin 状态管理
class JellyfinProvider extends ChangeNotifier {
  final JellyfinService _service;

  JellyfinStatus _status = JellyfinStatus.initial;
  String? _errorMessage;

  // 服务器信息
  String? _serverUrl;
  String? _userId;

  // 库列表
  List<JellyfinLibrary> _libraries = [];
  List<ImportedLibrary> _importedLibraries = [];

  // 电影列表
  List<JellyfinMovie> _movies = [];
  int _totalMoviesCount = 0;
  int _currentMoviePage = 0;
  final int _pageSize = 50;

  // 搜索
  String _searchTerm = '';

  // 当前选择的库
  String? _selectedLibraryId;

  // 导入进度
  int _importProgress = 0;
  int _importTotal = 0;
  ImportResult? _lastImportResult;

  JellyfinProvider({JellyfinService? service})
      : _service = service ?? JellyfinService();

  // Getters
  JellyfinStatus get status => _status;
  String? get errorMessage => _errorMessage;
  String? get serverUrl => _serverUrl;
  String? get userId => _userId;
  JellyfinService get service => _service;
  List<JellyfinLibrary> get libraries => _libraries;
  List<ImportedLibrary> get importedLibraries => _importedLibraries;
  List<JellyfinMovie> get movies => _movies;
  int get totalMoviesCount => _totalMoviesCount;
  int get currentMoviePage => _currentMoviePage;
  String get searchTerm => _searchTerm;
  String? get selectedLibraryId => _selectedLibraryId;
  int get importProgress => _importProgress;
  int get importTotal => _importTotal;
  ImportResult? get lastImportResult => _lastImportResult;

  bool get isConnected => _status == JellyfinStatus.connected;
  bool get isLoading => _status == JellyfinStatus.loading;
  bool get isImporting => _status == JellyfinStatus.importing;
  bool get hasError => _status == JellyfinStatus.error;
  bool get hasMoreMovies => _movies.length < _totalMoviesCount;

  /// 初始化
  Future<void> initialize() async {
    _status = JellyfinStatus.loading;
    notifyListeners();

    try {
      await _service.initialize();

      if (_service.isConnected) {
        _serverUrl = _service.serverUrl;
        _status = JellyfinStatus.connected;
      } else {
        _status = JellyfinStatus.disconnected;
      }

      // 加载已导入的库
      await loadImportedLibraries();
    } catch (e) {
      _status = JellyfinStatus.error;
      _errorMessage = e.toString();
    }

    notifyListeners();
  }

  /// 连接到服务器
  Future<bool> connect({
    required String serverUrl,
    String? apiKey,
    String? username,
    String? password,
  }) async {
    _status = JellyfinStatus.connecting;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _service.connect(
        serverUrl: serverUrl,
        apiKey: apiKey,
        username: username,
        password: password,
      );

      if (result) {
        _serverUrl = _service.serverUrl;
        _status = JellyfinStatus.connected;
        notifyListeners();
        return true;
      } else {
        _status = JellyfinStatus.error;
        _errorMessage = '连接失败';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _status = JellyfinStatus.error;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// 断开连接
  Future<void> disconnect() async {
    _service.disconnect();
    _status = JellyfinStatus.disconnected;
    _serverUrl = null;
    _userId = null;
    _libraries = [];
    _movies = [];
    _selectedLibraryId = null;
    notifyListeners();
  }

  /// 加载可用的库列表
  Future<void> loadLibraries() async {
    if (!isConnected) return;

    _status = JellyfinStatus.loading;
    notifyListeners();

    try {
      _libraries = await _service.getLibraries();
      _status = JellyfinStatus.connected;
    } catch (e) {
      _errorMessage = e.toString();
      _status = JellyfinStatus.error;
    }

    notifyListeners();
  }

  /// 加载已导入的库列表
  Future<void> loadImportedLibraries() async {
    try {
      _importedLibraries = await _service.getImportedLibraries();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('[JellyfinProvider] 加载已导入库列表失败: $e');
      }
    }
  }

  /// 选择库
  void selectLibrary(String? libraryId) {
    _selectedLibraryId = libraryId;
    _movies = [];
    _currentMoviePage = 0;
    _totalMoviesCount = 0;
    _searchTerm = '';
    notifyListeners();
  }

  /// 加载电影列表
  Future<void> loadMovies({bool loadMore = false}) async {
    if (!loadMore) {
      _currentMoviePage = 0;
      _movies = [];
    }

    // 如果既未连接也没有本地数据，直接返回
    if (!isConnected && _importedLibraries.isEmpty) return;

    // 如果未连接但有本地数据，使用本地数据状态
    final wasDisconnected = !isConnected;
    _status = JellyfinStatus.loading;
    notifyListeners();

    try {
      final newMovies = await _service.getLibraryMovies(
        libraryId: _selectedLibraryId,
        start: _currentMoviePage * _pageSize,
        limit: _pageSize,
        searchTerm: _searchTerm.isNotEmpty ? _searchTerm : null,
      );

      _totalMoviesCount = await _service.getLibraryMoviesCount(
        libraryId: _selectedLibraryId,
        searchTerm: _searchTerm.isNotEmpty ? _searchTerm : null,
      );

      if (loadMore) {
        _movies.addAll(newMovies);
      } else {
        _movies = newMovies;
      }

      _currentMoviePage++;
      // 如果原本是断开连接状态，加载本地数据后设为 localOnly
      _status = wasDisconnected ? JellyfinStatus.localOnly : JellyfinStatus.connected;
    } catch (e) {
      _errorMessage = e.toString();
      _status = JellyfinStatus.error;
    }

    notifyListeners();
  }

  /// 搜索
  Future<void> search(String term) async {
    if (_searchTerm == term) return;

    _searchTerm = term;
    _currentMoviePage = 0;
    _movies = [];
    _totalMoviesCount = 0;
    notifyListeners();

    if (term.isNotEmpty) {
      await loadMovies();
    }
  }

  /// 清除搜索
  void clearSearch() {
    _searchTerm = '';
    _currentMoviePage = 0;
    _movies = [];
    _totalMoviesCount = 0;
    notifyListeners();
  }

  /// 导入库
  Future<void> importLibrary(JellyfinLibrary library) async {
    _status = JellyfinStatus.importing;
    _importProgress = 0;
    _importTotal = 0;
    _lastImportResult = null;
    notifyListeners();

    try {
      final result = await _service.importLibrary(
        libraryId: library.id,
        libraryName: library.name,
        onProgress: (current, total) {
          _importProgress = current;
          _importTotal = total;
          notifyListeners();
        },
      );

      _lastImportResult = result;
      _status = JellyfinStatus.connected;

      // 重新加载已导入的库列表
      await loadImportedLibraries();
    } catch (e) {
      _errorMessage = e.toString();
      _status = JellyfinStatus.error;
      _lastImportResult = ImportResult(
        failed: 1,
        message: e.toString(),
      );
    }

    notifyListeners();
  }

  /// 增量同步库
  Future<void> syncLibraryIncremental(JellyfinLibrary library) async {
    _status = JellyfinStatus.importing;
    _importProgress = 0;
    _importTotal = 0;
    _lastImportResult = null;
    notifyListeners();

    try {
      final result = await _service.syncLibraryIncremental(
        libraryId: library.id,
        libraryName: library.name,
        onProgress: (current, total) {
          _importProgress = current;
          _importTotal = total;
          notifyListeners();
        },
      );

      _lastImportResult = result;
      _status = JellyfinStatus.connected;

      // 如果需要全量导入
      if (result.needsFullImport) {
        await importLibrary(library);
        return;
      }

      // 刷新当前电影列表
      if (_selectedLibraryId == library.id) {
        await loadMovies();
      }
    } catch (e) {
      _errorMessage = e.toString();
      _status = JellyfinStatus.error;
      _lastImportResult = ImportResult(
        failed: 1,
        message: e.toString(),
      );
    }

    notifyListeners();
  }

  /// 删除导入的库
  Future<void> deleteLibrary(String libraryId) async {
    try {
      await _service.deleteLibrary(libraryId);
      await loadImportedLibraries();

      if (_selectedLibraryId == libraryId) {
        _movies = [];
        _totalMoviesCount = 0;
        _selectedLibraryId = null;
      }
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      _status = JellyfinStatus.error;
      notifyListeners();
    }
  }

  /// 根据 video_id 查找电影
  Future<List<JellyfinMovie>> findMoviesByVideoId(String videoId) async {
    return await _service.findMoviesByVideoId(videoId);
  }

  /// 根据 item_id 从 API 获取影片详情（按需获取元数据）
  /// 返回包含完整信息的 JellyfinMovie，包括 overview, genres 等
  Future<JellyfinMovie?> fetchMovieDetails(String itemId) async {
    if (!isConnected) return null;

    try {
      final metadata = await _service.getItemMetadata(itemId);
      if (metadata == null) return null;

      // 从本地数据库获取基本信息（library_id 等）
      final localMovie = await _service.getMovieByItemId(itemId);

      // 使用 API 数据解析
      final libraryId = localMovie?.libraryId ?? '';
      final libraryName = localMovie?.libraryName ?? '';
      return _service.parseJellyfinItem(metadata, libraryId, libraryName);
    } catch (e) {
      if (kDebugMode) {
        print('[JellyfinProvider] 获取影片详情失败: $e');
      }
      return null;
    }
  }

  /// 更新播放计数
  Future<void> updatePlayCount(String itemId) async {
    await _service.updatePlayCount(itemId);
  }

  /// 清除错误
  void clearError() {
    _errorMessage = null;
    if (_status == JellyfinStatus.error) {
      _status = isConnected ? JellyfinStatus.connected : JellyfinStatus.initial;
    }
    notifyListeners();
  }

  /// 重置状态
  void reset() {
    _status = JellyfinStatus.initial;
    _errorMessage = null;
    _libraries = [];
    _importedLibraries = [];
    _movies = [];
    _totalMoviesCount = 0;
    _currentMoviePage = 0;
    _searchTerm = '';
    _selectedLibraryId = null;
    _importProgress = 0;
    _importTotal = 0;
    _lastImportResult = null;
    notifyListeners();
  }
}

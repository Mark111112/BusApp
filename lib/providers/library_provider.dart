import 'package:flutter/foundation.dart';
import '../models/jellyfin.dart';
import '../models/sort_option.dart';
import '../models/unified_library_item.dart' as ui;
import '../repositories/unified_library_repository.dart';
import '../services/unified_library_sync_service.dart';
import '../repositories/jellyfin_repository.dart';
import 'jellyfin_provider.dart';
import 'cloud115_provider.dart';

/// 媒体库信息
class MediaLibrary {
  final String id;       // 库 ID
  final String name;     // 库名称
  final ui.MediaSource source; // 来源
  final int itemCount;  // 项目数量

  MediaLibrary({
    required this.id,
    required this.name,
    required this.source,
    this.itemCount = 0,
  });

  factory MediaLibrary.from115({int itemCount = 0}) {
    return MediaLibrary(
      id: 'cloud115',
      name: '115库',
      source: ui.MediaSource.cloud115,
      itemCount: itemCount,
    );
  }

  factory MediaLibrary.fromJellyfinLibrary(ImportedLibrary library) {
    return MediaLibrary(
      id: library.id,
      name: library.name,
      source: ui.MediaSource.jellyfin,
      itemCount: library.itemCount,
    );
  }
}

/// 统一的媒体库 Provider - 使用 unified_library 表
class LibraryProvider extends ChangeNotifier {
  final UnifiedLibraryRepository _unifiedRepo;
  final UnifiedLibrarySyncService _syncService;
  final JellyfinRepository _jellyfinRepo;

  Cloud115Provider? _cloud115Provider;
  JellyfinProvider? _jellyfinProvider;
  bool _isInitialized = false;

  LibraryProvider({
    UnifiedLibraryRepository? unifiedRepo,
    UnifiedLibrarySyncService? syncService,
    JellyfinRepository? jellyfinRepo,
    Cloud115Provider? cloud115Provider,
    JellyfinProvider? jellyfinProvider,
  }) : _unifiedRepo = unifiedRepo ?? UnifiedLibraryRepository(),
       _syncService = syncService ?? UnifiedLibrarySyncService(),
       _jellyfinRepo = jellyfinRepo ?? JellyfinRepository(),
       _cloud115Provider = cloud115Provider,
       _jellyfinProvider = jellyfinProvider {
    if (_jellyfinProvider != null || _cloud115Provider != null) {
      initialize();
    }
  }

  /// 设置 Cloud115Provider
  void setCloud115Provider(Cloud115Provider? cloud115) {
    _cloud115Provider = cloud115;
  }

  /// 设置 JellyfinProvider
  void setJellyfinProvider(JellyfinProvider? jellyfin) {
    final wasNull = _jellyfinProvider == null;
    _jellyfinProvider = jellyfin;
    if (wasNull && jellyfin != null && !_isInitialized) {
      initialize();
    }
  }

  // 所有项目（从 unified_library 表加载）
  final List<ui.UnifiedLibraryItem> _allItems = [];

  // 当前显示的项目
  List<ui.UnifiedLibraryItem> _displayItems = [];

  // 所有库列表
  List<MediaLibrary> _libraries = [];

  // 当前选中的库 ID (null 表示全部)
  String? _selectedLibraryId;

  // 搜索关键词
  String _searchTerm = '';

  // 排序选项
  SortOption _sortOption = const SortOption(field: SortField.dateAdded);

  // 加载状态
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _isSyncing = false;
  String? _errorMessage;

  // 分页状态
  int _currentPage = 0;
  static const int _pageSize = 50;
  bool _hasMore = false;

  // Getters
  List<ui.UnifiedLibraryItem> get displayItems => _displayItems;
  List<MediaLibrary> get libraries => _libraries;
  String? get selectedLibraryId => _selectedLibraryId;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get isSyncing => _isSyncing;
  bool get hasMore => _hasMore;
  String? get errorMessage => _errorMessage;
  SortOption get sortOption => _sortOption;

  /// 是否已初始化
  bool get isInitialized => _isInitialized;

  /// 总项目数
  int get totalCount => _allItems.length;

  /// 设置排序选项并重新加载
  Future<void> setSortOption(SortOption option) async {
    if (_sortOption == option) return;
    _sortOption = option;
    // 清空当前数据并重新加载，以应用新的排序
    _allItems.clear();
    _currentPage = 0;
    await _loadInitialData();
    notifyListeners();
  }

  /// 初始化 - 加载数据（不同步，除非表为空）
  Future<void> initialize({bool forceSync = false}) async {
    if (_isInitialized) {
      notifyListeners();
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      // 检查 unified_library 表是否有数据
      final stats = await _unifiedRepo.getStatistics();
      final hasData = (stats['total'] ?? 0) > 0;

      // 只在表为空或强制同步时才同步数据
      if (!hasData || forceSync) {
        await syncData();
      }

      // 加载数据
      await _loadInitialData();

      // 更新库列表
      await _updateLibrariesList();

      _isInitialized = true;
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 同步数据到 unified_library 表
  Future<void> syncData({void Function(int, int, String)? onProgress}) async {
    _isSyncing = true;
    notifyListeners();

    try {
      await _syncService.syncAll(onProgress: onProgress);
    } catch (e) {
      rethrow;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// 加载初始数据
  Future<void> _loadInitialData() async {
    _currentPage = 0;
    await _loadMoreItems();
  }

  /// 加载更多数据
  Future<void> loadMore() async {
    if (_isLoadingMore || !_hasMore) return;

    _isLoadingMore = true;
    notifyListeners();

    try {
      await _loadMoreItems();
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  /// 从数据库加载更多项目
  Future<void> _loadMoreItems() async {
    final orderBy = _getOrderByClause();
    final offset = _currentPage * _pageSize;

    List<ui.UnifiedLibraryItem> items;

    if (_selectedLibraryId == null) {
      // 全部
      if (_searchTerm.isEmpty) {
        items = await _unifiedRepo.getAll(
          orderBy: orderBy,
          limit: _pageSize,
          offset: offset,
        );
      } else {
        items = await _unifiedRepo.search(
          keyword: _searchTerm,
          orderBy: orderBy,
          limit: _pageSize,
          offset: offset,
        );
      }
    } else if (_selectedLibraryId == 'cloud115') {
      // 115 库
      items = await _unifiedRepo.search(
        source: 'cloud115',
        keyword: _searchTerm.isEmpty ? null : _searchTerm,
        orderBy: orderBy,
        limit: _pageSize,
        offset: offset,
      );
    } else {
      // Jellyfin 库 - 传递 libraryId 参数以便在 SQL 中筛选
      items = await _unifiedRepo.search(
        source: 'jellyfin',
        libraryId: _selectedLibraryId,
        keyword: _searchTerm.isEmpty ? null : _searchTerm,
        orderBy: orderBy,
        limit: _pageSize,
        offset: offset,
      );
    }

    _allItems.addAll(items);
    _currentPage++;
    _hasMore = items.length >= _pageSize;

    await _applyFilter();
  }

  /// 获取排序子句
  String _getOrderByClause() {
    return _sortOption.getOrderByClause();
  }

  /// 选择库
  Future<void> selectLibrary(String? libraryId) async {
    if (_selectedLibraryId == libraryId) return;

    _selectedLibraryId = libraryId;
    _allItems.clear();
    _currentPage = 0;

    await _loadInitialData();
    notifyListeners();
  }

  /// 搜索
  Future<void> search(String term) async {
    if (_searchTerm == term) return;

    _searchTerm = term;
    _allItems.clear();
    _currentPage = 0;

    await _loadInitialData();
    notifyListeners();
  }

  /// 清除搜索
  Future<void> clearSearch() async {
    await search('');
  }

  /// 应用筛选
  Future<void> _applyFilter() async {
    _displayItems = _allItems;

    // 应用来源筛选
    // 注意：当选择 Jellyfin 库时，SQL 已经按 libraryId 筛选了，这里不需要再筛选
    if (_selectedLibraryId == 'cloud115') {
      _displayItems = _displayItems.where((item) => item.hasCloud115).toList();
    }

    notifyListeners();
  }

  /// 更新库列表
  Future<void> _updateLibrariesList() async {
    _libraries = [];

    // 添加 115 库
    final stats = await _unifiedRepo.getStatistics();
    if (stats['withCloud115'] != null && stats['withCloud115']! > 0) {
      _libraries.add(MediaLibrary.from115(itemCount: stats['withCloud115']!));
    }

    // 添加 Jellyfin 库
    final jfLibs = await _jellyfinRepo.getImportedLibraries();
    for (final lib in jfLibs) {
      _libraries.add(MediaLibrary.fromJellyfinLibrary(lib));
    }
  }

  /// 刷新（强制同步数据）
  Future<void> refresh() async {
    _allItems.clear();
    _currentPage = 0;
    _isInitialized = false;
    await initialize(forceSync: true);
  }

  /// 根据 videoId 查找项目
  Future<List<ui.UnifiedLibraryItem>> findItemsByVideoId(String videoId) async {
    final item = await _unifiedRepo.getByVideoId(videoId);
    if (item != null) {
      return [item];
    }

    // Fallback: 在已加载的项目中查找
    return _allItems.where((item) => item.unifiedId == videoId).toList();
  }

  /// 根据 unifiedId 获取项目
  Future<ui.UnifiedLibraryItem?> getByUnifiedId(String unifiedId) async {
    // 先在已加载的项目中查找
    final cached = _allItems.cast<ui.UnifiedLibraryItem?>().firstWhere(
      (item) => item?.unifiedId == unifiedId,
      orElse: () => null,
    );
    if (cached != null) return cached;

    // 从数据库查找
    return await _unifiedRepo.getByUnifiedId(unifiedId);
  }

  /// 获取播放信息
  Future<Map<String, dynamic>?> getPlayInfo(ui.UnifiedLibraryItem item) async {
    // 优先使用 Jellyfin
    final jellyfinSource = item.jellyfinSources.firstOrNull;
    if (jellyfinSource != null && jellyfinSource.itemId != null) {
      final movie = await _jellyfinRepo.getMovieByItemId(jellyfinSource.itemId!);
      if (movie?.playUrl != null && movie!.playUrl!.isNotEmpty) {
        return {
          'url': movie.playUrl,
          'title': movie.title,
          'isLocal': false,
          'itemId': movie.itemId,
        };
      }
    }

    // 使用 115
    final cloud115Source = item.cloud115Sources.firstOrNull;
    if (cloud115Source != null && cloud115Source.pickcode != null && _cloud115Provider != null) {
      final playInfo = await _cloud115Provider!.getPlayInfoByPickCode(cloud115Source.pickcode!);
      return playInfo;
    }

    return null;
  }

  /// 更新播放计数
  Future<void> updatePlayCount(String unifiedId) async {
    await _unifiedRepo.updatePlayCount(unifiedId);

    // 更新本地缓存
    final item = _allItems.cast<ui.UnifiedLibraryItem?>().firstWhere(
      (i) => i?.unifiedId == unifiedId,
      orElse: () => null,
    );
    if (item != null) {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      // 创建新实例（因为是不可变的）
      final index = _allItems.indexOf(item);
      _allItems[index] = ui.UnifiedLibraryItem(
        id: item.id,
        unifiedId: item.unifiedId,
        title: item.title,
        coverImage: item.coverImage,
        actors: item.actors,
        date: item.date,
        duration: item.duration,
        description: item.description,
        sources: item.sources,
        playCount: item.playCount + 1,
        lastPlayed: now,
        dateAdded: item.dateAdded,
        createdAt: item.createdAt,
        updatedAt: now,
      );
      await _applyFilter();
    }
  }
}

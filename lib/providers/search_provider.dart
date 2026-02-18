import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../models/search_result.dart';
import '../services/services.dart';

/// 搜索状态
enum SearchStatus { initial, searching, results, error, loadingMore }

/// 搜索提供者
class SearchProvider extends ChangeNotifier {
  final ScraperService _scraperService;
  final JavBusService _javBusService;

  SearchProvider({
    ScraperService? scraperService,
    JavBusService? javBusService,
  })  : _scraperService = scraperService ?? ScraperService(),
        _javBusService = javBusService ?? JavBusService();

  SearchStatus _status = SearchStatus.initial;
  List<SearchResultItem> _results = [];
  String? _errorMessage;

  // 分页状态
  String? _currentQuery;
  int _currentPage = 1;
  bool _hasNextPage = false;
  bool _isShowingLatest = false; // 是否正在显示最新影片

  // 开关状态
  bool _isUncensored = false; // 无码搜索
  bool _includeNoMagnets = false; // 包括无磁力影片

  // 磁力状态缓存 (movieId -> hasMagnets)
  final Map<String, bool> _magnetStatusCache = {};

  SearchStatus get status => _status;
  List<SearchResultItem> get results => _results;
  String? get errorMessage => _errorMessage;
  bool get isSearching => _status == SearchStatus.searching;
  bool get isLoadingMore => _status == SearchStatus.loadingMore;
  bool get hasResults => _results.isNotEmpty;
  bool get hasError => _status == SearchStatus.error;
  bool get isShowingLatest => _isShowingLatest;

  /// 是否有更多结果
  bool get hasNextPage => _hasNextPage;

  /// 总结果数
  int get resultCount => _results.length;

  /// 无码搜索开关
  bool get isUncensored => _isUncensored;
  set isUncensored(bool value) {
    if (_isUncensored != value) {
      _isUncensored = value;
      notifyListeners();
    }
  }

  /// 包括无磁力影片开关
  bool get includeNoMagnets => _includeNoMagnets;
  set includeNoMagnets(bool value) {
    if (_includeNoMagnets != value) {
      _includeNoMagnets = value;
      notifyListeners();
    }
  }

  /// 设置影片的磁力状态（从详情页调用）
  void setMagnetStatus(String movieId, bool hasMagnets) {
    _magnetStatusCache[movieId] = hasMagnets;
    notifyListeners();
  }

  /// 获取影片的磁力状态
  bool? getMagnetStatus(String movieId) {
    return _magnetStatusCache[movieId];
  }

  /// 获取过滤后的结果列表
  List<SearchResultItem> get filteredResults {
    if (!_includeNoMagnets) {
      // 不包括无磁力影片：过滤掉已知没有磁力的影片
      return _results.where((item) {
        final status = _magnetStatusCache[item.id];
        // 如果未知或已知有磁力，显示
        return status == null || status == true;
      }).toList();
    }
    // 包括所有影片
    return _results;
  }

  /// 搜索（空搜索显示最新影片）
  Future<void> search(String query) async {
    if (kDebugMode) print('SearchProvider.search 被调用, query: "$query", uncensored: $_isUncensored');

    _status = SearchStatus.searching;
    _errorMessage = null;
    _currentQuery = query;
    _currentPage = 1;
    _results = [];
    _isShowingLatest = query.trim().isEmpty;
    notifyListeners();

    try {
      SearchPagedResult pagedResult;

      if (query.trim().isEmpty) {
        // 空搜索：显示最新影片
        if (kDebugMode) print('开始获取最新影片...');
        pagedResult = await _javBusService.getLatestMovies(
          page: 1,
          uncensored: _isUncensored,
        );
      } else {
        // 关键词搜索
        if (kDebugMode) print('开始 JavBus 搜索...');
        pagedResult = await _javBusService.search(
          query,
          page: 1,
          uncensored: _isUncensored,
        );
      }

      if (kDebugMode) print('完成, 结果数: ${pagedResult.itemCount}');

      _results = pagedResult.items;
      _currentPage = pagedResult.currentPage;
      _hasNextPage = pagedResult.hasNextPage;
      _status = SearchStatus.results;
    } catch (e) {
      if (kDebugMode) print('失败: $e');
      _status = SearchStatus.error;
      _errorMessage = e.toString();
      _hasNextPage = false;
      _isShowingLatest = false;
    }

    notifyListeners();
  }

  /// 加载更多结果
  Future<void> loadMore() async {
    if (_hasNextPage == false || isLoadingMore || isSearching) {
      return;
    }

    if (kDebugMode) print('SearchProvider.loadMore 被调用, page: ${_currentPage + 1}');

    _status = SearchStatus.loadingMore;
    notifyListeners();

    try {
      final nextPage = _currentPage + 1;
      SearchPagedResult pagedResult;

      if (_isShowingLatest) {
        // 加载更多最新影片
        pagedResult = await _javBusService.getLatestMovies(
          page: nextPage,
          uncensored: _isUncensored,
        );
      } else {
        // 加载更多搜索结果
        pagedResult = await _javBusService.search(
          _currentQuery!,
          page: nextPage,
          uncensored: _isUncensored,
        );
      }

      if (kDebugMode) print('加载更多完成, 新结果数: ${pagedResult.itemCount}');

      _results.addAll(pagedResult.items);
      _currentPage = pagedResult.currentPage;
      _hasNextPage = pagedResult.hasNextPage;
      _status = SearchStatus.results;
    } catch (e) {
      if (kDebugMode) print('加载更多失败: $e');
      _status = SearchStatus.results;
      _errorMessage = e.toString();
    }

    notifyListeners();
  }

  /// 切换无码/有码并重新搜索
  Future<void> toggleUncensored() async {
    _isUncensored = !_isUncensored;
    notifyListeners();

    // 如果有当前搜索词，重新搜索
    if (_currentQuery != null) {
      await search(_currentQuery!);
    }
  }

  /// 清空结果
  void clear() {
    _results = [];
    _status = SearchStatus.initial;
    _errorMessage = null;
    _currentQuery = null;
    _currentPage = 1;
    _hasNextPage = false;
    _isShowingLatest = false;
    notifyListeners();
  }
}

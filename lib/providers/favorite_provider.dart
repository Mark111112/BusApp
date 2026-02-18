import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../models/models.dart';
import '../repositories/repositories.dart';

/// 收藏提供者
class FavoriteProvider extends ChangeNotifier {
  final FavoriteRepository _repository;
  final MovieRepository _movieRepository;

  FavoriteProvider({
    FavoriteRepository? repository,
    MovieRepository? movieRepository,
  })  : _repository = repository ?? FavoriteRepository(),
        _movieRepository = movieRepository ?? MovieRepository();

  Set<String> _favoriteIds = {};
  bool _isLoading = false;
  bool _isLoadingMovies = false;
  List<Movie> _movies = [];
  String? _errorMessage;
  SortOption _sortOption = const SortOption(field: SortField.dateAdded);

  Set<String> get favoriteIds => _favoriteIds;
  bool get isLoading => _isLoading;
  bool get isLoadingMovies => _isLoadingMovies;
  List<Movie> get movies => _movies;
  String? get errorMessage => _errorMessage;
  int get count => _favoriteIds.length;
  SortOption get sortOption => _sortOption;

  /// 待缓存的影片详情（收藏时保存）
  final Map<String, Movie> _pendingMovieCache = {};

  /// 设置排序选项
  void setSortOption(SortOption option) {
    _sortOption = option;
    notifyListeners();
  }

  /// 加载收藏列表
  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final favorites = await _repository.getFavorites(sortBy: _sortOption);
      _favoriteIds = favorites.toSet();
      if (kDebugMode) {
        print('[FavoriteProvider] load: 加载了 ${_favoriteIds.length} 个收藏 ID: $_favoriteIds');
      }
    } catch (e) {
      _favoriteIds = {};
      if (kDebugMode) {
        print('[FavoriteProvider] load: 出错 - $e');
      }
    }

    _isLoading = false;
    // 使用 scheduleMicrotask 避免在 build 阶段调用 notifyListeners
    scheduleMicrotask(() {
      notifyListeners();
    });
  }

  /// 加载收藏的影片详情
  Future<void> loadMovies() async {
    _isLoadingMovies = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final movies = <Movie>[];
      if (kDebugMode) {
        print('[FavoriteProvider] loadMovies: 开始加载 ${_favoriteIds.length} 个收藏影片');
      }
      for (final id in _favoriteIds) {
        final movie = await _movieRepository.getMovie(id);
        if (kDebugMode) {
          print('[FavoriteProvider] loadMovies: $id - ${movie != null ? "找到" : "未找到"}');
        }
        if (movie != null) {
          movies.add(movie);
        }
      }

      // 根据排序选项排序
      _movies = _sortMovies(movies, _sortOption);
      if (kDebugMode) {
        print('[FavoriteProvider] loadMovies: 完成，加载了 ${movies.length} 部影片');
      }
    } catch (e) {
      _errorMessage = e.toString();
      _movies = [];
      if (kDebugMode) {
        print('[FavoriteProvider] loadMovies: 出错 - $e');
      }
    }

    _isLoadingMovies = false;
    notifyListeners();
  }

  /// 根据排序选项对影片列表进行排序
  List<Movie> _sortMovies(List<Movie> movies, SortOption sortOption) {
    var sorted = List<Movie>.from(movies);

    switch (sortOption.field) {
      case SortField.dateAdded:
        // 由于已经按收藏时间顺序获取 ID 列表，这里保持原顺序
        // 降序 = 最新收藏在前（已经是这样了）
        if (sortOption.direction == SortDirection.ascending) {
          sorted.sort((a, b) => a.id.compareTo(b.id)); // 反转
        }
        break;
      case SortField.videoId:
        sorted.sort((a, b) => a.id.compareTo(b.id));
        if (sortOption.direction == SortDirection.descending) {
          sorted = sorted.reversed.toList();
        }
        break;
      case SortField.title:
        sorted.sort((a, b) => (a.title ?? a.id).compareTo(b.title ?? b.id));
        if (sortOption.direction == SortDirection.descending) {
          sorted = sorted.reversed.toList();
        }
        break;
      case SortField.date:
        sorted.sort((a, b) {
          final aDate = a.date ?? '';
          final bDate = b.date ?? '';
          return aDate.compareTo(bDate);
        });
        if (sortOption.direction == SortDirection.descending) {
          sorted = sorted.reversed.toList();
        }
        break;
      case SortField.random:
        sorted.shuffle();
        break;
      default:
        break;
    }

    return sorted;
  }

  /// 切换收藏状态
  /// [movie] 可选的影片对象，用于在收藏时保存详情到数据库
  Future<void> toggle(String id, {Movie? movie}) async {
    // 如果内存中的收藏列表为空，先加载一次以同步状态
    if (_favoriteIds.isEmpty) {
      await load();
    }

    // 检查是否已收藏（同时检查内存和数据库）
    final isFavInMemory = _favoriteIds.contains(id);
    final isFavInDb = await _repository.isFavorite(id);
    final isFav = isFavInMemory || isFavInDb;

    if (isFav) {
      // 取消收藏
      await _repository.removeFavorite(id);
      _favoriteIds.remove(id);
      _movies.removeWhere((m) => m.id == id);
      _pendingMovieCache.remove(id);
      if (kDebugMode) {
        print('[FavoriteProvider] 取消收藏: $id');
      }
    } else {
      // 添加收藏
      await _repository.addFavorite(id);
      _favoriteIds.add(id);
      // 如果提供了影片详情，保存到数据库
      if (movie != null) {
        await _movieRepository.saveMovie(movie);
        _pendingMovieCache[id] = movie;
        // 同时添加到列表
        _movies.insert(0, movie);
      }
      // 验证保存是否成功
      final savedMovie = await _movieRepository.getMovie(id);
      if (kDebugMode) {
        print('[FavoriteProvider] 收藏后验证: $id - ${savedMovie != null ? "成功找到" : "未找到"}');
      }
    }
    notifyListeners();
  }

  /// 设置影片缓存（用于收藏时保存详情）
  void cacheMovie(Movie movie) {
    _pendingMovieCache[movie.id] = movie;
  }

  /// 检查是否收藏
  bool isFavorite(String id) => _favoriteIds.contains(id);

  /// 检查是否收藏（异步，检查数据库）
  Future<bool> isFavoriteAsync(String id) async {
    if (_favoriteIds.contains(id)) return true;
    return await _repository.isFavorite(id);
  }

  /// 获取收藏的影片
  Future<List<Movie>> getFavoriteMovies() async {
    final movies = <Movie>[];
    for (final id in _favoriteIds) {
      final movie = await _movieRepository.getMovie(id);
      if (movie != null) {
        movies.add(movie);
      }
    }
    return movies;
  }

  /// 清空
  void clear() {
    _favoriteIds = {};
    _movies = [];
    _errorMessage = null;
    notifyListeners();
  }
}

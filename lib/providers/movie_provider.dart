import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../models/models.dart';
import '../../services/services.dart';
import '../repositories/repositories.dart';

/// 影片状态
enum MovieStatus { initial, loading, loaded, error }

/// 影片提供者
class MovieProvider extends ChangeNotifier {
  final MovieRepository _repository;
  final ScraperService _scraperService;
  final JavBusService _javBusService;

  MovieProvider({
    MovieRepository? repository,
    ScraperService? scraperService,
    JavBusService? javBusService,
  })  : _repository = repository ?? MovieRepository(),
        _scraperService = scraperService ?? ScraperService(),
        _javBusService = javBusService ?? JavBusService();

  MovieStatus _status = MovieStatus.initial;
  Movie? _movie;
  String? _errorMessage;

  MovieStatus get status => _status;
  Movie? get movie => _movie;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _status == MovieStatus.loading;
  bool get hasError => _status == MovieStatus.error;

  /// 加载影片详情
  /// 逻辑：
  /// 1. JavBus 提供主要数据（封面、演员、日期、磁力链接等）
  /// 2. 其他爬虫（TokyoHot、Heyzo 等）仅在点击"加载简介"按钮时调用
  Future<void> loadMovie(String videoId, {bool forceRefresh = false}) async {
    _status = MovieStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      // 先从本地数据库获取（除非强制刷新）
      var movie = await _repository.getMovie(videoId);

      // 如果本地没有 或 强制刷新，尝试从网络获取
      if (movie == null || forceRefresh) {
        if (kDebugMode) print('[MovieProvider] 从网络获取影片: $videoId (forceRefresh=$forceRefresh)');

        // 优先尝试 JavBus（有封面、演员、样本图片、磁力链接）
        try {
          final javbusMovie = await _javBusService.getMovieDetail(videoId);
          if (javbusMovie != null) {
            movie = javbusMovie;
            if (kDebugMode) print('[MovieProvider] JavBus 获取成功');
            // 保存 JavBus 数据（没有简介也保存）
            await _repository.saveMovie(movie);
          }
        } catch (e) {
          if (kDebugMode) print('[MovieProvider] JavBus 获取失败: $e，尝试 ScraperService');
          // JavBus 完全失败，使用 ScraperService 作为备选
          movie = await _scraperService.scrape(videoId);
          if (movie != null) {
            await _repository.saveMovie(movie);
          }
        }
      } else {
        if (kDebugMode) print('[MovieProvider] 从数据库加载影片: $videoId');
      }

      if (movie != null) {
        _movie = movie;
        _status = MovieStatus.loaded;
      } else {
        _status = MovieStatus.error;
        _errorMessage = '未找到影片';
      }
    } catch (e) {
      _status = MovieStatus.error;
      _errorMessage = e.toString();
      if (kDebugMode) print('[MovieProvider] 加载影片失败: $e');
    }

    notifyListeners();
  }

  /// 从 ScraperService 获取影片信息（根据番号特征自动选择爬虫）
  /// 用于补充 JavBus 缺失的简介或其他信息
  Future<void> loadFromScraper(String videoId) async {
    try {
      if (kDebugMode) print('[MovieProvider] 从 ScraperService 获取影片信息: $videoId');

      final scraperMovie = await _scraperService.scrape(videoId);
      if (scraperMovie != null) {
        // 合并到现有影片信息
        if (_movie != null) {
          _movie = _movie!.copyWith(
            description: _movie!.description ?? scraperMovie.description,
            title: (_movie!.title != null && _movie!.title!.isNotEmpty) ? _movie!.title : scraperMovie.title,
            date: _movie!.date ?? scraperMovie.date,
            duration: _movie!.duration ?? scraperMovie.duration,
            actors: (_movie!.actors != null && _movie!.actors!.isNotEmpty) ? _movie!.actors : scraperMovie.actors,
            samples: (_movie!.samples != null && _movie!.samples!.isNotEmpty) ? _movie!.samples : scraperMovie.samples,
          );
        } else {
          _movie = scraperMovie;
        }
        // 保存到数据库
        await _repository.saveMovie(_movie!);
        if (kDebugMode) print('[MovieProvider] ScraperService 数据已合并');
      }
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('[MovieProvider] ScraperService 获取失败: $e');
      rethrow;
    }
  }

  /// 翻译影片信息
  Future<void> translate(TranslatorService translator) async {
    if (_movie == null) return;

    try {
      // 翻译标题
      final titleTranslation = await translator.translate(_movie!.title ?? '');
      // 翻译简介
      final descriptionTranslation = await translator.translate(_movie!.description ?? '');

      _movie = _movie!.copyWith(
        translation: jsonEncode({
          'title': titleTranslation,
          'description': descriptionTranslation,
        }),
      );

      notifyListeners();
    } catch (e) {
      // 翻译失败不影响显示
    }
  }

  /// 清除状态
  void clear() {
    _movie = null;
    _status = MovieStatus.initial;
    _errorMessage = null;
    notifyListeners();
  }
}

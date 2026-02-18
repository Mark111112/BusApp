import 'package:flutter/foundation.dart';
import 'scrapers/base_scraper.dart';
import 'scrapers/scrapers.dart';
import 'scrapers/video_id_matcher.dart';
import '../models/models.dart';

/// 爬虫服务
/// 移植自 moviescraper.py
class ScraperService {
  final Map<String, BaseScraper> _scrapers = {};

  ScraperService() {
    // 注册爬虫
    _scrapers['fanza'] = FanzaScraper();
    _scrapers['dmm'] = FanzaScraper(); // DMM 复用 Fanza
    _scrapers['heyzo'] = HeyzoScraper();
    _scrapers['caribbean'] = CaribbeanScraper();
    // 新增爬虫
    _scrapers['musume'] = MusumeScraper();
    _scrapers['1pondo'] = OnePondoScraper();
    _scrapers['pacopacomama'] = PacopacomamaScraper();
    _scrapers['kin8tengoku'] = Kin8tengokuScraper();
    _scrapers['tokyohot'] = TokyoHotScraper();
  }

  /// 识别番号并获取爬虫
  VideoIdMatch identify(String videoId) {
    return VideoIdMatcher.identify(videoId);
  }

  /// 刮削影片信息（别名方法）
  Future<Movie?> scrape(String videoId) async {
    return getMovieInfo(videoId);
  }

  /// 获取影片信息
  Future<Movie?> getMovieInfo(String videoId) async {
    try {
      if (kDebugMode) {
        print('[ScraperService] ========== 开始获取影片信息: $videoId ==========');
      }

      final match = identify(videoId);
      final scraperType = VideoIdMatcher.getScraperType(match.type);

      if (kDebugMode) {
        print('[ScraperService] 番号: $videoId');
        print('[ScraperService] 识别类型: ${match.type}');
        print('[ScraperService] 爬虫类型: $scraperType');
      }

      final scraper = _scrapers[scraperType];
      if (scraper == null) {
        if (kDebugMode) print('[ScraperService] 错误: 未找到爬虫 $scraperType');
        throw ScraperException('不支持的番号类型: $scraperType');
      }

      if (kDebugMode) print('[ScraperService] 使用爬虫: ${scraper.runtimeType}');

      // 特殊处理 1pondo/pacopacomama
      if (match.type == VideoIdType.onePondo) {
        // 先尝试 1pondo
        try {
          if (kDebugMode) print('[ScraperService] 尝试 1Pondo...');
          final result = await _scrapers['1pondo']?.getMovieInfo(videoId);
          if (result != null) {
            if (kDebugMode) print('[ScraperService] 1Pondo 成功');
            return result;
          }
        } catch (e) {
          if (kDebugMode) print('[ScraperService] 1Pondo 失败: $e，尝试 Pacopacomama');
        }
        // 失败则尝试 pacopacomama
        if (kDebugMode) print('[ScraperService] 尝试 Pacopacomama...');
        return await _scrapers['pacopacomama']?.getMovieInfo(videoId);
      }

      if (kDebugMode) print('[ScraperService] 开始爬取...');
      final result = await scraper.getMovieInfo(videoId);
      if (kDebugMode) {
        if (result != null) {
          print('[ScraperService] 爬取成功: title=${result.title}, description=${result.description != null}');
        } else {
          print('[ScraperService] 爬取返回 null');
        }
      }
      return result;
    } catch (e, st) {
      if (kDebugMode) {
        print('[ScraperService] 异常: $e');
        print('[ScraperService] 堆栈: $st');
      }
      rethrow;
    }
  }

  /// 搜索影片
  Future<List<SearchResultItem>> search(String query) async {
    final match = identify(query);
    final scraperType = VideoIdMatcher.getScraperType(match.type);

    final scraper = _scrapers[scraperType];
    if (scraper == null) return [];

    try {
      final urls = await scraper.searchMovie(query);
      // 这里应该解析搜索结果页面
      // 简化处理：直接返回番号作为结果
      return [
        SearchResultItem(
          id: query.toUpperCase(),
          title: query.toUpperCase(),
        ),
      ];
    } catch (_) {
      return [];
    }
  }

  /// 获取爬虫实例
  BaseScraper? getScraper(String type) {
    return _scrapers[type];
  }

  /// 注册自定义爬虫
  void registerScraper(String type, BaseScraper scraper) {
    _scrapers[type] = scraper;
  }
}

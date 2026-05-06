import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;
import '../models/movie.dart';
import '../models/search_result.dart';

/// FC2 服务
/// 移植自 bus/modules/scrapers/fc2_scraper.py + fc2_list_provider.py
///
/// 功能：
/// - FC2 ID 规范化
/// - 精确 ID 详情获取（官方 → fc2club → JAVten 三级 fallback）
/// - 关键词列表搜索（JAVten 聚合站 + query widening）
/// - 搜索路由判断
class FC2Service {
  late final Dio _dio;

  // 数据源 URL
  static const _officialBase = 'https://adult.contents.fc2.com';
  static const _fallbackBases = ['https://fc2club.net', 'https://fc2club.com'];
  static const _javtenSearchBase = 'https://javten.com/search';
  static const int _defaultPerPage = 30;

  // ID 正则（与 Python 版本一致）
  static final RegExp _patternFc2Ppv =
      RegExp(r'FC2[-_ ]*PPV[-_ ]*(\d{2,10})', caseSensitive: false);
  static final RegExp _patternPpv =
      RegExp(r'\bPPV[-_ ]*(\d{2,10})\b', caseSensitive: false);
  static final RegExp _patternOfficialUrl =
      RegExp(r'adult\.contents\.fc2\.com/article/(\d{2,10})/?', caseSensitive: false);
  static final RegExp _patternFc2clubUrl =
      RegExp(r'fc2club\.(?:net|com)/html/FC2[-_ ]*(\d{2,10})\.html', caseSensitive: false);
  static final RegExp _patternNumeric = RegExp(r'\b(\d{5,10})\b');

  FC2Service() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
        'Accept-Language': 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7',
      },
    ));
  }

  // ============================================================
  // ID 识别与规范化
  // ============================================================

  /// 规范化 FC2 ID，返回标准格式 `FC2-PPV-{id}`，无法识别时返回 null
  String? normalizeId(String query) {
    if (query.isEmpty) return null;
    final q = query.trim();
    for (final pattern in [
      _patternFc2Ppv,
      _patternPpv,
      _patternOfficialUrl,
      _patternFc2clubUrl,
      _patternNumeric,
    ]) {
      final m = pattern.firstMatch(q);
      if (m != null) {
        return 'FC2-PPV-${m.group(1)}';
      }
    }
    return null;
  }

  /// 从规范化 ID 提取纯数字
  String? _extractNumericId(String canonicalId) {
    final m = RegExp(r'(\d+)$').firstMatch(canonicalId);
    return m?.group(1);
  }

  /// 精确 FC2 ID 识别（用于详情/ID 路径）
  bool isFc2Query(String query) => normalizeId(query) != null;

  /// 广泛 FC2 关键词识别（用于搜索路由）
  bool isFc2SearchKeyword(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return false;
    if (isFc2Query(q)) return true;
    if ({'fc2', 'fc2-ppv', 'fc2ppv', 'ppv'}.contains(q)) return true;
    if (q.contains('fc2') && q.contains('ppv')) return true;
    if (q.startsWith('fc2') || q.startsWith('ppv')) return true;
    return false;
  }

  // ============================================================
  // HTTP 请求
  // ============================================================

  Future<String?> _get(String url) async {
    for (final verify in [true, false]) {
      try {
        final resp = await _dio.get<String>(
          url,
          options: Options(
            validateStatus: (s) => s != null && s < 500,
            // ignore SSL errors on retry
          ),
        );
        if (resp.statusCode == 200 && (resp.data?.isNotEmpty ?? false)) {
          return resp.data!;
        }
      } catch (_) {}
    }
    return null;
  }

  // ============================================================
  // 精确 ID 详情获取（三级 fallback）
  // ============================================================

  /// 获取 FC2 影片详情
  ///
  /// Fallback 链：
  /// 1. FC2 官方 (adult.contents.fc2.com)
  /// 2. fc2club (fc2club.net / fc2club.com)
  /// 3. JAVten 详情页
  /// 后续源补全 primary 缺失字段
  Future<Movie?> getMovieInfo(String movieId) async {
    final canonicalId = normalizeId(movieId);
    if (canonicalId == null) return null;
    final numericId = _extractNumericId(canonicalId);
    if (numericId == null) return null;

    Movie? primary;

    // 1. FC2 官方
    final official = await _parseOfficial(numericId, canonicalId);
    if (official != null) primary = official;

    // 2. fc2club fallback
    final fc2club = await _parseFc2club(numericId, canonicalId);

    // 3. JAVten detail
    final javten = await _parseJavtenDetail(canonicalId);

    // 选择 primary
    primary ??= fc2club ?? javten;
    if (primary == null) return null;

    // 合并 fallback 数据
    if (fc2club != null) primary = _mergeMovie(primary, fc2club);
    if (javten != null) primary = _mergeMovie(primary, javten);

    return primary;
  }

  /// 解析 FC2 官方页面
  Future<Movie?> _parseOfficial(String numericId, String canonicalId) async {
    final html = await _get('$_officialBase/article/$numericId/');
    if (html == null) return null;

    try {
      final doc = html_parser.parse(html);

      String meta(String prop) {
        final tag = doc.querySelector('meta[property="$prop"]') ??
            doc.querySelector('meta[name="$prop"]');
        return (tag?.attributes['content'] ?? '').trim();
      }

      final rawTitle = meta('og:title');
      var title = _cleanTitle(rawTitle, canonicalId);

      // Prefer name=description over og:description
      var description = meta('description').isNotEmpty
          ? meta('description')
          : meta('og:description');
      description = description
          .replaceFirst(RegExp('^${RegExp.escape(canonicalId)}\\s*'), '')
          .trim();
      if (description.isEmpty || description == canonicalId) {
        description = title;
      }

      var cover = meta('og:image');
      if (cover.startsWith('//')) cover = 'https:$cover';

      final trailer = meta('og:video');

      // Seller
      String seller = '';
      final sellerLink = doc.querySelector('a[href*="/users/"]');
      if (sellerLink != null) seller = sellerLink.text.trim();

      // Tags
      final tags = <String>[];
      for (final el in doc.querySelectorAll('.items_article_TagArea a.tag, .tag.tagTag')) {
        final t = el.text.trim();
        if (t.isNotEmpty) tags.add(t);
      }

      // Date
      String date = '';
      for (final el in doc.querySelectorAll('p, li, div, span')) {
        final txt = el.text.trim();
        if (txt.contains('販売日') ||
            txt.contains('配信日') ||
            txt.contains('Releasedate') ||
            txt.contains('上架时间') ||
            txt.contains('发布时间') ||
            txt.contains('發布時間')) {
          date = _parseDate(txt);
          break;
        }
      }

      // Screenshots
      final screenshots = <SampleImage>[];
      for (final a in doc.querySelectorAll('.items_article_SampleImagesArea a[href]')) {
        final href = (a.attributes['href'] ?? '').trim();
        if (href.isNotEmpty) {
          screenshots.add(SampleImage(
            id: href,
            thumbnail: _normalizeUrl(href),
            src: _normalizeUrl(href),
          ));
        }
      }
      if (screenshots.isEmpty) {
        for (final img in doc.querySelectorAll('.items_article_SampleImagesArea img[src]')) {
          final src = _normalizeUrl(img.attributes['src'] ?? '');
          if (src.isNotEmpty) {
            screenshots.add(SampleImage(id: src, thumbnail: src, src: src));
          }
        }
      }

      return Movie(
        id: canonicalId,
        title: title.isNotEmpty ? title : canonicalId,
        cover: cover.isNotEmpty ? cover : null,
        date: date.isNotEmpty ? date : null,
        publisher: seller.isNotEmpty ? seller : null,
        producer: seller.isNotEmpty ? seller : null,
        series: 'FC2',
        genres: tags.isNotEmpty ? tags : null,
        samples: screenshots.isNotEmpty ? screenshots : null,
        description: description.isNotEmpty ? description : null,
      );
    } catch (e) {
      if (kDebugMode) print('[FC2] Official parse error: $e');
      return null;
    }
  }

  /// 解析 fc2club 页面
  Future<Movie?> _parseFc2club(String numericId, String canonicalId) async {
    for (final base in _fallbackBases) {
      final html = await _get('$base/html/FC2-$numericId.html');
      if (html == null) continue;

      try {
        final doc = html_parser.parse(html);
        final pageTitle = doc.querySelector('title')?.text.trim() ?? '';

        // 检查是否被重定向到 parking 页面
        if (pageTitle.toLowerCase().contains('parking') ||
            pageTitle.toLowerCase().contains('just a moment')) {
          continue;
        }

        String title = canonicalId;
        final titleEl = doc.querySelector('.show-top-grids h3') ?? doc.querySelector('h3');
        if (titleEl != null) {
          title = _cleanTitle(titleEl.text.trim(), canonicalId);
        }

        // 解析信息行
        final info = <String, String>{};
        for (final row in doc.querySelectorAll('.show-top-grids h5')) {
          final text = row.text.trim();
          if (text.contains('：')) {
            final parts = text.split('：');
            if (parts.length >= 2) info[parts[0].trim()] = parts[1].trim();
          } else if (text.contains(':')) {
            final parts = text.split(':');
            if (parts.length >= 2) info[parts[0].trim()] = parts[1].trim();
          }
        }

        final seller = info['卖家信息'] ?? info['販売者'] ?? '';
        final date = _parseDate(info['影片日期'] ?? info['配信日'] ?? '');

        // Tags
        final tags = <String>[];
        final tagText = info['影片标签'] ?? info['タグ'] ?? '';
        if (tagText.isNotEmpty) {
          tags.addAll(tagText.split(RegExp(r',|/|、')).map((t) => t.trim()).where((t) => t.isNotEmpty));
        }

        // Screenshots
        final screenshots = <SampleImage>[];
        for (final img in doc.querySelectorAll('ul.slides img[src]')) {
          final src = _normalizeUrl(img.attributes['src'] ?? '');
          if (src.isNotEmpty) {
            screenshots.add(SampleImage(id: src, thumbnail: src, src: src));
          }
        }

        final cover = screenshots.isNotEmpty ? screenshots[0].thumbnail : '';

        return Movie(
          id: canonicalId,
          title: title.isNotEmpty ? title : canonicalId,
          cover: cover.isNotEmpty ? cover : null,
          date: date.isNotEmpty ? date : null,
          publisher: seller.isNotEmpty ? seller : null,
          producer: seller.isNotEmpty ? seller : null,
          series: 'FC2',
          genres: tags.isNotEmpty ? tags : null,
          samples: screenshots.isNotEmpty ? screenshots : null,
        );
      } catch (e) {
        if (kDebugMode) print('[FC2] fc2club parse error: $e');
        continue;
      }
    }
    return null;
  }

  /// 解析 JAVten 详情页
  Future<Movie?> _parseJavtenDetail(String canonicalId) async {
    // 先搜索获取详情页 URL
    final searchHtml = await _get('$_javtenSearchBase?kw=${Uri.encodeComponent(canonicalId)}');
    if (searchHtml == null) return null;

    String? detailUrl;
    try {
      final doc = html_parser.parse(searchHtml);
      // 检查是否直接跳转到详情页
      // JAVten 搜索精确 ID 会 302 到详情页，但 Dio 跟随重定向
      // 所以从最终 URL 判断
      // 这里简单通过查找链接来判断
      final links = doc.querySelectorAll('a[href*="/video/"]');
      if (links.isNotEmpty) {
        detailUrl = links.first.attributes['href'] ?? '';
        if (detailUrl.startsWith('/')) {
          detailUrl = 'https://javten.com$detailUrl';
        }
      }
    } catch (_) {}

    if (detailUrl == null) return null;
    final html = await _get(detailUrl);
    if (html == null) return null;

    try {
      final doc = html_parser.parse(html);

      String meta(String prop, [String attr = 'property']) {
        final tag = doc.querySelector('meta[$attr="$prop"]');
        return (tag?.attributes['content'] ?? '').trim();
      }

      final rawTitle = meta('og:title');
      var title = rawTitle.replaceAll(' - JAVten.com', '').trim();
      title = _cleanTitle(title, canonicalId);

      var description = meta('description', 'name');
      if (description.isEmpty) description = meta('og:description');
      description = description
          .replaceAll('[$canonicalId]', '')
          .replaceAll('| Free Sample Video', '')
          .trim();

      // Try structured description from body
      final bodyDiv = doc.querySelector('div.col.des');
      if (bodyDiv != null) {
        final bodyText = bodyDiv.text.trim();
        if (bodyText.isNotEmpty && bodyText.length > description.length) {
          description = bodyText.length > 4000
              ? bodyText.substring(0, 4000)
              : bodyText;
        }
      }

      if (description.isEmpty) description = title;

      final cover = meta('og:image');

      // Tags
      final tags = <String>[];
      for (final a in doc.querySelectorAll('a.badge.badge-primary, a.badge')) {
        final t = a.text.trim();
        if (t.isNotEmpty && !tags.contains(t)) tags.add(t);
      }

      return Movie(
        id: canonicalId,
        title: title.isNotEmpty ? title : canonicalId,
        cover: cover.isNotEmpty ? cover : null,
        description: description.isNotEmpty ? description : null,
        series: 'FC2',
        genres: tags.isNotEmpty ? tags : null,
        samples: cover.isNotEmpty
            ? [SampleImage(id: cover, thumbnail: cover, src: cover)]
            : null,
      );
    } catch (e) {
      if (kDebugMode) print('[FC2] JAVten detail parse error: $e');
      return null;
    }
  }

  /// 合并两个 Movie，用 fallback 补全 primary 的空字段
  Movie _mergeMovie(Movie primary, Movie fallback) {
    return primary.copyWith(
      description: primary.description ?? fallback.description,
      date: primary.date ?? fallback.date,
      cover: primary.cover ?? fallback.cover,
      title: (primary.title == null || primary.title == primary.id)
          ? fallback.title
          : primary.title,
      publisher: primary.publisher ?? fallback.publisher,
      producer: primary.producer ?? fallback.producer,
      genres: (primary.genres == null || primary.genres!.isEmpty)
          ? fallback.genres
          : primary.genres,
      samples: (primary.samples == null || primary.samples!.isEmpty)
          ? fallback.samples
          : primary.samples,
    );
  }

  // ============================================================
  // 关键词列表搜索（JAVten 聚合站 + query widening）
  // ============================================================

  /// FC2 关键词列表搜索
  ///
  /// 策略：
  /// 1. 精确 ID → 详情包装成单条结果
  /// 2. 关键词 → JAVten 聚合站搜索（可能 query widening）
  /// 3. 都失败 → 空结果
  Future<SearchPagedResult> searchKeyword(String keyword, {int page = 1}) async {
    if (keyword.trim().isEmpty) {
      return const SearchPagedResult.empty();
    }

    // 精确 ID 优先（仅第一页）
    final canonical = normalizeId(keyword);
    if (canonical != null && page == 1) {
      final exact = await _exactIdAsList(canonical);
      if (exact.hasResults) return exact;
    }

    // 列表搜索
    try {
      final listResult = await _listSearch(keyword, page: page);
      if (listResult.hasResults) return listResult;
    } catch (e) {
      if (kDebugMode) print('[FC2] List provider failed: $e');
    }

    // 用纯数字 ID 再试
    if (canonical != null && page == 1) {
      final numeric = _extractNumericId(canonical);
      if (numeric != null) {
        try {
          final listResult = await _listSearch(numeric, page: 1);
          if (listResult.hasResults) return listResult;
        } catch (_) {}
      }
    }

    return const SearchPagedResult.empty();
  }

  /// 精确 ID 包装成列表结果
  Future<SearchPagedResult> _exactIdAsList(String canonicalId) async {
    final movie = await getMovieInfo(canonicalId);
    if (movie == null) return const SearchPagedResult.empty();

    return SearchPagedResult(
      items: [_movieToSearchResult(movie)],
      currentPage: 1,
      hasNextPage: false,
    );
  }

  /// JAVten 聚合站列表搜索（含 query widening）
  Future<SearchPagedResult> _listSearch(String keyword, {int page = 1}) async {
    final plans = _buildSearchPlans(keyword);

    final allItems = <SearchResultItem>[];
    final seenIds = <String>{};
    bool hasNext = false;

    for (final queryKw in plans) {
      final url = '$_javtenSearchBase?kw=${Uri.encodeComponent(queryKw)}'
          '${page > 1 ? '&page=$page' : ''}';
      if (kDebugMode) {
        print('[FC2-List] Searching keyword=$queryKw page=$page');
      }

      final html = await _get(url);
      if (html == null) continue;

      try {
        final doc = html_parser.parse(html);

        // 解析卡片
        for (final card in doc.querySelectorAll('div.card.shadow')) {
          final item = _parseCard(card);
          if (item != null && !seenIds.contains(item.id)) {
            seenIds.add(item.id);
            allItems.add(item);
          }
        }

        // 解析分页
        final paginationUl = doc.querySelector('ul.pagination');
        if (paginationUl != null) {
          for (final a in paginationUl.querySelectorAll('a[href]')) {
            final href = a.attributes['href'] ?? '';
            if (href.contains('page=')) {
              hasNext = true;
            }
          }
        }
      } catch (e) {
        if (kDebugMode) print('[FC2-List] Parse error: $e');
        continue;
      }
    }

    // 截取标准页大小
    final pageItems = allItems.take(_defaultPerPage).toList();

    return SearchPagedResult(
      items: pageItems,
      currentPage: page,
      hasNextPage: hasNext,
    );
  }

  /// Query widening：泛 FC2 意图扇出多查询
  List<String> _buildSearchPlans(String keyword) {
    final q = keyword.trim();
    final ql = q.toLowerCase().replaceAll(' ', '').replaceAll('_', '-');

    // 精确 ID 不扩宽
    if (_patternFc2Ppv.hasMatch(q)) return [q];

    final plans = <String>[];

    if ({'fc2-ppv', 'fc2ppv', 'fc2', 'ppv'}.contains(ql) ||
        (ql.contains('fc2') && ql.contains('ppv'))) {
      plans.addAll(['FC2', 'PPV', 'FC2-PPV']);
    } else if (ql.startsWith('fc2')) {
      plans.addAll([q, 'FC2']);
    } else if (ql.startsWith('ppv')) {
      plans.addAll([q, 'PPV', 'FC2']);
    } else {
      plans.add(q);
    }

    // 去重保序
    final seen = <String>{};
    return plans.where((p) {
      final key = p.toLowerCase();
      if (seen.contains(key)) return false;
      seen.add(key);
      return true;
    }).toList();
  }

  /// 解析 JAVten 搜索结果卡片
  SearchResultItem? _parseCard(html_dom.Element card) {
    final h4 = card.querySelector('h4.card-title');
    if (h4 == null) return null;

    final rawTitle = h4.text.trim();
    final idMatch = _patternFc2Ppv.firstMatch(rawTitle);
    if (idMatch == null) return null;

    final numericId = idMatch.group(1)!;
    final canonicalId = 'FC2-PPV-$numericId';

    // Description
    final descEl = card.querySelector('p.card-text');
    final description = descEl?.text.trim() ?? '';

    // Image
    String imgUrl = '';
    final imgContainer = card.querySelector('.b-image');
    if (imgContainer != null) {
      final imgTag = imgContainer.querySelector('img');
      if (imgTag != null) {
        for (final attr in ['data-src', 'data-original', 'src']) {
          final candidate = (imgTag.attributes[attr] ?? '').trim();
          if (candidate.isNotEmpty && !candidate.contains('loading')) {
            imgUrl = candidate;
            break;
          }
        }
      }
    }

    return SearchResultItem(
      id: canonicalId,
      title: description.isNotEmpty ? description : canonicalId,
      cover: imgUrl.isNotEmpty ? imgUrl : null,
      date: null,
      type: 'movie',
      isFc2: true,
    );
  }

  // ============================================================
  // 工具方法
  // ============================================================

  String _cleanTitle(String title, String canonicalId) {
    if (title.isEmpty) return canonicalId;
    var t = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    t = t.replaceFirst(RegExp(r'^FC2[-_ ]*PPV[-_ ]*\d+\s*', caseSensitive: false), '').trim();
    t = t.replaceFirst(RegExp('^${RegExp.escape(canonicalId)}\\s*', caseSensitive: false), '').trim();
    return t.isNotEmpty ? t : canonicalId;
  }

  String _parseDate(String text) {
    final m = RegExp(r'(\d{4})[/-](\d{2})[/-](\d{2})').firstMatch(text);
    if (m == null) return '';
    return '${m.group(1)}-${m.group(2)}-${m.group(3)}';
  }

  String _normalizeUrl(String url) {
    if (url.isEmpty) return '';
    if (url.startsWith('//')) return 'https:$url';
    return url;
  }

  SearchResultItem _movieToSearchResult(Movie movie) {
    return SearchResultItem(
      id: movie.id,
      title: movie.title ?? movie.id,
      cover: movie.cover,
      date: movie.date,
      type: 'movie',
      isFc2: true,
    );
  }
}

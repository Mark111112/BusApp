import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:flutter/foundation.dart';
import '../../models/movie.dart';

/// DMM 服务
/// 用于获取影片详细信息（简介）
///
/// 参考: modules/scrapers/dmm_scraper.py
class DMMService {
  late final Dio _dio;
  final bool _enabled;

  DMMService({
    bool enabled = true,
    int timeout = 15,
  }) : _enabled = enabled {
    _dio = Dio(BaseOptions(
      connectTimeout: Duration(seconds: timeout),
      receiveTimeout: Duration(seconds: timeout),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'Accept-Language': 'ja,en-US;q=0.9,en;q=0.8',
      },
    ));
  }

  /// 清理影片 ID
  /// 参考 Python: clean_movie_id()
  String _cleanMovieId(String movieId, {bool fiveDigit = false}) {
    if (kDebugMode) print('[DMM] 原始番号: $movieId');

    // 提取字母和数字部分
    final match = RegExp(r'([a-zA-Z]+)[-_]?(\d+)').firstMatch(movieId);
    if (match != null) {
      final label = match.group(1)!.toLowerCase(); // DMM 使用小写
      final number = match.group(2)!;

      // 格式化数字部分
      String formattedNumber = number;
      if (fiveDigit && number.length < 5) {
        formattedNumber = number.padLeft(5, '0');
      }

      final cleanedId = '$label$formattedNumber';
      if (kDebugMode) print('[DMM] 清理后番号: $cleanedId');
      return cleanedId;
    }
    return movieId;
  }

  /// 获取影片详情页 URL
  /// 参考 Python: get_movie_url()
  String _getDetailUrl(String movieId, {bool fiveDigit = false}) {
    final cleanedId = _cleanMovieId(movieId, fiveDigit: fiveDigit);
    // DMM URL 格式
    return 'https://www.dmm.co.jp/mono/dvd/-/detail/=/cid=$cleanedId/';
  }

  /// 搜索影片并获取详情页 URL
  /// 参考 Python: search_movie()
  Future<List<String>> _searchMovie(String movieId) async {
    final label = _cleanMovieId(movieId);
    final searchTerms = <String>[];

    // 添加基本格式
    searchTerms.add(label);

    // 添加5位数格式
    final fiveDigitId = _cleanMovieId(movieId, fiveDigit: true);
    if (label != fiveDigitId) {
      searchTerms.add(fiveDigitId);
    }

    final allUrls = <String>[];

    for (final term in searchTerms) {
      try {
        // 使用正确的 DMM 搜索 URL 格式
        final searchUrl = 'https://www.dmm.co.jp/search/=/searchstr=$term/limit=30/sort=rankprofile';
        if (kDebugMode) print('[DMM] 搜索 URL: $searchUrl');

        final response = await _dio.get(
          searchUrl,
          options: Options(
            headers: {
              'Referer': 'https://www.dmm.co.jp/',
              'Cookie': 'age_check_done=1; cklc=ja; locale=ja',
            },
          ),
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final html = response.data as String;
          if (kDebugMode) print('[DMM] 搜索页 HTML 长度: ${html.length}');

          final document = html_parser.parse(html);

          // 提取详情页链接
          final urls = _extractLinksFromSearchPage(document, movieId);
          allUrls.addAll(urls);
        }
      } catch (e) {
        if (kDebugMode) print('[DMM] 搜索失败: $e');
      }
    }

    // 去重并返回最佳匹配
    final uniqueUrls = allUrls.toSet().toList();
    if (uniqueUrls.isNotEmpty) {
      final bestUrl = _findBestMatch(uniqueUrls, movieId);
      if (bestUrl != null) {
        return [bestUrl, ...uniqueUrls.where((u) => u != bestUrl)];
      }
    }

    return uniqueUrls;
  }

  /// 从搜索结果页提取详情页链接
  /// 参考 Python: _extract_links_from_search_page()
  List<String> _extractLinksFromSearchPage(dynamic document, String movieId) {
    final urls = <String>[];
    if (document == null) return urls;

    // 尝试多种选择器
    final selectors = [
      '.tmb a',
      '.title a',
      '.d-item a',
      '[data-pid] a',
      '.productList a',
      '.fn-listPackageItem__link',  // 新的可能选择器
      'a[href*="/detail/"]',         // 通用匹配
    ];

    for (final selector in selectors) {
      final elements = document.querySelectorAll(selector);
      if (kDebugMode) print('[DMM] 选择器 "$selector" 找到 ${elements.length} 个元素');

      for (final elem in elements) {
        final href = elem.attributes['href'];
        if (href != null) {
          final url = href.startsWith('http') ? href : 'https://www.dmm.co.jp$href';
          if (url.contains('/mono/dvd/-/detail/') ||
              url.contains('/digital/videoa/-/detail/') ||
              url.contains('/digital/anime/-/detail/') ||
              url.contains('/digital/videoc/-/detail/')) {
            urls.add(url);
          }
        }
      }
    }

    // 尝试从 JavaScript 数据中提取链接
    final scripts = document.querySelectorAll('script');
    for (final script in scripts) {
      final scriptText = script.text;
      if (scriptText.contains('url') || scriptText.contains('cid')) {
        // 尝试提取 URL（使用更简单的正则表达式）
        final urlMatches = RegExp(r'https?://[\w\-./]+/detail/[\w\-./=?&]+').allMatches(scriptText);
        for (final match in urlMatches) {
          final url = match.group(0);
          if (url != null && url.contains('dmm.co.jp')) {
            urls.add(url);
          }
        }
      }
    }

    if (kDebugMode) print('[DMM] 从搜索页提取到 ${urls.length} 个链接');
    return urls;
  }

  /// 找到最佳匹配的 URL
  /// 参考 Python: _find_best_match()
  String? _findBestMatch(List<String> urls, String movieId) {
    if (urls.isEmpty) return null;
    if (urls.length == 1) return urls.first;

    final cleanedId = _cleanMovieId(movieId).toLowerCase();

    for (final url in urls) {
      final cidMatch = RegExp(r'/cid=([^/]+)/').firstMatch(url);
      if (cidMatch != null) {
        final cid = cidMatch.group(1)!.toLowerCase();
        if (cid.contains(cleanedId) || cleanedId.contains(cid)) {
          if (kDebugMode) print('[DMM] 找到最佳匹配: $url');
          return url;
        }
      }
    }

    return urls.first;
  }

  /// 获取影片页面内容（尝试多个 URL 格式）
  Future<String?> _fetchPageContent(String movieId) async {
    if (!_enabled) {
      if (kDebugMode) print('[DMM] 服务未启用');
      return null;
    }

    // 首先尝试搜索获取正确的详情页 URL
    final searchUrls = await _searchMovie(movieId);
    if (searchUrls.isNotEmpty) {
      if (kDebugMode) print('[DMM] 搜索到 ${searchUrls.length} 个详情页链接');
    }

    // 构建可能的直接 URL
    final directUrls = <String>[];
    directUrls.add(_getDetailUrl(movieId));
    directUrls.add(_getDetailUrl(movieId, fiveDigit: true));
    directUrls.add('https://www.dmm.co.jp/digital/videoa/-/detail/=/cid=${_cleanMovieId(movieId)}/');
    directUrls.add('https://www.dmm.co.jp/digital/anime/-/detail/=/cid=${_cleanMovieId(movieId)}/');

    // 合并搜索结果和直接 URL
    final allUrls = [...searchUrls, ...directUrls];
    if (kDebugMode) print('[DMM] 尝试的 URLs: $allUrls');

    for (final url in allUrls) {
      try {
        if (kDebugMode) print('[DMM] 尝试请求: $url');

        final response = await _dio.get(
          url,
          options: Options(
            headers: {
              'Referer': 'https://www.dmm.co.jp/',
              'Cookie': 'age_check_done=1; cklc=ja; locale=ja',
            },
          ),
        ).timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            if (kDebugMode) print('[DMM] 请求超时: $url');
            throw DioException(
              requestOptions: RequestOptions(path: url),
              type: DioExceptionType.receiveTimeout,
            );
          },
        );

        if (kDebugMode) print('[DMM] 响应状态: ${response.statusCode}');

        if (response.statusCode == 200) {
          final html = response.data as String;

          // 检查是否需要年龄验证
          if (html.contains('年龄確認') || html.contains('age_check')) {
            if (kDebugMode) print('[DMM] 需要年龄验证，尝试下一个 URL');
            continue;
          }

          // 检查是否是有效的详情页
          if (html.length < 1000) {
            if (kDebugMode) print('[DMM] 响应内容过短');
            continue;
          }

          // 检查是否包含详情页的特征元素（添加更多可能的元素）
          final hasDetailElements = html.contains('m-productInformation') ||
              html.contains('informationTable') ||
              html.contains('fn-productInfoBlock') ||
              html.contains('c-categoryList') ||
              html.contains('/detail/=/cid=') ||
              html.contains('d-review');

          if (!hasDetailElements) {
            if (kDebugMode) print('[DMM] 可能不是有效的详情页（缺少特征元素）');
            continue;
          }

          if (kDebugMode) print('[DMM] 成功获取页面: $url (${html.length} 字符)');
          return html;
        }
      } on DioException catch (e) {
        if (kDebugMode) print('[DMM] 请求失败: $url - ${e.message}');
        continue;
      } catch (e) {
        if (kDebugMode) print('[DMM] 请求异常: $url - $e');
        continue;
      }
    }

    if (kDebugMode) print('[DMM] 所有 URL 都失败了');
    return null;
  }

  /// 提取影片简介
  /// 参考 Python: extract_info_from_page() 中的简介提取逻辑
  String? _extractDescription(dynamic document) {
    if (document == null) return null;
    // Python 版本使用的选择器
    final selectors = [
      '.m-productInformation .m-ratioText',
      '#introduction .mg-b20',
      '.m-ratioText',
      '#introduction',
      '.description',
      '.area-description',
    ];

    for (final selector in selectors) {
      final elem = document.querySelector(selector);
      if (elem != null) {
        final desc = elem.text.trim();
        if (desc.isNotEmpty && desc.length > 20) {
          if (kDebugMode) print('[DMM] 从 "$selector" 找到简介 (${desc.length} 字符)');
          return desc;
        }
      }
    }

    // 如果上面的选择器都失败，尝试从整个页面中查找可能的简介文本
    // 查找包含大量文本的 p 标签
    final pTags = document.querySelectorAll('p');
    for (final p in pTags) {
      final text = p.text.trim();
      if (text.length > 100 && !text.contains('発売日') && !text.contains('収録時間') &&
          !text.contains('出演者') && !text.contains('シリーズ')) {
        if (kDebugMode) print('[DMM] 从 p 标签找到可能的简介 (${text.length} 字符)');
        return text;
      }
    }

    if (kDebugMode) print('[DMM] 未找到简介');
    return null;
  }

  /// 获取影片简介
  Future<String?> getDescription(String movieId) async {
    final html = await _fetchPageContent(movieId);
    if (html == null) return null;

    try {
      final document = html_parser.parse(html);
      return _extractDescription(document);
    } catch (e) {
      if (kDebugMode) print('[DMM] 解析简介失败: $e');
      return null;
    }
  }

  /// 获取详细信息（简介）
  /// 注意: DMM 详情页通常不包含用户评论，只有评分
  Future<DetailedInfo?> getDetailedInfo(String movieId) async {
    if (!_enabled) {
      if (kDebugMode) print('[DMM] 服务未启用');
      return null;
    }

    if (kDebugMode) print('[DMM] ========== 开始获取详细信息: $movieId ==========');

    try {
      final html = await _fetchPageContent(movieId);
      if (html == null) {
        if (kDebugMode) print('[DMM] 无法获取页面内容');
        return null;
      }

      final document = html_parser.parse(html);

      // 提取简介
      final description = _extractDescription(document);

      if (kDebugMode) {
        print('[DMM] ========== 获取完成 ==========');
        print('[DMM] 简介: ${description != null ? "有 (${description.length} 字符)" : "无"}');
      }

      if (description == null) {
        return null;
      }

      return DetailedInfo(
        description: description,
        comments: [], // DMM 详情页通常没有用户评论
      );
    } catch (e) {
      if (kDebugMode) print('[DMM] 获取详细信息失败: $e');
      return null;
    }
  }

  /// 是否启用
  bool get isEnabled => _enabled;
}

/// 详细信息类
class DetailedInfo {
  final String? description;
  final List<MovieComment> comments;

  DetailedInfo({
    this.description,
    this.comments = const [],
  });
}

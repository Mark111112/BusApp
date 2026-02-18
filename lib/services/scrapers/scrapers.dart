import 'base_scraper.dart';
import '../../models/models.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;
import 'dart:core';

/// Fanza 爬虫
/// 参考: modules/scrapers/fanza_scraper.py
class FanzaScraper extends BaseScraper {
  FanzaScraper({super.dio})
      : super(
          baseUrl: 'https://www.dmm.co.jp',
          customCookies: {
            'age_check_done': '1',
            'locale': 'ja',
          },
          customHeaders: {
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
            'Accept-Language': 'ja,en-US;q=0.9,en;q=0.8',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
            'Sec-Fetch-Dest': 'document',
            'Sec-Fetch-Mode': 'navigate',
            'Sec-Fetch-Site': 'none',
          },
        );

  // analyze 参数提高搜索精确度
  static const String _analyzeParam = 'analyze=V1EBAwoQAQcGXQ0OXw4C';

  /// 清理影片ID
  (String? label, String? number, String cleanId) _cleanMovieId(String movieId) {
    final match = RegExp(r'([a-zA-Z]+)[-_]?(\d+)', caseSensitive: false)
        .firstMatch(movieId);
    if (match == null) return (null, null, movieId);

    final label = match.group(1)!.toUpperCase();
    final number = match.group(2)!;
    final cleanId = '$label-$number';
    return (label, number, cleanId);
  }

  /// 格式化ID为URL格式
  String _formatId(String videoId) {
    return videoId.toUpperCase().replaceAll('-', '').toLowerCase();
  }

  @override
  bool get canDirectAccess => false;

  @override
  String? getDirectUrl(String videoId) {
    final (label, number, _) = _cleanMovieId(videoId);
    if (label == null || number == null) return null;

    final formatted = _formatId(videoId);
    // 尝试多种可能的 URL 格式
    return '$baseUrl/digital/videoa/-/detail/=/cid=$formatted';
  }

  @override
  Future<List<String>> searchMovie(String videoId) async {
    final (label, number, cleanId) = _cleanMovieId(videoId);
    if (label == null || number == null) return [];

    // 尝试多种搜索格式
    final searchTerms = [
      cleanId, // ABC-123
      '$label-${number.padLeft(5, '0')}', // ABC-00123
      '$label$number', // ABC123
      '${label.toLowerCase()}$number', // abc123
    ];

    for (final term in searchTerms) {
      try {
        final encodedTerm = Uri.encodeComponent(term);
        final searchUrl =
            '$baseUrl/search/=/searchstr=$encodedTerm/$_analyzeParam/';

        final page = await getPage(searchUrl);

        // 检查是否直接跳转到详情页
        final titleText = page.querySelector('title')?.text.toLowerCase() ?? '';
        if (titleText.contains('detail') || titleText.contains('商品')) {
          final canonicalLink = page.querySelector('link[rel="canonical"]');
          if (canonicalLink != null) {
            final href = canonicalLink.attributes['href'];
            if (href != null && href.isNotEmpty) {
              return [href];
            }
          }
        }

        // 提取搜索结果链接
        final urls = _extractLinksFromSearchPage(page, cleanId);
        if (urls.isNotEmpty) {
          return urls;
        }
      } catch (e) {
        // 继续尝试下一个搜索格式
        continue;
      }
    }

    return [];
  }

  /// 从搜索结果页提取链接
  List<String> _extractLinksFromSearchPage(dynamic page, String movieId) {
    final urls = <String>[];
    final cleanIdLower = movieId.toLowerCase();

    // 调试：输出页面上所有包含 video.dmm.co.jp 的链接
    if (kDebugMode) {
      final allLinks = page.querySelectorAll('a');
      final videoDmmLinks = <String>[];
      for (final link in allLinks) {
        final href = link.attributes['href'];
        if (href != null && href.contains('video.dmm.co.jp')) {
          videoDmmLinks.add(href);
        }
      }
      print('[FanzaScraper] 页面上所有包含 video.dmm.co.jp 的链接 (${videoDmmLinks.length} 个):');
      for (int i = 0; i < videoDmmLinks.length && i < 10; i++) {
        print('[FanzaScraper]   $i. ${videoDmmLinks[i]}');
      }
      if (videoDmmLinks.length > 10) {
        print('[FanzaScraper]   ... 还有 ${videoDmmLinks.length - 10} 个');
      }
    }

    // 多种 CSS 选择器（参考 Python 版本）
    final selectors = [
      'p.tmb a',  // Python 版本主要选择器
      'div.box-image a',
      'li.tmb li.type3 a',
      'a[href*="cid="]',
      'a[href*="/av/content/?id="]',
      'a[href*="/amateur/content/?id="]',
      'a[href*="video.dmm.co.jp/av/content/"]',
      'a[href*="video.dmm.co.jp/amateur/content/"]',
      'a[href*="//video.dmm.co.jp"]',  // 协议相对 URL
    ];

    if (kDebugMode) print('[FanzaScraper] 搜索结果页，尝试 ${selectors.length} 个选择器');

    for (int i = 0; i < selectors.length; i++) {
      final selector = selectors[i];
      final links = page.querySelectorAll(selector);
      if (kDebugMode) print('[FanzaScraper] 选择器 $i: "$selector", 找到 ${links.length} 个链接');

      for (final link in links) {
        final href = link.attributes['href'];
        if (href == null || href.isEmpty) continue;

        // 检查是否是目标链接
        final isTargetLink = href.contains('cid=') ||
            href.contains('/av/content/?id=') ||
            href.contains('/amateur/content/?id=') ||
            href.contains('video.dmm.co.jp/av/content/') ||
            href.contains('video.dmm.co.jp/amateur/content/');

        if (isTargetLink) {
          String url;
          if (href.startsWith('http')) {
            url = href;
          } else if (href.startsWith('//')) {
            // 协议相对 URL
            url = 'https:$href';
          } else {
            url = '$baseUrl$href';
          }
          urls.add(url);
        }
      }

      // 移除早期退出，尝试所有选择器以找到所有链接
      // if (urls.isNotEmpty) break;
    }

    if (kDebugMode) print('[FanzaScraper] 搜索结果共找到 ${urls.length} 个链接');

    // 按优先级排序
    return _sortUrlsByPriority(urls, cleanIdLower);
  }

  /// 按 URL 优先级排序（参考 Python 版本）
  List<String> _sortUrlsByPriority(List<String> urls, String cleanIdLower) {
    if (urls.isEmpty) return urls;

    // 计算优先级
    int getPriority(String url) {
      int priority = 0;
      final urlLower = url.toLowerCase();

      // 1. video.dmm.co.jp 的内容页优先级最高（可直接GraphQL）
      if (urlLower.contains('video.dmm.co.jp/av/content')) {
        priority += 1000;
      } else if (urlLower.contains('video.dmm.co.jp/amateur/content')) {
        priority += 1000;
      }

      // 2. 优先考虑数字版（digital/videoa）
      if (urlLower.contains('digital/videoa')) {
        priority += 100;
      }
      // 3. 其次考虑DVD版
      else if (urlLower.contains('mono/dvd')) {
        priority += 50;
      }
      // 4. 再次考虑动画
      else if (urlLower.contains('digital/videoc')) {
        priority += 30;
      }
      // 5. 最后考虑租赁（优先级最低）
      else if (urlLower.contains('rental')) {
        priority += 10;
      }

      // 6. 降低monthly链接的优先级
      if (urlLower.contains('monthly/')) {
        priority -= 10000;
      }

      // 7. 检查CID匹配度
      final cidMatch = RegExp(r'cid=([^/&]+)', caseSensitive: false).firstMatch(url);
      if (cidMatch != null) {
        final cid = cidMatch.group(1)!.toLowerCase();
        // 完全匹配
        if (cid == cleanIdLower) {
          priority += 10000;
        }
      }

      return priority;
    }

    // 按优先级排序
    urls.sort((a, b) => getPriority(b).compareTo(getPriority(a)));

    if (kDebugMode) {
      print('[FanzaScraper] URL 优先级排序结果:');
      for (int i = 0; i < urls.length && i < 5; i++) {
        print('[FanzaScraper]   $i. 优先级=${getPriority(urls[i])}, ${urls[i]}');
      }
    }

    return urls;
  }

  @override
  Future<Movie?> getMovieInfo(String videoId) async {
    try {
      if (kDebugMode) print('[FanzaScraper] ========== getMovieInfo: $videoId ==========');

      // 1. 先尝试搜索
      final searchResults = await searchMovie(videoId);

      if (searchResults.isEmpty) {
        if (kDebugMode) print('[FanzaScraper] 搜索未返回结果，尝试直接访问');
        // 2. 搜索失败，尝试直接访问
        final directUrl = getDirectUrl(videoId);
        if (directUrl != null) {
          final result = await _parseDetailPage(directUrl, videoId);
          if (result != null) return result;
        }
        return null;
      }

      if (kDebugMode) print('[FanzaScraper] 搜索返回 ${searchResults.length} 个结果');

      // 3. 尝试每个搜索结果，直到成功
      for (int i = 0; i < searchResults.length; i++) {
        final url = searchResults[i];
        if (kDebugMode) print('[FanzaScraper] 尝试 URL $i: $url');

        final result = await _parseDetailPage(url, videoId);
        if (result != null) {
          if (kDebugMode) print('[FanzaScraper] URL $i 解析成功');
          return result;
        }
        if (kDebugMode) print('[FanzaScraper] URL $i 解析失败，尝试下一个');
      }

      if (kDebugMode) print('[FanzaScraper] 所有 URL 都解析失败');
      return null;
    } catch (e) {
      if (kDebugMode) print('[FanzaScraper] getMovieInfo 异常: $e');
      throw ScraperException('获取 Fanza 影片信息失败', e);
    }
  }

  Future<Movie?> _parseDetailPage(String url, String videoId) async {
    try {
      if (kDebugMode) print('[FanzaScraper] _parseDetailPage: $url');

      // 跳过租赁版（优先级低，且结构不同）
      if (url.contains('/rental/')) {
        if (kDebugMode) print('[FanzaScraper] 跳过租赁版页面');
        return null;
      }

      // 检查是否是 video.dmm.co.jp 的链接（需要 GraphQL）
      if (url.contains('video.dmm.co.jp')) {
        if (kDebugMode) print('[FanzaScraper] 使用 video.dmm.co.jp GraphQL API');
        // 提取 content_id
        final contentId = _extractContentIdFromVideoUrl(url);
        if (contentId != null) {
          return await _fetchVideoDmmContentByContentId(contentId, videoId);
        }
        // 无法提取 content_id，尝试从 videoId 构建
        final builtContentId = _buildVideoDmmId(videoId);
        if (builtContentId != null) {
          return await _fetchVideoDmmContentByContentId(builtContentId, videoId);
        }
        if (kDebugMode) print('[FanzaScraper] 无法获取 content_id');
        return null;
      }

      final page = await getPage(url);

      // 调试：列出页面上所有的 h1 元素
      if (kDebugMode) {
        final allH1 = page.querySelectorAll('h1');
        print('[FanzaScraper] 页面上的 h1 元素数量: ${allH1.length}');
        for (int i = 0; i < allH1.length && i < 5; i++) {
          final h1 = allH1[i];
          final id = h1.attributes['id'] ?? '';
          final className = h1.attributes['class'] ?? '';
          final text = h1.text?.trim().substring(0, h1.text!.length > 30 ? 30 : h1.text!.length) ?? '';
          print('[FanzaScraper]   h1[$i]: id="$id", class="$className", text="$text"');
        }
      }

      // 检查是否是有效详情页 - 使用多种选择器（Python 版本方式）
      // soup.find("h1", class_="item-name") or soup.find("h1", id="title")
      final titleEl = page.querySelector('h1.item-name') ??
          page.querySelector('h1#title') ??
          page.querySelector('h1[id="title"]') ??
          page.querySelector('#title h1') ??
          page.querySelector('h1');
      if (titleEl == null) {
        if (kDebugMode) print('[FanzaScraper] 未找到标题元素');
        return null;
      }

      // 提取标题
      final title = titleEl.text?.trim() ?? '';
      if (title.isEmpty) {
        if (kDebugMode) print('[FanzaScraper] 标题为空');
        return null;
      }
      if (kDebugMode) print('[FanzaScraper] 标题: $title');

      // 提取信息表格
      final infoTable =
          page.querySelector('table.mg-b20') ?? page.querySelector('table.mg-b12');
      if (infoTable == null) {
        if (kDebugMode) print('[FanzaScraper] 未找到信息表格');
        return null;
      }

      String? date;
      int? duration;
      final actresses = <ActorInfo>[];
      String? description;
      String? cover;

      // 解析表格行
      final rows = infoTable.querySelectorAll('tr');
      for (final row in rows) {
        final labelEl =
            row.querySelector('td.nw') ?? row.querySelector('td[width="100"]');
        if (labelEl == null) continue;

        final label = labelEl.text.trim();
        final valueEl = labelEl.nextElementSibling;
        if (valueEl == null) continue;

        final value = valueEl.text.trim();

        // 解析各种字段
        if (label.contains('発売日') ||
            label.contains('配信開始日') ||
            label.contains('発売日')) {
          date = value.replaceAll('/', '-');
        } else if (label.contains('収録時間') || label.contains('時間')) {
          final match = RegExp(r'(\d+)').firstMatch(value);
          if (match != null) {
            duration = int.tryParse(match.group(1)!);
          }
        } else if (label.contains('出演者') || label.contains('女優')) {
          final actorLinks = valueEl.querySelectorAll('a');
          for (final link in actorLinks) {
            final name = link.text.trim();
            if (name.isNotEmpty && name != '：') {
              final href = link.attributes['href'] ?? '';
              final idMatch = RegExp(r'/id=(\d+)/').firstMatch(href);
              final id = idMatch?.group(1) ?? '';
              actresses.add(ActorInfo(
                id: id,
                name: name,
                avatar: id.isNotEmpty
                    ? 'https://pics.dmm.co.jp/mono/actjpgs/$id.jpg'
                    : null,
              ));
            }
          }
        }
      }

      // 提取封面
      final coverImg = page.querySelector('#sample-video img') ??
          page.querySelector('.item-image img');
      if (coverImg != null) {
        final src = coverImg.attributes['src'] ??
            coverImg.attributes['data-src'] ??
            coverImg.attributes['data-lazy'];
        if (src != null && src.isNotEmpty) {
          cover = _convertToHighQualityImage(src);
        }
      }

      // 提取简介 - 参考 Python 版本的多层逻辑
      if (kDebugMode) print('[FanzaScraper] ========== 开始提取简介 ==========');

      // 定义需过滤的广告关键词
      const adKeywords = [
        '特典', 'セット商品', 'キャンペーン', 'オフ', 'セール',
        '詳しくはこちら', 'コンビニ受取', '注文方法', '送料無料', 'ポイント'
      ];

      // 7.1 优先选择 page-detail 区域内的正文段落
      String? extractDescription() {
        // 先查找 page-detail 根区域
        final detailRoot = page.querySelector('div.page-detail');
        final candidates = <html_dom.Element>[];

        if (detailRoot != null) {
          if (kDebugMode) print('[FanzaScraper] 找到 div.page-detail 根区域');
          // 在 page-detail 内查找
          final paragraphs = detailRoot.querySelectorAll('div.mg-b20.lh4 p');
          final pMgB20 = detailRoot.querySelectorAll('p.mg-b20');
          candidates.addAll(paragraphs);
          candidates.addAll(pMgB20);
          if (kDebugMode) print('[FanzaScraper] 在 page-detail 内找到 ${candidates.length} 个段落');
        } else {
          if (kDebugMode) print('[FanzaScraper] 未找到 div.page-detail，全局查找');
          // 全局查找
          final paragraphs = page.querySelectorAll('div.mg-b20.lh4 p');
          final pMgB20 = page.querySelectorAll('p.mg-b20');
          candidates.addAll(paragraphs);
          candidates.addAll(pMgB20);
          if (kDebugMode) print('[FanzaScraper] 全局找到 ${candidates.length} 个段落');
        }

        if (candidates.isEmpty) {
          if (kDebugMode) print('[FanzaScraper] 没有找到任何候选段落');
          return null;
        }

        // 过滤并提取有效段落
        final cleanedCandidates = <String>[];
        final seenTexts = <String>{}; // 用于去重

        for (int i = 0; i < candidates.length; i++) {
          try {
            final p = candidates[i];
            final text = _extractTextWithLineBreaks(p);
            if (kDebugMode) print('[FanzaScraper] 段落 $i: 长度=${text.length}, 前50字符=${text.length > 50 ? text.substring(0, 50) : text}');

            if (text.isEmpty) continue;

            // 去重：如果相同文本已处理过，跳过
            if (seenTexts.contains(text)) {
              if (kDebugMode) print('[FanzaScraper] 段落 $i 重复，跳过');
              continue;
            }

            // 过滤包含广告关键词的段落
            bool hasAdKeyword = false;
            for (final keyword in adKeywords) {
              if (text.contains(keyword)) {
                if (kDebugMode) print('[FanzaScraper] 段落 $i 包含广告关键词: $keyword');
                hasAdKeyword = true;
                break;
              }
            }
            if (hasAdKeyword) continue;

            // 过滤过短的段落
            if (text.length < 50) {
              if (kDebugMode) print('[FanzaScraper] 段落 $i 过短 (<50)');
              continue;
            }

            // 过滤处于广告说明容器内的段落
            final parent = p.parent;
            if (parent != null) {
              final parentClass = parent.attributes['class'] ?? '';
              if (parentClass.contains('d-boxother') || parentClass.contains('mg-t20')) {
                if (kDebugMode) print('[FanzaScraper] 段落 $i 在广告容器内: $parentClass');
                continue;
              }
            }

            if (kDebugMode) print('[FanzaScraper] 段落 $i 有效，添加到结果');
            cleanedCandidates.add(text);
            seenTexts.add(text); // 记录已处理的文本
          } catch (e) {
            if (kDebugMode) print('[FanzaScraper] 段落 $i 处理异常: $e');
            continue;
          }
        }

        // 按长度排序，优先保留较长的段落
        if (cleanedCandidates.isNotEmpty) {
          if (kDebugMode) print('[FanzaScraper] 找到 ${cleanedCandidates.length} 个有效段落');
          cleanedCandidates.sort((a, b) => b.length.compareTo(a.length));

          // 如果只有一个段落，直接使用
          if (cleanedCandidates.length == 1) {
            if (kDebugMode) print('[FanzaScraper] 使用单个有效段落，长度=${cleanedCandidates[0].length}');
            return cleanedCandidates[0];
          }

          // 多个段落时，用双换行符分隔
          final result = cleanedCandidates.join('\n\n');
          if (kDebugMode) print('[FanzaScraper] 合并 ${cleanedCandidates.length} 个段落，总长度=${result.length}');
          return result;
        }

        if (kDebugMode) print('[FanzaScraper] 没有找到任何有效段落');
        return null;
      }

      // 尝试提取简介
      description = extractDescription();
      if (description != null) {
        if (kDebugMode) print('[FanzaScraper] 7.1 提取成功，长度=${description.length}');
      } else {
        if (kDebugMode) print('[FanzaScraper] 7.1 提取失败，尝试兜底方案');
      }

      // 7.2 兜底：尝试 introduction 区域
      if (description == null || description.isEmpty) {
        try {
          final introEl = page.querySelector('#introduction-text') ??
              page.querySelector('.mg-b20.lh4');
          if (introEl != null) {
            if (kDebugMode) print('[FanzaScraper] 7.2 找到 introduction 元素');
            final paras = introEl.querySelectorAll('p');
            if (kDebugMode) print('[FanzaScraper] 7.2 找到 ${paras.length} 个 p 标签');
            final validParas = <String>[];

            for (final p in paras) {
              try {
                final text = _extractTextWithLineBreaks(p);
                if (kDebugMode) print('[FanzaScraper] 7.2 段落: 长度=${text.length}');
                if (text.length >= 50) {
                  // 检查广告关键词
                  bool hasAd = false;
                  for (final keyword in adKeywords) {
                    if (text.contains(keyword)) {
                      hasAd = true;
                      break;
                    }
                  }
                  if (!hasAd) {
                    validParas.add(text);
                  }
                }
              } catch (_) {}
            }

            if (validParas.isNotEmpty) {
              description = validParas.join('\n\n');
              if (kDebugMode) print('[FanzaScraper] 7.2 提取成功，有效段落=${validParas.length}');
            } else {
              description = _extractTextWithLineBreaks(introEl);
              if (kDebugMode) print('[FanzaScraper] 7.2 提取文本，长度=${description?.length ?? 0}');
            }
          } else {
            if (kDebugMode) print('[FanzaScraper] 7.2 未找到 introduction 元素');
          }
        } catch (e) {
          if (kDebugMode) print('[FanzaScraper] 7.2 异常: $e');
        }
      }

      // 7.3 兜底：meta 描述
      if (description == null || description.isEmpty) {
        try {
          final metaDesc = page.querySelector('meta[property="og:description"]') ??
              page.querySelector('meta[name="description"]');
          if (metaDesc != null) {
            final content = metaDesc.attributes['content'];
            if (content != null && content.isNotEmpty) {
              description = content.trim();
              if (kDebugMode) print('[FanzaScraper] 7.3 从 meta 提取，长度=${description.length}');
            }
          } else {
            if (kDebugMode) print('[FanzaScraper] 7.3 未找到 meta description');
          }
        } catch (e) {
          if (kDebugMode) print('[FanzaScraper] 7.3 异常: $e');
        }
      }

      if (kDebugMode) {
        print('[FanzaScraper] 最终简介状态: ${description != null ? "有内容(长度=${description.length})" : "无内容"}');
      }

      return Movie(
        id: videoId.toUpperCase(),
        title: title,
        cover: cover,
        date: date,
        description: description,
        duration: duration,
        actors: actresses,
      );
    } catch (e) {
      return null;
    }
  }

  /// 转换为高质量图片
  String _convertToHighQualityImage(String imgUrl) {
    if (imgUrl.isEmpty) return imgUrl;

    // ps.jpg -> pl.jpg
    if (imgUrl.contains('ps.jpg')) {
      return imgUrl.replaceAll('ps.jpg', 'pl.jpg');
    }
    // pt.jpg -> pl.jpg
    if (imgUrl.contains('pt.jpg')) {
      return imgUrl.replaceAll('pt.jpg', 'pl.jpg');
    }
    return imgUrl;
  }

  /// 提取文本并保留换行
  String _extractTextWithLineBreaks(dynamic element) {
    if (element == null) return '';

    // 如果是字符串，直接返回
    if (element is String) {
      return _formatText(element as String);
    }

    // 判断是否是 html 包的 Element 对象
    if (element is! html_dom.Element) {
      return _formatText(element.toString());
    }

    final elem = element as html_dom.Element;

    // 策略：优先查找段落标签 <p>，保留段落结构
    final paragraphs = elem.querySelectorAll('p');
    if (paragraphs.isNotEmpty) {
      final buffer = StringBuffer();
      for (int i = 0; i < paragraphs.length; i++) {
        final p = paragraphs[i];
        // 获取段落文本，去除首尾空白
        String pText = p.text?.trim() ?? '';
        if (pText.isNotEmpty) {
          if (buffer.isNotEmpty) {
            buffer.write('\n\n');  // 段落之间用双换行分隔
          }
          buffer.write(pText);
        }
      }
      return buffer.toString();
    }

    // 兜底：使用 text 属性
    final text = elem.text ?? '';
    if (text.isEmpty) return '';
    return _formatText(text);
  }

  /// 格式化文本：清理多余的空白行
  String _formatText(String text) {
    if (text.isEmpty) return '';

    // 标准化换行符
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n');

    // 去除首尾空行
    while (lines.isNotEmpty && lines.first.isEmpty) {
      lines.removeAt(0);
    }
    while (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }

    // 清理单空行，保留双空行作为段落分隔
    final result = <String>[];
    int blankRun = 0;
    for (final line in lines) {
      if (line.isEmpty) {
        blankRun++;
        continue;
      }
      if (blankRun >= 2 && result.isNotEmpty) {
        result.add('');
      }
      blankRun = 0;
      result.add(line.trim());
    }

    return result.join('\n');
  }

  /// 遍历 DOM 节点提取文本
  void _traverseNodes(html_dom.Node node, StringBuffer buffer) {
    if (node is html_dom.Text) {
      final text = (node as html_dom.Text).data?.trim();
      if (text != null && text.isNotEmpty) {
        if (buffer.isNotEmpty) buffer.write(' ');
        buffer.write(text);
      }
    } else if (node is html_dom.Element) {
      final element = node as html_dom.Element;
      // 对于某些标签，添加换行
      final tagName = element.localName?.toLowerCase() ?? '';
      if (tagName == 'br' || tagName == 'p' || tagName == 'div') {
        if (buffer.isNotEmpty && buffer.toString().isNotEmpty) {
          buffer.write('\n');
        }
      }
      for (final child in element.nodes) {
        _traverseNodes(child, buffer);
      }
    }
  }

  /// 从 video.dmm.co.jp URL 中提取 content_id
  /// 例如: https://video.dmm.co.jp/av/content/?id=cosx00088 -> cosx00088
  String? _extractContentIdFromVideoUrl(String url) {
    try {
      final match = RegExp(r'[?&]id=([^&#]+)', caseSensitive: false).firstMatch(url);
      return match?.group(1);
    } catch (_) {
      return null;
    }
  }

  /// 构造 video.dmm.co.jp 使用的 ID（如 cosx00088）
  /// 例如: COSX-088 -> cosx00088
  String? _buildVideoDmmId(String movieId) {
    try {
      final (label, number, _) = _cleanMovieId(movieId);
      if (label == null || number == null) return null;
      // 数字部分补零到 5 位
      final paddedNumber = number.padLeft(5, '0');
      return '${label.toLowerCase()}$paddedNumber';
    } catch (_) {
      return null;
    }
  }

  /// 使用 GraphQL 从 video.dmm.co.jp 获取影片信息
  /// 参考: modules/scrapers/fanza_scraper.py::_fetch_video_dmm_content_by_content_id
  Future<Movie?> _fetchVideoDmmContentByContentId(String contentId, String videoId) async {
    if (kDebugMode) print('[FanzaScraper] GraphQL: contentId=$contentId');

    try {
      final graphqlUrl = 'https://api.video.dmm.co.jp/graphql';

      // GraphQL 查询
      const query = r'''
query Content($id: ID!) {
  ppvContent(id: $id) {
    id
    title
    releaseStatus
    description
    duration
    deliveryStartDate
    makerReleasedAt
    makerContentId
    contentType
    packageImage { largeUrl mediumUrl }
    sampleImages { number imageUrl largeImageUrl }
    actresses { id name }
    directors { id name }
    series { id name }
    maker { id name }
    label { id name }
    genres { id name }
  }
}
''';

      final payload = {
        'query': query,
        'variables': {'id': contentId},
      };

      // 使用自定义 Dio 实例（GraphQL 需要不同的 headers）
      final graphqlDio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Accept': 'application/graphql-response+json, application/json',
          'Content-Type': 'application/json',
          'Origin': 'https://video.dmm.co.jp',
          'Referer': 'https://video.dmm.co.jp/',
          'Sec-Fetch-Site': 'same-site',
          'Sec-Fetch-Mode': 'cors',
          'Sec-Fetch-Dest': 'empty',
          'Fanza-Device': 'BROWSER',
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36',
        },
      ));

      final response = await graphqlDio.post(
        graphqlUrl,
        data: payload,
        options: Options(responseType: ResponseType.json),
      );

      if (response.statusCode != 200) {
        if (kDebugMode) print('[FanzaScraper] GraphQL 请求失败: ${response.statusCode}');
        return null;
      }

      final data = response.data as Map<String, dynamic>?;
      if (data == null) {
        if (kDebugMode) print('[FanzaScraper] GraphQL 响应为空');
        return null;
      }

      // 检查错误
      if (data.containsKey('errors')) {
        if (kDebugMode) print('[FanzaScraper] GraphQL 返回错误: ${data['errors']}');
        return null;
      }

      final contentData = data['data'] as Map<String, dynamic>?;
      if (contentData == null) {
        if (kDebugMode) print('[FanzaScraper] GraphQL 无 data 字段');
        return null;
      }

      final ppvContent = contentData['ppvContent'] as Map<String, dynamic>?;
      if (ppvContent == null) {
        if (kDebugMode) print('[FanzaScraper] GraphQL 无 ppvContent 字段');
        return null;
      }

      if (kDebugMode) print('[FanzaScraper] GraphQL 成功获取内容');

      // 提取标题
      final title = ppvContent['title']?.toString() ?? '';

      // 提取发行日期
      String? date;
      final makerReleasedAt = ppvContent['makerReleasedAt']?.toString();
      if (makerReleasedAt != null && makerReleasedAt.isNotEmpty) {
        date = makerReleasedAt.split('T')[0].replaceAll('/', '-');
      }

      // 提取时长
      int? duration;
      final durationSec = ppvContent['duration'];
      if (durationSec is int && durationSec > 0) {
        duration = (durationSec / 60).round();
      }

      // 提取简介
      final description = ppvContent['description']?.toString();

      // 提取封面
      String? cover;
      final packageImage = ppvContent['packageImage'] as Map<String, dynamic>?;
      if (packageImage != null) {
        cover = packageImage['largeUrl']?.toString() ?? packageImage['mediumUrl']?.toString();
      }

      // 提取演员
      final actresses = <ActorInfo>[];
      final actressesData = ppvContent['actresses'] as List?;
      if (actressesData != null) {
        for (final actress in actressesData) {
          if (actress is Map<String, dynamic>) {
            final name = actress['name']?.toString();
            final id = actress['id']?.toString();
            if (name != null && name.isNotEmpty) {
              actresses.add(ActorInfo(
                id: id ?? name,
                name: name,
              ));
            }
          }
        }
      }

      // 提取样本图片
      final samples = <SampleImage>[];
      final sampleImagesData = ppvContent['sampleImages'] as List?;
      if (sampleImagesData != null) {
        for (final sample in sampleImagesData) {
          if (sample is Map<String, dynamic>) {
            final number = sample['number']?.toString();
            final imageUrl = sample['largeImageUrl']?.toString() ?? sample['imageUrl']?.toString();
            if (number != null && imageUrl != null) {
              samples.add(SampleImage(
                id: number,
                src: imageUrl,
                thumbnail: sample['imageUrl']?.toString() ?? imageUrl,
              ));
            }
          }
        }
      }

      if (kDebugMode) {
        print('[FanzaScraper] GraphQL 解析完成: title=$title, date=$date, actresses=${actresses.length}');
      }

      return Movie(
        id: videoId.toUpperCase(),
        title: title,
        cover: cover,
        date: date,
        description: description,
        duration: duration,
        actors: actresses,
        samples: samples,
      );
    } catch (e, st) {
      if (kDebugMode) {
        print('[FanzaScraper] GraphQL 异常: $e');
        print('[FanzaScraper] 堆栈: $st');
      }
      return null;
    }
  }
}

/// Heyzo 爬虫
/// 参考: modules/scrapers/heyzo_scraper.py
class HeyzoScraper extends BaseScraper {
  HeyzoScraper({super.dio})
      : super(
          baseUrl: 'https://www.heyzo.com',
          customCookies: {
            'age_auth': '1',
            'locale': 'ja',
          },
        );

  @override
  bool get canDirectAccess => true;

  @override
  String? getDirectUrl(String videoId) {
    // 提取数字部分（支持3-5位数字）
    final match = RegExp(r'(?:heyzo[-_]?)?(\d{3,5})', caseSensitive: false)
        .firstMatch(videoId);
    if (match != null) {
      final number = match.group(1)!.padLeft(4, '0'); // 确保4位数字格式
      return '$baseUrl/moviepages/$number/index.html';
    }
    return null;
  }

  @override
  Future<List<String>> searchMovie(String videoId) async {
    final url = getDirectUrl(videoId);
    return url != null ? [url] : [];
  }

  @override
  Future<Movie?> getMovieInfo(String videoId) async {
    final url = getDirectUrl(videoId);
    if (url == null) return null;

    try {
      if (kDebugMode) print('[HeyzoScraper] 正在获取: $url');
      final page = await getPage(url);

      // 提取标题 - 使用多个选择器
      String title = '';
      try {
        final titleEl = page.querySelector('h1') ?? page.querySelector('h2');
        if (titleEl != null) {
          final text = titleEl.text;
          if (text != null) {
            title = text.trim();
          }
        }
        // 兜底：从 meta 获取
        if (title.isEmpty) {
          final metaTitle = page.querySelector('meta[property="og:title"]');
          if (metaTitle != null) {
            final content = metaTitle.attributes['content'];
            if (content != null && content.isNotEmpty) {
              // 去除网站名称
              title = content.replaceAll(RegExp(r'\s*-\s*.*$'), '').trim();
            }
          }
        }
      } catch (e) {
        if (kDebugMode) print('[HeyzoScraper] 提取标题失败: $e');
      }

      // 从URL中提取影片ID
      final urlMatch = RegExp(r'/moviepages/(\d+)/index\.html').firstMatch(url);
      final movieId = urlMatch?.group(1);

      // 提取封面
      String? cover;
      if (movieId != null) {
        cover = 'https://www.heyzo.com/contents/3000/$movieId/images/player_thumbnail.jpg';
      }

      // 从 movieInfo 表格中提取详细信息（Python 版本方式）
      final actresses = <ActorInfo>[];
      String? date;
      String? description;

      try {
        final infoTable = page.querySelector('table.movieInfo');
        if (infoTable != null) {
          if (kDebugMode) print('[HeyzoScraper] 找到 movieInfo 表格');

          // 提取发行日期
          try {
            final releaseRow = infoTable.querySelector('.table-release-day');
            if (releaseRow != null) {
              final dateCell = releaseRow.querySelector('td:nth-of-type(2)');
              if (dateCell != null && dateCell.text != null) {
                date = dateCell.text!.trim();
              }
            }
          } catch (e) {
            if (kDebugMode) print('[HeyzoScraper] 提取日期失败: $e');
          }

          // 提取演员
          try {
            final actorRow = infoTable.querySelector('.table-actor');
            if (actorRow != null) {
              final actorLinks = actorRow.querySelectorAll('a');
              for (final link in actorLinks) {
                final text = link.text;
                if (text != null && text.isNotEmpty) {
                  final name = text.trim();
                  if (name.isNotEmpty) {
                    actresses.add(ActorInfo(id: name, name: name));
                  }
                }
              }
            }
          } catch (e) {
            if (kDebugMode) print('[HeyzoScraper] 提取演员失败: $e');
          }

          // 提取简介
          try {
            final memoRow = infoTable.querySelector('.table-memo');
            if (memoRow != null) {
              final memoP = memoRow.querySelector('p.memo');
              if (memoP != null && memoP.text != null) {
                description = memoP.text!.trim();
              }
            }
          } catch (e) {
            if (kDebugMode) print('[HeyzoScraper] 提取简介失败: $e');
          }
        } else {
          if (kDebugMode) print('[HeyzoScraper] 未找到 movieInfo 表格，尝试备用选择器');

          // 备用：直接从页面查找
          try {
            final actorLink = page.querySelector('.table-actor a');
            if (actorLink != null && actorLink.text != null) {
              final name = actorLink.text!.trim();
              if (name.isNotEmpty) {
                actresses.add(ActorInfo(id: name, name: name));
              }
            }
          } catch (_) {}

          try {
            final releaseRow = page.querySelector('.table-release-day');
            if (releaseRow != null) {
              final dateCell = releaseRow.querySelector('td:nth-of-type(2)');
              if (dateCell != null && dateCell.text != null) {
                date = dateCell.text!.trim();
              }
            }
          } catch (_) {}
        }
      } catch (e) {
        if (kDebugMode) print('[HeyzoScraper] 解析表格失败: $e');
      }

      // 提取样本图片（前5张高质量，后续缩略图）
      final samples = <SampleImage>[];
      if (movieId != null) {
        for (int i = 1; i <= 21; i++) {
          final imgNum = i.toString().padLeft(3, '0');
          final imgUrl = i <= 5
              ? 'https://www.heyzo.com/contents/3000/$movieId/gallery/$imgNum.jpg'
              : 'https://www.heyzo.com/contents/3000/$movieId/gallery/thumbnail_$imgNum.jpg';
          samples.add(SampleImage(
            id: 'sample_$i',
            src: imgUrl,
            thumbnail: imgUrl,
          ));
        }
      }

      // 提取 Heyzo 编号
      final heyzoMatch = RegExp(r'\d{3,5}').firstMatch(videoId);
      final heyzoId = heyzoMatch != null ? 'HEYZO-${heyzoMatch.group(0)!}' : videoId.toUpperCase();

      if (kDebugMode) {
        print('[HeyzoScraper] 解析完成: title=$title, date=$date, actors=${actresses.length}');
      }

      return Movie(
        id: heyzoId,
        title: title,
        cover: cover,
        date: date,
        description: description,
        actors: actresses,
        samples: samples,
      );
    } catch (e, st) {
      if (kDebugMode) {
        print('[HeyzoScraper] 错误: $e');
        print('[HeyzoScraper] 堆栈: $st');
      }
      throw ScraperException('获取 Heyzo 影片信息失败', e);
    }
  }
}

/// Caribbean 爬虫
/// 参考: modules/scrapers/caribbean_scraper.py
class CaribbeanScraper extends BaseScraper {
  CaribbeanScraper({super.dio})
      : super(
          baseUrl: 'https://www.caribbeancom.com',
          customCookies: {
            'age_check_done': '1',
            'lang': 'ja',
          },
        );

  @override
  bool get canDirectAccess => true;

  @override
  String? getDirectUrl(String videoId) {
    // Caribbean 格式: 123456-789 (需要保留连字符)
    final match = RegExp(r'(\d{6})[-_](\d{3})').firstMatch(videoId);
    if (match != null) {
      final part1 = match.group(1)!;
      final part2 = match.group(2)!;
      return '$baseUrl/moviepages/$part1-$part2/index.html';
    }
    return null;
  }

  @override
  Future<List<String>> searchMovie(String videoId) async {
    final url = getDirectUrl(videoId);
    return url != null ? [url] : [];
  }

  @override
  Future<Movie?> getMovieInfo(String videoId) async {
    final url = getDirectUrl(videoId);
    if (url == null) return null;

    try {
      final page = await getPage(url);

      // 提取标题 - 使用多个选择器
      final titleEl = page.querySelector('h1.heading') ?? page.querySelector('h1');
      final title = titleEl?.text.trim() ?? '';

      // 提取封面
      String? cover;
      final match = RegExp(r'(\d{6})[-_](\d{3})').firstMatch(videoId);
      if (match != null) {
        final part1 = match.group(1)!;
        final part2 = match.group(2)!;
        cover = 'https://www.caribbeancom.com/moviepages/$part1-$part2/images/l_l.jpg';
      }

      // 提取发行日期
      String? date;
      try {
        final dateElems = page.querySelectorAll('li.movie-spec');
        for (final elem in dateElems) {
          final text = elem.text;
          if (text.contains('配信日')) {
            final span = elem.querySelector('span');
            if (span != null) {
              date = span.text.trim();
            }
            break;
          }
        }
      } catch (_) {}

      // 提取演员
      final actresses = <ActorInfo>[];
      try {
        final actorElems = page.querySelectorAll('span[itemprop="actors"] a, a[itemprop="actor"]');
        for (final elem in actorElems) {
          final name = elem.text.trim();
          if (name.isNotEmpty) {
            actresses.add(ActorInfo(id: name, name: name));
          }
        }
      } catch (_) {}

      // 提取简介
      String? description;
      try {
        final descEl = page.querySelector('.movie-comment') ?? page.querySelector('p[itemprop="description"]');
        if (descEl != null) {
          description = descEl.text.trim();
        }
      } catch (_) {}

      // 提取时长
      int? duration;
      try {
        final durationElems = page.querySelectorAll('li.movie-spec');
        for (final elem in durationElems) {
          final text = elem.text;
          if (text.contains('再生時間')) {
            final span = elem.querySelector('span');
            if (span != null) {
              final durationText = span.text.trim();
              final durationMatch = RegExp(r'(\d+)分').firstMatch(durationText);
              if (durationMatch != null) {
                duration = int.tryParse(durationMatch.group(1)!);
              }
            }
            break;
          }
        }
      } catch (_) {}

      // 提取样本图片
      final samples = <SampleImage>[];
      if (match != null) {
        final part1 = match.group(1)!;
        final part2 = match.group(2)!;
        for (int i = 1; i <= 5; i++) {
          final imgUrl = 'https://www.caribbeancom.com/moviepages/$part1-$part2/images/l/${i.toString().padLeft(3, '0')}.jpg';
          samples.add(SampleImage(
            id: 'sample_$i',
            src: imgUrl,
            thumbnail: imgUrl,
          ));
        }
      }

      return Movie(
        id: videoId.toUpperCase().replaceAll('_', '-'),
        title: title,
        cover: cover,
        date: date,
        description: description,
        duration: duration,
        actors: actresses,
        samples: samples,
      );
    } catch (e, st) {
      if (kDebugMode) {
        print('[CaribbeanScraper] 错误: $e');
        print('[CaribbeanScraper] 堆栈: $st');
      }
      throw ScraperException('获取 Caribbean 影片信息失败', e);
    }
  }
}

/// 10Musume (1Pondo) 爬虫
/// 参考: modules/scrapers/musume_scraper.py
class MusumeScraper extends BaseScraper {
  MusumeScraper({super.dio}) : super(baseUrl: 'https://www.10musume.com');

  @override
  bool get canDirectAccess => true;

  @override
  String? getDirectUrl(String videoId) {
    final match = RegExp(r'(\d{6})[-_](\d{2})', caseSensitive: false).firstMatch(videoId);
    if (match != null) {
      return '$baseUrl/movies/${match.group(1)}_${match.group(2)}/';
    }
    return null;
  }

  @override
  Future<List<String>> searchMovie(String videoId) async {
    final url = getDirectUrl(videoId);
    return url != null ? [url] : [];
  }

  @override
  Future<Movie?> getMovieInfo(String videoId) async {
    final url = getDirectUrl(videoId);
    if (url == null) return null;

    try {
      // 尝试从 API 获取数据
      final match = RegExp(r'(\d{6})[-_](\d{2})', caseSensitive: false).firstMatch(videoId);
      if (match == null) return null;

      final number = '${match.group(1)}_${match.group(2)}';
      final apiUrl = 'https://www.10musume.com/dyn/phpauto/movie_details/movie_id/$number.json';

      try {
        final dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ));
        final response = await dio.get(
          apiUrl,
          options: Options(
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36',
              'Referer': 'https://www.10musume.com/movies/',
            },
          ),
        );

        if (response.statusCode == 200 && response.data is Map) {
          final data = response.data as Map<String, dynamic>;
          return _parseApiData(data, videoId);
        }
      } catch (e) {
        // API 失败，尝试解析 HTML 页面
      }

      // 回退到 HTML 解析
      final page = await getPage(url);
      return _parseHtmlPage(page, videoId);
    } catch (e) {
      throw ScraperException('获取 10Musume 影片信息失败', e);
    }
  }

  Movie? _parseApiData(Map<String, dynamic> data, String videoId) {
    try {
      final title = data['Title'] as String? ?? '';
      final cover = data['ThumbHigh'] as String? ?? data['MovieThumb'] as String? ?? '';
      final date = data['Release'] as String? ?? '';
      final durationSec = data['Duration'] as int? ?? 0;
      final duration = durationSec > 0 ? durationSec ~/ 60 : null;

      // 提取演员
      final actresses = <ActorInfo>[];
      final actorsData = data['ActressesJa'] as List?;
      if (actorsData != null) {
        for (final actor in actorsData) {
          if (actor is String) {
            actresses.add(ActorInfo(id: actor, name: actor));
          }
        }
      } else if (data['Actor'] != null) {
        actresses.add(ActorInfo(id: data['Actor'], name: data['Actor']));
      }

      // 提取简介
      final description = data['Desc'] as String? ?? '';

      // 构建样本图片
      final samples = <SampleImage>[];
      final movieId = data['MovieID'] as String?;
      if (movieId != null) {
        for (int i = 1; i <= 5; i++) {
          samples.add(SampleImage(
            id: 'sample_$i',
            src: 'https://www.10musume.tv/moviepages/$movieId/images/popu/$i.jpg',
            thumbnail: 'https://www.10musume.tv/moviepages/$movieId/images/popu/$i.jpg',
          ));
        }
      }

      return Movie(
        id: '10MUSUME-$videoId',
        title: title,
        cover: cover,
        date: date,
        description: description,
        duration: duration,
        actors: actresses,
        samples: samples,
      );
    } catch (e) {
      return null;
    }
  }

  Movie? _parseHtmlPage(dynamic page, String videoId) {
    final titleEl = page.querySelector('.movie-title h1');
    final title = titleEl?.text.trim() ?? '';

    final coverEl = page.querySelector('.movie-thumbnail img');
    final cover = coverEl?.attributes['src'] ?? '';

    return Movie(
      id: '10MUSUME-$videoId',
      title: title,
      cover: cover,
    );
  }
}

/// 1Pondo 爬虫
/// 参考: modules/scrapers/pondo_scraper.py
class OnePondoScraper extends BaseScraper {
  OnePondoScraper({super.dio}) : super(baseUrl: 'https://www.1pondo.tv');

  @override
  bool get canDirectAccess => true;

  @override
  String? getDirectUrl(String videoId) {
    final match = RegExp(r'(\d{6})[-_](\d{3})', caseSensitive: false).firstMatch(videoId);
    if (match != null) {
      return '$baseUrl/movies/${match.group(1)}_${match.group(2)}';
    }
    return null;
  }

  @override
  Future<List<String>> searchMovie(String videoId) async {
    final url = getDirectUrl(videoId);
    return url != null ? [url] : [];
  }

  @override
  Future<Movie?> getMovieInfo(String videoId) async {
    final url = getDirectUrl(videoId);
    if (url == null) return null;

    try {
      // 尝试从 API 获取数据
      final match = RegExp(r'(\d{6})[-_](\d{3})', caseSensitive: false).firstMatch(videoId);
      if (match == null) return null;

      final number = '${match.group(1)}_${match.group(2)}';
      final apiUrl = 'https://www.1pondo.tv/dyn/phpauto/movie_details/movie_id/$number.json';

      try {
        final dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ));
        final response = await dio.get(
          apiUrl,
          options: Options(
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36',
              'Referer': 'https://www.1pondo.tv/movies/',
            },
          ),
        );

        if (response.statusCode == 200 && response.data is Map) {
          final data = response.data as Map<String, dynamic>;
          return _parseApiData(data, videoId);
        }
      } catch (e) {
        // API 失败，尝试解析 HTML 页面
      }

      // 回退到 HTML 解析
      final page = await getPage(url);
      return _parseHtmlPage(page, videoId);
    } catch (e) {
      throw ScraperException('获取 1Pondo 影片信息失败', e);
    }
  }

  Movie? _parseApiData(Map<String, dynamic> data, String videoId) {
    try {
      final title = data['Title'] as String? ?? '';
      final cover = data['ThumbHigh'] as String? ?? data['MovieThumb'] as String? ?? '';
      final date = data['Release'] as String? ?? '';
      final durationSec = data['Duration'] as int? ?? 0;
      final duration = durationSec > 0 ? durationSec ~/ 60 : null;

      // 提取演员
      final actresses = <ActorInfo>[];
      final actorsData = data['ActressesJa'] as List?;
      if (actorsData != null) {
        for (final actor in actorsData) {
          if (actor is String) {
            actresses.add(ActorInfo(id: actor, name: actor));
          }
        }
      } else if (data['Actor'] != null) {
        actresses.add(ActorInfo(id: data['Actor'], name: data['Actor']));
      }

      // 提取简介
      final description = data['Desc'] as String? ?? '';

      // 构建样本图片
      final samples = <SampleImage>[];
      final movieId = data['MovieID'] as String?;
      if (movieId != null) {
        for (int i = 1; i <= 5; i++) {
          samples.add(SampleImage(
            id: 'sample_$i',
            src: 'https://www.1pondo.tv/moviepages/$movieId/images/popu/$i.jpg',
            thumbnail: 'https://www.1pondo.tv/moviepages/$movieId/images/popu/$i.jpg',
          ));
        }
      }

      return Movie(
        id: '1PONDO-$videoId',
        title: title,
        cover: cover,
        date: date,
        description: description,
        duration: duration,
        actors: actresses,
        samples: samples,
      );
    } catch (e) {
      return null;
    }
  }

  Movie? _parseHtmlPage(dynamic page, String videoId) {
    final titleEl = page.querySelector('.movie-title h1');
    final title = titleEl?.text.trim() ?? '';

    final coverEl = page.querySelector('.movie-thumbnail img');
    final cover = coverEl?.attributes['src'] ?? '';

    return Movie(
      id: '1PONDO-$videoId',
      title: title,
      cover: cover,
    );
  }
}

/// Pacopacomama 爬虫
/// 参考: modules/scrapers/pacopacomama_scraper.py
class PacopacomamaScraper extends BaseScraper {
  PacopacomamaScraper({super.dio}) : super(baseUrl: 'https://www.pacopacomama.com');

  @override
  bool get canDirectAccess => true;

  @override
  String? getDirectUrl(String videoId) {
    final match = RegExp(r'(\d{6})[-_](\d{3})', caseSensitive: false).firstMatch(videoId);
    if (match != null) {
      return '$baseUrl/movies/${match.group(1)}_${match.group(2)}/';
    }
    return null;
  }

  @override
  Future<List<String>> searchMovie(String videoId) async {
    final url = getDirectUrl(videoId);
    return url != null ? [url] : [];
  }

  @override
  Future<Movie?> getMovieInfo(String videoId) async {
    final url = getDirectUrl(videoId);
    if (url == null) return null;

    try {
      // 尝试从 API 获取数据
      final match = RegExp(r'(\d{6})[-_](\d{3})', caseSensitive: false).firstMatch(videoId);
      if (match == null) return null;

      final number = '${match.group(1)}_${match.group(2)}';
      final apiUrl = 'https://www.pacopacomama.com/dyn/phpauto/movie_details/movie_id/$number.json';

      try {
        final dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ));
        final response = await dio.get(
          apiUrl,
          options: Options(
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36',
              'Referer': 'https://www.pacopacomama.com/movies/',
            },
          ),
        );

        if (response.statusCode == 200 && response.data is Map) {
          final data = response.data as Map<String, dynamic>;
          return _parseApiData(data, videoId);
        }
      } catch (e) {
        // API 失败，尝试解析 HTML 页面
      }

      // 回退到 HTML 解析
      final page = await getPage(url);
      return _parseHtmlPage(page, videoId);
    } catch (e) {
      throw ScraperException('获取 Pacopacomama 影片信息失败', e);
    }
  }

  Movie? _parseApiData(Map<String, dynamic> data, String videoId) {
    try {
      final title = data['Title'] as String? ?? '';
      final cover = data['ThumbHigh'] as String? ?? data['MovieThumb'] as String? ?? '';
      final date = data['Release'] as String? ?? '';
      final durationSec = data['Duration'] as int? ?? 0;
      final duration = durationSec > 0 ? durationSec ~/ 60 : null;

      // 提取演员
      final actresses = <ActorInfo>[];
      final actorsData = data['ActressesJa'] as List?;
      if (actorsData != null) {
        for (final actor in actorsData) {
          if (actor is String) {
            actresses.add(ActorInfo(id: actor, name: actor));
          }
        }
      } else if (data['Actor'] != null) {
        actresses.add(ActorInfo(id: data['Actor'], name: data['Actor']));
      }

      // 提取简介
      final description = data['Desc'] as String? ?? '';

      // 构建样本图片
      final samples = <SampleImage>[];
      final movieId = data['MovieID'] as String?;
      if (movieId != null) {
        for (int i = 1; i <= 5; i++) {
          samples.add(SampleImage(
            id: 'sample_$i',
            src: 'https://www.pacopacomama.com/moviepages/$movieId/images/popu/$i.jpg',
            thumbnail: 'https://www.pacopacomama.com/moviepages/$movieId/images/popu/$i.jpg',
          ));
        }
      }

      return Movie(
        id: 'PACOPACOMAMA-$videoId',
        title: title,
        cover: cover,
        date: date,
        description: description,
        duration: duration,
        actors: actresses,
        samples: samples,
      );
    } catch (e) {
      return null;
    }
  }

  Movie? _parseHtmlPage(dynamic page, String videoId) {
    final titleEl = page.querySelector('.movie-title h1');
    final title = titleEl?.text.trim() ?? '';

    final coverEl = page.querySelector('.movie-thumbnail img');
    final cover = coverEl?.attributes['src'] ?? '';

    return Movie(
      id: 'PACOPACOMAMA-$videoId',
      title: title,
      cover: cover,
    );
  }
}

/// Kin8tengoku 爬虫
/// 参考: modules/scrapers/kin8tengoku_scraper.py
class Kin8tengokuScraper extends BaseScraper {
  Kin8tengokuScraper({super.dio}) : super(baseUrl: 'https://www.kin8tengoku.com');

  @override
  bool get canDirectAccess => true;

  @override
  String? getDirectUrl(String videoId) {
    // kin8-xxxx 或纯数字
    final match = RegExp(r'kin8[^\d]*(\d+)', caseSensitive: false).firstMatch(videoId);
    if (match != null) {
      final id = match.group(1);
      return 'https://www.kin8tengoku.com/moviepages/$id/index.html';
    }
    // 尝试纯数字
    final numMatch = RegExp(r'^(\d{4,})$').firstMatch(videoId);
    if (numMatch != null) {
      return 'https://www.kin8tengoku.com/moviepages/${numMatch.group(1)}/index.html';
    }
    return null;
  }

  @override
  Future<List<String>> searchMovie(String videoId) async {
    final url = getDirectUrl(videoId);
    return url != null ? [url] : [];
  }

  @override
  Future<Movie?> getMovieInfo(String videoId) async {
    final url = getDirectUrl(videoId);
    if (url == null) return null;

    try {
      final page = await getPage(url);

      // 提取标题 - 从图片 alt 属性获取
      final titleImg = page.querySelector('img[alt]');
      String title = '';
      if (titleImg != null) {
        title = titleImg.attributes['alt']?.trim() ?? '';
      }
      if (title.isEmpty) {
        final titleEl = page.querySelector('title');
        if (titleEl != null) {
          title = titleEl.text
              .replaceAll(RegExp(r'\s*\|\s*.*'), '')
              .trim();
        }
      }

      // 提取纯数字 ID
      final idMatch = RegExp(r'(\d+)').firstMatch(videoId);
      final cleanId = idMatch?.group(1) ?? videoId;

      // 构建封面和样本图片
      final cover = 'https://www.kin8tengoku.com/$cleanId/pht/1.jpg';
      final samples = <SampleImage>[];

      // 添加大图 (2-4)
      for (int i = 2; i <= 4; i++) {
        samples.add(SampleImage(
          id: 'sample_${i}_lg',
          src: 'https://www.kin8tengoku.com/$cleanId/pht/${i}_lg.jpg',
          thumbnail: 'https://www.kin8tengoku.com/$cleanId/pht/${i}_lg.jpg',
        ));
      }
      // 添加小图 (5-13)
      for (int i = 5; i <= 13; i++) {
        samples.add(SampleImage(
          id: 'sample_$i',
          src: 'https://www.kin8tengoku.com/$cleanId/pht/$i.jpg',
          thumbnail: 'https://www.kin8tengoku.com/$cleanId/pht/$i.jpg',
        ));
      }

      // 提取演员
      final actresses = <ActorInfo>[];
      final actorLink = page.querySelector('.actor a');
      if (actorLink != null) {
        actresses.add(ActorInfo(
          id: actorLink.text.trim(),
          name: actorLink.text.trim(),
        ));
      }

      // 提取发行日期
      String date = '';
      final dateElem = page.querySelector('.release-date');
      if (dateElem != null) {
        final dateText = dateElem.text.trim();
        final dateMatch = RegExp(r'(\d{4}/\d{2}/\d{2})').firstMatch(dateText);
        if (dateMatch != null) {
          date = dateMatch.group(1)!;
        }
      }

      return Movie(
        id: 'KIN8-$cleanId',
        title: title,
        cover: cover,
        date: date,
        actors: actresses,
        samples: samples,
      );
    } catch (e) {
      throw ScraperException('获取 Kin8tengoku 影片信息失败', e);
    }
  }
}

/// TokyoHot 爬虫
/// 参考: modules/scrapers/tokyohot_scraper.py
class TokyoHotScraper extends BaseScraper {
  TokyoHotScraper({super.dio}) : super(baseUrl: 'https://my.tokyo-hot.com');

  @override
  bool get canDirectAccess => false; // 需要搜索

  @override
  String? getDirectUrl(String videoId) {
    // TokyoHot 格式: n1234, k1234, n765 等
    final match = RegExp(r'([a-z]+)(\d+)', caseSensitive: false).firstMatch(videoId);
    if (match != null) {
      final letter = match.group(1)!.toLowerCase();
      final number = match.group(2);
      return 'https://my.tokyo-hot.com/product/$letter$number/?lang=ja';
    }
    return null;
  }

  @override
  Future<List<String>> searchMovie(String videoId) async {
    // 清理影片 ID
    final match = RegExp(r'([a-z]+)(\d+)', caseSensitive: false).firstMatch(videoId);
    if (match == null) return [];

    final letter = match.group(1)!.toUpperCase();
    final number = match.group(2)!;
    final cleanId = '$letter$number';

    // 构建搜索 URL
    final searchUrl = 'https://my.tokyo-hot.com/product/?q=${cleanId.toLowerCase()}&x=0&y=0';

    try {
      final page = await getPage(searchUrl);

      // 使用 Python 版本相同的 CSS 选择器
      final productLinks = page.querySelectorAll('ul.list.slider.cf li.detail a.rm');
      if (productLinks.isEmpty) {
        // 回退：尝试其他选择器
        final fallbackLinks = page.querySelectorAll('li.detail a');
        if (fallbackLinks.isEmpty) {
          // 最后尝试：查找所有包含 /product/ 的链接
          final allLinks = page.querySelectorAll('a[href*="/product/"]');
          if (allLinks.isEmpty) return [];
          return _findBestMatch(allLinks, cleanId);
        }
        return _findBestMatch(fallbackLinks, cleanId);
      }

      return _findBestMatch(productLinks, cleanId);
    } catch (e) {
      return [];
    }
  }

  /// 从链接列表中找出最匹配的结果
  List<String> _findBestMatch(List<dynamic> links, String cleanId) {
    final results = <String>[];
    final cleanIdLower = cleanId.toLowerCase();

    for (final link in links) {
      final href = link.attributes['href'];
      if (href == null || href.isEmpty) continue;

      // 提取产品 ID
      final productIdMatch = RegExp(r'/product/([a-zA-Z0-9\-]+)/').firstMatch(href);
      if (productIdMatch == null) continue;

      // 检查描述中的作品编号
      final descriptionEl = link.querySelector('.actor');
      if (descriptionEl != null) {
        final descText = descriptionEl.text;
        final numberMatch = RegExp(r'作品番号:\s*([a-zA-Z0-9\-]+)').firstMatch(descText);
        if (numberMatch != null) {
          final foundNumber = numberMatch.group(1)!.toLowerCase();
          if (foundNumber == cleanIdLower) {
            final fullUrl = href.startsWith('http')
                ? href
                : 'https://my.tokyo-hot.com$href';
            return [fullUrl];
          }
        }
      }

      // 检查标题中的编号
      final titleEl = link.querySelector('.title');
      if (titleEl != null) {
        final titleText = titleEl.text.trim();
        final titleMatch = RegExp(r'([a-zA-Z]+[\-]?\d+)', caseSensitive: false)
            .firstMatch(titleText);
        if (titleMatch != null) {
          final titleNumber = titleMatch.group(1)!.toLowerCase();
          if (titleNumber == cleanIdLower) {
            final fullUrl = href.startsWith('http')
                ? href
                : 'https://my.tokyo-hot.com$href';
            return [fullUrl];
          }
        }
      }

      // 如果没有精确匹配，添加到结果列表（URL 中包含产品 ID）
      if (href.contains('/product/')) {
        final fullUrl = href.startsWith('http')
            ? href
            : 'https://my.tokyo-hot.com$href';
        // 添加 lang=ja 参数
        if (!fullUrl.contains('?')) {
          results.add('$fullUrl?lang=ja');
        } else if (!fullUrl.contains('lang=')) {
          results.add('$fullUrl&lang=ja');
        } else {
          results.add(fullUrl);
        }
      }
    }

    return results;
  }

  @override
  Future<Movie?> getMovieInfo(String videoId) async {
    try {
      final searchResults = await searchMovie(videoId);
      if (searchResults.isEmpty) return null;

      final page = await getPage(searchResults.first);

      // 提取标题 - 使用更精确的选择器
      final titleEl = page.querySelector('#main .contents h2');
      final title = titleEl?.text.trim() ?? '';

      // 提取简介
      final descEl = page.querySelector('#main .contents .sentence');
      final description = descEl?.text.trim() ?? '';

      // 提取封面
      String? cover;
      final jacketEl = page.querySelector('a[href*="/jacket/"]');
      if (jacketEl != null) {
        cover = jacketEl.attributes['href'];
      }
      if (cover == null || cover.isEmpty) {
        final videoEl = page.querySelector('video[poster]');
        if (videoEl != null) {
          cover = videoEl.attributes['poster'];
        }
      }

      // 提取演员
      final actresses = <ActorInfo>[];
      final infoWrapper = page.querySelector('#main .contents .infowrapper');
      if (infoWrapper != null) {
        // 查找出演者 dt
        final dts = infoWrapper.querySelectorAll('dt');
        for (final dt in dts) {
          if (dt.text.contains('出演者')) {
            final dd = dt.nextElementSibling;
            if (dd != null) {
              final actorLinks = dd.querySelectorAll('a');
              for (final link in actorLinks) {
                final name = link.text.trim();
                if (name.isNotEmpty) {
                  actresses.add(ActorInfo(
                    id: name,
                    name: name,
                  ));
                }
              }
            }
            break;
          }
        }
      }

      // 提取发行日期
      String? date;
      if (infoWrapper != null) {
        final dts = infoWrapper.querySelectorAll('dt');
        for (final dt in dts) {
          if (dt.text.contains('配信開始日')) {
            final dd = dt.nextElementSibling;
            if (dd != null) {
              date = dd.text.trim();
            }
            break;
          }
        }
      }

      // 提取时长
      int? duration;
      if (infoWrapper != null) {
        final dts = infoWrapper.querySelectorAll('dt');
        for (final dt in dts) {
          if (dt.text.contains('収録時間')) {
            final dd = dt.nextElementSibling;
            if (dd != null) {
              final durationText = dd.text.trim();
              final durationMatch = RegExp(r'(\d{2}):(\d{2}):(\d{2})').firstMatch(durationText);
              if (durationMatch != null) {
                final hours = int.tryParse(durationMatch.group(1) ?? '0') ?? 0;
                final minutes = int.tryParse(durationMatch.group(2) ?? '0') ?? 0;
                final seconds = int.tryParse(durationMatch.group(3) ?? '0') ?? 0;
                duration = hours * 60 + minutes + (seconds >= 30 ? 1 : 0);
              }
            }
            break;
          }
        }
      }

      // 提取样本图片
      final samples = <SampleImage>[];
      final vcapDiv = page.querySelector('#main .contents .vcap');
      if (vcapDiv != null) {
        final capLinks = vcapDiv.querySelectorAll('a[rel="cap"]');
        int sampleIndex = 0;
        for (final link in capLinks) {
          final href = link.attributes['href'] ?? '';
          if (href.isNotEmpty) {
            samples.add(SampleImage(
              id: 'sample_${sampleIndex++}',
              src: href.startsWith('http') ? href : 'https://my.tokyo-hot.com$href',
              thumbnail: href.startsWith('http') ? href : 'https://my.tokyo-hot.com$href',
            ));
          }
        }
      }

      // 规范化 ID
      final match = RegExp(r'([a-z]+)(\d+)', caseSensitive: false).firstMatch(videoId);
      final cleanId = match != null
          ? '${match.group(1)!.toUpperCase()}${match.group(2)}'
          : videoId.toUpperCase();

      // 如果没有封面，使用第一张样本图
      if ((cover == null || cover.isEmpty) && samples.isNotEmpty) {
        cover = samples.first.src;
      }

      return Movie(
        id: cleanId,
        title: title,
        cover: cover,
        date: date,
        description: description,
        duration: duration,
        actors: actresses,
        samples: samples,
      );
    } catch (e) {
      throw ScraperException('获取 TokyoHot 影片信息失败', e);
    }
  }
}

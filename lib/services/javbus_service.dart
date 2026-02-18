import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../models/search_result.dart';

/// JavBus 服务
/// 移植自 modules/javbus_service/
class JavBusService {
  late final String _baseUrl;
  late final Dio _dio;
  final bool _enabled;

  JavBusService({
    String? baseUrl,
    bool enabled = true,
    int timeout = 15,
  })  : _baseUrl = baseUrl ?? 'https://www.javbus.com',
        _enabled = enabled {
    _dio = Dio(BaseOptions(
      connectTimeout: Duration(seconds: timeout),
      receiveTimeout: Duration(seconds: timeout),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'Referer': 'https://www.javbus.com/',
      },
      followRedirects: true,
      validateStatus: (status) => status != null && status < 500,
    ));
  }

  /// 搜索影片（带分页）
  Future<SearchPagedResult> search(String keyword, {int page = 1, bool uncensored = false}) async {
    if (!_enabled) return const SearchPagedResult.empty();

    try {
      // JavBus 搜索 URL 格式:
      // 有码: /search/{keyword}/{page}
      // 无码: /uncensored/search/{keyword}/{page}
      final url = uncensored
          ? '$_baseUrl/uncensored/search/${Uri.encodeComponent(keyword)}/$page'
          : '$_baseUrl/search/${Uri.encodeComponent(keyword)}/$page';
      if (kDebugMode) print('JavBus 搜索 URL: $url (page: $page, uncensored: $uncensored)');

      final response = await _dio.get(url).timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          throw Exception('请求超时 (20秒) - 可能需要配置镜像站');
        },
      );

      if (kDebugMode) print('响应状态: ${response.statusCode}');

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final html = response.data as String;
      if (kDebugMode) print('HTML 长度: ${html.length}');

      // 检查是否被重定向到验证页面
      if (html.contains('verifying') || html.contains('captcha') || html.contains('验证')) {
        throw Exception('需要人机验证 - 请更换镜像站');
      }

      final document = html_parser.parse(html);

      final results = <SearchResultItem>[];

      // 使用正确的 CSS 选择器 (参考 Python 版本)
      final movieItems = document.querySelectorAll('#waterfall .item');
      if (kDebugMode) print('找到 ${movieItems.length} 个搜索结果');

      for (final item in movieItems) {
        try {
          // 获取链接
          final linkTag = item.querySelector('a.movie-box') ?? item.querySelector('a');
          if (linkTag == null) continue;

          // 解析封面图 - 检查多个属性
          final imgTag = item.querySelector('.photo-frame img');
          String? imgUrl;
          if (imgTag != null) {
            // 按优先级检查属性: data-src, data-original, data-echo, src
              imgUrl = imgTag.attributes['data-src'] ??
                      imgTag.attributes['data-original'] ??
                      imgTag.attributes['data-echo'] ??
                      imgTag.attributes['src'];

            // 过滤掉 loading/blank 图片
            if (imgUrl != null && (imgUrl.contains('loading') || imgUrl.contains('blank'))) {
              imgUrl = null;
            }

            // 转换为绝对 URL
            if (imgUrl != null) {
              if (imgUrl.startsWith('//')) {
                imgUrl = 'https:$imgUrl';
              } else if (imgUrl.startsWith('/')) {
                imgUrl = '$_baseUrl$imgUrl';
              }
            }
          }

          // 解析影片编号与日期
          String code = '';
          String releaseDate = '';
          final infoDates = item.querySelectorAll('.photo-info date');
          if (infoDates.isNotEmpty) {
            code = infoDates[0].text.trim();
            if (infoDates.length > 1) {
              releaseDate = infoDates[1].text.trim();
            }
          }

          final movieUrl = linkTag.attributes['href']?.trim() ?? '';
          final fallbackId = movieUrl.endsWith('/')
              ? movieUrl.split('/').where((s) => s.isNotEmpty).last
              : movieUrl.split('/').last;
          final movieId = code.isNotEmpty ? code : fallbackId;

          // 解析标题
          String title = '';
          if (imgTag != null) {
            title = imgTag.attributes['title']?.trim() ?? '';
          }
          if (title.isEmpty) {
            final titleSpan = item.querySelector('.photo-info span');
            if (titleSpan != null) {
              title = titleSpan.text.trim();
            }
          }
          if (title.isEmpty) {
            title = movieId;
          }

          // 检查是否有磁力链接标识
          // 注意：JavBus 搜索结果页面通常不显示磁力状态
          // 这里检查可能存在的磁力图标或标识
          bool? hasMagnets;
          final magnetIcon = item.querySelector('.magnet-icon, .fa-magnet, .icon-magnet');

          // 如果找到磁力图标，标记为有磁力
          // 否则保持 null（未知状态，需要进入详情页确认）
          if (magnetIcon != null) {
            hasMagnets = true;
          }

          if (movieId.isNotEmpty) {
            results.add(SearchResultItem(
              id: movieId.toUpperCase(),
              title: title,
              cover: imgUrl,
              date: releaseDate.isNotEmpty ? releaseDate : null,
              type: 'movie',
              hasMagnets: hasMagnets,
            ));
          }
        } catch (e) {
          if (kDebugMode) print('解析影片项失败: $e');
          continue;
        }
      }

      if (kDebugMode) print('返回 ${results.length} 个结果');

      // 解析分页信息
      final pagination = _parsePagination(document, page);

      return SearchPagedResult(
        items: results,
        currentPage: page,
        hasNextPage: pagination['hasNextPage'] as bool,
        nextPage: pagination['nextPage'] as int?,
      );
    } on DioException catch (e) {
      if (kDebugMode) print('Dio 错误: ${e.message}, 类型: ${e.type}');
      String errorMsg = '网络请求失败';
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        errorMsg = '连接超时 - 请检查网络或配置镜像站';
      } else if (e.type == DioExceptionType.connectionError) {
        errorMsg = '无法连接服务器 - 请配置镜像站';
      } else if (e.response?.statusCode == 403 || e.response?.statusCode == 404) {
        errorMsg = '访问被拒绝 - 请更换镜像站';
      }
      throw Exception(errorMsg);
    } catch (e) {
      if (kDebugMode) print('JavBus 搜索错误: $e');
      throw Exception('搜索失败: $e');
    }
  }

  /// 解析分页信息
  Map<String, dynamic> _parsePagination(dynamic document, int currentPage) {
    try {
      final paginationEl = document.querySelector('.pagination');
      if (paginationEl == null) {
        return {'hasNextPage': false, 'nextPage': null};
      }

      // 查找所有页码链接
      final pageLinks = paginationEl.querySelectorAll('a');
      final pages = <int>[];
      int? nextPage;

      for (final link in pageLinks) {
        final href = link.attributes['href'];
        if (href == null || href.isEmpty) continue;

        // 提取页码: /search/keyword/2 -> 2
        final pageMatch = RegExp(r'/(\d+)/?$').firstMatch(href);
        if (pageMatch != null) {
          final pageNum = int.tryParse(pageMatch.group(1) ?? '');
          if (pageNum != null) {
            pages.add(pageNum);
          }
        }

        // 检查是否有"下一页"链接
        final text = link.text.trim();
        if (text == '›' || text == 'Next' || text == '下一页') {
          final nextMatch = RegExp(r'/(\d+)/?$').firstMatch(href);
          if (nextMatch != null) {
            nextPage = int.tryParse(nextMatch.group(1) ?? '');
          }
        }
      }

      // 去重并排序
      final uniquePages = pages.toSet().toList()..sort();

      // 判断是否有下一页 - 如果有页码大于当前页，或者有"下一页"链接
      final hasHigherPage = uniquePages.any((p) => p > currentPage);
      final hasNextPage = nextPage != null || hasHigherPage;

      return {
        'hasNextPage': hasNextPage,
        'nextPage': nextPage ?? (hasHigherPage ? currentPage + 1 : null),
        'pages': uniquePages,
      };
    } catch (e) {
      if (kDebugMode) print('解析分页失败: $e');
      return {'hasNextPage': false, 'nextPage': null};
    }
  }

  /// 获取最新影片列表（带分页）
  /// 当 page=1 时访问首页，page>1 时访问 /page/{page}
  Future<SearchPagedResult> getLatestMovies({int page = 1, bool uncensored = false}) async {
    if (!_enabled) return const SearchPagedResult.empty();

    try {
      // JavBus 首页或分页 URL:
      // 有码: / 或 /page/{page}
      // 无码: /uncensored 或 /uncensored/page/{page}
      final url = uncensored
          ? (page == 1 ? '$_baseUrl/uncensored' : '$_baseUrl/uncensored/page/$page')
          : (page == 1 ? _baseUrl : '$_baseUrl/page/$page');
      if (kDebugMode) print('JavBus 最新影片 URL: $url (page: $page, uncensored: $uncensored)');

      final response = await _dio.get(url).timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          throw Exception('请求超时 (20秒) - 可能需要配置镜像站');
        },
      );

      if (kDebugMode) print('响应状态: ${response.statusCode}');

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final html = response.data as String;
      if (kDebugMode) print('HTML 长度: ${html.length}');

      // 检查是否被重定向到验证页面
      if (html.contains('verifying') || html.contains('captcha') || html.contains('验证')) {
        throw Exception('需要人机验证 - 请更换镜像站');
      }

      final document = html_parser.parse(html);

      final results = <SearchResultItem>[];

      // 使用相同的 CSS 选择器
      final movieItems = document.querySelectorAll('#waterfall .item');
      if (kDebugMode) print('找到 ${movieItems.length} 个影片');

      for (final item in movieItems) {
        try {
          // 获取链接
          final linkTag = item.querySelector('a.movie-box') ?? item.querySelector('a');
          if (linkTag == null) continue;

          // 解析封面图
          final imgTag = item.querySelector('.photo-frame img');
          String? imgUrl;
          if (imgTag != null) {
            imgUrl = imgTag.attributes['data-src'] ??
                    imgTag.attributes['data-original'] ??
                    imgTag.attributes['data-echo'] ??
                    imgTag.attributes['src'];

            if (imgUrl != null && (imgUrl.contains('loading') || imgUrl.contains('blank'))) {
              imgUrl = null;
            }

            if (imgUrl != null) {
              if (imgUrl.startsWith('//')) {
                imgUrl = 'https:$imgUrl';
              } else if (imgUrl.startsWith('/')) {
                imgUrl = '$_baseUrl$imgUrl';
              }
            }
          }

          // 解析影片编号与日期
          String code = '';
          String releaseDate = '';
          final infoDates = item.querySelectorAll('.photo-info date');
          if (infoDates.isNotEmpty) {
            code = infoDates[0].text.trim();
            if (infoDates.length > 1) {
              releaseDate = infoDates[1].text.trim();
            }
          }

          final movieUrl = linkTag.attributes['href']?.trim() ?? '';
          final fallbackId = movieUrl.endsWith('/')
              ? movieUrl.split('/').where((s) => s.isNotEmpty).last
              : movieUrl.split('/').last;
          final movieId = code.isNotEmpty ? code : fallbackId;

          // 解析标题
          String title = '';
          if (imgTag != null) {
            title = imgTag.attributes['title']?.trim() ?? '';
          }
          if (title.isEmpty) {
            final titleSpan = item.querySelector('.photo-info span');
            if (titleSpan != null) {
              title = titleSpan.text.trim();
            }
          }
          if (title.isEmpty) {
            title = movieId;
          }

          // 检查是否有磁力链接标识
          // 注意：JavBus 搜索结果页面通常不显示磁力状态
          // 这里检查可能存在的磁力图标或标识
          bool? hasMagnets;
          final magnetIcon = item.querySelector('.magnet-icon, .fa-magnet, .icon-magnet');

          // 如果找到磁力图标，标记为有磁力
          // 否则保持 null（未知状态，需要进入详情页确认）
          if (magnetIcon != null) {
            hasMagnets = true;
          }

          if (movieId.isNotEmpty) {
            results.add(SearchResultItem(
              id: movieId.toUpperCase(),
              title: title,
              cover: imgUrl,
              date: releaseDate.isNotEmpty ? releaseDate : null,
              type: 'movie',
              hasMagnets: hasMagnets,
            ));
          }
        } catch (e) {
          if (kDebugMode) print('解析影片项失败: $e');
          continue;
        }
      }

      if (kDebugMode) print('返回 ${results.length} 个结果');

      // 解析分页信息
      final pagination = _parsePagination(document, page);

      return SearchPagedResult(
        items: results,
        currentPage: page,
        hasNextPage: pagination['hasNextPage'] as bool,
        nextPage: pagination['nextPage'] as int?,
      );
    } on DioException catch (e) {
      if (kDebugMode) print('Dio 错误: ${e.message}, 类型: ${e.type}');
      String errorMsg = '网络请求失败';
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        errorMsg = '连接超时 - 请检查网络或配置镜像站';
      } else if (e.type == DioExceptionType.connectionError) {
        errorMsg = '无法连接服务器 - 请配置镜像站';
      } else if (e.response?.statusCode == 403 || e.response?.statusCode == 404) {
        errorMsg = '访问被拒绝 - 请更换镜像站';
      }
      throw Exception(errorMsg);
    } catch (e) {
      if (kDebugMode) print('JavBus 获取最新影片失败: $e');
      throw Exception('获取失败: $e');
    }
  }

  /// 获取影片详情
  Future<Movie?> getMovieDetail(String videoId) async {
    if (!_enabled) return null;

    try {
      final url = '$_baseUrl/$videoId';
      if (kDebugMode) print('JavBus 详情 URL: $url');

      final response = await _dio.get(url).timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          throw Exception('请求超时 (20秒)');
        },
      );

      final document = html_parser.parse(response.data as String);

      // 提取标题
      final titleEl = document.querySelector('h3');
      String rawTitle = titleEl?.text.trim() ?? '';

      // 如果标题以番号开头，提取番号后面的部分作为标题
      String displayTitle;
      if (rawTitle.isEmpty) {
        displayTitle = videoId;
      } else if (rawTitle.toUpperCase().startsWith(videoId.toUpperCase())) {
        // 标题包含番号，去掉番号部分
        displayTitle = rawTitle.substring(videoId.length).trim();
        if (displayTitle.isEmpty) {
          displayTitle = rawTitle; // 如果去掉后为空，使用原标题
        }
      } else {
        // 标题不包含番号，拼接
        displayTitle = '$videoId $rawTitle';
      }

      if (kDebugMode) {
        print('[JavBus] 原始标题: "$rawTitle"');
        print('[JavBus] 显示标题: "$displayTitle"');
      }

      // 提取封面大图
      String? cover;
      final coverLinkEl = document.querySelector('a.bigImage');
      if (coverLinkEl != null) {
        final href = coverLinkEl.attributes['href'];
        if (href != null && href.isNotEmpty) {
          cover = _absoluteUrl(href);
        } else {
          final imgEl = coverLinkEl.querySelector('img');
          cover = imgEl?.attributes['src'];
        }
      }

      // 基本信息（在 .info 区域）
      String? date;
      int? duration;
      String? director;
      String? producer;      // 制作商
      String? publisher;     // 发行商
      String? series;

      final infoSection = document.querySelector('.info');

      if (kDebugMode) {
        print('[JavBus] .info 区域: ${infoSection != null ? "找到" : "未找到"}');
        if (infoSection != null) {
          print('[JavBus] .info HTML: ${infoSection.outerHtml.substring(0, infoSection.outerHtml.length > 500 ? 500 : infoSection.outerHtml.length)}...');
        }
      }

      if (infoSection != null) {
        final pTags = infoSection.querySelectorAll('p');
        for (final p in pTags) {
          final pText = p.text;

          // 简介（在 JavBus 上通常不显示，但尝试提取）
          // 简介通常在详情页的其他位置，后续添加

          // 发行日期
          if (pText.contains('發行日期:')) {
            final dateMatch = RegExp(r'(\d{4}-\d{2}-\d{2})').firstMatch(pText);
            if (dateMatch != null) {
              date = dateMatch.group(1);
            }
          }

          // 时长
          if (pText.contains('長度:')) {
            final lengthMatch = RegExp(r'(\d+)').firstMatch(pText);
            if (lengthMatch != null) {
              duration = int.tryParse(lengthMatch.group(1)!);
            }
          }

          // 导演
          if (pText.contains('導演:')) {
            final directorLink = p.querySelector('a');
            if (directorLink != null) {
              director = directorLink.text.trim();
            }
          }

          // 制作商
          if (pText.contains('製作商:')) {
            final makerLink = p.querySelector('a');
            if (makerLink != null) {
              producer = makerLink.text.trim();
            }
          }

          // 发行商
          if (pText.contains('發行商:')) {
            final publisherLink = p.querySelector('a');
            if (publisherLink != null) {
              publisher = publisherLink.text.trim();
            }
          }

          // 系列
          if (pText.contains('系列:')) {
            final seriesLink = p.querySelector('a');
            if (seriesLink != null) {
              series = seriesLink.text.trim();
            }
          }
        }

        // 类别（genres）
        final genres = <String>[];
        final genreTags = infoSection.querySelectorAll('span.genre a');
        for (final genreLink in genreTags) {
          final genreName = genreLink.text.trim();
          if (genreName.isNotEmpty) {
            genres.add(genreName);
          }
        }

        if (kDebugMode) {
          print('[JavBus] 找到 ${genres.length} 个类别: $genres');
        }

        // 演员
        final actors = <ActorInfo>[];

        // 先尝试找 div.star-name 容器
        final starNameDivs = infoSection.querySelectorAll('div.star-name');
        if (kDebugMode) {
          print('[JavBus] 找到 ${starNameDivs.length} 个 div.star-name');
        }

        for (final starDiv in starNameDivs) {
          final starLink = starDiv.querySelector('a');
          if (starLink != null) {
            final href = starLink.attributes['href'] ?? '';
            final idMatch = RegExp(r'/star/([a-z0-9-]+)', caseSensitive: false).firstMatch(href);
            final id = idMatch?.group(1)?.toLowerCase() ?? '';  // 保持小写用于头像 URL

            // JavBus 演员头像 URL 格式
            final avatar = id.isNotEmpty ? 'https://www.javbus.com/pics/actress/${id}_a.jpg' : null;

            if (kDebugMode) {
              print('[JavBus] 演员: name=${starLink.text.trim()}, id=$id, href=$href, avatar=$avatar');
            }

            actors.add(ActorInfo(
              id: id.toUpperCase(),  // 存储为大写
              name: starLink.text.trim(),
              avatar: avatar,
            ));
          }
        }

        if (kDebugMode) {
          print('[JavBus] 找到 ${actors.length} 个演员');
        }

        // 提取 gid 和 uc（用于获取磁力链接）
        String? gid;
        String? uc;
        final scriptTags = document.querySelectorAll('script');
        for (final script in scriptTags) {
          final scriptText = script.text;
          final gidMatch = RegExp(r'var\s+gid\s*=\s*(\d+)').firstMatch(scriptText);
          if (gidMatch != null) {
            gid = gidMatch.group(1);
          }
          final ucMatch = RegExp(r'var\s+uc\s*=\s*(\d+)').firstMatch(scriptText);
          if (ucMatch != null) {
            uc = ucMatch.group(1);
          }
        }

        if (kDebugMode) {
          print('[JavBus] 提取到 gid=$gid, uc=$uc');
        }

        // 提取样本预览图
        final samples = <SampleImage>[];
        final sampleBoxes = document.querySelectorAll('#sample-waterfall .sample-box');

        if (kDebugMode) {
          print('[JavBus] 找到 ${sampleBoxes.length} 个样本预览图');
        }

        for (int idx = 0; idx < sampleBoxes.length; idx++) {
          final sampleBox = sampleBoxes[idx];
          final sampleBoxEl = sampleBox;

          // 获取大图 URL
          String? bigSrcUrl;
          if (sampleBoxEl.localName == 'a') {
            final href = sampleBoxEl.attributes['href'];
            if (href != null && href.isNotEmpty) {
              bigSrcUrl = _absoluteUrl(href);
            }
          }

          // 获取缩略图 URL
          final imgTag = sampleBoxEl.querySelector('img');
          String javbusThumbUrl = '';
          if (imgTag != null) {
            final src = imgTag.attributes['src'];
            final dataSrc = imgTag.attributes['data-src'];
            javbusThumbUrl = src ?? dataSrc ?? '';
          }

          // 从缩略图路径提取 id
          String sampleId = '';
          if (javbusThumbUrl.isNotEmpty) {
            final parts = javbusThumbUrl.replaceAll('\\', '/').split('/');
            if (parts.isNotEmpty) {
              final filename = parts.last;
              final dotIndex = filename.lastIndexOf('.');
              if (dotIndex > 0) {
                sampleId = filename.substring(0, dotIndex);
              } else {
                sampleId = filename;
              }
            }
          }
          if (sampleId.isEmpty) {
            sampleId = '${videoId}_${idx + 1}';
          }

          final thumbnailUrl = javbusThumbUrl.isNotEmpty ? _absoluteUrl(javbusThumbUrl) : '';

          samples.add(SampleImage(
            id: sampleId,
            thumbnail: thumbnailUrl,
            src: bigSrcUrl,
            alt: '$displayTitle - 樣品圖像 - ${idx + 1}',
          ));
        }

        // 如果有 gid 和 uc，获取磁力链接
        List<MagnetInfo> magnetInfo = [];
        if (gid != null && gid.isNotEmpty) {
          try {
            magnetInfo = await _getMagnets(videoId, gid, uc ?? '0');
          } catch (e) {
            if (kDebugMode) print('获取磁力链接失败: $e');
          }
        }

        if (kDebugMode) {
          print('[JavBus] 影片解析完成:');
          print('  - 标题: $displayTitle');
          print('  - 封面: ${cover ?? "无"}');
          print('  - 日期: ${date ?? "无"}');
          print('  - 时长: ${duration ?? "无"}');
          print('  - 导演: ${director ?? "无"}');
          print('  - 制作商: ${producer ?? "无"}');
          print('  - 发行商: ${publisher ?? "无"}');
          print('  - 系列: ${series ?? "无"}');
          print('  - 类别数量: ${genres.length}');
          print('  - 演员数量: ${actors.length}');
          print('  - 样本图数量: ${samples.length}');
          print('  - 磁力链接数量: ${magnetInfo.length}');
        }

        return Movie(
          id: videoId.toUpperCase(),
          title: displayTitle,
          cover: cover,
          date: date,
          duration: duration,
          director: director,
          producer: producer,
          publisher: publisher,
          series: series,
          actors: actors,
          genres: genres,
          samples: samples,
          magnetInfo: magnetInfo,
          // 兼容旧版本，同时生成简单的磁力链接列表
          magnets: magnetInfo.map((m) => m.link).toList(),
          gid: gid,
          uc: uc,
        );
      }

      // 如果没有找到 .info 区域，返回基本影片信息
      return Movie(
        id: videoId.toUpperCase(),
        title: displayTitle,
        cover: cover,
        date: date,
      );
    } catch (e) {
      if (kDebugMode) print('获取影片详情失败: $e');
      throw Exception('获取影片详情失败: $e');
    }
  }

  /// 获取磁力链接（AJAX）
  Future<List<MagnetInfo>> _getMagnets(
    String movieId,
    String gid,
    String uc,
  ) async {
    final ajaxUrl = '$_baseUrl/ajax/uncledatoolsbyajax.php';

    try {
      final params = {
        'gid': gid,
        'lang': 'zh',
        'img': movieId,
        'uc': uc,
        'floor': DateTime.now().millisecondsSinceEpoch.toString(),
      };

      if (kDebugMode) {
        print('[JavBus] 请求磁力链接: $ajaxUrl');
        print('[JavBus] 参数: $params');
      }

      final response = await _dio.get(
        ajaxUrl,
        queryParameters: params,
        options: Options(
          headers: {
            'Referer': '$_baseUrl/$movieId',
            'X-Requested-With': 'XMLHttpRequest',
          },
        ),
      );

      if (kDebugMode) {
        print('[JavBus] 磁力链接响应状态: ${response.statusCode}');
        print('[JavBus] 响应内容长度: ${(response.data as String).length}');
        // 打印响应内容的前500字符用于调试
        final responseText = response.data as String;
        print('[JavBus] 响应内容预览: ${responseText.substring(0, responseText.length > 500 ? 500 : responseText.length)}');
      }

      // 直接传递原始 HTML，避免 html_parser 把 tr/td 过滤掉
      final responseText = response.data as String;
      final magnets = _parseMagnetsRaw(responseText);

      if (kDebugMode) {
        print('[JavBus] 解析到 ${magnets.length} 个磁力链接');
      }

      return magnets;
    } catch (e) {
      if (kDebugMode) print('AJAX 磁力链接请求失败: $e');
      return [];
    }
  }

  /// 解析磁力链接 - 使用正则分割 <tr> 元素
  List<MagnetInfo> _parseMagnetsRaw(String html) {
    final magnets = <MagnetInfo>[];

    try {
      if (kDebugMode) {
        print('[JavBus] HTML 内容长度: ${html.length}');
      }

      // 用于去重的 Set
      final seenBtihs = <String>{};

      // 按行分割，找到包含 <tr> 的行
      final lines = html.split('\n');
      String currentTr = '';

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('<tr')) {
          currentTr = trimmed;
        } else if (currentTr.isNotEmpty) {
          currentTr += trimmed;
          if (trimmed.contains('</tr>')) {
            // 完整的 tr，开始解析
            final magnetMatch = RegExp(r'magnet:\?xt=urn:btih:([A-F0-9a-f]{40})', caseSensitive: false).firstMatch(currentTr);
            if (magnetMatch != null) {
              final btih = magnetMatch.group(1)!.toLowerCase();

              if (!seenBtihs.contains(btih)) {
                seenBtihs.add(btih);

                // 提取完整的 magnet 链接
                final magnetLinkMatch = RegExp("magnet:\\?xt=[^\"'>\\s]+", caseSensitive: false).firstMatch(currentTr);
                String magnetLink = magnetLinkMatch?.group(0) ?? 'magnet:?xt=urn:btih:$btih';

                // 提取标题
                String title = '';
                final dnMatch = RegExp("[?&]dn=([^&\"'>\\s]+)").firstMatch(magnetLink);
                if (dnMatch != null) {
                  try {
                    title = Uri.decodeComponent(dnMatch.group(1)!);
                  } catch (_) {
                    title = dnMatch.group(1)!;
                  }
                }
                if (title.isEmpty) {
                  title = btih;
                }

                // 提取大小和日期
                String size = '';
                String shareDate = '';
                bool isHD = false;
                bool hasSubtitle = false;

                // 查找所有 td 内容
                final tdMatches = RegExp('<td[^>]*>(.*?)</td>', dotAll: true).allMatches(currentTr).toList();

                for (int i = 0; i < tdMatches.length; i++) {
                  final tdContent = tdMatches[i].group(1) ?? '';
                  // 移除 HTML 标签
                  final text = tdContent.replaceAll(RegExp('<[^>]+>'), '').trim();

                  // 检查 HD/字幕
                  if (text.contains('高清') || text.toUpperCase().contains('HD')) {
                    isHD = true;
                  }
                  if (text.contains('字幕') || text.contains('中文')) {
                    hasSubtitle = true;
                  }

                  // td[1] 通常是大小, td[2] 通常是日期
                  if (i == 1 && text.isNotEmpty) {
                    size = text;
                  }
                  if (i == 2 && text.isNotEmpty) {
                    shareDate = text;
                  }
                }

                // 解析字节数
                int numberSize = 0;
                if (size.isNotEmpty) {
                  final sizeMatch = RegExp(r'([\d.]+)\s*([KMGT]?B)?', caseSensitive: false).firstMatch(size);
                  if (sizeMatch != null) {
                    final num = double.tryParse(sizeMatch.group(1)!) ?? 0;
                    final unit = sizeMatch.group(2)?.toUpperCase() ?? 'B';
                    const multipliers = {
                      'B': 1,
                      'KB': 1024,
                      'MB': 1024 * 1024,
                      'GB': 1024 * 1024 * 1024,
                      'TB': 1024 * 1024 * 1024 * 1024
                    };
                    numberSize = (num * (multipliers[unit] ?? 1)).toInt();
                  }
                }

                // 统一日期格式
                if (shareDate.isNotEmpty) {
                  final dateMatch = RegExp(r'(\d{4}-\d{2}-\d{2})').firstMatch(shareDate);
                  if (dateMatch != null) {
                    shareDate = dateMatch.group(1)!;
                  }
                }

                magnets.add(MagnetInfo(
                  id: btih,
                  link: magnetLink,
                  isHD: isHD,
                  title: title,
                  size: size,
                  numberSize: numberSize,
                  shareDate: shareDate,
                  hasSubtitle: hasSubtitle,
                ));

                if (kDebugMode) {
                  print('[JavBus] 解析磁力: $title | 大小: $size | 日期: $shareDate | HD: $isHD');
                }
              }
            }
            currentTr = '';
          }
        }
      }

      if (kDebugMode) {
        print('[JavBus] 共解析 ${magnets.length} 个磁力链接');
      }
    } catch (e) {
      if (kDebugMode) print('[JavBus] 解析磁力列表失败: $e');
    }

    return magnets;
  }

  /// 移除 HTML 标签，获取纯文本
  String _stripHtmlTags(String html) {
    // 移除所有 HTML 标签
    final tagRegex = RegExp(r'<[^>]+>');
    var text = html.replaceAll(tagRegex, '');
    // 解码 HTML 实体
    text = text.replaceAll('&nbsp;', ' ');
    text = text.replaceAll('&lt;', '<');
    text = text.replaceAll('&gt;', '>');
    text = text.replaceAll('&amp;', '&');
    text = text.replaceAll('&quot;', '"');
    return text;
  }

  /// 将相对 URL 转换为绝对 URL
  String _absoluteUrl(String url) {
    if (url.isEmpty) return url;
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (url.startsWith('//')) {
      // 提取 base URL 的 scheme
      final schemeIndex = _baseUrl.indexOf('://');
      if (schemeIndex > 0) {
        return '${_baseUrl.substring(0, schemeIndex)}:$url';
      }
      return 'https:$url';
    }
    if (url.startsWith('/')) {
      return '$_baseUrl$url';
    }
    return '$_baseUrl/$url';
  }

  /// 获取演员详情
  Future<Actor?> getActorDetail(String actorId) async {
    if (!_enabled) return null;

    try {
      final url = '$_baseUrl/star/$actorId';
      final response = await _dio.get(url);
      final document = html_parser.parse(response.data as String);

      final nameEl = document.querySelector('.star-name h3');
      final name = nameEl?.text.trim() ?? '';

      final avatarEl = document.querySelector('.star-avatar img');
      final avatar = avatarEl?.attributes['src'] ?? '';

      // 提取信息
      final infoEls = document.querySelectorAll('.star-info p');
      String? birthday, age, height, bust, waistline, hipline, birthplace;

      for (final el in infoEls) {
        final text = el.text.trim();
        if (text.contains('生日:')) {
          birthday = text.replaceAll('生日:', '').trim();
        } else if (text.contains('年齡:')) {
          age = text.replaceAll('年齡:', '').trim();
        } else if (text.contains('身高:')) {
          height = text.replaceAll('身高:', '').trim();
        } else if (text.contains('罩杯:')) {
          bust = text.replaceAll('罩杯:', '').trim();
        } else if (text.contains('腰圍:')) {
          waistline = text.replaceAll('腰圍:', '').trim();
        } else if (text.contains('臀圍:')) {
          hipline = text.replaceAll('臀圍:', '').trim();
        } else if (text.contains('出生地:')) {
          birthplace = text.replaceAll('出生地:', '').trim();
        }
      }

      return Actor(
        id: actorId.toUpperCase(),
        name: name,
        avatar: avatar,
        birthday: birthday,
        age: age,
        height: height,
        bust: bust,
        waistline: waistline,
        hipline: hipline,
        birthplace: birthplace,
      );
    } catch (e) {
      throw Exception('获取演员详情失败: $e');
    }
  }

  /// 是否启用
  bool get isEnabled => _enabled;

  /// 设置基础 URL
  set baseUrl(String url) => _baseUrl = url;
}

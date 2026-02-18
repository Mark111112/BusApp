import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;
import '../../models/models.dart';

/// 爬虫基础类
abstract class BaseScraper {
  final Dio _dio;
  final String baseUrl;
  final Map<String, String> _customHeaders;
  final Map<String, String> _customCookies;

  BaseScraper({
    Dio? dio,
    String? baseUrl,
    Map<String, String>? customHeaders,
    Map<String, String>? customCookies,
  })  : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              headers: {
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36',
                'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
                'Accept-Language': 'ja,en-US;q=0.9,en;q=0.8',
                'Accept-Charset': 'UTF-8,*;q=0.1',
              },
            )),
        baseUrl = baseUrl ?? '',
        _customHeaders = customHeaders ?? {},
        _customCookies = customCookies ?? {};

  /// 获取页面内容（支持自定义 headers 和 cookies）
  Future<html_dom.Document> getPage(
    String url, {
    Map<String, String>? headers,
    Map<String, String>? cookies,
  }) async {
    try {
      // 合并自定义 headers
      final finalHeaders = <String, String>{
        ..._dio.options.headers.map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        ),
        ..._customHeaders,
        ...?headers,
      };

      // 构建 cookies 字符串
      final allCookies = <String, String>{..._customCookies, ...?cookies};
      String cookieHeader = '';
      if (allCookies.isNotEmpty) {
        cookieHeader = allCookies.entries
            .map((e) => '${e.key}=${e.value}')
            .join('; ');
        finalHeaders['Cookie'] = cookieHeader;
      }

      // 使用 ResponseType.plain 让 Dio 根据响应头自动处理编码
      final response = await _dio.get<String>(
        url,
        options: Options(
          headers: finalHeaders,
          responseType: ResponseType.plain,
        ),
      );

      if (response.statusCode == 200) {
        String htmlContent = response.data as String;

        // 调试日志
        if (kDebugMode) {
          print('[BaseScraper] URL: $url');
          print('[BaseScraper] Content-Type: ${response.headers['content-type']}');
          print('[BaseScraper] HTML 前100字符: ${htmlContent.length >= 100 ? htmlContent.substring(0, 100) : htmlContent}');
        }

        return html_parser.parse(htmlContent);
      }
      throw Exception('HTTP ${response.statusCode}');
    } catch (e) {
      throw Exception('获取页面失败: $e');
    }
  }

  /// 搜索影片
  Future<List<String>> searchMovie(String videoId);

  /// 获取影片信息
  Future<Movie?> getMovieInfo(String videoId);

  /// 是否可以直接访问详情页
  bool get canDirectAccess => false;

  /// 获取直接访问的 URL
  String? getDirectUrl(String videoId) => null;

  /// 清理文本
  String cleanText(String? text) {
    if (text == null) return '';
    return text
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'[\n\r\t]'), ' ');
  }
}

/// 爬虫结果
class ScraperResult {
  final Movie movie;
  final String source;

  ScraperResult({required this.movie, required this.source});
}

/// 爬虫异常
class ScraperException implements Exception {
  final String message;
  final dynamic originalError;

  ScraperException(this.message, [this.originalError]);

  @override
  String toString() => 'ScraperException: $message';
}

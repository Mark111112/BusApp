import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';

/// 115云盘本地代理服务器
/// 用于转发视频请求并添加Cookie等认证信息
class Cloud115ProxyServer {
  HttpServer? _server;
  String? _url;
  String? _cookie;
  int _port = 0;

  /// HttpClient 实例（复用连接）
  HttpClient? _client;

  /// URL 过期刷新回调
  /// 返回新的 URL 和 Cookie，如果返回 null 则表示无法刷新
  Future<Map<String, String>?> Function()? _onUrlExpired;

  /// 正在刷新 URL（防止并发刷新）
  bool _isRefreshing = false;

  /// 刷新完成的通知器
  Completer<void>? _refreshCompleter;

  /// 启动代理服务器
  Future<int> start({
    required String url,
    required String cookie,
  }) async {
    if (_server != null) {
      await stop();
    }

    _url = url;
    _cookie = cookie;

    // 创建可复用的 HttpClient（类似 Python 的 requests.Session）
    _client = HttpClient();
    _client!.autoUncompress = false;
    // 设置更长的连接超时，保持连接活跃
    _client!.connectionTimeout = const Duration(seconds: 30);
    _client!.idleTimeout = const Duration(seconds: 60);

    // 绑定到随机端口
    _server = await HttpServer.bind('127.0.0.1', 0);
    _port = _server!.port;

    if (kDebugMode) {
      print('[Proxy] 代理服务器启动在端口 $_port');
      print('[Proxy] 目标URL: $url');
    }

    _server!.listen((HttpRequest request) async {
      await _handleRequest(request);
    });

    return _port;
  }

  /// 设置 URL 过期刷新回调
  void setUrlExpiredCallback(Future<Map<String, String>?> Function()? callback) {
    _onUrlExpired = callback;
  }

  /// 更新 URL 和 Cookie（用于 URL 刷新）
  /// 同时重建 HttpClient 连接以避免 CDN 连接追踪
  void updateUrl(String url, String cookie) {
    _url = url;
    _cookie = cookie;
    // 重建连接以避免 CDN 基于连接状态的追踪
    _recreateClient();
    if (kDebugMode) {
      print('[Proxy] URL 已更新，连接已重建');
      print('[Proxy] 新 URL: $url');
    }
  }

  /// 重建 HttpClient 连接
  void _recreateClient() {
    _client?.close(force: true);
    _client = HttpClient();
    _client!.autoUncompress = false;
    _client!.connectionTimeout = const Duration(seconds: 30);
    _client!.idleTimeout = const Duration(seconds: 60);
    if (kDebugMode) {
      print('[Proxy] HttpClient 连接已重建');
    }
  }

  /// 停止代理服务器
  Future<void> stop() async {
    if (_server != null) {
      await _server!.close();
      _server = null;
      _port = 0;
    }
    if (_client != null) {
      _client!.close(force: true);
      _client = null;
    }
    if (kDebugMode) print('[Proxy] 代理服务器已停止');
  }

  /// 获取代理URL
  String get proxyUrl => 'http://127.0.0.1:$_port/video';

  /// 处理HTTP请求
  Future<void> _handleRequest(HttpRequest request) async {
    if (request.uri.path != '/video') {
      _sendNotFound(request);
      return;
    }

    if (kDebugMode) {
      print('[Proxy] 收到请求: ${request.method} ${request.uri}');
      print('[Proxy] Headers: ${request.headers}');
    }

    // 检查 client 是否可用
    if (_client == null) {
      _sendError(request, 'HttpClient not initialized');
      return;
    }

    try {
      // 构建目标请求
      String targetUrl = _url ?? '';

      // 复制Range头（用于分段下载/播放）
      final rangeHeader = request.headers.value('Range');

      // 手动跟随重定向，确保 Cookie 被传递
      HttpClientResponse? targetResponse;
      int redirectCount = 0;
      const maxRedirects = 5;

      while (redirectCount < maxRedirects) {
        final uri = Uri.parse(targetUrl);

        if (kDebugMode) {
          print('[Proxy] 请求目标: $targetUrl');
        }

        final targetRequest = await _client!.openUrl('GET', uri);

        // 添加Range头
        if (rangeHeader != null) {
          targetRequest.headers.set('Range', rangeHeader);
          if (kDebugMode) print('[Proxy] Range: $rangeHeader');
        }

        // 添加认证相关的请求头
        final cookie = _cookie ?? '';
        targetRequest.headers.set('Cookie', cookie);
        targetRequest.headers.set('Accept', '*/*');
        targetRequest.headers.set('Accept-Language', 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7');
        targetRequest.headers.set('Origin', 'https://115.com');
        targetRequest.headers.set('Referer', 'https://115.com/');
        targetRequest.headers.set('User-Agent', 'Mozilla/5.0 115Browser/27.0.5.7');

        if (kDebugMode) {
          final cookiePreview = cookie.length > 50 ? '${cookie.substring(0, 50)}...' : cookie;
          print('[Proxy] 发送Cookie: $cookiePreview');
        }

        // 发送请求
        targetResponse = await targetRequest.close();

        if (kDebugMode) {
          print('[Proxy] 响应状态: ${targetResponse.statusCode}');
          print('[Proxy] Content-Type: ${targetResponse.headers.contentType?.value}');
          print('[Proxy] Content-Length: ${targetResponse.contentLength}');
        }

        // 检查是否是重定向
        if (targetResponse.statusCode >= 300 && targetResponse.statusCode < 400) {
          final location = targetResponse.headers.value('location');
          if (location != null) {
            if (kDebugMode) {
              print('[Proxy] 重定向到: $location');
            }
            // 处理相对路径
            if (location.startsWith('/')) {
              targetUrl = '${uri.scheme}://${uri.host}$location';
            } else if (!location.startsWith('http')) {
              targetUrl = '${uri.scheme}://${uri.host}/$location';
            } else {
              targetUrl = location;
            }
            redirectCount++;
            await targetResponse.drain();
            continue;
          }
        }
        // 非 3xx 响应，退出循环
        break;
      }

      if (targetResponse == null) {
        throw Exception('无法获取响应');
      }

      // 检查 403 错误（URL 过期或 Range 限制）
      bool responseWasRefreshed = false; // 标志：是否通过 URL 刷新获得了新响应

      if (targetResponse.statusCode == 403) {
        // 读取响应体以获取更多调试信息
        String? errorBody;
        if (targetResponse.contentLength > 0 && targetResponse.contentLength < 1000) {
          try {
            final errorBytes = await targetResponse.fold<List<int>>([], (prev, chunk) => prev..addAll(chunk));
            errorBody = utf8.decode(errorBytes);
            if (kDebugMode) {
              print('[Proxy] 403 响应内容: $errorBody');
            }
          } catch (_) {
            // 忽略读取错误
          }
        } else {
          // 消费响应流
          await targetResponse.drain();
        }

        // 检查是否是 "115 pmt 3-2" 错误
        // 这个错误表示当前 URL/会话已被 115 CDN 标记，需要刷新 URL
        final isPmtError = errorBody != null && errorBody.contains('pmt 3-2');

        if (isPmtError) {
          if (kDebugMode) {
            print('[Proxy] 检测到 115 pmt 3-2 错误 - 触发 URL 刷新');
          }

          // 尝试刷新 URL
          if (_onUrlExpired != null) {
            try {
              // 如果正在刷新，等待刷新完成
              if (_isRefreshing) {
                if (kDebugMode) {
                  print('[Proxy] URL 正在刷新中，等待完成...');
                }
                await _refreshCompleter?.future.timeout(
                  const Duration(seconds: 5),
                  onTimeout: () {
                    throw Exception('URL 刷新超时');
                  },
                );
                // 等待完成后，用新 URL 重试
                final uri = Uri.parse(_url!);
                final retryRequest = await _client!.openUrl('GET', uri);
                if (rangeHeader != null) {
                  retryRequest.headers.set('Range', rangeHeader);
                }
                retryRequest.headers.set('Cookie', _cookie ?? '');
                retryRequest.headers.set('Accept', '*/*');
                retryRequest.headers.set('Accept-Language', 'zh-CN,zh;q=0.9');
                retryRequest.headers.set('Origin', 'https://115.com');
                retryRequest.headers.set('Referer', 'https://115.com/');
                retryRequest.headers.set('User-Agent', 'Mozilla/5.0 115Browser/27.0.5.7');

                final retryResponse = await retryRequest.close();

                if (kDebugMode) {
                  print('[Proxy] 等待刷新后重试响应: ${retryResponse.statusCode}');
                }

                if (retryResponse.statusCode == 206 || retryResponse.statusCode == 200) {
                  targetResponse = retryResponse;
                  responseWasRefreshed = true;
                } else {
                  throw Exception('刷新后仍返回 ${retryResponse.statusCode}');
                }
              } else {
                // 开始刷新
                _isRefreshing = true;
                _refreshCompleter = Completer<void>();

                try {
                  final newInfo = await _onUrlExpired!();
                  if (newInfo != null) {
                    final newUrl = newInfo['url'] ?? _url;
                    final newCookie = newInfo['cookie'] ?? _cookie;
                    _url = newUrl;
                    _cookie = newCookie;

                    if (kDebugMode) {
                      print('[Proxy] URL 刷新成功，使用新 URL 重试请求');
                      print('[Proxy] 新 URL: $_url');
                    }

                    // 关键：重建连接以避免 CDN 基于连接状态的追踪
                    _recreateClient();

                    // 响应已被消费，短暂延迟让新 URL 生效
                    await Future.delayed(const Duration(milliseconds: 500));

                    // 用新 URL 重试原始请求
                    final uri = Uri.parse(_url!);
                    final retryRequest = await _client!.openUrl('GET', uri);

                    if (rangeHeader != null) {
                      retryRequest.headers.set('Range', rangeHeader);
                    }
                    retryRequest.headers.set('Cookie', _cookie ?? '');
                    retryRequest.headers.set('Accept', '*/*');
                    retryRequest.headers.set('Accept-Language', 'zh-CN,zh;q=0.9');
                    retryRequest.headers.set('Origin', 'https://115.com');
                    retryRequest.headers.set('Referer', 'https://115.com/');
                    retryRequest.headers.set('User-Agent', 'Mozilla/5.0 115Browser/27.0.5.7');
                    retryRequest.headers.set('Cache-Control', 'no-cache');
                    retryRequest.headers.set('Pragma', 'no-cache');

                    final retryResponse = await retryRequest.close();

                    if (kDebugMode) {
                      print('[Proxy] 新 URL 重试响应状态: ${retryResponse.statusCode}');
                    }

                    if (retryResponse.statusCode == 206 || retryResponse.statusCode == 200) {
                      // 成功！使用新响应
                      targetResponse = retryResponse;
                      responseWasRefreshed = true;
                      if (kDebugMode) {
                        print('[Proxy] URL 刷新后请求成功！');
                      }
                    } else if (retryResponse.statusCode == 403) {
                      // 读取响应体检查是否还是 pmt 错误
                      try {
                        final errorBytes = await retryResponse.fold<List<int>>([], (prev, chunk) => prev..addAll(chunk));
                        final newErrorBody = utf8.decode(errorBytes);
                        if (newErrorBody.contains('pmt 3-2')) {
                          if (kDebugMode) {
                            print('[Proxy] 新 URL 仍返回 pmt 3-2 错误');
                          }
                          throw Exception('新 URL 仍被限制');
                        }
                      } catch (_) {
                        // 忽略读取错误
                      }
                      throw Exception('刷新后仍返回 403');
                    } else {
                      throw Exception('刷新后返回 ${retryResponse.statusCode}');
                    }
                  } else {
                    throw Exception('无法刷新下载链接');
                  }
                } finally {
                  _isRefreshing = false;
                  _refreshCompleter?.complete();
                }
              }
            } catch (e) {
              if (kDebugMode) {
                print('[Proxy] URL 刷新失败: $e');
              }
              // URL 刷新失败，返回 416
              final response = request.response;
              response.statusCode = 416;
              response.headers.add('Access-Control-Allow-Origin', '*');
              response.write('Range Not Satisfiable (URL refresh failed: $e)');
              response.close();
              return;
            }
          } else {
            // 没有刷新回调，返回 416
            final response = request.response;
            response.statusCode = 416;
            response.headers.add('Access-Control-Allow-Origin', '*');
            response.write('Range Not Satisfiable (no refresh callback)');
            response.close();
            return;
          }
        }

        // 如果不是 pmt 错误或刷新失败，继续处理常规 403
        if (!responseWasRefreshed) {
          if (kDebugMode) {
            print('[Proxy] 收到403响应，URL可能已过期，尝试刷新URL...');
          }

          // 尝试刷新 URL
          if (_onUrlExpired != null) {
            try {
              // 如果正在刷新，等待刷新完成
              if (_isRefreshing) {
                if (kDebugMode) {
                  print('[Proxy] URL 正在刷新中，等待完成...');
                }
                await _refreshCompleter?.future;
                // 使用刷新后的 URL 重试（响应已被消费）
                final uri = Uri.parse(_url!);
                final retryRequest = await _client!.openUrl('GET', uri);
                if (rangeHeader != null) {
                  retryRequest.headers.set('Range', rangeHeader);
                }
                retryRequest.headers.set('Cookie', _cookie ?? '');
                retryRequest.headers.set('Accept', '*/*');
                retryRequest.headers.set('Accept-Language', 'zh-CN,zh;q=0.9');
                retryRequest.headers.set('Origin', 'https://115.com');
                retryRequest.headers.set('Referer', 'https://115.com/');
                retryRequest.headers.set('User-Agent', 'Mozilla/5.0 115Browser/27.0.5.7');
                targetResponse = await retryRequest.close();

                if (kDebugMode) {
                  print('[Proxy] 等待刷新后重试响应: ${targetResponse.statusCode}');
                }

                if (targetResponse.statusCode == 403) {
                  throw Exception('下载链接刷新后仍无效');
                }
              } else {
                // 开始刷新
                _isRefreshing = true;
                _refreshCompleter = Completer<void>();

                try {
                  final newInfo = await _onUrlExpired!();
                  if (newInfo != null) {
                    final newUrl = newInfo['url'] ?? _url;
                    final newCookie = newInfo['cookie'] ?? _cookie;
                    _url = newUrl;
                    _cookie = newCookie;

                    if (kDebugMode) {
                      print('[Proxy] URL 刷新成功，等待片刻后重试...');
                    }

                    // 关键：重建连接以避免 CDN 基于连接状态的追踪
                    _recreateClient();

                    // 响应已被消费，短暂延迟让新 URL 生效
                    await Future.delayed(const Duration(milliseconds: 500));

                    // 重试请求
                    final uri = Uri.parse(_url!);
                    final retryRequest = await _client!.openUrl('GET', uri);

                    if (rangeHeader != null) {
                      retryRequest.headers.set('Range', rangeHeader);
                    }
                    retryRequest.headers.set('Cookie', _cookie ?? '');
                    retryRequest.headers.set('Accept', '*/*');
                    retryRequest.headers.set('Accept-Language', 'zh-CN,zh;q=0.9');
                    retryRequest.headers.set('Origin', 'https://115.com');
                    retryRequest.headers.set('Referer', 'https://115.com/');
                    retryRequest.headers.set('User-Agent', 'Mozilla/5.0 115Browser/27.0.5.7');
                    retryRequest.headers.set('Cache-Control', 'no-cache');
                    retryRequest.headers.set('Pragma', 'no-cache');

                    targetResponse = await retryRequest.close();

                    if (kDebugMode) {
                      print('[Proxy] 重试响应状态: ${targetResponse.statusCode}');
                    }

                    // 如果还是 403，放弃重试
                    if (targetResponse.statusCode == 403) {
                      throw Exception('下载链接已过期且刷新失败');
                    }
                  } else {
                    throw Exception('无法刷新下载链接');
                  }
                } finally {
                  _isRefreshing = false;
                  _refreshCompleter?.complete();
                }
              }
            } catch (e) {
              if (kDebugMode) {
                print('[Proxy] URL 刷新失败: $e');
              }
              throw Exception('下载链接已过期: $e');
            }
          } else {
            throw Exception('下载链接已过期，请重新获取');
          }
        }
      }

      // 检查响应类型，如果是 HTML 说明请求失败
      final contentType = targetResponse.headers.contentType?.value ?? '';
      if (contentType.contains('text/html') && kDebugMode) {
        print('[Proxy] 收到HTML响应，可能Cookie已过期或URL无效');

        // 打印所有响应头用于调试
        print('[Proxy] === 响应头 ===');
        targetResponse.headers.forEach((name, values) {
          print('[Proxy] $name: $values');
        });

        // 尝试读取响应内容
        final bytes = await targetResponse.fold<List<int>>(
          <int>[],
          (List<int> previous, List<int> element) => previous..addAll(element),
        );

        // 检查是否是 gzip 压缩
        if (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
          print('[Proxy] 响应是gzip压缩的');
          try {
            final decompressed = gzip.decode(bytes);
            final html = utf8.decode(decompressed);
            final preview = html.length > 300 ? html.substring(0, 300) : html;
            print('[Proxy] HTML预览: $preview');
          } catch (e) {
            print('[Proxy] 解压失败: $e');
          }
        } else {
          try {
            final html = utf8.decode(bytes.take(300).toList());
            print('[Proxy] HTML预览: $html');
          } catch (e) {
            print('[Proxy] 解码失败: $e, bytes: ${bytes.take(50).toList()}');
          }
        }

        throw Exception('收到HTML响应而非视频流');
      }

      // 设置响应头
      final response = request.response;

      // 复制重要的响应头
      if (contentType.isNotEmpty) {
        response.headers.contentType = ContentType.parse(contentType);
      }

      final contentLength = targetResponse.contentLength;
      if (contentLength >= 0) {
        response.headers.contentLength = contentLength;
      }

      // 复制其他响应头
      targetResponse.headers.forEach((name, values) {
        if (name.toLowerCase() == 'content-range') {
          response.headers.add(name, values);
        }
        if (name.toLowerCase() == 'accept-ranges') {
          response.headers.add(name, values);
        }
      });

      // 添加CORS头（允许本地访问）
      response.headers.add('Access-Control-Allow-Origin', '*');
      response.headers.add('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
      response.headers.add('Access-Control-Allow-Headers', '*');

      response.statusCode = targetResponse.statusCode;

      // 流式传输响应数据
      final completer = Completer<void>();

      targetResponse.listen(
        (data) {
          response.add(data);
        },
        onDone: () {
          response.close();
          completer.complete();
        },
        onError: (e) {
          if (kDebugMode) {
            print('[Proxy] 流传输错误: $e');
          }
          response.close();
          completer.completeError(e);
        },
        cancelOnError: false,
      );

      await completer.future;
    } catch (e) {
      if (kDebugMode) {
        print('[Proxy] 请求处理失败: $e');
      }
      _sendError(request, e);
    }
  }

  void _sendNotFound(HttpRequest request) {
    final response = request.response;
    response.statusCode = HttpStatus.notFound;
    response.write('Not Found');
    response.close();
  }

  void _sendError(HttpRequest request, Object error) {
    final response = request.response;
    response.statusCode = HttpStatus.internalServerError;
    response.write('Error: $error');
    response.close();
  }

  /// 是否正在运行
  bool get isRunning => _server != null;
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class MissAVWebViewService {
  final String _baseUrl;

  MissAVWebViewService({String? baseUrl}) : _baseUrl = baseUrl ?? 'https://missav.ai';

  Future<String?> getStreamUrl(
    String movieId, {
    required BuildContext context,
  }) async {
    final movieUrl = '$_baseUrl/$movieId';
    debugPrint('[MissAVWebView] Loading: $movieUrl');

    return Navigator.of(context).push<String?>(
      MaterialPageRoute(
        builder: (context) => _MissAVWebViewLoader(url: movieUrl, movieId: movieId),
      ),
    );
  }

  void updateBaseUrl(String baseUrl) {
    // 在新实例中生效
  }
}

class _MissAVWebViewLoader extends StatefulWidget {
  final String url;
  final String movieId;

  const _MissAVWebViewLoader({
    required this.url,
    required this.movieId,
  });

  @override
  State<_MissAVWebViewLoader> createState() => _MissAVWebViewLoaderState();
}

class _MissAVWebViewLoaderState extends State<_MissAVWebViewLoader> {
  bool _isLoading = true;
  bool _hasFoundUrl = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 30), () {
      if (mounted && !_hasFoundUrl) {
        Navigator.of(context).pop(null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('正在获取播放地址...'),
        leading: const SizedBox(),
      ),
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(widget.url)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
            ),
            onWebViewCreated: (controller) {
              _setupJavaScriptHandlers(controller);
            },
            onLoadStop: (controller, url) {
              setState(() {
                _isLoading = false;
              });
              _extractVideoUrl(controller);
            },
            onConsoleMessage: (controller, consoleMessage) {
              debugPrint('[WebView Console] ${consoleMessage.message}');
            },
            onReceivedError: (controller, request, error) {
              setState(() {
                _isLoading = false;
              });
              debugPrint('[WebView Error] ${error.description}');
            },
            onProgressChanged: (controller, progress) {
              if (progress == 100) {
                setState(() {
                  _isLoading = false;
                });
              }
            },
          ),
          if (_isLoading)
            const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在连接 MissAV...'),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _setupJavaScriptHandlers(InAppWebViewController controller) {
    controller.addJavaScriptHandler(
      handlerName: 'onVideoUrlFound',
      callback: (args) {
        if (args.isNotEmpty && args[0] is String) {
          final url = args[0] as String;
          debugPrint('[MissAVWebView] Found URL: $url');
          _hasFoundUrl = true;
          if (mounted) {
            Navigator.of(context).pop(url);
          }
        }
      },
    );
  }

  Future<void> _extractVideoUrl(InAppWebViewController controller) async {
    await Future.delayed(const Duration(milliseconds: 1500));

    const jsCode = r'''
(function() {
  try {
    const scripts = document.querySelectorAll('script');
    for (let script of scripts) {
      const text = script.textContent;
      if (text && text.includes('m3u8')) {
        const match1 = text.match(/m3u8\|([a-f0-9\|]+)\|com\|surrit\|https\|video/);
        if (match1) {
          const parts = match1[1].split('|').reverse();
          const uuid = parts.join('-');
          if (/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(uuid)) {
            return 'https://surrit.com/' + uuid + '/playlist.m3u8';
          }
        }
        const match2 = text.match(/https:\/\/surrit\.com\/([a-f0-9-]+)\/playlist\.m3u8/);
        if (match2) {
          return 'https://surrit.com/' + match2[1] + '/playlist.m3u8';
        }
      }
    }
    const video = document.querySelector('video');
    if (video && video.src) {
      if (video.src.includes('m3u8')) {
        return video.src;
      }
    }
    const allText = document.body.innerText;
    const m3u8Match = allText.match(/https:\/\/surrit\.com\/[a-f0-9-]+\/playlist\.m3u8/);
    if (m3u8Match) {
      return m3u8Match[0];
    }
    return null;
  } catch (e) {
    console.error('Extract error:', e);
    return null;
  }
})();
''';

    final result = await controller.evaluateJavascript(source: jsCode);

    if (result != null && result is String && result.isNotEmpty) {
      debugPrint('[MissAVWebView] Extracted URL: $result');
      _hasFoundUrl = true;
      if (mounted) {
        Navigator.of(context).pop(result);
      }
    }
  }
}

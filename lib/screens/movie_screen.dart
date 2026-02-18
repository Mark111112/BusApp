import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/jellyfin.dart';
import '../models/unified_library_item.dart' as ui;
import '../providers/providers.dart';
import '../services/missav_service.dart';
import '../services/missav_webview_service.dart';
import '../services/translator_service.dart';
import '../widgets/javbus_image.dart';

/// 影片详情页面
class MovieScreen extends StatefulWidget {
  const MovieScreen({super.key});

  @override
  State<MovieScreen> createState() => _MovieScreenState();
}

class _MovieScreenState extends State<MovieScreen> {
  bool _hasInitialized = false;
  bool _addedToHistory = false;
  String? _currentMovieId;
  List<ui.UnifiedLibraryItem> _cloud115Items = [];  // 115 库项目列表（支持多个文件）
  JellyfinMovie? _jellyfinFallback;  // JavBus 失败时的后备选项
  List<JellyfinMovie> _jellyfinMovies = [];
  bool _isLoadingJellyfin = false;

  // Jellyfin 按需加载的详情（用于没有 video_id 的影片）
  JellyfinMovie? _jellyfinOnDemandDetails;
  bool _isLoadingJellyfinDetails = false;

  // Scraper 详细信息状态
  String? _dmmDescription;
  bool _isLoadingDmmInfo = false;

  // MissAV 在线播放状态
  bool _isLoadingMissAV = false;

  // 翻译状态
  bool _isTranslating = false;
  Map<String, dynamic>? _translation;
  String? _dmmTranslation; // DMM 简介的翻译

  // 用于跟踪当前处理的参数，检测导航变化
  String? _lastProcessedVideoId;
  String? _lastProcessedUnifiedId;

  @override
  void initState() {
    super.initState();
    // 重置状态
    _hasInitialized = false;
    _addedToHistory = false;
    _currentMovieId = null;
    _cloud115Items = [];
    _jellyfinFallback = null;
    _jellyfinMovies = [];
    _isLoadingJellyfin = false;
    _jellyfinOnDemandDetails = null;
    _isLoadingJellyfinDetails = false;
    _dmmDescription = null;
    _isLoadingDmmInfo = false;
    _isLoadingMissAV = false;
    _isTranslating = false;
    _translation = null;
    _dmmTranslation = null;
    // 重置跟踪变量
    _lastProcessedVideoId = null;
    _lastProcessedUnifiedId = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final args = ModalRoute.of(context)?.settings.arguments;
    String? videoId;
    ui.UnifiedLibraryItem? unifiedItem;

    // 处理不同类型的参数
    if (args == null) {
      return;
    } else if (args is String) {
      videoId = args;
    } else if (args is Map<String, dynamic>) {
      videoId = args['videoId'] as String?;
      unifiedItem = args['unifiedItem'] as ui.UnifiedLibraryItem?;
      // jellyfinFallback: 当 JavBus 失败时的后备选项
      _jellyfinFallback = args['jellyfinFallback'] as JellyfinMovie?;
      // cloud115Item: 115 库项目（用于直链播放）
      final cloud115Item = args['cloud115Item'] as ui.UnifiedLibraryItem?;
      if (cloud115Item != null) {
        _cloud115Items = [cloud115Item];
      }
    }

    // 检查参数是否发生变化（用于检测导航到新的影片）
    final unifiedId = unifiedItem?.unifiedId;
    final argsChanged = (videoId != null && videoId != _lastProcessedVideoId) ||
        (unifiedId != null && unifiedId != _lastProcessedUnifiedId);

    if (argsChanged) {
      // 参数发生变化，重置状态并重新处理
      _resetState();
      _lastProcessedVideoId = videoId;
      _lastProcessedUnifiedId = unifiedId;
    } else if (_hasInitialized) {
      // 参数没变且已初始化，跳过
      return;
    }

    _hasInitialized = true;

    // 如果有 unifiedItem，使用它来初始化
    if (unifiedItem != null) {
      _cloud115Items = [unifiedItem];
      _currentMovieId = unifiedItem.videoId;
      _addedToHistory = false;

      // 如果有 videoId，尝试加载完整信息
      if (videoId != null && videoId.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          context.read<MovieProvider>().loadMovie(videoId!);
          _loadJellyfinMovies(videoId!);
        });
      } else if (unifiedItem.hasJellyfin) {
        // 没有 videoId 但有 Jellyfin 来源，按需加载详情
        final jellyfinSource = unifiedItem.jellyfinSources.firstOrNull;
        if (jellyfinSource?.itemId != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _loadJellyfinDetails(jellyfinSource!.itemId!);
          });
        }
      }
    } else if (videoId != null && videoId.isNotEmpty) {
      _currentMovieId = videoId;
      _addedToHistory = false;
      _jellyfinMovies = [];
      _dmmDescription = null;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<MovieProvider>().loadMovie(videoId!);
        _loadJellyfinMovies(videoId!);

        // 如果没有传递 cloud115Item，主动检查库中是否有匹配的 115 项目
        if (_cloud115Items.isEmpty) {
          _checkLibraryItems(videoId!);
        }
      });
    }
  }

  /// 重置状态（用于切换到新的影片时）
  void _resetState() {
    _currentMovieId = null;
    _cloud115Items = [];
    _jellyfinFallback = null;
    _jellyfinMovies = [];
    _isLoadingJellyfin = false;
    _jellyfinOnDemandDetails = null;
    _isLoadingJellyfinDetails = false;
    _dmmDescription = null;
    _isLoadingDmmInfo = false;
    _addedToHistory = false;
    _isLoadingMissAV = false;
    _isTranslating = false;
    _translation = null;
    // 清除 MovieProvider 的数据
    context.read<MovieProvider>().clear();
  }

  /// 检查库中是否有匹配的 115 项目
  /// 直接从数据库查询，不依赖 LibraryProvider.displayItems
  /// 返回所有匹配的项目（支持同一番号有多个文件）
  /// Jellyfin 项目由 _loadJellyfinMovies 方法处理
  Future<void> _checkLibraryItems(String videoId) async {
    // 使用 LibraryProvider 查询（包括 115 和 Jellyfin）
    try {
      final library = context.read<LibraryProvider>();
      final items = await library.findItemsByVideoId(videoId);

      if (items.isNotEmpty) {
        setState(() {
          _cloud115Items = items;
        });
        if (kDebugMode) {
          print('[MovieScreen] 从数据库找到 ${items.length} 个库项目');
          for (var item in items) {
            print('  - ${item.sourceDisplayName}');
          }
        }
      } else {
        if (kDebugMode) print('[MovieScreen] 库中未找到 videoId=$videoId 的项目');
      }
    } catch (e) {
      if (kDebugMode) print('[MovieScreen] 查询库失败: $e');
    }
  }

  /// 加载影片详细信息（简介）
  /// 根据番号特征自动选择正确的爬虫（TokyoHot、Heyzo、Caribbean 等）
  Future<void> _loadScraperInfo(String movieId) async {
    if (_isLoadingDmmInfo) {
      if (kDebugMode) print('[MovieScreen] 正在加载中，忽略重复请求');
      return;
    }

    if (kDebugMode) print('[MovieScreen] ========== 开始加载影片简介: $movieId ==========');

    setState(() {
      _isLoadingDmmInfo = true;
    });

    try {
      // 使用 MovieProvider 的 loadFromScraper 方法
      final movieProvider = context.read<MovieProvider>();
      await movieProvider.loadFromScraper(movieId);

      // 获取更新后的影片信息
      final updatedMovie = movieProvider.movie;
      if (updatedMovie != null && updatedMovie.description != null) {
        setState(() {
          _dmmDescription = updatedMovie.description;
          _isLoadingDmmInfo = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('简介加载成功'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        setState(() {
          _isLoadingDmmInfo = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('该影片暂无简介'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (kDebugMode) print('[MovieScreen] 加载影片信息异常: $e');
      setState(() {
        _isLoadingDmmInfo = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('加载失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 加载匹配的Jellyfin影片
  Future<void> _loadJellyfinMovies(String videoId) async {
    setState(() {
      _isLoadingJellyfin = true;
    });

    try {
      final jellyfinProvider = context.read<JellyfinProvider>();
      var movies = await jellyfinProvider.findMoviesByVideoId(videoId);


      setState(() {
        _jellyfinMovies = movies;
        _isLoadingJellyfin = false;
      });
    } catch (e) {
      setState(() {
        _jellyfinMovies = [];
        _isLoadingJellyfin = false;
      });
    }
  }

  /// 按 itemId 从 Jellyfin API 获取影片详情（用于没有 video_id 的影片）
  Future<void> _loadJellyfinDetails(String itemId) async {
    if (_isLoadingJellyfinDetails) return;

    setState(() {
      _isLoadingJellyfinDetails = true;
    });

    try {
      final jellyfinProvider = context.read<JellyfinProvider>();
      final details = await jellyfinProvider.fetchMovieDetails(itemId);

      if (mounted) {
        setState(() {
          _jellyfinOnDemandDetails = details;
          _isLoadingJellyfinDetails = false;
        });
      }
    } catch (e) {
      if (kDebugMode) print('[MovieScreen] 获取 Jellyfin 详情失败: $e');
      if (mounted) {
        setState(() {
          _isLoadingJellyfinDetails = false;
        });
      }
    }
  }

  /// MissAV 在线播放
  Future<void> _playWithMissAV() async {
    if (_currentMovieId == null) return;

    // 在 async 之前获取 context
    final config = context.read<ConfigProvider>();

    // 使用 PostFrameCallback 确保 setState 不在 build 过程中调用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _isLoadingMissAV = true;
        });
      }
    });

    // 等待一小段时间让状态更新完成
    await Future.delayed(const Duration(milliseconds: 50));

    try {
      // 优先使用 Python 服务器（如果配置了）
      if (config.pythonServerUrl.isNotEmpty) {
        final missAVService = MissAVService(
          baseUrl: config.missAvUrlPrefix,
          pythonServerUrl: config.pythonServerUrl,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('正在通过服务器获取播放地址...'),
              duration: Duration(seconds: 2),
            ),
          );
        }

        final streamUrl = await missAVService.getStreamUrl(_currentMovieId!);

        if (streamUrl != null && mounted) {
          _startPlayback(streamUrl);
          return;
        }
      }

      // 使用 WebView 方式获取播放地址
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('正在打开浏览器获取播放地址...'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      final webViewService = MissAVWebViewService(
        baseUrl: config.missAvUrlPrefix,
      );

      final streamUrl = await webViewService.getStreamUrl(
        _currentMovieId!,
        context: context,
      );

      if (streamUrl != null && mounted) {
        _startPlayback(streamUrl);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('无法获取在线播放地址，该影片可能不支持在线播放'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('在线播放失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMissAV = false;
        });
      }
    }
  }

  /// 开始播放
  void _startPlayback(String streamUrl) {
    if (!mounted) return;

    Navigator.pushNamed(
      context,
      '/player',
      arguments: {
        'url': streamUrl,
        'title': '在线播放: $_currentMovieId',
        'isLocal': false,
      },
    );
  }

  /// 翻译影片信息
  Future<void> _translateMovie() async {
    if (_currentMovieId == null) return;

    setState(() {
      _isTranslating = true;
    });

    try {
      // 直接从 SharedPreferences 读取翻译配置（使用 bus115_ 前缀）
      final prefs = await SharedPreferences.getInstance();
      final apiUrl = prefs.getString('bus115_translation_api_url') ?? '';
      final apiToken = prefs.getString('bus115_translation_api_token') ?? '';
      final model = prefs.getString('bus115_translation_model') ?? 'gpt-3.5-turbo';

      // 检查是否已配置
      if (apiUrl.isEmpty || (apiToken.isEmpty && !_isOllama(apiUrl))) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('请先在设置中配置翻译 API'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
        setState(() {
          _isTranslating = false;
        });
        return;
      }

      final movieProvider = context.read<MovieProvider>();
      final movie = movieProvider.movie;

      if (movie == null) {
        setState(() {
          _isTranslating = false;
        });
        return;
      }

      // 使用 TranslatorService 进行翻译
      final translatorService = TranslatorService();
      await translatorService.saveConfig(
        apiUrl: apiUrl,
        apiToken: apiToken,
        model: model,
      );

      int translatedCount = 0;
      final results = <String, String>{};

      // 翻译标题
      if (movie.title != null && movie.title!.isNotEmpty) {
        final titleTranslation = await translatorService.translate(movie.title!);
        if (titleTranslation != null) {
          results['title'] = titleTranslation;
          translatedCount++;
        }
        // 延迟避免请求过快
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // 翻译 JavBus 简介
      if (movie.description != null && movie.description!.isNotEmpty) {
        final descTranslation = await translatorService.translate(movie.description!);
        if (descTranslation != null) {
          results['description'] = descTranslation;
          translatedCount++;
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // 翻译 DMM 简介
      if (_dmmDescription != null && _dmmDescription!.isNotEmpty) {
        final dmmTranslation = await translatorService.translate(_dmmDescription!);
        if (dmmTranslation != null) {
          _dmmTranslation = dmmTranslation;
          translatedCount++;
        }
      }

      if (translatedCount > 0 && mounted) {
        setState(() {
          _translation = results;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('翻译完成 ($translatedCount 项)'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('翻译失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTranslating = false;
        });
      }
    }
  }

  /// 判断是否为 Ollama
  bool _isOllama(String url) {
    final lower = url.toLowerCase();
    return lower.contains('ollama') ||
        url.contains(':11434') ||
        RegExp(r'localhost|127\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.')
            .hasMatch(url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('影片详情'),
        actions: [
          // 刷新按钮
          Consumer<MovieProvider>(
            builder: (context, movie, child) {
              final isLoading = movie.isLoading;
              return IconButton(
                icon: isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                onPressed: isLoading
                    ? null
                    : () {
                        if (_currentMovieId != null) {
                          context.read<MovieProvider>().loadMovie(_currentMovieId!, forceRefresh: true);
                        }
                      },
              );
            },
          ),
          Consumer<FavoriteProvider>(
            builder: (context, favorites, child) {
              return Consumer<MovieProvider>(
                builder: (context, movie, child) {
                  if (movie.movie == null) return const SizedBox();
                  final isFav = favorites.isFavorite(movie.movie!.id);
                  return IconButton(
                    icon: Icon(isFav ? Icons.favorite : Icons.favorite_border),
                    onPressed: () {
                      // 收藏时传递影片详情，以便保存到数据库
                      favorites.toggle(movie.movie!.id, movie: movie.movie!);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(isFav ? '已取消收藏' : '已收藏'),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
          // 翻译按钮
          IconButton(
            icon: _isTranslating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.translate),
            onPressed: _isTranslating ? null : _translateMovie,
            tooltip: '翻译',
          ),
        ],
      ),
      body: Consumer<MovieProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.hasError) {
            // JavBus 失败，检查是否有 Jellyfin 后备
            if (_jellyfinFallback != null) {
              // 延迟导航，避免在 build 过程中调用 Navigator
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  Navigator.pushReplacementNamed(
                    context,
                    '/jellyfin_detail',
                    arguments: _jellyfinFallback,
                  );
                }
              });
            }
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(provider.errorMessage ?? '加载失败'),
                  if (_jellyfinFallback != null) ...[
                    const SizedBox(height: 8),
                    const Text('正在切换到 Jellyfin 详情...'),
                  ],
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('返回'),
                  ),
                ],
              ),
            );
          }

          final movie = provider.movie;

          // 如果没有 Movie 数据，但有 unifiedItem（从库传递过来的），显示 unifiedItem 的详情
          if (movie == null) {
            return _buildUnifiedItemView();
          }

          // 添加到浏览历史（确保影片ID匹配）
          if (!_addedToHistory && movie.id == _currentMovieId) {
            _addedToHistory = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              context.read<HistoryProvider>().addView(
                movieId: movie.id,
                title: movie.title,
                cover: movie.cover,
              );
            });
          }

          // 更新搜索提供者中的磁力状态缓存
          // 这样用户返回搜索结果时，该影片的磁力状态就被记录了
          final hasMagnets = movie.magnetInfo != null && movie.magnetInfo!.isNotEmpty;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            context.read<SearchProvider>().setMagnetStatus(movie.id, hasMagnets);
          });

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 封面
                if (movie.cover != null)
                  JavBusImage(
                    imageUrl: movie.cover!,
                    width: double.infinity,
                    height: 300,
                    fit: BoxFit.cover,
                  ),

                // 基本信息
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        movie.id,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        movie.title ?? '',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      // 翻译标题
                      if (_translation != null && _translation!['title'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            _translation!['title']!,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Colors.blue[700],
                                  fontStyle: FontStyle.italic,
                                ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      if (movie.date != null)
                        _InfoRow(icon: Icons.calendar_month, label: '日期', value: movie.date!),
                      if (movie.duration != null)
                        _InfoRow(icon: Icons.schedule, label: '时长', value: '${movie.duration} 分钟'),
                      if (movie.director != null)
                        _InfoRow(icon: Icons.movie_creation, label: '导演', value: movie.director!),
                      if (movie.producer != null)
                        _InfoRow(icon: Icons.video_library, label: '制作商', value: movie.producer!),
                      if (movie.publisher != null)
                        _InfoRow(icon: Icons.business, label: '发行商', value: movie.publisher!),
                      if (movie.series != null)
                        _InfoRow(icon: Icons.collections, label: '系列', value: movie.series!),
                    ],
                  ),
                ),

                // 演员
                if (movie.actors != null && movie.actors!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('演员', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: movie.actors!.map((actor) {
                            return Chip(
                              avatar: actor.avatar != null && actor.avatar!.isNotEmpty
                                  ? ClipOval(
                                      child: SizedBox(
                                        width: 32,
                                        height: 32,
                                        child: JavBusImage(
                                          imageUrl: actor.avatar!,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    )
                                  : const CircleAvatar(child: Icon(Icons.person, size: 18)),
                              label: Text(actor.name ?? ''),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),

                // 类别/标签
                if (movie.genres != null && movie.genres!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('类别', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: movie.genres!.map((genre) {
                            return Chip(
                              label: Text(genre),
                              backgroundColor: Colors.blue[50],
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),

                // 简介
                if (movie.description != null && movie.description!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('简介', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            if (_dmmDescription != null && _dmmDescription!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Chip(
                                  label: const Text('JavBus + 官网', style: TextStyle(fontSize: 10)),
                                  backgroundColor: Colors.blue[50],
                                  padding: EdgeInsets.zero,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              )
                            else
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Chip(
                                  label: const Text('JavBus', style: TextStyle(fontSize: 10)),
                                  backgroundColor: Colors.grey[300],
                                  padding: EdgeInsets.zero,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _buildDescriptionText(movie.description!),
                        // 翻译简介
                        if (_translation != null && _translation!['description'] != null)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  const Text('翻译',
                                      style: TextStyle(fontSize: 14, color: Colors.grey, fontStyle: FontStyle.italic)),
                                  const SizedBox(width: 8),
                                  Container(width: 40, height: 1, color: Colors.grey[300]),
                                ],
                              ),
                              const SizedBox(height: 8),
                              _buildDescriptionText(_translation!['description']!,
                                  style: const TextStyle(color: Colors.blue, fontStyle: FontStyle.italic)),
                            ],
                          ),
                      ],
                    ),
                  ),

                // 加载影片信息按钮（根据番号特征自动选择爬虫）
                if (!_isLoadingDmmInfo && _dmmDescription == null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          if (kDebugMode) print('[MovieScreen] 按钮被点击, _currentMovieId: $_currentMovieId');
                          if (_currentMovieId != null) {
                            _loadScraperInfo(_currentMovieId!);
                          } else {
                            if (kDebugMode) print('[MovieScreen] _currentMovieId 为 null，无法加载');
                          }
                        },
                        icon: const Icon(Icons.download),
                        label: const Text('加载影片简介（自动识别来源）'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange[50],
                        ),
                      ),
                    ),
                  ),

                // 样本预览图
                if (movie.samples != null && movie.samples!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('样本预览', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 3 / 4,
                          ),
                          itemCount: movie.samples!.length,
                          itemBuilder: (context, index) {
                            final sample = movie.samples![index];
                            return GestureDetector(
                              onTap: () {
                                // 点击查看大图，支持左右滑动
                                if (sample.src != null) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => _FullScreenImage(
                                        imageUrls: movie.samples!.map((s) => s.src).toList(),
                                        initialIndex: index,
                                        thumbnails: movie.samples!.map((s) => s.thumbnail).toList(),
                                      ),
                                    ),
                                  );
                                }
                              },
                              child: JavBusImage(
                                imageUrl: sample.thumbnail,
                                fit: BoxFit.cover,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                // 磁力链接（详细版本）
                if (movie.magnetInfo != null && movie.magnetInfo!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('磁力链接', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        ...movie.magnetInfo!.map((magnet) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    magnet.title.isNotEmpty ? magnet.title : movie.id,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (magnet.isHD)
                                  const Chip(
                                    label: Text('HD', style: TextStyle(fontSize: 10)),
                                    backgroundColor: Colors.orange,
                                    padding: EdgeInsets.zero,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                if (magnet.hasSubtitle)
                                  const Chip(
                                    label: Text('字幕', style: TextStyle(fontSize: 10)),
                                    backgroundColor: Colors.green,
                                    padding: EdgeInsets.zero,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                              ],
                            ),
                            subtitle: Row(
                              children: [
                                Icon(Icons.data_usage, size: 14, color: Colors.grey[600]),
                                const SizedBox(width: 4),
                                Text(magnet.size, style: TextStyle(color: Colors.grey[600])),
                                const SizedBox(width: 16),
                                Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                                const SizedBox(width: 4),
                                Text(magnet.shareDate, style: TextStyle(color: Colors.grey[600])),
                              ],
                            ),
                            leading: const Icon(Icons.link),
                            trailing: const Icon(Icons.content_copy, size: 18),
                            onTap: () {
                              // 复制磁力链接
                              Clipboard.setData(ClipboardData(text: magnet.link));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('磁力链接已复制')),
                              );
                            },
                          ),
                        )),
                      ],
                    ),
                  ),

                // 磁力链接（简单版本，兼容旧数据）
                if (movie.magnetInfo == null && movie.magnets != null && movie.magnets!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('磁力链接', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        ...movie.magnets!.map((magnet) => ListTile(
                          title: Text(magnet, maxLines: 1, overflow: TextOverflow.ellipsis),
                          leading: const Icon(Icons.link),
                          onTap: () {
                            // 复制磁力链接
                            Clipboard.setData(ClipboardData(text: magnet));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('磁力链接已复制')),
                            );
                          },
                        )),
                      ],
                    ),
                  ),

                // Jellyfin 影片播放
                if (_jellyfinMovies.isNotEmpty || _isLoadingJellyfin)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Jellyfin 影片',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 8),
                            Icon(Icons.play_circle, color: Colors.green[700], size: 20),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_isLoadingJellyfin)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        else
                          ..._jellyfinMovies.map((jfMovie) => Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                color: Colors.green[50],
                                child: ListTile(
                                  leading: jfMovie.coverImage != null
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(4),
                                          child: Image.network(
                                            jfMovie.coverImage!,
                                            width: 50,
                                            height: 70,
                                            fit: BoxFit.cover,
                                            errorBuilder: (context, error, stackTrace) {
                                              return Container(
                                                width: 50,
                                                height: 70,
                                                color: Colors.grey[300],
                                                child: const Icon(Icons.movie),
                                              );
                                            },
                                          ),
                                        )
                                      : const SizedBox(
                                          width: 50,
                                          height: 70,
                                          child: Icon(Icons.movie),
                                        ),
                                  title: Text(
                                    jfMovie.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (jfMovie.libraryName != null)
                                        Text('库: ${jfMovie.libraryName}'),
                                      if (jfMovie.runtimeText != null)
                                        Text('时长: ${jfMovie.runtimeText}'),
                                      if (jfMovie.fileSizeText != null)
                                        Text('大小: ${jfMovie.fileSizeText}'),
                                      // 显示文件路径（文件名）
                                      if (jfMovie.path != null)
                                        Text(
                                          '文件: ${_getFileNameFromPath(jfMovie.path!)}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                        ),
                                    ],
                                  ),
                                  trailing: Icon(Icons.play_circle, color: Colors.green[700], size: 32),
                                  onTap: () {
                                    // 播放Jellyfin影片
                                    if (jfMovie.playUrl != null) {
                                      Navigator.pushNamed(
                                        context,
                                        '/player',
                                        arguments: {
                                          'url': jfMovie.playUrl,
                                          'title': jfMovie.title,
                                          'isLocal': false,
                                          'itemId': jfMovie.itemId,  // 传递 itemId 用于转码重试
                                        },
                                      );
                                      // 更新播放计数
                                      context.read<JellyfinProvider>().updatePlayCount(jfMovie.itemId);
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('播放链接不可用')),
                                      );
                                    }
                                  },
                                ),
                              )),
                      ],
                    ),
                  ),

                // MissAV 在线播放按钮
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isLoadingMissAV ? null : _playWithMissAV,
                      icon: _isLoadingMissAV
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.play_circle_outline),
                      label: Text(_isLoadingMissAV ? '正在获取播放地址...' : '在线播放'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),

                // 115 库文件信息
                if (_cloud115Items.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              _cloud115Items.length > 1
                                  ? '115 网盘文件 (${_cloud115Items.length})'
                                  : '115 网盘文件',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 8),
                            Icon(Icons.cloud, color: Colors.orange[700], size: 20),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ..._cloud115Items.map((item) {
                          // 获取 115 来源信息
                          final cloud115Source = item.cloud115Sources.firstOrNull;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            color: Colors.orange[50],
                            child: ListTile(
                              leading: const Icon(Icons.video_file, color: Colors.orange),
                              title: Text(
                                cloud115Source?.filepath ?? item.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w500),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (cloud115Source?.pickcode != null)
                                    Text('Pickcode: ${cloud115Source!.pickcode}', style: const TextStyle(fontSize: 12)),
                                  if (cloud115Source?.size != null && cloud115Source!.size!.isNotEmpty)
                                    Text('大小: ${cloud115Source.size}', style: const TextStyle(fontSize: 12)),
                                ],
                              ),
                              trailing: Icon(Icons.play_circle, color: Colors.orange[700], size: 32),
                              onTap: () => _tryPlayWithFallback(context, preferredItem: item),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),

                const SizedBox(height: 80),
              ],
            ),
          );
        },
      ),
      floatingActionButton: Consumer<MovieProvider>(
        builder: (context, movieProvider, child) {
          // 有完整的 Movie 数据
          if (movieProvider.movie != null) {
            // 根据可用的播放源决定按钮颜色
            Color buttonColor = Colors.blue; // 默认
            if (_jellyfinMovies.isNotEmpty) {
              buttonColor = Colors.green; // Jellyfin 优先
            } else if (_cloud115Items.isNotEmpty) {
              buttonColor = Colors.orange; // 115
            }

            return FloatingActionButton(
              backgroundColor: buttonColor,
              onPressed: () => _tryPlayWithFallback(context),
              child: const Icon(Icons.play_arrow),
            );
          }

          // 没有 Movie 数据，但有 unifiedItem
          if (_cloud115Items.isNotEmpty) {
            final item = _cloud115Items.first;
            Color buttonColor = Colors.blue; // 默认
            if (item.hasJellyfin) {
              buttonColor = Colors.green;
            } else if (item.hasCloud115) {
              buttonColor = Colors.orange;
            } else if (item.hasStrm) {
              buttonColor = Colors.purple;
            }

            return FloatingActionButton(
              backgroundColor: buttonColor,
              onPressed: () => _playUnifiedItem(item),
              child: const Icon(Icons.play_arrow),
            );
          }

          return const SizedBox();
        },
      ),
    );
  }

  /// 尝试播放，按照优先级：Jellyfin > 115 > 在线播放
  /// [preferredItem] 优先使用的文件（如果用户点击了特定的文件卡片）
  Future<void> _tryPlayWithFallback(BuildContext context, {ui.UnifiedLibraryItem? preferredItem}) async {
    if (_currentMovieId == null) return;

    // 1. 优先尝试 Jellyfin 播放
    if (_jellyfinMovies.isNotEmpty) {
      final jfMovie = _jellyfinMovies.first;
      if (jfMovie.playUrl != null) {
        if (kDebugMode) print('[MovieScreen] 使用 Jellyfin 播放');
        Navigator.pushNamed(
          context,
          '/player',
          arguments: {
            'url': jfMovie.playUrl,
            'title': jfMovie.title,
            'isLocal': false,
            'itemId': jfMovie.itemId,  // 传递 itemId 用于转码重试
          },
        );
        // 更新播放计数
        context.read<JellyfinProvider>().updatePlayCount(jfMovie.itemId);
        return;
      }
    }

    // 2. 尝试 115 播放
    // 优先使用用户指定的文件，否则使用列表中的第一个
    final cloud115Item = preferredItem ?? (_cloud115Items.isNotEmpty ? _cloud115Items.first : null);
    if (cloud115Item != null && cloud115Item.hasCloud115) {
      final cloud115Source = cloud115Item.cloud115Sources.firstOrNull;
      if (cloud115Source != null &&
          cloud115Source.pickcode != null &&
          cloud115Source.pickcode!.isNotEmpty) {
        if (kDebugMode) print('[MovieScreen] 尝试 115 播放: ${cloud115Item.title}');
        final cloud115 = context.read<Cloud115Provider>();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('正在获取 115 播放地址...')),
          );
        }

        try {
          final playInfo = await cloud115.getPlayInfoByPickCode(cloud115Source.pickcode!);
          if (playInfo != null && mounted) {
            if (kDebugMode) print('[MovieScreen] 115 播放成功');
            Navigator.pushNamed(
              context,
              '/player',
              arguments: {
                'url': playInfo['url'],
                'title': cloud115Item.title,
                'isLocal': false,
                'pickcode': cloud115Source.pickcode,
                ...playInfo,
              },
            );
            return;
          }
        } catch (e) {
          if (kDebugMode) print('[MovieScreen] 115 播放失败: $e');
        }
      }
    }

    // 3. 尝试 MissAV 在线播放
    if (kDebugMode) print('[MovieScreen] 尝试在线播放');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正在尝试在线播放...')),
      );
    }
    await _playWithMissAV();
    // 注意：_playWithMissAV 内部会处理成功/失败的情况
    // 如果失败，它已经显示了 SnackBar
  }

  /// 构建简介文本，按段落显示并保持段落间距
  Widget _buildDescriptionText(String text, {TextStyle? style}) {
    // 按双换行符分割段落
    final paragraphs = text.split('\n\n').where((p) => p.trim().isNotEmpty).toList();

    if (paragraphs.isEmpty) {
      return const SizedBox();
    }

    // 如果只有一个段落且没有换行符，直接显示
    if (paragraphs.length == 1 && !paragraphs[0].contains('\n')) {
      return Text(text, style: style);
    }

    // 多个段落，分别显示并用间距分隔
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < paragraphs.length; i++) ...[
          Text(paragraphs[i].trim(), style: style),
          if (i < paragraphs.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }

  /// 从路径中提取文件名
  String _getFileNameFromPath(String path) {
    // 处理 Windows 路径和 Unix 路径
    final separator = path.contains('\\') ? '\\' : '/';
    final parts = path.split(separator);
    if (parts.isNotEmpty) {
      return parts.last;
    }
    return path;
  }

  /// 构建 unifiedItem 的详情视图（用于没有 video_id 的影片）
  Widget _buildUnifiedItemView() {
    if (_cloud115Items.isEmpty) {
      return const Center(child: Text('影片信息为空'));
    }

    final item = _cloud115Items.first;

    // 使用按需获取的 Jellyfin 详情（如果有）
    final jellyfinDetails = _jellyfinOnDemandDetails;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 封面
          if (item.coverImage != null && item.coverImage!.isNotEmpty)
            JavBusImage(
              imageUrl: item.coverImage!,
              width: double.infinity,
              height: 300,
              fit: BoxFit.cover,
            ),

          // 基本信息
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.videoId != null && item.videoId!.isNotEmpty)
                  Text(
                    item.videoId!,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                const SizedBox(height: 8),
                Text(
                  item.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (item.sourceDisplayName.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Chip(
                    label: Text(item.sourceDisplayName),
                    backgroundColor: Color(item.sourceColor).withOpacity(0.2),
                  ),
                ],
                const SizedBox(height: 8),
                if (item.date != null)
                  _InfoRow(icon: Icons.calendar_month, label: '日期', value: item.date!),
                // 优先使用 Jellyfin 的时长格式（xx:yy），否则使用本地存储的分钟数
                if (jellyfinDetails?.runtimeText != null)
                  _InfoRow(icon: Icons.schedule, label: '时长', value: jellyfinDetails!.runtimeText!)
                else if (item.duration != null)
                  _InfoRow(icon: Icons.schedule, label: '时长', value: '${item.duration} 分钟'),
                if (item.playCount > 0)
                  _InfoRow(icon: Icons.play_arrow, label: '播放次数', value: '${item.playCount}'),
                if (item.lastPlayed != null && item.lastPlayed! > 0)
                  _InfoRow(
                    icon: Icons.access_time,
                    label: '最后播放',
                    value: DateTime.fromMillisecondsSinceEpoch(item.lastPlayed! * 1000)
                        .toString().split('.')[0],
                  ),

                // 加载详情指示器
                if (_isLoadingJellyfinDetails)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text('正在加载详情...'),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // 演员（优先使用 Jellyfin 详情中的演员）
          if (jellyfinDetails != null && jellyfinDetails.actors.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('演员', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: jellyfinDetails.actors.map((actor) {
                      return Chip(
                        label: Text(actor),
                        avatar: const CircleAvatar(child: Icon(Icons.person, size: 14)),
                      );
                    }).toList(),
                  ),
                ],
              ),
            )
          else if (item.actors != null && item.actors!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('演员', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _parseActors(item.actors!).map((actor) {
                      return Chip(
                        label: Text(actor),
                        avatar: const CircleAvatar(child: Icon(Icons.person, size: 14)),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

          // 分类（来自 Jellyfin 详情）
          if (jellyfinDetails != null && jellyfinDetails.genres.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('分类', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: jellyfinDetails.genres.map((genre) {
                      return Chip(
                        label: Text(genre),
                        backgroundColor: Colors.blue[50],
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

          // 简介（优先使用 Jellyfin overview）
          if (jellyfinDetails?.overview != null && jellyfinDetails!.overview!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('简介', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _buildDescriptionText(jellyfinDetails.overview!),
                ],
              ),
            )
          else if (item.description != null && item.description!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('简介', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _buildDescriptionText(item.description!),
                ],
              ),
            ),

          // 文件信息（来自 Jellyfin 详情）
          if (jellyfinDetails != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('文件信息', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  // 文件名（支持换行）
                  if (jellyfinDetails.path != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.insert_drive_file, size: 18, color: Colors.grey),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('文件名', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                                Text(
                                  _getFileNameFromPath(jellyfinDetails.path!),
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  // 文件大小
                  if (jellyfinDetails.fileSizeText != null)
                    _InfoRow(
                      icon: Icons.data_usage,
                      label: '大小',
                      value: jellyfinDetails.fileSizeText!,
                    ),
                  // 分辨率
                  if (jellyfinDetails.resolution != null)
                    _InfoRow(
                      icon: Icons.hd,
                      label: '分辨率',
                      value: jellyfinDetails.resolution!,
                    ),
                  // 时长
                  if (jellyfinDetails.runtimeText != null)
                    _InfoRow(
                      icon: Icons.schedule,
                      label: '时长',
                      value: jellyfinDetails.runtimeText!,
                    ),
                  // 路径（完整显示，自动换行）
                  if (jellyfinDetails.path != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.folder, size: 18, color: Colors.grey),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              jellyfinDetails.path!,
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

          // Jellyfin 源播放
          if (item.hasJellyfin)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Text(
                        'Jellyfin 影片',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.play_circle, color: Colors.green, size: 20),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...item.jellyfinSources.map((jfSource) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: Colors.green[50],
                        child: ListTile(
                          leading: item.coverImage != null && item.coverImage!.isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: Image.network(
                                    item.coverImage!,
                                    width: 50,
                                    height: 70,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        width: 50,
                                        height: 70,
                                        color: Colors.grey[300],
                                        child: const Icon(Icons.movie),
                                      );
                                    },
                                  ),
                                )
                              : const SizedBox(
                                  width: 50,
                                  height: 70,
                                  child: Icon(Icons.movie),
                                ),
                          title: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (jfSource.libraryName != null)
                                Text('库: ${jfSource.libraryName}'),
                              if (jfSource.filepath != null)
                                Text(
                                  '文件: ${_getFileNameFromPath(jfSource.filepath!)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                ),
                            ],
                          ),
                          trailing: const Icon(Icons.play_circle, color: Colors.green, size: 32),
                          onTap: () => _playUnifiedItem(item),
                        ),
                      )),
                ],
              ),
            ),

          // 115 源播放
          if (item.hasCloud115)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Text(
                        '115 网盘文件',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.cloud, color: Colors.orange, size: 20),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...item.cloud115Sources.map((c115Source) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: Colors.orange[50],
                        child: ListTile(
                          leading: const Icon(Icons.video_file, color: Colors.orange),
                          title: Text(
                            c115Source.filepath ?? item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (c115Source.pickcode != null)
                                Text('Pickcode: ${c115Source.pickcode}', style: const TextStyle(fontSize: 12)),
                              if (c115Source.size != null && c115Source.size!.isNotEmpty)
                                Text('大小: ${c115Source.size}', style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                          trailing: const Icon(Icons.play_circle, color: Colors.orange, size: 32),
                          onTap: () => _playUnifiedItem(item),
                        ),
                      )),
                ],
              ),
            ),

          // STRM 源播放
          if (item.hasStrm)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Text(
                        'STRM 文件',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.link, color: Colors.purple, size: 20),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...item.strmSources.map((strmSource) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: Colors.purple[50],
                        child: ListTile(
                          leading: const Icon(Icons.movie, color: Colors.purple),
                          title: Text(
                            strmSource.filepath ?? item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: strmSource.url != null
                              ? Text(strmSource.url!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))
                              : null,
                          trailing: const Icon(Icons.play_circle, color: Colors.purple, size: 32),
                          onTap: () => _playStrmItem(strmSource, item),
                        ),
                      )),
                ],
              ),
            ),

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  /// 解析演员字符串（支持 JSON 数组和逗号分隔）
  List<String> _parseActors(String actorsStr) {
    if (actorsStr.isEmpty) return [];

    // 尝试解析 JSON 数组
    if (actorsStr.startsWith('[')) {
      try {
        final dynamic json = jsonDecode(actorsStr);
        if (json is List) {
          return json.map((e) {
            if (e is Map) {
              return e['name']?.toString() ?? '';
            } else if (e is String) {
              return e;
            }
            return '';
          }).where((s) => s.isNotEmpty).toList();
        }
      } catch (e) {
        // 不是有效的 JSON，继续使用逗号分隔
      }
    }

    // 使用逗号分隔
    return actorsStr.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }

  /// 播放 unifiedItem（按照优先级：Jellyfin > 115）
  Future<void> _playUnifiedItem(ui.UnifiedLibraryItem item) async {
    // 优先使用 Jellyfin
    if (item.hasJellyfin) {
      final playInfo = await context.read<LibraryProvider>().getPlayInfo(item);
      if (playInfo != null && mounted) {
        Navigator.pushNamed(
          context,
          '/player',
          arguments: playInfo,
        );
        // 更新播放计数
        context.read<LibraryProvider>().updatePlayCount(item.unifiedId);
        return;
      }
    }

    // 使用 115
    if (item.hasCloud115) {
      final cloud115Source = item.cloud115Sources.firstOrNull;
      if (cloud115Source != null &&
          cloud115Source.pickcode != null &&
          cloud115Source.pickcode!.isNotEmpty) {
        final cloud115 = context.read<Cloud115Provider>();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('正在获取 115 播放地址...')),
          );
        }

        try {
          final playInfo = await cloud115.getPlayInfoByPickCode(cloud115Source.pickcode!);
          if (playInfo != null && mounted) {
            Navigator.pushNamed(
              context,
              '/player',
              arguments: {
                'url': playInfo['url'],
                'title': item.title,
                'isLocal': false,
                'pickcode': cloud115Source.pickcode,
                ...playInfo,
              },
            );
            // 更新播放计数
            context.read<LibraryProvider>().updatePlayCount(item.unifiedId);
            return;
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('播放失败: $e')),
            );
          }
        }
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法播放：没有可用的播放源')),
      );
    }
  }

  /// 播放 STRM 项目
  Future<void> _playStrmItem(ui.MediaSourceInfo strmSource, ui.UnifiedLibraryItem item) async {
    if (strmSource.url != null && strmSource.url!.isNotEmpty) {
      Navigator.pushNamed(
        context,
        '/player',
        arguments: {
          'url': strmSource.url,
          'title': item.title,
          'isLocal': false,
        },
      );
      // 更新播放计数
      context.read<LibraryProvider>().updatePlayCount(item.unifiedId);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('STRM 文件没有有效的 URL')),
        );
      }
    }
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 8),
          Text('$label: '),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

/// 全屏图片查看器
class _FullScreenImage extends StatefulWidget {
  final List<String?> imageUrls;
  final int initialIndex;
  final List<String?> thumbnails;

  const _FullScreenImage({
    required this.imageUrls,
    required this.initialIndex,
    this.thumbnails = const [],
  });

  @override
  State<_FullScreenImage> createState() => _FullScreenImageState();
}

class _FullScreenImageState extends State<_FullScreenImage> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          '${_currentIndex + 1} / ${widget.imageUrls.length}',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        itemCount: widget.imageUrls.length,
        itemBuilder: (context, index) {
          final imageUrl = widget.imageUrls[index];
          if (imageUrl == null) {
            return const Center(
              child: Text(
                '图片加载失败',
                style: TextStyle(color: Colors.white),
              ),
            );
          }
          return Center(
            child: JavBusImage(
              imageUrl: imageUrl,
              fit: BoxFit.contain,
            ),
          );
        },
      ),
    );
  }
}

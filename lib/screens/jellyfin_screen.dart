import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/jellyfin.dart';
import '../providers/providers.dart';
import '../widgets/widgets.dart';

/// Jellyfin 库管理页面
/// 设置功能已移至总设置页面
class JellyfinScreen extends StatefulWidget {
  const JellyfinScreen({super.key});

  @override
  State<JellyfinScreen> createState() => _JellyfinScreenState();
}

class _JellyfinScreenState extends State<JellyfinScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _hasInitialized = false;

  @override
  void initState() {
    super.initState();
    // 延迟初始化，确保 Provider 已准备好
    Future.microtask(() => _initializeData());
  }

  Future<void> _initializeData() async {
    if (_hasInitialized) return;
    _hasInitialized = true;

    final jellyfin = context.read<JellyfinProvider>();
    // 加载已导入的库列表
    await jellyfin.loadImportedLibraries();
    // 加载电影列表（默认加载全部）
    await jellyfin.loadMovies();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<JellyfinProvider>(
      builder: (context, jellyfin, child) {
        return DefaultTabController(
          initialIndex: 1, // 默认显示"已导入"tab
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Jellyfin 库'),
              actions: [
                // 连接状态指示器
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: _buildStatusIndicator(jellyfin.status),
                  ),
                ),
                // 设置按钮 - 跳转到总设置页面
                IconButton(
                  icon: const Icon(Icons.settings),
                  tooltip: '设置',
                  onPressed: () => Navigator.pushNamed(context, '/settings'),
                ),
              ],
              bottom: const TabBar(
                tabs: [
                  Tab(text: '媒体库', icon: Icon(Icons.video_library)),
                  Tab(text: '已导入', icon: Icon(Icons.folder)),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                _buildLibrariesTab(jellyfin),
                _buildImportedTab(jellyfin),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusIndicator(JellyfinStatus status) {
    switch (status) {
      case JellyfinStatus.connected:
        return const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 16),
            SizedBox(width: 4),
            Text('已连接', style: TextStyle(fontSize: 12)),
          ],
        );
      case JellyfinStatus.localOnly:
        return const Row(
          children: [
            Icon(Icons.offline_pin, color: Colors.orange, size: 16),
            SizedBox(width: 4),
            Text('仅本地数据', style: TextStyle(fontSize: 12)),
          ],
        );
      case JellyfinStatus.connecting:
      case JellyfinStatus.loading:
        return const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 4),
            Text('连接中...', style: TextStyle(fontSize: 12)),
          ],
        );
      case JellyfinStatus.importing:
        return const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 4),
            Text('导入中...', style: TextStyle(fontSize: 12)),
          ],
        );
      case JellyfinStatus.error:
        return const Row(
          children: [
            Icon(Icons.error, color: Colors.red, size: 16),
            SizedBox(width: 4),
            Text('错误', style: TextStyle(fontSize: 12)),
          ],
        );
      default:
        return const Row(
          children: [
            Icon(Icons.circle, color: Colors.grey, size: 16),
            SizedBox(width: 4),
            Text('未连接', style: TextStyle(fontSize: 12)),
          ],
        );
    }
  }

  Widget _buildLibrariesTab(JellyfinProvider jellyfin) {
    if (!jellyfin.isConnected) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('请先在设置页面连接服务器'),
            const SizedBox(height: 8),
            if (jellyfin.importedLibraries.isNotEmpty)
              const Text(
                '或切换到"已导入"标签页查看本地数据',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/settings'),
              icon: const Icon(Icons.settings),
              label: const Text('前往设置'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // 刷新按钮
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              IconButton(
                icon: jellyfin.status == JellyfinStatus.loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                onPressed: jellyfin.status == JellyfinStatus.loading
                    ? null
                    : () => jellyfin.loadLibraries(),
              ),
              const Text('可用的媒体库'),
            ],
          ),
        ),
        // 库列表
        Expanded(
          child: jellyfin.libraries.isEmpty
              ? const Center(child: Text('没有可用的媒体库'))
              : ListView.builder(
                  itemCount: jellyfin.libraries.length,
                  itemBuilder: (context, index) {
                    final library = jellyfin.libraries[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: ListTile(
                        leading: Icon(
                          _getLibraryIcon(library.type),
                          color: Theme.of(context).primaryColor,
                        ),
                        title: Text(library.name),
                        subtitle: Text('项目数: ${library.itemCount}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 增量同步按钮
                            if (_isLibraryImported(jellyfin, library.id))
                              IconButton(
                                icon: const Icon(Icons.sync),
                                tooltip: '增量同步',
                                onPressed: jellyfin.isImporting
                                    ? null
                                    : () => _syncLibrary(jellyfin, library),
                              ),
                            // 导入按钮
                            IconButton(
                              icon: jellyfin.isImporting &&
                                      _lastImportLibraryId(jellyfin) == library.id
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.download),
                              tooltip: '导入此库',
                              onPressed: jellyfin.isImporting
                                  ? null
                                  : () => _importLibrary(jellyfin, library),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildImportedTab(JellyfinProvider jellyfin) {
    return Column(
      children: [
        // 搜索框
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: '搜索电影',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        jellyfin.clearSearch();
                      },
                    )
                  : null,
              border: const OutlineInputBorder(),
            ),
            onChanged: (value) {
              // 防抖搜索
              Future.delayed(const Duration(milliseconds: 500), () {
                if (_searchController.text == value) {
                  jellyfin.search(value);
                }
              });
            },
          ),
        ),
        // 库选择器
        if (jellyfin.importedLibraries.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: FilterChip(
                      label: const Text('全部'),
                      selected: jellyfin.selectedLibraryId == null,
                      onSelected: (selected) {
                        if (selected) {
                          jellyfin.selectLibrary(null);
                          jellyfin.loadMovies();
                        }
                      },
                    ),
                  ),
                  ...jellyfin.importedLibraries.map((lib) {
                    final isSelected = jellyfin.selectedLibraryId == lib.id;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FilterChip(
                            label: Text(lib.name),
                            selected: isSelected,
                            onSelected: (selected) {
                              jellyfin.selectLibrary(selected ? lib.id : null);
                              jellyfin.loadMovies();
                            },
                          ),
                          // 管理菜单
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert, size: 18),
                            padding: EdgeInsets.zero,
                            onSelected: (value) => _handleLibraryAction(value, lib, jellyfin),
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'sync',
                                child: Row(
                                  children: [
                                    Icon(Icons.sync, size: 18),
                                    SizedBox(width: 8),
                                    Text('增量同步'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete, size: 18, color: Colors.red),
                                    SizedBox(width: 8),
                                    Text('删除此库', style: TextStyle(color: Colors.red)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
          ),
        // 电影列表
        Expanded(
          child: jellyfin.movies.isEmpty && !jellyfin.isLoading
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        jellyfin.importedLibraries.isEmpty
                            ? Icons.folder_off
                            : Icons.movie,
                        size: 64,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        jellyfin.importedLibraries.isEmpty
                            ? '没有导入的库\n请先在设置页面连接服务器，然后在"媒体库"标签页导入'
                            : '没有找到电影',
                        textAlign: TextAlign.center,
                      ),
                      if (jellyfin.importedLibraries.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: ElevatedButton.icon(
                            onPressed: () => Navigator.pushNamed(context, '/settings'),
                            icon: const Icon(Icons.settings),
                            label: const Text('前往设置'),
                          ),
                        ),
                    ],
                  ),
                )
              : NotificationListener<ScrollNotification>(
                  onNotification: (scrollInfo) {
                    if (scrollInfo.metrics.pixels >=
                            scrollInfo.metrics.maxScrollExtent - 200 &&
                        jellyfin.hasMoreMovies &&
                        !jellyfin.isLoading) {
                      jellyfin.loadMovies(loadMore: true);
                    }
                    return false;
                  },
                  child: GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 0.8,
                    ),
                    itemCount: jellyfin.movies.length +
                        (jellyfin.hasMoreMovies && jellyfin.isLoading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= jellyfin.movies.length) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }

                      final movie = jellyfin.movies[index];
                      return _buildMovieCard(movie, jellyfin);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildMovieCard(JellyfinMovie movie, JellyfinProvider jellyfin) {
    final displayTitle = _cleanTitle(movie.title, movie.videoId);

    // 构建播放按钮覆盖层（Jellyfin 特有的大播放按钮）
    final playButtonOverlay = Positioned.fill(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _playVideo(movie),
          child: Center(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(12),
              child: const Icon(
                Icons.play_arrow,
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
        ),
      ),
    );

    return MovieCard(
      coverUrl: movie.coverImage,
      title: displayTitle,
      videoId: movie.videoId,
      date: movie.runtimeText,
      style: MovieCardStyle.library,
      libraryLabel: 'Jellyfin',
      libraryLabelColor: Colors.green[600],
      customSuffixIcon: playButtonOverlay,
      onTap: () {
        // 点击进入影片详情页
        if (movie.videoId != null && movie.videoId!.isNotEmpty) {
          Navigator.pushNamed(
            context,
            '/movie',
            arguments: movie.videoId!,
          );
        } else {
          // 如果没有video_id，使用title作为搜索关键词
          Navigator.pushNamed(
            context,
            '/search',
          );
        }
      },
    );
  }

  /// 直接播放视频
  Future<void> _playVideo(JellyfinMovie movie) async {
    if (movie.playUrl == null || movie.playUrl!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法播放：缺少播放 URL')),
        );
      }
      return;
    }

    // 更新播放计数
    final jellyfin = context.read<JellyfinProvider>();
    await jellyfin.updatePlayCount(movie.itemId);

    if (mounted) {
      Navigator.pushNamed(
        context,
        '/player',
        arguments: {
          'url': movie.playUrl,
          'title': movie.title,
          'isLocal': false,
        },
      );
    }
  }

  IconData _getLibraryIcon(String type) {
    switch (type.toLowerCase()) {
      case 'movies':
        return Icons.movie;
      case 'tvshows':
        return Icons.tv;
      case 'music':
        return Icons.music_note;
      case 'books':
        return Icons.book;
      default:
        return Icons.folder;
    }
  }

  bool _isLibraryImported(JellyfinProvider jellyfin, String libraryId) {
    return jellyfin.importedLibraries.any((lib) => lib.id == libraryId);
  }

  String? _lastImportLibraryId(JellyfinProvider jellyfin) {
    // 从导入结果或选择中获取
    return jellyfin.selectedLibraryId;
  }

  Future<void> _importLibrary(JellyfinProvider jellyfin, JellyfinLibrary library) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入媒体库'),
        content: Text('确定要导入 "${library.name}" 吗？\n\n这可能需要一些时间，具体取决于库的大小。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await jellyfin.importLibrary(library);

      if (mounted) {
        if (jellyfin.lastImportResult != null) {
          final result = jellyfin.lastImportResult!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('导入完成: 成功 ${result.imported}, 失败 ${result.failed}'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  Future<void> _syncLibrary(JellyfinProvider jellyfin, JellyfinLibrary library) async {
    await jellyfin.syncLibraryIncremental(library);

    if (mounted) {
      if (jellyfin.lastImportResult != null) {
        final result = jellyfin.lastImportResult!;
        if (result.message != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.message!),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  /// 处理库操作菜单
  Future<void> _handleLibraryAction(
    String action,
    ImportedLibrary lib,
    JellyfinProvider jellyfin,
  ) async {
    switch (action) {
      case 'sync':
        // 找到对应的 JellyfinLibrary
        final targetLib = jellyfin.libraries.firstWhere(
          (l) => l.id == lib.id,
          orElse: () => JellyfinLibrary(
            id: lib.id,
            name: lib.name,
            type: 'movies',
            itemCount: lib.itemCount,
          ),
        );
        await _syncLibrary(jellyfin, targetLib);
        break;

      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('删除库'),
            content: Text('确定要删除已导入的 "${lib.name}" 吗？\n\n此操作只会删除本地缓存，不会影响 Jellyfin 服务器上的数据。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('删除', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );

        if (confirmed == true) {
          await jellyfin.deleteLibrary(lib.id);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('已删除 "${lib.name}"')),
            );
          }
        }
        break;
    }
  }

  /// 清理标题中的番号前缀
  /// 例如: "BLK-148 XXXXXX" -> "XXXXXX"
  String _cleanTitle(String title, String? videoId) {
    if (videoId == null || videoId.isEmpty) {
      return title;
    }

    // 移除标题开头的番号（可能后面跟着空格、下划线、连字符等）
    final patterns = [
      RegExp('^${RegExp.escape(videoId)}\\s+'), // BLK-148 后面跟空格
      RegExp('^${RegExp.escape(videoId)}[-_\\s]+'), // BLK-148 后面跟分隔符
      RegExp('^${RegExp.escape(videoId)}'), // BLK-148 直接开头
    ];

    for (final pattern in patterns) {
      if (pattern.hasMatch(title)) {
        return title.replaceFirst(pattern, '').trim();
      }
    }

    return title;
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/providers.dart';
import '../models/unified_library_item.dart' as ui;
import '../widgets/widgets.dart';

/// 统一的媒体库页面
/// 整合 115 库和 Jellyfin 库
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // 初始化库数据
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LibraryProvider>().initialize();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// 滚动监听，触发加载更多
  void _onScroll() {
    final library = context.read<LibraryProvider>();
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (library.hasMore && !library.isLoadingMore) {
        library.loadMore();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LibraryProvider>(
      builder: (context, library, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Library'),
            actions: [
              if (library.isLoading)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => library.refresh(),
                  tooltip: '刷新',
                ),
              IconButton(
                icon: const Icon(Icons.video_library),
                tooltip: 'Jellyfin库',
                onPressed: () => Navigator.pushNamed(context, '/jellyfin'),
              ),
            ],
          ),
          body: Column(
            children: [
              // 搜索框
              _buildSearchBar(library),
              // 库筛选 chips
              _buildLibraryChips(library),
              // 影片网格
              Expanded(
                child: _buildMovieGrid(library),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchBar(LibraryProvider library) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: '搜索影片',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          library.clearSearch();
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) {
                library.search(value);
              },
            ),
          ),
          const SizedBox(width: 8),
          // 排序按钮
          SortSelectorButton(
            currentSort: library.sortOption,
            onSortChanged: (option) => library.setSortOption(option),
          ),
        ],
      ),
    );
  }

  Widget _buildLibraryChips(LibraryProvider library) {
    final chips = <Widget>[
      // 全部
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: FilterChip(
          label: const Text('全部'),
          selected: library.selectedLibraryId == null,
          onSelected: (selected) {
            if (selected) library.selectLibrary(null);
          },
        ),
      ),
    ];

    // 添加各个库
    for (final lib in library.libraries) {
      final isSelected = library.selectedLibraryId == lib.id;
      final label = lib.itemCount > 0 ? '${lib.name} (${lib.itemCount})' : lib.name;
      chips.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: FilterChip(
            label: Text(label),
            selected: isSelected,
            onSelected: (selected) {
              library.selectLibrary(selected ? lib.id : null);
            },
            avatar: isSelected
                ? null
                : _getSourceIcon(lib.source),
          ),
        ),
      );
    }

    return SizedBox(
      height: 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: chips,
      ),
    );
  }

  Widget? _getSourceIcon(ui.MediaSource source) {
    switch (source) {
      case ui.MediaSource.cloud115:
        return Container(
          width: 16,
          height: 16,
          decoration: const BoxDecoration(
            color: Colors.orange,
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: Text('115', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
          ),
        );
      case ui.MediaSource.jellyfin:
        return Container(
          width: 16,
          height: 16,
          decoration: const BoxDecoration(
            color: Colors.blue,
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: Text('JF', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
          ),
        );
      default:
        return null;
    }
  }

  Widget _buildMovieGrid(LibraryProvider library) {
    if (library.isLoading && !library.isLoadingMore) {
      return const Center(child: CircularProgressIndicator());
    }

    if (library.displayItems.isEmpty && !library.isLoading) {
      return _buildEmptyState(library);
    }

    final itemCount = library.displayItems.length +
        (library.isLoadingMore ? 1 : 0);

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.8,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        // 加载更多指示器
        if (index == library.displayItems.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final item = library.displayItems[index];
        return _buildMovieCard(item, library);
      },
    );
  }

  Widget _buildMovieCard(ui.UnifiedLibraryItem item, LibraryProvider library) {
    final displayTitle = _cleanTitle(item.title, item.videoId);

    return MovieCard(
      coverUrl: item.coverImage,
      title: displayTitle,
      videoId: item.videoId,
      actorName: item.actors,
      date: item.date,
      style: MovieCardStyle.library,
      libraryLabel: item.sourceDisplayName,
      libraryLabelColor: Color(item.sourceColor),
      customSuffixIcon: _buildPlayButton(item),
      onTap: () => _showItemDetail(item),
    );
  }

  /// 构建播放按钮
  Widget _buildPlayButton(ui.UnifiedLibraryItem item) {
    return Positioned(
      bottom: 8,
      right: 8,
      child: GestureDetector(
        onTap: () => _playVideo(item),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(
            Icons.play_arrow,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(LibraryProvider library) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_off, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            library.libraries.isEmpty ? '没有导入的媒体库' : '没有找到影片',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            library.libraries.isEmpty
                ? '请先在 115 网盘或 Jellyfin 中导入视频'
                : '请尝试选择其他库或搜索',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
          if (library.libraries.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pushNamed(context, '/cloud115'),
                    icon: const Icon(Icons.cloud),
                    label: const Text('115 网盘'),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pushNamed(context, '/settings'),
                    icon: const Icon(Icons.settings),
                    label: const Text('Jellyfin 设置'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 显示影片详情
  void _showItemDetail(ui.UnifiedLibraryItem item) {
    // 传递 videoId（如果有）和完整的 unifiedItem
    Navigator.pushNamed(
      context,
      '/movie',
      arguments: {
        if (item.videoId != null && item.videoId!.isNotEmpty) 'videoId': item.videoId,
        'unifiedItem': item,
      },
    );
  }

  /// 播放视频
  Future<void> _playVideo(ui.UnifiedLibraryItem item) async {
    final library = context.read<LibraryProvider>();

    // 优先使用 Jellyfin
    if (item.hasJellyfin) {
      final playInfo = await library.getPlayInfo(item);
      if (playInfo != null && mounted) {
        Navigator.pushNamed(
          context,
          '/player',
          arguments: playInfo,
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法播放：缺少播放 URL')),
        );
      }
      return;
    }

    // 使用 115
    if (item.hasCloud115) {
      final cloud115Source = item.cloud115Sources.firstOrNull;
      if (cloud115Source == null || cloud115Source.pickcode == null || cloud115Source.pickcode!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('无法播放：缺少 pickcode')),
          );
        }
        return;
      }

      final cloud115 = context.read<Cloud115Provider>();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('正在获取播放地址...')),
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
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('获取播放地址失败')),
          );
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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/providers.dart';
import '../providers/search_provider.dart';
import '../models/search_result.dart';
import '../widgets/widgets.dart';

/// 搜索页面
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _hasInitialized = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    final search = context.read<SearchProvider>();
    if (search.hasNextPage && !search.isLoadingMore && !search.isSearching) {
      await search.loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('搜索'),
      ),
      body: Column(
        children: [
          // 搜索框
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: '输入番号',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _performSearch(_controller.text),
                ),
                border: const OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
              onSubmitted: _performSearch,
            ),
          ),
          // 筛选开关
          _buildFilterChips(),
          // 结果列表
          Expanded(
            child: _buildResults(),
          ),
        ],
      ),
    );
  }

  /// 筛选开关
  Widget _buildFilterChips() {
    return Consumer<SearchProvider>(
      builder: (context, search, child) {
        return SizedBox(
          height: 50,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              // 无码开关
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: FilterChip(
                  label: const Text('无码'),
                  selected: search.isUncensored,
                  onSelected: (selected) {
                    search.isUncensored = selected;
                    // 如果有搜索内容，重新搜索
                    if (_controller.text.isNotEmpty || search.hasResults) {
                      _performSearch(_controller.text);
                    }
                  },
                  selectedColor: Colors.pink[100],
                  checkmarkColor: Colors.pink,
                ),
              ),
              // 磁力开关
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: FilterChip(
                  label: const Text('包括无磁力'),
                  selected: search.includeNoMagnets,
                  onSelected: (selected) {
                    search.includeNoMagnets = selected;
                  },
                  selectedColor: Colors.blue[100],
                  checkmarkColor: Colors.blue,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildResults() {
    return Consumer<SearchProvider>(
      builder: (context, search, child) {
        if (search.isSearching) {
          return const Center(child: CircularProgressIndicator());
        }

        if (search.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text(search.errorMessage ?? '搜索失败'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => _performSearch(_controller.text),
                  child: const Text('重试'),
                ),
              ],
            ),
          );
        }

        if (!search.hasResults) {
          final hasSearched = search.status == SearchStatus.results;
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(hasSearched ? Icons.search_off : Icons.search,
                    size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  hasSearched ? '没有找到结果' : '输入番号搜索，或留空查看最新影片',
                  style: const TextStyle(color: Colors.grey),
                ),
                if (hasSearched) ...[
                  const SizedBox(height: 8),
                  const Text(
                    '请检查番号格式或在设置中配置 JavBus 镜像站',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ],
            ),
          );
        }

        // 显示结果数量
        final results = search.filteredResults;
        final itemCount = results.length;
        final totalCount = search.resultCount;
        final hasMore = search.hasNextPage;
        final isLoadingMore = search.isLoadingMore;
        final isShowingLatest = search.isShowingLatest;
        final isUncensored = search.isUncensored;
        final includeNoMagnets = search.includeNoMagnets;

        return Column(
          children: [
            // 结果数量栏
            if (itemCount > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      _getResultLabel(isShowingLatest, isUncensored, itemCount, totalCount, includeNoMagnets),
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                    if (hasMore)
                      const SizedBox(width: 8),
                    if (hasMore)
                      const Icon(Icons.more_horiz, size: 16, color: Colors.grey),
                  ],
                ),
              ),
            // 网格视图
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (scrollInfo) {
                  if (scrollInfo.metrics.pixels >=
                          scrollInfo.metrics.maxScrollExtent - 200 &&
                      hasMore &&
                      !isLoadingMore) {
                    _loadMore();
                  }
                  return false;
                },
                child: GridView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 0.8,
                  ),
                  itemCount: itemCount + (hasMore || isLoadingMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    // 加载更多指示器
                    if (index >= itemCount) {
                      return isLoadingMore
                          ? const Center(
                              child: CircularProgressIndicator(),
                            )
                          : const SizedBox.shrink();
                    }

                    final item = results[index];
                    return _buildResultCard(item);
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _getResultLabel(bool isLatest, bool isUncensored, int count, int totalCount, bool includeNoMagnets) {
    final typeLabel = isUncensored ? '无码' : '有码';
    if (isLatest) {
      return '最新$typeLabel影片 ($count)';
    }

    // 如果有过滤，显示过滤信息
    if (!includeNoMagnets && count < totalCount) {
      return '显示 $count 个有磁力影片 (共 $totalCount 个结果)';
    }

    return '找到 $count 个$typeLabel结果';
  }

  Widget _buildResultCard(SearchResultItem item) {
    return Consumer<SearchProvider>(
      builder: (context, search, child) {
        // 获取磁力状态
        final magnetStatus = search.getMagnetStatus(item.id);

        // 构建磁力状态图标
        Widget? buildMagnetIcon() {
          if (magnetStatus == true) {
            return Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(
                  Icons.link,
                  color: Colors.white,
                  size: 14,
                ),
              ),
            );
          } else if (magnetStatus == false) {
            return Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(
                  Icons.link_off,
                  color: Colors.white70,
                  size: 14,
                ),
              ),
            );
          }
          return null;
        }

        return MovieCard(
          coverUrl: item.cover,
          title: item.title,
          videoId: item.id,
          date: item.date,
          style: MovieCardStyle.search,
          topRightIcon: buildMagnetIcon(),
          onTap: () {
            Navigator.pushNamed(
              context,
              '/movie',
              arguments: item.id,
            );
          },
        );
      },
    );
  }

  void _performSearch(String query) {
    // 允许空搜索 - 显示最新影片
    context.read<SearchProvider>().search(query);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasInitialized) {
      _hasInitialized = true;
      if (ModalRoute.of(context)?.settings.arguments != null) {
        final query = ModalRoute.of(context)?.settings.arguments as String;
        _controller.text = query;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          context.read<SearchProvider>().search(query);
        });
      }
    }
  }
}

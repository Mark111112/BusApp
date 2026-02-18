import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../models/unified_library_item.dart' as ui;
import '../providers/providers.dart';
import '../providers/library_provider.dart';
import '../services/cloud115_service.dart';
import '../widgets/javbus_image.dart';

/// 首页
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  final _pageController = PageController();

  int _currentIndex = 0;

  @override
  void dispose() {
    _searchController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BUS115'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() => _currentIndex = index);
        },
        children: const [
          _RecentTab(),
          _FavoritesTab(),
          _Cloud115Tab(),
          _JellyfinTab(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() => _currentIndex = index);
          _pageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        },
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: '首页',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.favorite),
            label: '收藏',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.cloud),
            label: '115',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.video_library),
            label: 'Library',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showSearchDialog,
        child: const Icon(Icons.search),
      ),
    );
  }

  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('搜索番号'),
        content: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入番号，如 SSIS-406（留空查看最新）',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.characters,
          onSubmitted: (value) {
            Navigator.pop(context);
            Navigator.pushNamed(
              context,
              '/search',
              arguments: value.trim(),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(
                context,
                '/search',
                arguments: _searchController.text.trim(),
              );
            },
            child: const Text('搜索'),
          ),
        ],
      ),
    );
  }
}

/// 最近浏览标签页
class _RecentTab extends StatelessWidget {
  const _RecentTab();

  @override
  Widget build(BuildContext context) {
    return Consumer<HistoryProvider>(
      builder: (context, history, child) {
        return Column(
          children: [
            if (history.hasHistory)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.clear_all, size: 18),
                      label: const Text('清空'),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('清空浏览历史'),
                            content: const Text('确定要清空所有浏览历史吗？'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('取消'),
                              ),
                              TextButton(
                                onPressed: () {
                                  history.clear();
                                  Navigator.pop(context);
                                },
                                child: const Text('确定'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Builder(
                builder: (context) {
                  if (history.isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!history.hasHistory) {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.history, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('暂无浏览历史', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: history.count,
                    itemBuilder: (context, index) {
                      final item = history.history[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: item.cover != null && item.cover!.isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: JavBusImage(
                                    imageUrl: item.cover!,
                                    width: 50,
                                    height: 75,
                                    fit: BoxFit.cover,
                                    errorWidget: Container(
                                      width: 50,
                                      height: 75,
                                      color: Colors.grey[300],
                                      child: const Icon(Icons.movie, size: 24),
                                    ),
                                  ),
                                )
                              : Container(
                                  width: 50,
                                  height: 75,
                                  decoration: BoxDecoration(
                                    color: Colors.grey[300],
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Icon(Icons.movie, size: 24),
                                ),
                          title: Text(item.title?.isNotEmpty == true ? item.title! : item.movieId),
                          subtitle: Text(item.movieId),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => history.remove(item.movieId),
                          ),
                          onTap: () {
                            Navigator.pushNamed(
                              context,
                              '/movie',
                              arguments: item.movieId,
                            );
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 收藏标签页
class _FavoritesTab extends StatefulWidget {
  const _FavoritesTab();

  @override
  State<_FavoritesTab> createState() => _FavoritesTabState();
}

class _FavoritesTabState extends State<_FavoritesTab> {
  bool _hasInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasInitialized) {
      _hasInitialized = true;
      _loadFavorites();
    }
  }

  Future<void> _loadFavorites() async {
    final favorites = context.read<FavoriteProvider>();
    await favorites.load();
    await favorites.loadMovies();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<FavoriteProvider>(
      builder: (context, favorites, child) {
        if (favorites.isLoading || favorites.isLoadingMovies) {
          return const Center(child: CircularProgressIndicator());
        }

        if (favorites.count == 0) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.favorite_border, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text('暂无收藏', style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }

        if (favorites.movies.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.orange),
                const SizedBox(height: 16),
                const Text('收藏详情加载失败'),
                const SizedBox(height: 8),
                Text(
                  '有 ${favorites.count} 个收藏，但无法加载详情',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _loadFavorites,
                  child: const Text('重试'),
                ),
              ],
            ),
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.all(8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 0.8,
          ),
          itemCount: favorites.movies.length,
          itemBuilder: (context, index) {
            final movie = favorites.movies[index];
            return _buildMovieCard(movie, favorites);
          },
        );
      },
    );
  }

  Widget _buildMovieCard(Movie movie, FavoriteProvider favorites) {
    // 获取演员名称
    String? getActorName() {
      if (movie.actors != null && movie.actors!.isNotEmpty) {
        return movie.actors!.first.name;
      }
      return null;
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.pushNamed(
            context,
            '/movie',
            arguments: movie.id,
          );
        },
        onLongPress: () {
          _showRemoveConfirmDialog(movie.id);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  movie.cover != null
                      ? JavBusImage(
                          imageUrl: movie.cover!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                        )
                      : Container(
                          color: Colors.grey[300],
                          child: const Center(
                            child: Icon(Icons.movie, size: 48, color: Colors.grey),
                          ),
                        ),
                  // 收藏图标 - 左上角
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(
                        Icons.favorite,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                  // 播放图标 - 右下角，小一点
                  Positioned(
                    bottom: 8,
                    right: 8,
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
                ],
              ),
            ),
            // 标题和信息
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 片库类型和番号 - 注意: 库来源检查功能暂时移除
                  // 因为新的 LibraryProvider 使用异步查询，无法在同步构建中使用
                  Consumer<LibraryProvider>(
                    builder: (context, library, child) {
                      final hasMagnets = movie.magnetInfo != null && movie.magnetInfo!.isNotEmpty;

                      // 简化版本：仅显示磁力链接指示器
                      String getLibraryLabel() {
                        if (hasMagnets) return '磁力';
                        return '';
                      }

                      Color getLabelColor() {
                        if (hasMagnets) return Colors.blue[600]!;
                        return Colors.grey;
                      }

                      return Row(
                        children: [
                          if (getLibraryLabel().isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: getLabelColor(),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                getLibraryLabel(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          if (getLibraryLabel().isNotEmpty) const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              movie.id,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 4),
                  // 标题
                  Text(
                    movie.title ?? movie.id,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  // 演员或日期
                  if (getActorName() != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        getActorName()!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                    ),
                  if (movie.date != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        movie.date!,
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRemoveConfirmDialog(String movieId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('取消收藏'),
        content: const Text('确定要取消收藏这部影片吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              context.read<FavoriteProvider>().toggle(movieId);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已取消收藏')),
              );
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

/// 115 网盘标签页
class _Cloud115Tab extends StatelessWidget {
  const _Cloud115Tab();

  @override
  Widget build(BuildContext context) {
    return Consumer<Cloud115Provider>(
      builder: (context, cloud115, child) {
        return Column(
          children: [
            // 顶部操作栏
            _Cloud115Header(cloud115: cloud115),
            // 文件列表
            Expanded(
              child: _Cloud115FileList(cloud115: cloud115),
            ),
          ],
        );
      },
    );
  }
}

/// 115 网盘顶部栏
class _Cloud115Header extends StatelessWidget {
  final Cloud115Provider cloud115;

  const _Cloud115Header({required this.cloud115});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：标题和设置按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.cloud, color: Colors.orange),
                  const SizedBox(width: 8),
                  Text(
                    '115 网盘',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  if (cloud115.isLoggedIn)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '已登录',
                        style: TextStyle(fontSize: 12, color: Colors.green[700]),
                      ),
                    )
                  else
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '未登录',
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
                    ),
                ],
              ),
              TextButton.icon(
                icon: const Icon(Icons.video_library, size: 18),
                label: const Text('库管理'),
                onPressed: () => Navigator.pushNamed(context, '/cloud115_library'),
              ),
            ],
          ),
          // 第二行：面包屑导航
          if (cloud115.isLoggedIn && cloud115.folderPath.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 4,
                children: cloud115.folderPath.asMap().entries.map((entry) {
                  final index = entry.key;
                  final name = entry.value;
                  final isLast = index == cloud115.folderPath.length - 1;

                  if (isLast) {
                    return Text(
                      name,
                      style: TextStyle(
                        color: Colors.orange[700],
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  }

                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: () => _navigateToIndex(context, index),
                        child: Text(
                          name,
                          style: TextStyle(color: Colors.blue[700]),
                        ),
                      ),
                      Text(' /', style: TextStyle(color: Colors.grey[600])),
                    ],
                  );
                }).toList(),
              ),
            ),
          // 第三行：工具栏
          if (cloud115.isLoggedIn)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: cloud115.isLoading
                        ? null
                        : () => cloud115.refresh(),
                    tooltip: '刷新',
                  ),
                  if (cloud115.folderPath.length > 1)
                    IconButton(
                      icon: const Icon(Icons.arrow_upward, size: 20),
                      onPressed: cloud115.isLoading
                          ? null
                          : () => cloud115.navigateUp(),
                      tooltip: '返回上级',
                    ),
                  const Spacer(),
                  Text(
                    '${cloud115.folders.length} 文件夹, ${cloud115.onlyFiles.length} 文件',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _navigateToIndex(BuildContext context, int index) {
    final provider = context.read<Cloud115Provider>();
    while (provider.folderPath.length > index + 1) {
      provider.navigateUp();
    }
  }
}

/// 115 网盘文件列表
class _Cloud115FileList extends StatelessWidget {
  final Cloud115Provider cloud115;

  const _Cloud115FileList({required this.cloud115});

  @override
  Widget build(BuildContext context) {
    if (cloud115.isLoading && cloud115.files.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!cloud115.isLoggedIn) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 64, color: Colors.orange),
            const SizedBox(height: 16),
            const Text(
              '未登录 115 网盘',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              '请在设置中配置 115 Cookie',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.settings),
              label: const Text('去设置'),
              onPressed: () => Navigator.pushNamed(context, '/settings'),
            ),
          ],
        ),
      );
    }

    if (cloud115.errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              cloud115.errorMessage!,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                cloud115.clearError();
                cloud115.checkLoginStatus();
              },
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (cloud115.files.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => cloud115.refresh(),
        child: ListView(
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.5,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.folder_open, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text('此文件夹为空', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => cloud115.refresh(),
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: cloud115.files.length,
        itemBuilder: (context, index) {
          final file = cloud115.files[index];
          return _Cloud115FileItem(file: file);
        },
      ),
    );
  }
}

/// 115 网盘文件项
class _Cloud115FileItem extends StatelessWidget {
  final Cloud115FileInfo file;

  const _Cloud115FileItem({required this.file});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: _buildIcon(context),
        title: Text(
          file.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          file.isFile ? file.formattedSize : '文件夹',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        trailing: _buildTrailing(context),
        onTap: () => _handleTap(context),
      ),
    );
  }

  Widget? _buildIcon(BuildContext context) {
    if (!file.isFile) {
      return const Icon(Icons.folder, color: Colors.orange, size: 48);
    }

    if (file.isVideo) {
      return const Icon(Icons.play_circle_filled, color: Colors.red, size: 48);
    }

    if (file.thumbnail != null && file.thumbnail!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.network(
          file.thumbnail!,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return const Icon(Icons.insert_drive_file, color: Colors.grey, size: 48);
          },
        ),
      );
    }

    return const Icon(Icons.insert_drive_file, color: Colors.grey, size: 48);
  }

  Widget? _buildTrailing(BuildContext context) {
    if (file.isVideo) {
      return const Icon(Icons.play_circle_outline, color: Colors.green, size: 32);
    }
    return const Icon(Icons.chevron_right);
  }

  void _handleTap(BuildContext context) async {
    final cloud115 = context.read<Cloud115Provider>();

    if (!file.isFile) {
      // 进入文件夹
      await cloud115.enterFolder(file);
    } else if (file.isVideo) {
      // 播放视频 - 返回包含URL和Cookie的Map
      final playInfo = await cloud115.playVideo(file);
      if (playInfo != null && context.mounted) {
        Navigator.pushNamed(
          context,
          '/player',
          arguments: playInfo,
        );
      }
      if (cloud115.errorMessage != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(cloud115.errorMessage!)),
        );
        cloud115.clearError();
      }
    } else {
      // 非视频文件，提示无法预览
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${file.name} 不是视频文件')),
      );
    }
  }
}

/// Library 标签页 - 统一的媒体库入口
class _JellyfinTab extends StatelessWidget {
  const _JellyfinTab();

  @override
  Widget build(BuildContext context) {
    return Consumer<LibraryProvider>(
      builder: (context, library, child) {
        return Column(
          children: [
            // 顶部操作区
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '媒体库',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.manage_accounts),
                    tooltip: 'Jellyfin 库管理',
                    onPressed: () => Navigator.pushNamed(context, '/jellyfin'),
                  ),
                ],
              ),
            ),
            // 媒体库概览
            Expanded(
              child: Builder(
                builder: (context) {
                  if (library.isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (library.libraries.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.folder_open, size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            '尚未导入媒体库',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '请先在 115 网盘或 Jellyfin 中导入视频',
                            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                          ),
                          const SizedBox(height: 16),
                          Row(
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
                                label: const Text('设置'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }

                  // 显示所有库
                  int totalItems = 0;
                  for (final lib in library.libraries) {
                    totalItems += lib.itemCount;
                  }

                  return RefreshIndicator(
                    onRefresh: () => library.refresh(),
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: library.libraries.length + 1,
                      itemBuilder: (context, index) {
                        // 第一项：全部库
                        if (index == 0) {
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Colors.orange, Colors.blue],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.video_library,
                                  color: Colors.white,
                                ),
                              ),
                              title: const Text('全部库'),
                              subtitle: Text('共 $totalItems 个项目'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                library.selectLibrary(null);
                                Navigator.pushNamed(context, '/library');
                              },
                            ),
                          );
                        }

                        // 各个库
                        final lib = library.libraries[index - 1];
                        final isCloud115 = lib.source == ui.MediaSource.cloud115;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: isCloud115 ? Colors.orange[100] : Colors.blue[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: isCloud115
                                    ? const Text(
                                        '115',
                                        style: TextStyle(
                                          color: Colors.orange,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.movie,
                                        color: Colors.blue,
                                      ),
                              ),
                            ),
                            title: Text(lib.name),
                            subtitle: Text('${lib.itemCount} 个项目'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              // 选择库并跳转到详情页
                              library.selectLibrary(lib.id);
                              Navigator.pushNamed(context, '/library');
                            },
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

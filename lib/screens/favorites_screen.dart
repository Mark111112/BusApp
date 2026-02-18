import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../widgets/widgets.dart';

/// 收藏页面
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的收藏'),
        actions: [
          Consumer<FavoriteProvider>(
            builder: (context, favorites, child) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  child: Text(
                    '${favorites.count} 部',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              );
            },
          ),
          // 排序按钮
          Consumer<FavoriteProvider>(
            builder: (context, favorites, child) {
              return SortSelectorButton(
                currentSort: favorites.sortOption,
                onSortChanged: (option) async {
                  favorites.setSortOption(option);
                  await favorites.loadMovies();
                },
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Consumer<FavoriteProvider>(
        builder: (context, favorites, child) {
          if (favorites.isLoading || favorites.isLoadingMovies) {
            return const Center(child: CircularProgressIndicator());
          }

          if (favorites.errorMessage != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(favorites.errorMessage!),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadFavorites,
                    child: const Text('重试'),
                  ),
                ],
              ),
            );
          }

          if (favorites.movies.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.favorite_border, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    '还没有收藏',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '在影片详情页点击收藏按钮添加',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
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
      ),
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
          // 长按取消收藏
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

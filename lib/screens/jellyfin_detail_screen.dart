import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/jellyfin.dart';
import '../providers/jellyfin_provider.dart';

/// Jellyfin 影片详情页面
/// 用于没有 JavBus 数据的 Jellyfin 影片
class JellyfinDetailScreen extends StatefulWidget {
  const JellyfinDetailScreen({super.key});

  @override
  State<JellyfinDetailScreen> createState() => _JellyfinDetailScreenState();
}

class _JellyfinDetailScreenState extends State<JellyfinDetailScreen> {
  JellyfinMovie? _movie;
  Map<String, dynamic>? _metadata;
  bool _isLoadingMetadata = false;
  bool _hasError = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is JellyfinMovie && _movie == null) {
      _movie = args;
      _loadMetadata();
    }
  }

  Future<void> _loadMetadata() async {
    if (_movie == null) return;

    setState(() {
      _isLoadingMetadata = true;
      _hasError = false;
    });

    try {
      final jellyfinProvider = context.read<JellyfinProvider>();
      final service = jellyfinProvider.service;

      if (service != null && service.isConnected) {
        final metadata = await service.getItemMetadata(_movie!.itemId);
        if (mounted) {
          setState(() {
            _metadata = metadata;
            _isLoadingMetadata = false;
          });
        }
      } else if (mounted) {
        setState(() {
          _isLoadingMetadata = false;
          _hasError = true;
        });
      }
    } catch (e) {
      if (kDebugMode) print('[JellyfinDetail] 获取元数据失败: $e');
      if (mounted) {
        setState(() {
          _isLoadingMetadata = false;
          _hasError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_movie == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Jellyfin 影片')),
        body: const Center(child: Text('影片信息为空')),
      );
    }

    final movie = _movie!;

    return Scaffold(
      appBar: AppBar(
        title: Text(movie.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.play_arrow),
            onPressed: () => _playVideo(movie),
            tooltip: '播放',
          ),
        ],
      ),
      body: _buildContent(movie),
    );
  }

  Widget _buildContent(JellyfinMovie movie) {
    if (_isLoadingMetadata && _metadata == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_hasError && _metadata == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            const Text('获取影片信息失败'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadMetadata,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    // 从 API 元数据解析详细信息
    final metadata = _metadata;

    // 解析演员
    List<String> actors = movie.actors;
    if (metadata != null && metadata['People'] != null) {
      final people = metadata['People'] as List? ?? [];
      actors = people
          .where((p) => p is Map<String, dynamic> && p['Type'] == 'Actor')
          .map((p) => p['Name'] as String? ?? '')
          .where((n) => n.isNotEmpty)
          .toList();
    }

    // 解析类型
    List<String> genres = [];
    if (metadata != null && metadata['Genres'] != null) {
      genres = (metadata['Genres'] as List? ?? [])
          .map((g) => g.toString())
          .where((g) => g.isNotEmpty)
          .toList();
    }

    // 解析时长
    String? runtimeText = movie.runtimeText;
    if (metadata != null && metadata['RunTimeTicks'] != null) {
      final runtimeSeconds = (metadata['RunTimeTicks'] as int) ~/ 10000000;
      runtimeText = _formatDuration(runtimeSeconds);
    }

    // 解析文件大小
    String? fileSizeText;
    if (metadata != null && metadata['MediaSources'] != null) {
      final mediaSources = metadata['MediaSources'] as List? ?? [];
      if (mediaSources.isNotEmpty) {
        final sizeBytes = mediaSources[0]['Size'] as int?;
        if (sizeBytes != null) {
          fileSizeText = _formatSize(sizeBytes);
        }
      }
    }

    // 解析简介
    String? overview = movie.overview;
    if (metadata != null && metadata['Overview'] != null) {
      overview = metadata['Overview'] as String?;
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 封面
          if (movie.coverImage != null && movie.coverImage!.isNotEmpty)
            Image.network(
              movie.coverImage!,
              width: double.infinity,
              height: 300,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  width: double.infinity,
                  height: 300,
                  color: Colors.grey[300],
                  child: const Icon(Icons.movie, size: 64, color: Colors.grey),
                );
              },
            ),

          // 来源标识
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.blue[50],
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '来自 Jellyfin: ${movie.libraryName}',
                    style: TextStyle(color: Colors.blue[700], fontWeight: FontWeight.bold),
                  ),
                ),
                if (_isLoadingMetadata)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue[700]),
                  ),
              ],
            ),
          ),

          // 基本信息
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  movie.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (movie.videoId != null && movie.videoId!.isNotEmpty)
                  _InfoRow(icon: Icons.movie, label: '番号', value: movie.videoId!),
                if (movie.date != null)
                  _InfoRow(icon: Icons.calendar_month, label: '日期', value: movie.date!),
                if (runtimeText != null)
                  _InfoRow(icon: Icons.schedule, label: '时长', value: runtimeText),
                if (fileSizeText != null)
                  _InfoRow(icon: Icons.data_usage, label: '文件大小', value: fileSizeText),
                if (movie.playCount > 0)
                  _InfoRow(icon: Icons.play_circle, label: '播放次数', value: '${movie.playCount}'),
              ],
            ),
          ),

          // 简介
          if (overview != null && overview.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('简介', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(overview),
                ],
              ),
            ),

          // 演员
          if (actors.isNotEmpty)
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
                    children: actors.map((actor) {
                      return Chip(
                        avatar: const CircleAvatar(child: Icon(Icons.person, size: 18)),
                        label: Text(actor),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

          // 类型/标签
          if (genres.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('标签', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: genres.map((genre) {
                      return Chip(
                        label: Text(genre),
                        backgroundColor: Colors.grey[200],
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  void _playVideo(JellyfinMovie movie) {
    if (movie.playUrl == null || movie.playUrl!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法播放：缺少播放 URL')),
      );
      return;
    }

    // 更新播放计数
    context.read<JellyfinProvider>().updatePlayCount(movie.itemId);

    Navigator.pushNamed(
      context,
      '/player',
      arguments: {
        'url': movie.playUrl,
        'title': movie.title,
        'isLocal': false,
        'itemId': movie.itemId,  // 传递 itemId 用于转码重试
      },
    );
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
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

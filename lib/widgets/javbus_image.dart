import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// JavBus 图片组件 - 自动添加 Referer 头以解决 403 问题
class JavBusImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  const JavBusImage({
    required this.imageUrl,
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      return _buildPlaceholder();
    }

    return CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit,
      httpHeaders: const {
        'Referer': 'https://www.javbus.com/',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      },
      placeholder: (context, url) => placeholder ??
          Container(
            width: width,
            height: height,
            color: Colors.grey[200],
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
      errorWidget: (context, url, error) => errorWidget ??
          Container(
            width: width,
            height: height,
            color: Colors.grey[300],
            child: Icon(Icons.broken_image, color: Colors.grey[500]),
          ),
    );
  }

  Widget _buildPlaceholder() {
    return placeholder ??
        Container(
          width: width,
          height: height,
          color: Colors.grey[300],
          child: Icon(Icons.movie, color: Colors.grey[500]),
        );
  }
}

# Flutter 项目结构

## 目录说明

```
bus_app/
├── android/              # Android 平台代码
├── assets/              # 静态资源
├── lib/                 # Dart 源代码
│   ├── core/            # 核心功能
│   │   ├── app.dart          # 应用入口
│   │   ├── constants.dart    # 常量定义
│   │   └── injection_container.dart  # 依赖注入
│   ├── models/          # 数据模型
│   │   ├── movie.dart        # 影片模型
│   │   ├── actor.dart        # 演员模型
│   │   ├── video_source.dart # 视频源模型
│   │   └── search_result.dart # 搜索结果模型
│   ├── services/        # 服务层（业务逻辑）
│   │   ├── database_service.dart   # 数据库服务
│   │   ├── config_service.dart     # 配置服务
│   │   ├── javbus_service.dart     # JavBus 服务
│   │   ├── scraper_service.dart    # 爬虫服务
│   │   ├── scrapers/               # 爬虫实现
│   │   ├── cloud115_service.dart   # 115 网盘服务
│   │   ├── jellyfin_service.dart   # Jellyfin 服务
│   │   ├── translator_service.dart # 翻译服务
│   │   └── crypto/                 # 加密算法
│   ├── repositories/     # 仓库层（数据访问）
│   │   ├── movie_repository.dart
│   │   ├── favorite_repository.dart
│   │   ├── search_history_repository.dart
│   │   └── playback_repository.dart
│   ├── providers/       # 状态管理
│   │   ├── movie_provider.dart
│   │   ├── search_provider.dart
│   │   ├── favorite_provider.dart
│   │   └── config_provider.dart
│   ├── screens/          # 页面
│   │   ├── home_screen.dart
│   │   ├── search_screen.dart
│   │   ├── movie_screen.dart
│   │   ├── favorites_screen.dart
│   │   ├── settings_screen.dart
│   │   └── player_screen.dart
│   ├── utils/           # 工具类
│   │   └── theme.dart
│   ├── widgets/         # 通用组件
│   └── main.dart        # 程序入口
├── pubspec.yaml         # 依赖配置
└── README.md           # 说明文档
```

## 架构分层

```
┌─────────────────────────────────────┐
│           UI (screens/widgets)         │
├─────────────────────────────────────┤
│     Provider (状态管理)               │
├─────────────────────────────────────┤
│     Repository (数据访问层)           │
├─────────────────────────────────────┤
│     Service (业务逻辑层)              │
├─────────────────────────────────────┤
│     Model (数据模型)                  │
└─────────────────────────────────────┘
```

## 核心功能模块

| 模块 | 说明 | 状态 |
|------|------|------|
| 番号搜索 | 支持 9+ 站点爬虫 | ✅ |
| 本地缓存 | SQLite 存储 | ✅ |
| 115 网盘 | 包含 m115 加密算法 | ✅ |
| Jellyfin | 媒体库集成 | ✅ |
| 翻译 | 支持 Ollama/OpenAI | ✅ |
| 视频播放 | HLS/MP4 播放 | ✅ |
| 收藏夹 | 本地存储 | ✅ |

## 开发指南

1. 运行项目：
   ```bash
   cd bus_app
   flutter pub get
   flutter run
   ```

2. 构建 APK：
   ```bash
   flutter build apk --release
   ```

3. 添加新爬虫：
   - 继承 `BaseScraper`
   - 实现 `searchMovie` 和 `getMovieInfo`
   - 在 `ScraperService` 中注册

## 依赖说明

- **状态管理**: provider
- **网络请求**: dio
- **数据库**: sqflite
- **HTML 解析**: html
- **加密**: pointycastle
- **视频播放**: video_player
- **图片缓存**: cached_network_image

# BUS115 - 影片库管理与播放系统

一个功能强大的 Flutter 影片管理应用，整合了 JavBus 搜索、115 网盘、Jellyfin 媒体库和在线播放功能。

![Flutter](https://img.shields.io/badge/Flutter-3.0+-blue.svg)
![Android](https://img.shields.io/badge/Android-API%2021+-green.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

## ✨ 主要功能

### 🔍 智能搜索
- 支持 **9+ 站点**并发搜索（JavBus、Fanza、DMM 等）
- 实时搜索结果预览
- 智能番号匹配和识别
- 搜索历史记录

### 💾 数据源整合
- **JavBus 集成**：影片信息、演员资料、预览图
- **115 网盘支持**：
  - 完整的 m115 加密算法实现
  - 文件浏览和下载
  - 视频转码功能
  - 离线下载管理
- **Jellyfin 媒体库**：
  - 媒体库浏览和搜索
  - 直接播放 Jellyfin 资源
  - 与本地收藏同步

### 🎬 视频播放
- **多格式支持**：HLS (.m3u8)、MP4、WebM
- **在线播放**：
  - MissAV 视频流解析
  - 多源自动切换
  - 播放进度记忆
- **本地播放**：集成 video_player 和 media_kit
- **播放器控制**：倍速、画质切换、全屏支持

### 📚 收藏管理
- 本地 SQLite 数据库存储
- 收藏夹分类管理
- 快速添加/移除收藏
- 收藏同步功能

### 🌐 翻译支持
- 集成翻译服务（支持 Ollama/OpenAI）
- 影片简介翻译
- 演员/导演名称本地化

### ⚙️ 配置管理
- 灵活的服务配置（JavBus、115、Jellyfin、翻译）
- 安全的认证信息存储（加密保存 115 Cookie）
- Basic Auth 支持
- 实时配置验证

## 📸 应用界面

- **首页**：快速搜索、浏览推荐、最近访问
- **搜索页**：多站点搜索结果聚合
- **影片详情**：完整信息、演员列表、预览图
- **收藏夹**：管理收藏的影片
- **115 网盘**：文件浏览、转码、下载
- **Jellyfin 媒体库**：媒体库浏览和播放
- **播放器**：功能强大的视频播放界面
- **设置页**：一站式配置管理

## 🚀 安装指南

### 方式 1：下载 APK（推荐）

1. 从 [Releases](https://github.com/Mark111112/BusApp/releases) 下载最新 APK
2. 在 Android 设备上安装
3. 打开应用即可使用

### 方式 2：从源码构建

**前置要求：**
- Flutter SDK 3.0+
- Dart SDK 3.0+
- Android Studio 或 VS Code

**构建步骤：**

```bash
# 克隆仓库
git clone https://github.com/Mark111112/BusApp.git
cd BusApp

# 安装依赖
flutter pub get

# 运行调试版本
flutter run

# 构建 Release APK
flutter build apk --release

# 构建 App Bundle（用于上传 Google Play）
flutter build appbundle --release
```

构建产物位置：
- APK: `build/app/outputs/flutter-apk/app-release.apk`
- AAB: `build/app/outputs/bundle/release/app-release.aab`

## 🔧 配置指南

### 首次使用

1. **打开应用设置**
2. **配置数据源**（至少配置一个）：
   - **JavBus URL**：默认使用官方站点
   - **115 Cookie**（可选）：用于网盘功能
   - **Jellyfin 服务器**（可选）：用于媒体库集成
   - **翻译服务**（可选）：用于翻译功能

### 115 网盘配置

1. 登录 [115.com](https://115.com)
2. 打开浏览器开发者工具（F12）
3. 切换到 Application/存储 标签
4. 找到 Cookies 并复制 `UID`、`CID`、SEID` 的值
5. 在应用设置中粘贴 Cookie：
   ```
   UID=xxx; CID=xxx; SEID=xxx
   ```
6. 点击"验证"按钮确认 Cookie 有效

### MissAV Stream 服务（可选）

用于在线播放 MissAV 视频：

1. 配置后端服务地址（例如：`http://192.168.1.246:9090`）
2. 应用会自动调用 API 解析视频流
3. 支持外部网络访问（需配置反向代理）

### Jellyfin 配置

1. **服务器地址**：例如 `http://192.168.1.100:8096`
2. **认证方式**（二选一）：
   - **API Key**：推荐方式
   - **用户名 + 密码**
3. 点击"连接"测试配置

## 📖 使用说明

### 搜索影片

1. 在首页点击搜索按钮
2. 输入番号或关键词
3. 查看来自多个站点的搜索结果
4. 点击结果查看详情

### 添加到收藏

1. 在影片详情页点击收藏按钮
2. 选择收藏夹（可选）
3. 在"收藏夹"页面管理收藏

### 115 网盘操作

**浏览文件：**
- 导航到目标文件夹
- 查看视频文件列表

**下载到本地：**
- 选择视频文件
- 点击下载按钮
- 在"离线下载"页面查看进度

**转码播放：**
- 选择视频文件
- 点击转码按钮
- 等待转码完成后播放

### Jellyfin 媒体库

**浏览媒体：**
- 查看最新的电影、剧集
- 搜索媒体库

**直接播放：**
- 点击媒体项目
- 使用集成播放器播放
- 同步播放进度到 Jellyfin

### 视频播放

**基本控制：**
- 播放/暂停
- 快进/快退（左右滑动）
- 音量调节
- 全屏切换

**高级功能：**
- 倍速播放（0.5x - 2.0x）
- 画质切换（自适应）
- 后台播放（音频）
- 画面比例调整

## 🛠️ 技术栈

### 核心框架
- **Flutter 3.0+**：跨平台 UI 框架
- **Provider**：状态管理
- **SQLite**：本地数据存储

### 网络与数据
- **Dio**：HTTP 客户端
- **HTML 解析**：网页内容提取
- **Cached Network Image**：图片缓存

### 视频播放
- **Video Player**：基础视频播放
- **Media Kit (libmpv)**：高级播放功能
- **Flutter InAppWebView**：WebView 播放器

### 加密与安全
- **PointyCastle**：加密算法
- **M115 加密**：115 网盘专用加密

### 其他依赖
- **Google Fonts**：字体
- **Shimmer**：加载动画
- **Connectivity Plus**：网络状态检测

## 📂 项目结构

```
lib/
├── core/               # 核心功能
│   ├── app.dart        # 应用入口
│   └── constants.dart  # 常量定义
├── models/             # 数据模型
├── services/           # 业务逻辑
│   ├── scrapers/       # 爬虫实现
│   └── crypto/         # 加密算法
├── repositories/       # 数据访问层
├── providers/          # 状态管理
├── screens/            # 用户界面
├── utils/              # 工具类
└── widgets/            # 通用组件
```

## 🔐 隐私与安全

- 所有配置信息存储在本地
- 115 Cookie 加密存储
- 不收集用户数据
- 不包含第三方追踪

## 📝 开发路线图

- [x] 多站点搜索
- [x] 115 网盘集成
- [x] Jellyfin 媒体库支持
- [x] MissAV 在线播放
- [x] 视频转码功能
- [ ] iOS 平台支持
- [ ] 字幕支持
- [ ] 多语言界面
- [ ] 播放列表功能

## 🤝 贡献

欢迎贡献代码、报告问题或提出建议！

1. Fork 本仓库
2. 创建功能分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启 Pull Request

## 📄 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](LICENSE) 文件

## 💖 打赏

如果你觉得这个项目对你有帮助，欢迎请我喝杯咖啡！☕

**以太坊 (ETH)：**
```
0x5DEcf1e18968112ED4caD5C71315B45cC844b647
```

*您的支持是我持续开发的动力！* ❤️

## 🙏 致谢

- [Flutter](https://flutter.dev/) - 跨平台 UI 框架
- [JavBus](https://www.javbus.com/) - 影片数据来源
- [115 网盘](https://115.com/) - 云存储服务
- [Jellyfin](https://jellyfin.org/) - 媒体服务器
- [MissAV](https://missav.ai/) - 在线视频源

## 📮 联系方式

- **问题反馈**：[GitHub Issues](https://github.com/Mark111112/BusApp/issues)
- **功能建议**：[GitHub Discussions](https://github.com/Mark111112/BusApp/discussions)

---

**享受观影！** 🎬

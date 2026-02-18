import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/providers.dart';

/// 设置页面
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        children: [
          const _SectionHeader(title: 'JavBus'),
          _ConfigTile(
            title: 'JavBus URL',
            subtitle: '数据源地址',
            configKey: 'javbus_base_url',
            icon: Icons.language,
          ),

          const _SectionHeader(title: '115 网盘'),
          _Cloud115CookieTile(),
          const _115TranscodeConfigTile(),

          const _SectionHeader(title: 'Jellyfin'),
          _JellyfinConfigTile(),

          const _SectionHeader(title: '翻译'),
          _ConfigTile(
            title: 'API 地址',
            subtitle: '翻译 API URL',
            configKey: 'translation_api_url',
            icon: Icons.translate,
          ),
          _ConfigTile(
            title: 'API Token',
            subtitle: '翻译 API 密钥',
            configKey: 'translation_api_token',
            icon: Icons.vpn_key,
            obscure: true,
          ),
          _ConfigTile(
            title: '模型',
            subtitle: '翻译模型名称',
            configKey: 'translation_model',
            icon: Icons.model_training,
          ),

          const _SectionHeader(title: '在线播放'),
          _MissAVStreamServiceTile(),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _ConfigTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String configKey;
  final IconData icon;
  final bool obscure;

  const _ConfigTile({
    required this.title,
    required this.subtitle,
    required this.configKey,
    required this.icon,
    this.obscure = false,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<ConfigProvider>(
      builder: (context, config, child) {
        final value = config.get(configKey) ?? '';

        return ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(
            obscure ? '•' * 8 : (value.isEmpty ? '未设置' : value),
            style: TextStyle(
              color: value.isEmpty ? Colors.grey : null,
            ),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showEditDialog(context, config, value),
        );
      },
    );
  }

  void _showEditDialog(BuildContext context, ConfigProvider config, String currentValue) {
    final controller = TextEditingController(text: currentValue);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: subtitle,
            border: const OutlineInputBorder(),
            suffixIcon: currentValue.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      controller.clear();
                    },
                  )
                : null,
          ),
          obscureText: obscure,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await config.set(configKey, controller.text);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}

/// 115 Cookie 配置项（带验证功能）
class _Cloud115CookieTile extends StatelessWidget {
  const _Cloud115CookieTile();

  @override
  Widget build(BuildContext context) {
    return Consumer2<ConfigProvider, Cloud115Provider>(
      builder: (context, config, cloud115, child) {
        final cookie = config.get('cloud115_cookie') ?? '';
        final hasCookie = cookie.isNotEmpty;

        return ListTile(
          leading: Icon(
            Icons.cloud,
            color: cloud115.isLoggedIn ? Colors.green : Colors.grey,
          ),
          title: const Text('115 Cookie'),
          subtitle: Row(
            children: [
              Expanded(
                child: Text(
                  hasCookie ? '已设置' : '未设置',
                  style: TextStyle(
                    color: hasCookie ? null : Colors.grey,
                  ),
                ),
              ),
              if (cloud115.isLoggedIn)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green[100],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '有效',
                    style: TextStyle(fontSize: 12, color: Colors.green[700]),
                  ),
                )
              else if (hasCookie)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange[100],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '待验证',
                    style: TextStyle(fontSize: 12, color: Colors.orange[700]),
                  ),
                ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasCookie)
                IconButton(
                  icon: const Icon(Icons.verified, size: 20),
                  tooltip: '验证 Cookie',
                  onPressed: cloud115.isLoading
                      ? null
                      : () => _verifyCookie(context, cookie, cloud115),
                ),
              IconButton(
                icon: const Icon(Icons.edit, size: 20),
                onPressed: () => _showEditDialog(context, config, cookie),
              ),
            ],
          ),
          onTap: () => _showEditDialog(context, config, cookie),
        );
      },
    );
  }

  Future<void> _verifyCookie(
    BuildContext context,
    String cookie,
    Cloud115Provider cloud115,
  ) async {
    // 先保存 Cookie
    final config = context.read<ConfigProvider>();
    await config.set('cloud115_cookie', cookie);

    // 再验证
    await cloud115.setCookie(cookie);

    if (context.mounted) {
      final scaffoldMessenger = ScaffoldMessenger.of(context);
      if (cloud115.isLoggedIn) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Cookie 验证成功'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        final error = cloud115.errorMessage ?? 'Cookie 验证失败';
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(error),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showEditDialog(
    BuildContext context,
    ConfigProvider config,
    String currentValue,
  ) {
    final controller = TextEditingController(text: currentValue);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('115 Cookie'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Cookie',
                hintText: 'UID=xxx; CID=xxx; SEID=xxx',
                border: OutlineInputBorder(),
                helperText: '从浏览器 115driver 获取 Cookie',
              ),
              maxLines: 3,
              obscureText: false,
            ),
            const SizedBox(height: 16),
            const Text(
              '获取方法：\n'
              '1. 登录 https://115.com/\n'
              '2. 打开浏览器开发者工具 (F12)\n'
              '3. 切换到 Application/存储 标签\n'
              '4. 找到 Cookies 并复制 UID、CID、SEID 的值',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await config.set('cloud115_cookie', controller.text);
              if (context.mounted) {
                Navigator.pop(context);
                // 自动验证新设置的 Cookie
                final cloud115 = context.read<Cloud115Provider>();
                await cloud115.setCookie(controller.text);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(cloud115.isLoggedIn ? 'Cookie 已设置并验证成功' : 'Cookie 已保存'),
                      backgroundColor: cloud115.isLoggedIn ? Colors.green : Colors.orange,
                    ),
                  );
                }
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}

/// Jellyfin 配置项（简化版，参考 115 转码服务样式）
class _JellyfinConfigTile extends StatefulWidget {
  const _JellyfinConfigTile();

  @override
  State<_JellyfinConfigTile> createState() => _JellyfinConfigTileState();
}

class _JellyfinConfigTileState extends State<_JellyfinConfigTile> {
  bool _isConnecting = false;

  @override
  Widget build(BuildContext context) {
    return Consumer2<ConfigProvider, JellyfinProvider>(
      builder: (context, config, jellyfin, child) {
        final serverUrl = config.get('jellyfin_server_url') ?? '';
        final apiKey = config.get('jellyfin_api_key') ?? '';
        final username = config.get('jellyfin_username') ?? '';
        final password = config.get('jellyfin_password') ?? '';
        final hasServer = serverUrl.isNotEmpty;
        final hasCredentials = apiKey.isNotEmpty || (username.isNotEmpty && password.isNotEmpty);
        final isConnected = jellyfin.isConnected;

        return Column(
          children: [
            // 服务器地址
            ListTile(
              leading: Icon(
                Icons.storage,
                color: isConnected ? Colors.green : Colors.grey,
              ),
              title: const Text('Jellyfin 服务器'),
              subtitle: Row(
                children: [
                  Expanded(
                    child: Text(
                      serverUrl.isEmpty ? '未配置' : serverUrl,
                      style: TextStyle(
                        color: serverUrl.isEmpty ? Colors.grey : null,
                      ),
                    ),
                  ),
                  if (isConnected)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green[100],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '已连接',
                        style: TextStyle(fontSize: 10, color: Colors.green[700]),
                      ),
                    )
                  else if (hasServer && hasCredentials)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange[100],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '待连接',
                        style: TextStyle(fontSize: 10, color: Colors.orange[700]),
                      ),
                    ),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasServer && hasCredentials && !_isConnecting)
                    IconButton(
                      icon: Icon(isConnected ? Icons.refresh : Icons.login, size: 20),
                      tooltip: isConnected ? '重新连接' : '连接',
                      onPressed: () => _connect(context, config, jellyfin, serverUrl, username, password, apiKey),
                    ),
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    onPressed: () => _showConfigDialog(context, config, serverUrl, apiKey, username, password),
                  ),
                ],
              ),
              onTap: () => _showConfigDialog(context, config, serverUrl, apiKey, username, password),
            ),
            // 认证信息（已配置时显示）
            if (hasServer)
              ListTile(
                leading: const Icon(Icons.lock, size: 20),
                title: const Text('认证信息'),
                subtitle: Text(
                  apiKey.isNotEmpty ? 'API Key: ${apiKey.substring(0, 8)}...' : (username.isEmpty ? '未设置' : '用户: $username'),
                  style: TextStyle(
                    color: (apiKey.isNotEmpty || username.isNotEmpty) ? null : Colors.grey,
                    fontSize: 12,
                  ),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.edit, size: 18),
                  onPressed: () => _showAuthDialog(context, config, apiKey, username, password),
                ),
                onTap: () => _showAuthDialog(context, config, apiKey, username, password),
              ),
            // 连接状态（连接中或错误时显示）
            if (_isConnecting || (jellyfin.hasError && !isConnected))
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _isConnecting ? Colors.blue[50] : Colors.red[50],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    if (_isConnecting)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Icon(Icons.error, color: Colors.red[700], size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _isConnecting ? '连接中...' : (jellyfin.errorMessage ?? '连接失败'),
                        style: TextStyle(
                          color: _isConnecting ? Colors.blue[900] : Colors.red[900],
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _connect(
    BuildContext context,
    ConfigProvider config,
    JellyfinProvider jellyfin,
    String serverUrl,
    String username,
    String password,
    String apiKey,
  ) async {
    setState(() => _isConnecting = true);

    try {
      // 优先使用 API Key，否则使用用户名密码
      final success = await jellyfin.connect(
        serverUrl: serverUrl,
        apiKey: apiKey.isNotEmpty ? apiKey : null,
        username: apiKey.isEmpty ? username : null,
        password: apiKey.isEmpty ? password : null,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? '连接成功' : '连接失败，请检查配置'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('连接失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  void _showConfigDialog(
    BuildContext context,
    ConfigProvider config,
    String currentServerUrl,
    String currentApiKey,
    String currentUsername,
    String currentPassword,
  ) {
    final serverController = TextEditingController(text: currentServerUrl);
    final apiKeyController = TextEditingController(text: currentApiKey);
    final usernameController = TextEditingController(text: currentUsername);
    final passwordController = TextEditingController(text: currentPassword);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Jellyfin 服务器配置'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: serverController,
                decoration: const InputDecoration(
                  labelText: '服务器地址',
                  hintText: 'http://192.168.1.100:8096',
                  border: OutlineInputBorder(),
                  helperText: 'Jellyfin 服务器 URL',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: apiKeyController,
                decoration: const InputDecoration(
                  labelText: 'API Key（可选）',
                  hintText: '留空则使用用户名密码登录',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              const Text(
                '认证方式（二选一）',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: usernameController,
                decoration: const InputDecoration(
                  labelText: '用户名',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                decoration: const InputDecoration(
                  labelText: '密码',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await config.set('jellyfin_server_url', serverController.text.trim());
              await config.set('jellyfin_api_key', apiKeyController.text.trim());
              await config.set('jellyfin_username', usernameController.text.trim());
              await config.set('jellyfin_password', passwordController.text);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showAuthDialog(
    BuildContext context,
    ConfigProvider config,
    String currentApiKey,
    String currentUsername,
    String currentPassword,
  ) {
    final apiKeyController = TextEditingController(text: currentApiKey);
    final usernameController = TextEditingController(text: currentUsername);
    final passwordController = TextEditingController(text: currentPassword);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Jellyfin 认证信息'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: apiKeyController,
                decoration: const InputDecoration(
                  labelText: 'API Key（可选）',
                  hintText: '留空则使用用户名密码',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text('或', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: usernameController,
                decoration: const InputDecoration(
                  labelText: '用户名',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                decoration: const InputDecoration(
                  labelText: '密码',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await config.set('jellyfin_api_key', apiKeyController.text.trim());
              await config.set('jellyfin_username', usernameController.text.trim());
              await config.set('jellyfin_password', passwordController.text);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}

/// MissAV Stream 服务配置项
class _MissAVStreamServiceTile extends StatelessWidget {
  const _MissAVStreamServiceTile();

  @override
  Widget build(BuildContext context) {
    return Consumer<ConfigProvider>(
      builder: (context, config, child) {
        final serverUrl = config.pythonServerUrl;

        return ListTile(
          leading: const Icon(Icons.cloud_sync_outlined),
          title: const Text('MissAV Stream 服务'),
          subtitle: Text(
            serverUrl.isEmpty ? '未配置' : serverUrl,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 12,
            ),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showEditDialog(context, config, serverUrl),
        );
      },
    );
  }

  void _showEditDialog(
    BuildContext context,
    ConfigProvider config,
    String currentValue,
  ) {
    final controller = TextEditingController(text: currentValue);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('MissAV Stream 服务地址'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: '服务地址',
                hintText: 'http://192.168.1.100:5000',
                border: OutlineInputBorder(),
                helperText: 'MissAV 视频解析服务地址',
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '配置后将通过该服务获取 MissAV 视频流\n'
              '无需在本地处理 Cloudflare 保护\n'
              '留空则直接请求 MissAV 网站（可能失败）',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final url = controller.text.trim();
              await config.setPythonServerUrl(url);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}

/// 115 转码配置项
class _115TranscodeConfigTile extends StatelessWidget {
  const _115TranscodeConfigTile();

  @override
  Widget build(BuildContext context) {
    return Consumer<ConfigProvider>(
      builder: (context, config, child) {
        final backendUrl = config.pythonBackendUrl;
        final user = config.pythonBackendUser;
        final pass = config.pythonBackendPass;
        final isConfigured = backendUrl.isNotEmpty;
        final hasAuth = user != null && user.isNotEmpty && pass != null && pass.isNotEmpty;

        return Column(
          children: [
            // 服务地址
            ListTile(
              leading: Icon(
                Icons.hd,
                color: isConfigured ? Colors.green : Colors.grey,
              ),
              title: const Text('115 转码服务'),
              subtitle: Row(
                children: [
                  Expanded(
                    child: Text(
                      backendUrl.isEmpty ? '未配置' : backendUrl,
                      style: TextStyle(
                        color: backendUrl.isEmpty ? Colors.grey : null,
                      ),
                    ),
                  ),
                  if (hasAuth)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green[100],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '已认证',
                        style: TextStyle(fontSize: 10, color: Colors.green[700]),
                      ),
                    ),
                ],
              ),
              trailing: IconButton(
                icon: const Icon(Icons.edit, size: 20),
                onPressed: () => _showEditDialog(context, config),
              ),
              onTap: () => _showEditDialog(context, config),
            ),
            // 认证信息（已配置时显示）
            if (isConfigured)
              ListTile(
                leading: const Icon(Icons.lock, size: 20),
                title: const Text('认证信息'),
                subtitle: Text(
                  hasAuth ? '用户: $user' : '未设置',
                  style: TextStyle(
                    color: hasAuth ? null : Colors.grey,
                    fontSize: 12,
                  ),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.edit, size: 18),
                  onPressed: () => _showAuthDialog(context, config, user ?? '', ''),
                ),
                onTap: () => _showAuthDialog(context, config, user ?? '', ''),
              ),
          ],
        );
      },
    );
  }

  void _showEditDialog(BuildContext context, ConfigProvider config) {
    final controller = TextEditingController(text: config.pythonBackendUrl);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('115 转码服务地址'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '后端地址',
            hintText: 'http://192.168.1.100:5000',
            border: OutlineInputBorder(),
            helperText: 'Python 后端服务地址',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final url = controller.text.trim();
              await config.setPythonBackendUrl(url);
              if (context.mounted) {
                print('[Settings] 保存转码服务地址: $url');
                Navigator.pop(context);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showAuthDialog(
    BuildContext context,
    ConfigProvider config,
    String currentuser,
    String currentPass,
  ) {
    final userController = TextEditingController(text: currentuser);
    final passController = TextEditingController(text: currentPass);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('115 转码服务认证'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: userController,
              decoration: const InputDecoration(
                labelText: '用户名',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passController,
              decoration: const InputDecoration(
                labelText: '密码',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            const Text(
              'Basic Auth 认证信息\n用于 lucky 反向代理',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await config.setPythonBackendUser(userController.text.trim());
              await config.setPythonBackendPass(passController.text);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}

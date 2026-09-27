import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../theme.dart';
import 'chat_page.dart';
import 'logs_page.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _ip = '获取中…';

  @override
  void initState() {
    super.initState();
    _loadIp();
  }

  Future<void> _loadIp() async {
    try {
      for (final ni in await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLoopback: false)) {
        for (final a in ni.addresses) {
          if (a.address.startsWith('192.') ||
              a.address.startsWith('10.') ||
              a.address.startsWith('172.')) {
            setState(() => _ip = a.address);
            return;
          }
        }
      }
      setState(() => _ip = '未连接 Wi-Fi');
    } catch (_) {
      setState(() => _ip = '未知');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final base = 'http://$_ip:${state.serverPort}';
    return Scaffold(
      appBar: AppBar(
        title: const Text('豆包 API 控制台'),
        actions: [
          IconButton(
            icon: const Icon(Icons.terminal),
            tooltip: '对话测试',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ChatPage())),
          ),
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: '请求日志',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const LogsPage())),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '设置',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsPage())),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          // 服务器开关卡片
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: state.serverRunning
                  ? AppTheme.brandGradient
                  : LinearGradient(colors: [
                      scheme.surfaceVariant,
                      scheme.surfaceVariant,
                    ]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      state.serverRunning ? Icons.cloud_done : Icons.cloud_off,
                      color: state.serverRunning ? Colors.white : scheme.onSurfaceVariant,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            state.serverRunning ? 'API 服务运行中' : 'API 服务已停止',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: state.serverRunning ? Colors.white : scheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            state.serverRunning
                                ? '$base/v1'
                                : '点击下方按钮启动 OpenAI 兼容服务',
                            style: TextStyle(
                              fontSize: 12,
                              color: state.serverRunning
                                  ? Colors.white70
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: state.serverRunning
                              ? Colors.white24
                              : scheme.primary,
                          foregroundColor: state.serverRunning
                              ? Colors.white
                              : scheme.onPrimary,
                        ),
                        onPressed: () async {
                          if (!state.bridge.isReady && !state.serverRunning) {
                            final ok = await state.startServer();
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(ok ? '服务已启动' : '启动失败，端口可能被占用')));
                          } else {
                            await state.toggleServer(!state.serverRunning);
                          }
                        },
                        icon: Icon(state.serverRunning ? Icons.stop : Icons.play_arrow),
                        label: Text(state.serverRunning ? '停止服务' : '启动服务'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 状态卡片
          Row(
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () async {
                    final ok = await state.refreshLoginState();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(ok ? '已保存：检测到登录状态' : '未检测到登录，请先登录')));
                  },
                  child: _statCard(
                    context,
                    '登录状态（点击刷新）',
                    state.bridge.loggedIn ? '已登录' : '未登录',
                    state.bridge.loggedIn
                        ? Icons.check_circle
                        : Icons.warning_amber,
                    state.bridge.loggedIn ? Colors.green : Colors.orange,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _statCard(
                  context,
                  '请求数',
                  '${state.server.logs.length}',
                  Icons.swap_horiz,
                  scheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.save, size: 18),
              label: const Text('保存登录状态'),
              onPressed: () async {
                final ok = await state.refreshLoginState();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(ok ? '登录状态已保存' : '未登录，请先在设置中登录豆包')));
              },
            ),
          ),
          const SizedBox(height: 10),

          // 接入信息
          Text('接入信息',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          _infoTile(context, 'Base URL', '$base/v1'),
          _infoTile(context, 'API Key', state.apiKey.isEmpty ? '(未设置，无需认证)' : state.apiKey),
          _infoTile(context, '模型', 'doubao / doubao-think / doubao-expert'),
          const SizedBox(height: 20),

          // 使用示例
          Text('使用示例',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.surfaceVariant.withOpacity(0.5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: SelectableText(
              'curl $base/v1/chat/completions \\\n'
              '  -H "Content-Type: application/json" \\\n'
              '  -d \'{"model":"doubao","messages":[{"role":"user","content":"你好"}]}\'',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: TextButton.icon(
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('刷新本机 IP'),
              onPressed: _loadIp,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(BuildContext context, String title, String value,
      IconData icon, Color color) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 10),
          Text(value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text(title, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _infoTile(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        title: Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        subtitle: SelectableText(value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        trailing: IconButton(
          icon: const Icon(Icons.copy, size: 18),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: value));
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('已复制')));
          },
        ),
      ),
    );
  }
}

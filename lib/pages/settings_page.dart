import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import 'web_login_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TextEditingController _key;
  late TextEditingController _port;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    _key = TextEditingController(text: s.apiKey);
    _port = TextEditingController(text: '${s.serverPort}');
  }

  @override
  void dispose() {
    _key.dispose();
    _port.dispose();
    super.dispose();
  }

  void _snack(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _header('账号'),
          Card(
            child: ListTile(
              leading: Icon(
                state.bridge.isReady ? Icons.check_circle : Icons.login,
                color: state.bridge.isReady ? Colors.green : scheme.primary,
              ),
              title: Text(state.bridge.isReady ? '已登录豆包' : '登录豆包账号'),
              subtitle: const Text('在应用内网页登录，登录态自动保持'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const WebLoginPage()));
              },
            ),
          ),
          const SizedBox(height: 16),
          _header('服务配置'),
          TextField(
            controller: _port,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '监听端口',
              hintText: '9090',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _key,
            decoration: const InputDecoration(
              labelText: 'API Key',
              hintText: '留空表示无需认证',
            ),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: () async {
              final port = int.tryParse(_port.text.trim()) ?? 9090;
              await state.saveServerConfig(key: _key.text.trim(), port: port);
              _snack('已保存');
            },
            child: const Text('保存配置'),
          ),
          const SizedBox(height: 16),
          _header('后台与悬浮窗'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('后台保活'),
                  subtitle: const Text('保持服务常驻，避免被系统回收'),
                  value: state.keepAlive,
                  onChanged: (v) => state.setKeepAlive(v),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('悬浮球'),
                  subtitle: const Text('在其它应用上也能快速呼出助手'),
                  value: state.floatingBall,
                  onChanged: (v) async {
                    final ok = await state.setFloatingBall(v);
                    if (v && !ok) _snack('请先授予悬浮窗权限');
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _header('外观'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'system', label: Text('跟随系统')),
                  ButtonSegment(value: 'light', label: Text('浅色')),
                  ButtonSegment(value: 'dark', label: Text('深色')),
                ],
                selected: {
                  state.themeMode == ThemeMode.dark
                      ? 'dark'
                      : (state.themeMode == ThemeMode.light ? 'light' : 'system')
                },
                onSelectionChanged: (s) => state.saveSettings(themeMode: s.first),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text('豆包助手 v1.0.0',
                style: TextStyle(fontSize: 12, color: scheme.outline)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _header(String t) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
        child: Text(t,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
      );
}

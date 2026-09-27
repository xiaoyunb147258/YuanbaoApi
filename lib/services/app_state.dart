// 应用全局状态管理
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import 'api_server.dart';
import 'webview_bridge.dart';
import 'doubao_client.dart';
import 'system_channel.dart';

class AppState extends ChangeNotifier {
  late ApiServer server;
  final WebViewBridge bridge = WebViewBridge();
  final List<ChatMessage> messages = [];

  String apiKey = '';
  int serverPort = 9090;
  bool serverRunning = false;
  bool useBackend = false;
  String backendUrl = 'http://127.0.0.1:9090';
  String backendKey = '';

  int needDeepThink = 0;
  bool connected = false;
  bool engineReady = false;
  String? conversationId;
  String? localConvId;
  bool loading = false;
  ThemeMode themeMode = ThemeMode.system;
  bool floatingBall = false;
  bool keepAlive = true;

  AppState() {
    server = ApiServer(bridge: bridge);
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    apiKey = p.getString('apiKey') ?? '';
    serverPort = p.getInt('serverPort') ?? 9090;
    useBackend = p.getBool('useBackend') ?? false;
    backendUrl = p.getString('backendUrl') ?? 'http://127.0.0.1:9090';
    backendKey = p.getString('backendKey') ?? '';
    floatingBall = p.getBool('floatingBall') ?? false;
    keepAlive = p.getBool('keepAlive') ?? true;
    final tm = p.getString('themeMode') ?? 'system';
    themeMode = tm == 'dark'
        ? ThemeMode.dark
        : (tm == 'light' ? ThemeMode.light : ThemeMode.system);
    _apply();
    notifyListeners();
  }

  void _apply() {
    server.apiKey = apiKey;
    server.port = serverPort;
  }

  void markEngineReady() {
    engineReady = true;
    connected = true;
    notifyListeners();
  }

  /// 重新检测登录态（登录后手动保存时调用）
  Future<bool> refreshLoginState() async {
    await bridge.refreshLogin();
    await bridge.extractParams();
    await Future.delayed(const Duration(milliseconds: 800));
    connected = bridge.loggedIn;
    notifyListeners();
    return bridge.loggedIn;
  }

  Future<bool> startServer() async {
    try {
      server.apiKey = apiKey;
      server.port = serverPort;
      await server.start();
      serverRunning = true;
      notifyListeners();
      return true;
    } catch (e) {
      serverRunning = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> stopServer() async {
    await server.stop();
    serverRunning = false;
    notifyListeners();
  }

  Future<void> toggleServer(bool on) async {
    if (on) {
      await startServer();
    } else {
      await stopServer();
    }
  }

  Future<void> saveServerConfig({String? key, int? port}) async {
    final p = await SharedPreferences.getInstance();
    if (key != null) {
      apiKey = key;
      await p.setString('apiKey', key);
    }
    if (port != null) {
      serverPort = port;
      await p.setInt('serverPort', port);
    }
    _apply();
    notifyListeners();
  }

  Future<void> setKeepAlive(bool v) async {
    keepAlive = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool('keepAlive', v);
    await SystemChannel.toggleForegroundService(v);
    notifyListeners();
  }

  Future<bool> setFloatingBall(bool v) async {
    if (v) {
      final granted = await SystemChannel.requestOverlayPermission();
      if (!granted) return false;
    }
    floatingBall = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool('floatingBall', v);
    await SystemChannel.toggleFloatingBall(v);
    notifyListeners();
    return true;
  }

  Future<void> saveSettings({
    String? backendUrl,
    String? backendKey,
    bool? useBackend,
    String? themeMode,
  }) async {
    final p = await SharedPreferences.getInstance();
    if (backendUrl != null) {
      this.backendUrl = backendUrl;
      await p.setString('backendUrl', backendUrl);
    }
    if (backendKey != null) {
      this.backendKey = backendKey;
      await p.setString('backendKey', backendKey);
    }
    if (useBackend != null) {
      this.useBackend = useBackend;
      await p.setBool('useBackend', useBackend);
    }
    if (themeMode != null) {
      this.themeMode = themeMode == 'dark'
          ? ThemeMode.dark
          : (themeMode == 'light' ? ThemeMode.light : ThemeMode.system);
      await p.setString('themeMode', themeMode);
    }
    _apply();
    notifyListeners();
  }

  Future<bool> checkConnection() async {
    connected = bridge.loggedIn;
    notifyListeners();
    return connected;
  }

  void clearMessages() {
    messages.clear();
    conversationId = null;
    localConvId = null;
    notifyListeners();
  }

  void clearLogs() {
    server.logs.clear();
    notifyListeners();
  }

  int cycleMode() {
    final next = (needDeepThink + 1) % 3;
    needDeepThink = next == 0 ? 0 : (next == 1 ? 1 : 3);
    notifyListeners();
    return needDeepThink;
  }

  String get modeName =>
      needDeepThink == 0 ? '快速' : (needDeepThink == 1 ? '思考' : '专家');

  Future<void> sendMessage(String text) async {
    final userMsg = ChatMessage(role: 'user', content: text);
    messages.add(userMsg);
    final aiMsg = ChatMessage(role: 'assistant', isStreaming: true);
    messages.add(aiMsg);
    loading = true;
    notifyListeners();

    try {
      localConvId ??= 'local_${DateTime.now().millisecondsSinceEpoch}';
      final c = DoubaoClient(
          deviceId: bridge.deviceId, webId: bridge.webId, fp: bridge.fp);
      final url = '/chat/completion?${c.buildQueryString()}';
      final payload = c.buildChatPayload(
          text, needDeepThink, conversationId, localConvId!);
      await for (final d
          in bridge.chatStream(url: url, payloadJson: jsonEncode(payload))) {
        final cid = d['conversation_id']?.toString();
        if (cid != null && cid.isNotEmpty && cid != '0') {
          conversationId = cid;
        }
        if (d['text'] != null) aiMsg.content += d['text'].toString();
        if (d['error'] != null) aiMsg.content += '\n[错误] ${d['error']}';
        notifyListeners();
      }
    } catch (e) {
      aiMsg.content += '\n[异常] $e';
    }
    aiMsg.isStreaming = false;
    loading = false;
    notifyListeners();
  }
}

// WebView 桥接 - 复刻 doubao2api 的 browser_client 原理
// 在隐藏的 WebView 中加载豆包网页，利用豆包自身 JS 完成 a_bogus / msToken 签名，
// 再通过注入的 JS 在其页面上下文中发起 fetch 请求，实现 100% 可用的直连。
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

typedef StreamCallback = void Function(Map<String, dynamic> delta);

class WebViewBridge {
  WebViewController? _controller;
  bool ready = false;
  bool loggedIn = false;
  Completer<void>? _readyCompleter;
  final Map<String, StreamCallback> _streams = {};
  int _seq = 0;

  WebViewController createController({required VoidCallback onPageFinished}) {
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel('FlutterBridge', onMessageReceived: _onJsMessage)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          ready = true;
          if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
            _readyCompleter!.complete();
          }
          _injectHelper();
          onPageFinished();
        },
      ))
      ..loadRequest(Uri.parse('https://www.doubao.com/chat/'));
    _controller = c;
    return c;
  }

  bool get isReady => _controller != null && ready;

  Future<void> waitReady() {
    if (ready) return Future.value();
    _readyCompleter = Completer<void>();
    return _readyCompleter!.future.timeout(const Duration(seconds: 30),
        onTimeout: () {});
  }

  // 注入 JS 辅助函数：把 SSE 流解析后通过 FlutterBridge 回传
  Future<void> _injectHelper() async {
    final js = r'''
(function(){
  if (window.__bridgeInjected) return;
  window.__bridgeInjected = true;
  window.__chatStream = async function(id, payload) {
    try {
      const params = "aid=497858&device_platform=web&version_code=20800&language=zh&pkg_type=release_version&real_aid=497858&samantha_web=1&use-olympus-account=0";
      const resp = await fetch("https://www.doubao.com/samantha/chat/completion?" + params, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        credentials: "include",
        body: JSON.stringify(payload)
      });
      const reader = resp.body.getReader();
      const decoder = new TextDecoder();
      let buf = "";
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        buf += decoder.decode(value, { stream: true });
        const lines = buf.split("\n");
        buf = lines.pop();
        for (const line of lines) {
          const t = line.trim();
          if (!t.startsWith("data:")) continue;
          const data = t.substring(5).trim();
          if (!data || data === "[DONE]") continue;
          FlutterBridge.postMessage(JSON.stringify({ id: id, data: data }));
        }
      }
      FlutterBridge.postMessage(JSON.stringify({ id: id, done: true }));
    } catch (e) {
      FlutterBridge.postMessage(JSON.stringify({ id: id, error: String(e) }));
    }
  };

  window.__checkLogin = function() {
    const logged = !document.querySelector("[class*=login]");
    FlutterBridge.postMessage(JSON.stringify({ check: "login", value: logged }));
  };
})();
''';
    await _controller?.runJavaScript(js);
  }

  void _onJsMessage(JavaScriptMessage msg) {
    try {
      final j = jsonDecode(msg.message) as Map<String, dynamic>;
      if (j['check'] == 'login') {
        loggedIn = j['value'] == true;
        return;
      }
      final id = j['id']?.toString();
      if (id == null) return;
      final cb = _streams[id];
      if (cb == null) return;
      if (j['done'] == true) {
        cb({'done': true});
        _streams.remove(id);
        return;
      }
      if (j['error'] != null) {
        cb({'error': j['error'].toString()});
        _streams.remove(id);
        return;
      }
      if (j['data'] != null) {
        cb({'raw': j['data'].toString()});
      }
    } catch (_) {}
  }

  // 发起流式对话，返回解析后的增量流
  Stream<Map<String, dynamic>> chatStream(Map<String, dynamic> payload) {
    final id = 'stream_${_seq++}';
    final controller = StreamController<Map<String, dynamic>>();
    _streams[id] = (delta) {
      if (delta['done'] == true) {
        controller.close();
        return;
      }
      if (delta['error'] != null) {
        controller.add({'error': delta['error']});
        controller.close();
        return;
      }
      if (delta['raw'] != null) {
        final parsed = _parseSse(delta['raw'].toString());
        if (parsed != null) controller.add(parsed);
      }
    };
    _runJsChat(id, payload);
    return controller.stream;
  }

  Future<void> _runJsChat(String id, Map<String, dynamic> payload) async {
    final payloadJson = jsonEncode(payload);
    final js = 'window.__chatStream("$id", $payloadJson);';
    await _controller?.runJavaScript(js);
  }

  // 解析豆包 SSE 单条事件（复刻 doubao2api sse.py 的核心逻辑）
  Map<String, dynamic>? _parseSse(String raw) {
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final eventType = j['event_type'];
      final result = <String, dynamic>{};

      if (eventType == 2002) {
        final cid = j['conversation_id']?.toString() ??
            (j['message'] is Map ? j['message']['conversation_id']?.toString() : null);
        if (cid != null) result['conversation_id'] = cid;
        return result.isEmpty ? null : result;
      }
      if (eventType == 2003) return {'done': true};
      if (eventType == 2005) {
        return {'error': j['message']?.toString() ?? 'stream error'};
      }
      if (eventType == 2001) {
        final ct = j['content_type'];
        final msg = j['message'];
        String? content;
        if (msg is Map && msg['content'] is String) {
          content = msg['content'];
        } else if (msg is String) {
          content = msg;
        }
        if (ct == 10040) return {'thinkingStart': true};
        if (ct == 10000) {
          if (content != null && content.isNotEmpty) return {'text': content};
          return null;
        }
        if (ct == 2008) {
          if (content != null) return {'thinking': content};
          return null;
        }
        if (ct == 2001) {
          if (content != null && content.isNotEmpty) return {'text': content};
          return null;
        }
        if (ct == 2010) {
          if (msg is Map) {
            final url = msg['image_url']?.toString() ?? msg['url']?.toString();
            if (url != null) return {'image': url};
          }
          return null;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> reload() async {
    ready = false;
    await _controller?.reload();
  }

  WebViewController? get controller => _controller;
}

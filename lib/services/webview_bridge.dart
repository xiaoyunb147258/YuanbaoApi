// WebView 桥接 - 严格复刻 doubao2api browser_client.py 的协议
// 加载豆包网页，复用其 fetch hook（自动注入 a_bogus/msToken），
// 通过注入 JS 在页面上下文发起请求并回传响应。
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class WebViewBridge {
  WebViewController? _controller;
  bool ready = false;
  bool loggedIn = false;
  Completer<void>? _readyCompleter;
  final Map<String, void Function(String?)> _streams = {};
  int _seq = 0;

  // device params (extracted from page like the original)
  String deviceId = '';
  String webId = '';
  String fp = '';

  WebViewController createController({required VoidCallback onPageFinished}) {
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel('DBBridge', onMessageReceived: _onJsMessage)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) async {
          ready = true;
          if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
            _readyCompleter!.complete();
          }
          await injectHelper();
          await extractParams();
          await refreshLogin();
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
    return _readyCompleter!.future
        .timeout(const Duration(seconds: 40), onTimeout: () {});
  }

  /// 检测登录态：登录按钮存在 = 未登录
  Future<void> refreshLogin() async {
    await _controller?.runJavaScript(
      "try{var b=document.querySelectorAll('button'),h=false;"
      "for(var i=0;i<b.length;i++){if((b[i].innerText||'').trim()==='登录'){h=true;break;}}"
      "DBBridge.postMessage(JSON.stringify({kind:'login',value:!h}));"
      "}catch(e){DBBridge.postMessage(JSON.stringify({kind:'login',value:false}));}",
    );
  }

  /// 提取 device_id / web_id / fp
  Future<void> extractParams() async {
    await _controller?.runJavaScript(
      "(function(){var r={};try{var a=JSON.parse(localStorage.getItem('samantha_web_web_id')||'{}');r.d=a.web_id||'';}catch(e){}"
      "try{var t=JSON.parse(localStorage.getItem('__tea_cache_tokens_497858')||'{}');r.w=t.web_id||'';}catch(e){}"
      "var c=document.cookie.split(';').map(function(x){return x.trim();}).find(function(x){return x.indexOf('s_v_web_id=')===0;});"
      "r.f=c?c.split('=')[1]:'';"
      "DBBridge.postMessage(JSON.stringify({kind:'params',d:r.d,w:r.w,f:r.f}));})();",
    );
  }

  /// 注入请求辅助函数
  Future<void> injectHelper() async {
    await _controller?.runJavaScript('''
window.__dbFetch = async function(rid, path, body){
  try {
    var m = document.cookie.match(/passport_csrf_token=([^;]+)/);
    var h = {'Content-Type':'application/json','agw-js-conv':'str, str'};
    if(m) h['x-tt-passport-csrf-token'] = m[1];
    var res = await fetch(path, {method:'POST', headers:h, body:body, credentials:'include'});
    if(!res.ok){var t=await res.text();
      DBBridge.postMessage(JSON.stringify({kind:'stream',id:rid,httpError:res.status,body:t.slice(0,400)}));
      DBBridge.postMessage(JSON.stringify({kind:'stream',id:rid,done:true}));return;}
    var r = res.body.getReader(), d = new TextDecoder(), buf='', ev='';
    while(true){
      var g = await r.read(); if(g.done) break;
      buf += d.decode(g.value, {stream:true});
      var ls = buf.split('\\n'); buf = ls.pop();
      for(var i=0;i<ls.length;i++){
        var t = ls[i].trim();
        if(!t) continue;
        if(t.indexOf('event: ')===0){ev=t.slice(7);continue;}
        if(t.indexOf('id: ')===0) continue;
        if(t.indexOf('data: ')===0){
          var ds=t.slice(6);
          if(ds && ds!=='{}') DBBridge.postMessage(JSON.stringify({kind:'stream',id:rid,event:ev,data:ds}));
        }
      }
    }
    DBBridge.postMessage(JSON.stringify({kind:'stream',id:rid,done:true}));
  } catch(e){
    DBBridge.postMessage(JSON.stringify({kind:'stream',id:rid,error:String(e)}));
    DBBridge.postMessage(JSON.stringify({kind:'stream',id:rid,done:true}));
  }
};
window.__dbOnce = async function(rid, path, body){
  try {
    var m = document.cookie.match(/passport_csrf_token=([^;]+)/);
    var h = {'Content-Type':'application/json','agw-js-conv':'str, str'};
    if(m) h['x-tt-passport-csrf-token'] = m[1];
    var res = await fetch(path, {method:'POST', headers:h, body:body, credentials:'include'});
    var t = await res.text();
    DBBridge.postMessage(JSON.stringify({kind:'once',id:rid,body:t}));
    DBBridge.postMessage(JSON.stringify({kind:'once',id:rid,done:true}));
  } catch(e){
    DBBridge.postMessage(JSON.stringify({kind:'once',id:rid,error:String(e)}));
    DBBridge.postMessage(JSON.stringify({kind:'once',id:rid,done:true}));
  }
};
''');
  }

  void _onJsMessage(JavaScriptMessage msg) {
    try {
      final j = jsonDecode(msg.message) as Map<String, dynamic>;
      final kind = j['kind'];
      if (kind == 'login') {
        loggedIn = j['value'] == true;
        return;
      }
      if (kind == 'params') {
        deviceId = j['d']?.toString() ?? '';
        webId = j['w']?.toString() ?? '';
        fp = j['f']?.toString() ?? '';
        return;
      }
      final id = j['id']?.toString();
      if (id == null) return;
      final cb = _streams[id];
      if (cb == null) return;
      if (j['done'] == true) {
        cb(null);
        _streams.remove(id);
        return;
      }
      if (j['httpError'] != null) {
        cb('__HTTP_ERROR__:${j['httpError']}:${j['body'] ?? ''}');
        return;
      }
      if (j['error'] != null) {
        cb('__ERROR__:${j['error']}');
        return;
      }
      if (j['data'] != null) {
        cb('EVENT:${j['event'] ?? ''}|${j['data']}');
        return;
      }
      if (j['body'] != null) {
        cb('__ONCE__:${j['body']}');
        return;
      }
    } catch (_) {}
  }

  Stream<Map<String, dynamic>> chatStream(
      {required String url, required String payloadJson}) {
    final id = 'r${_seq++}';
    final ctrl = StreamController<Map<String, dynamic>>();
    _streams[id] = (chunk) {
      if (chunk == null) {
        if (!ctrl.isClosed) ctrl.close();
        return;
      }
      if (chunk.startsWith('__HTTP_ERROR__:')) {
        if (!ctrl.isClosed) ctrl.add({'error': chunk});
        return;
      }
      if (chunk.startsWith('__ERROR__:')) {
        if (!ctrl.isClosed) ctrl.add({'error': chunk.substring(10)});
        return;
      }
      String event = '';
      String data = chunk;
      if (chunk.startsWith('EVENT:')) {
        final idx = chunk.indexOf('|');
        event = chunk.substring(6, idx);
        data = chunk.substring(idx + 1);
      }
      final parsed = parseEvent(event, data);
      if (parsed != null && !ctrl.isClosed) ctrl.add(parsed);
    };
    final js =
        'window.__dbFetch("$id", ${jsonEncode(url)}, ${jsonEncode(payloadJson)});';
    _controller?.runJavaScript(js);
    return ctrl.stream;
  }

  Future<String> fetchOnce(
      {required String url,
      required String payloadJson,
      int timeoutSeconds = 300}) async {
    final id = 'o${_seq++}';
    final completer = Completer<String>();
    final buf = StringBuffer();
    _streams[id] = (chunk) {
      if (chunk == null) {
        if (!completer.isCompleted) completer.complete(buf.toString());
      } else if (chunk.startsWith('__ONCE__:')) {
        buf.write(chunk.substring(8));
      } else if (chunk.startsWith('__HTTP_ERROR__:') ||
          chunk.startsWith('__ERROR__:')) {
        if (!completer.isCompleted) completer.complete('__ERROR__:$chunk');
      }
    };
    final js = 'window.__dbOnce("$id", ${jsonEncode(url)}, ${jsonEncode(payloadJson)});';
    await _controller?.runJavaScript(js);
    return completer.future.timeout(Duration(seconds: timeoutSeconds + 20),
        onTimeout: () => buf.toString());
  }

  /// 解析 /chat/completion 事件（复刻 _extract_text + extract_conversation_id）
  Map<String, dynamic>? parseEvent(String event, String data) {
    Map<String, dynamic> j;
    try {
      j = jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
    final result = <String, dynamic>{};
    final ack = j['ack_client_meta'];
    if (ack is Map && ack['conversation_id'] != null) {
      result['conversation_id'] = ack['conversation_id'].toString();
    }
    final meta = j['meta'];
    if (meta is Map && meta['conversation_id'] != null) {
      result['conversation_id'] = meta['conversation_id'].toString();
    }
    final text = extractText(event, j);
    if (text.isNotEmpty) result['text'] = text;
    return result.isEmpty ? null : result;
  }

  String extractText(String event, Map<String, dynamic> e) {
    if (event == 'CHUNK_DELTA' && e['text'] != null) return e['text'].toString();
    final patchOp = e['patch_op'];
    if (patchOp is List) {
      for (final op in patchOp) {
        if (op is! Map) continue;
        final pv = op['patch_value'];
        if (pv is Map) {
          final cb = pv['content_block'];
          if (cb is List) {
            for (final block in cb) {
              if (block is! Map) continue;
              final content = block['content'];
              if (content is Map) {
                final tb = content['text_block'];
                if (tb is Map &&
                    tb['text'] != null &&
                    tb['text'].toString().isNotEmpty) {
                  return tb['text'].toString();
                }
              }
            }
          }
          if (op['patch_object'] == 102) {
            final raw = pv['content'];
            if (raw is String && raw.isNotEmpty) {
              try {
                final p = jsonDecode(raw);
                if (p is Map && p['text'] != null) return p['text'].toString();
              } catch (_) {}
            }
          }
        }
      }
    }
    if (event == 'STREAM_MSG_NOTIFY') {
      final content = e['content'];
      if (content is Map) {
        final cb = content['content_block'];
        if (cb is List) {
          for (final block in cb) {
            if (block is! Map) continue;
            final c2 = block['content'];
            if (c2 is Map) {
              final tb = c2['text_block'];
              if (tb is Map && tb['text'] != null) return tb['text'].toString();
            }
          }
        }
      }
    }
    return '';
  }

  Future<void> reload() async {
    ready = false;
    await _controller?.reload();
  }

  WebViewController? get controller => _controller;
}
